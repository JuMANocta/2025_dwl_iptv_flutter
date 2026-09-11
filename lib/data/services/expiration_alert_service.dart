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

  /// Revue 2026-09-11, D4B-10 — La requête lancée par [fetchAll], par compte,
  /// TANT QU'ELLE COURT.
  ///
  /// La page Comptes demandait DEUX fois `get_account_info` par compte, à
  /// chaque ouverture et à chaque rafraîchissement : [fetchAll] (pour les
  /// puces d'expiration), puis chaque carte dans son `initState` (pour son
  /// bloc Xtream) — la même requête, sérialisée par §hostGate sur des panels
  /// qui n'acceptent qu'une connexion. La carte reprend désormais CE futur :
  /// même requête, même résultat, même attente (chaque futur se termine avec
  /// SA requête, pas avec la plus lente du lot).
  ///
  /// ⚠️ Trouvé à la relecture : une requête TERMINÉE n'est PAS gardée. La
  /// liste des comptes est un `ListView.builder` : une carte sortie de l'écran
  /// est détruite, remontée au retour, et refaisait sa requête. Lui rendre un
  /// futur terminé lui ferait afficher les chiffres de l'ouverture de la page
  /// (connexions actives comprises) au lieu de chiffres frais — un changement
  /// d'affichage, pas une économie.
  static final Map<String, Future<AccountInfo?>> _inFlight =
      <String, Future<AccountInfo?>>{};

  /// Le futur de la requête EN COURS lancée par [fetchAll] pour ce compte, ou
  /// `null` s'il n'y en a pas (jamais demandée, ou déjà terminée : l'appelant
  /// fait alors la sienne, comme avant). Ne lève pas : un échec rend `null`,
  /// comme dans [infos].
  static Future<AccountInfo?>? pendingFor(String accountId) =>
      _inFlight[accountId];

  /// Garde [f] tant qu'elle court. ⚠️ Test d'IDENTITÉ : un [fetchAll] plus
  /// récent a pu la remplacer, et sa fin ne doit pas effacer la suivante.
  /// ⚠️ Rappel au corps en bloc, jamais `whenComplete(() => map.remove(k))`,
  /// qui s'interbloque (D1B-23). Fonction synchrone : aucun futur ignoré dans
  /// un corps `async` (`unawaited_futures`).
  static void _track(String accountId, Future<AccountInfo?> f) {
    _inFlight[accountId] = f;
    void release() {
      if (identical(_inFlight[accountId], f)) _inFlight.remove(accountId);
    }

    f.then<void>((_) => release(), onError: (Object _) => release());
  }

  /// Fetch en parallèle les AccountInfo de tous les comptes fournis et
  /// remplit le cache. Sûr d'appeler plusieurs fois (idempotent).
  static Future<void> fetchAll(List<StreamAccount> accounts) async {
    if (accounts.isEmpty) return;
    // Toutes les requêtes partent ICI, avant le premier `await` : même
    // départ simultané qu'avant, et [pendingFor] est à jour dès le retour.
    final List<MapEntry<String, Future<AccountInfo?>>> started =
        <MapEntry<String, Future<AccountInfo?>>>[
      for (final StreamAccount a in accounts) MapEntry(a.id, _fetchOne(a)),
    ];
    for (final MapEntry<String, Future<AccountInfo?>> e in started) {
      _track(e.key, e.value);
    }
    final results = await Future.wait(
      started.map((e) async => MapEntry<String, AccountInfo?>(e.key, await e.value)),
    );
    final next = Map<String, AccountInfo?>.from(infos.value);
    for (final e in results) {
      next[e.key] = e.value;
    }
    infos.value = next;
  }

  static Future<AccountInfo?> _fetchOne(StreamAccount a) async {
    try {
      return await StreamAccountService.fetchAccountInfo(a);
    } catch (e) {
      debugPrint('❌ ExpirationAlertService fetch ${a.label}: $e');
      return null;
    }
  }

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
