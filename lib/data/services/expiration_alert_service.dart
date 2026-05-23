import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account_info.dart';
import '../models/stream_account.dart';
import 'stream_account_service.dart';

/// Service §17b — gestion centralisée des AccountInfo (cache mémoire) +
/// dédoublonnage des alertes "expiration <30j" (SharedPreferences).
///
/// Utilisé par :
///   - `_LaunchDecider` (popup au démarrage si au moins un compte <30j)
///   - `AccountsPage._AccountTile` (chip "⚠ X JOURS")
///   - `PlaylistManagementPage` (texte rouge dans le bloc Xtream)
///
/// Tous les consommateurs partagent le même cache (évite les re-fetch
/// inutiles). Le notifier `infos` permet aux UI de se rebuilder quand le
/// fetch async termine.
class ExpirationAlertService {
  /// Seuil en jours sous lequel on alerte (rouge + popup au démarrage).
  static const int kAlertThresholdDays = 30;

  /// Cache mémoire des AccountInfo récupérés. Clé = `accountId`.
  /// `null` = pas Xtream-compatible (URL Flussonic, custom...).
  /// Absent de la map = pas encore fetché.
  static final ValueNotifier<Map<String, AccountInfo?>> infos =
      ValueNotifier<Map<String, AccountInfo?>>({});

  /// Fetch en parallèle les AccountInfo de tous les comptes fournis et
  /// remplit le cache. Sûr d'appeler plusieurs fois (idempotent).
  static Future<void> fetchAll(List<StreamAccount> accounts) async {
    if (accounts.isEmpty) return;
    final results = await Future.wait(
      accounts.map((a) async {
        try {
          final info = await StreamAccountService.fetchAccountInfo(a);
          return MapEntry(a.id, info);
        } catch (e) {
          debugPrint('❌ ExpirationAlertService fetch ${a.label}: $e');
          return MapEntry<String, AccountInfo?>(a.id, null);
        }
      }),
    );
    final next = Map<String, AccountInfo?>.from(infos.value);
    for (final e in results) {
      next[e.key] = e.value;
    }
    infos.value = next;
  }

  /// Lecture synchrone d'un info (null si pas encore fetché ou pas Xtream).
  static AccountInfo? getCached(String accountId) => infos.value[accountId];

  /// Retourne le nombre de jours avant expiration, négatif si expiré, null
  /// si pas de date disponible (info absente, ou compte non-Xtream).
  static int? daysUntilExpiration(String accountId) {
    final exp = infos.value[accountId]?.expirationDate;
    if (exp == null) return null;
    final now = DateTime.now();
    // Compte le nombre de jours entiers restants à partir de minuit.
    final today = DateTime(now.year, now.month, now.day);
    final expDay = DateTime(exp.year, exp.month, exp.day);
    return expDay.difference(today).inDays;
  }

  /// Liste des comptes pour lesquels une alerte doit être levée (≤30 jours
  /// OU déjà expirés). Format : `(account, AccountInfo, daysLeft)`.
  static List<({StreamAccount account, AccountInfo info, int daysLeft})>
      computeAlerts(List<StreamAccount> accounts) {
    final result =
        <({StreamAccount account, AccountInfo info, int daysLeft})>[];
    for (final acc in accounts) {
      final info = infos.value[acc.id];
      if (info?.expirationDate == null) continue;
      final days = daysUntilExpiration(acc.id);
      if (days == null) continue;
      if (days <= kAlertThresholdDays) {
        result.add((account: acc, info: info!, daysLeft: days));
      }
    }
    // Tri : les plus critiques (jours les plus bas) en premier.
    result.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return result;
  }

  // ── Dédoublonnage popup ───────────────────────────────────────────────────

  /// Clé SharedPreferences keyée sur l'accountId + la date d'expiration ISO
  /// (jour seul) : ne re-popup pas tant que la date ne change pas.
  static String _ackKey(String accountId, DateTime expDate) {
    final iso =
        '${expDate.year.toString().padLeft(4, '0')}-${expDate.month.toString().padLeft(2, '0')}-${expDate.day.toString().padLeft(2, '0')}';
    return 'expiration_alert_acked_${accountId}_$iso';
  }

  /// Vrai si l'utilisateur a déjà acquitté l'alerte pour ce couple
  /// `(accountId, expirationDate)`.
  static Future<bool> isAcked(String accountId, DateTime expDate) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_ackKey(accountId, expDate)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Marque l'alerte comme acquittée pour ce couple.
  static Future<void> ack(String accountId, DateTime expDate) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_ackKey(accountId, expDate), true);
    } catch (_) {}
  }

  /// Filtre `computeAlerts` pour ne garder que les non-acquittées.
  /// **Exception** : les comptes déjà expirés (`daysLeft < 0`) sont TOUJOURS
  /// inclus, même acquittés — l'app ne sert plus à rien sans playlist active.
  static Future<List<({StreamAccount account, AccountInfo info, int daysLeft})>>
      computeUnackedAlerts(List<StreamAccount> accounts) async {
    final all = computeAlerts(accounts);
    final filtered =
        <({StreamAccount account, AccountInfo info, int daysLeft})>[];
    for (final a in all) {
      if (a.daysLeft < 0) {
        filtered.add(a);
        continue;
      }
      final acked = await isAcked(a.account.id, a.info.expirationDate!);
      if (!acked) filtered.add(a);
    }
    return filtered;
  }
}
