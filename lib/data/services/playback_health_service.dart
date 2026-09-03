import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// §stallCount — Ce que chaque fournisseur a réellement servi, par compte.
///
/// ## La question à laquelle ce service répond
///
/// « Lequel de mes abonnements rame ? » — jusqu'ici invérifiable. On ressentait
/// des coupures sans pouvoir dire lequel des trois comptes les causait, ni si
/// elles empiraient. C'est le prolongement direct de §qualityTruth : celui-là
/// vérifie que les listes ne mentent pas sur la **définition**, celui-ci vérifie
/// qu'elles ne mentent pas sur le **service**.
///
/// ## Ce qui est compté, et ce qui ne l'est pas
///
/// Un blocage = la lecture s'était lancée, puis s'est **arrêtée pour attendre le
/// réseau**. Ne comptent donc PAS : la mise en tampon initiale (ce n'est pas une
/// interruption, c'est un démarrage) ni celle qui suit un déplacement demandé
/// par l'utilisateur (`Media3Engine` l'amnistie). Sans ces deux exclusions, le
/// compteur accuserait le fournisseur de ce que l'utilisateur a provoqué.
///
/// ⚠️ Une session de moins de 10 secondes de lecture effective n'est pas
/// enregistrée : elle ne dit rien du fournisseur, et diluerait les moyennes.
///
/// ## Ce que ces chiffres ne sont pas
///
/// Ils ne distinguent pas un panel saturé d'un Wi-Fi faible : les deux
/// produisent des blocages. Ils deviennent parlants par **comparaison** — deux
/// comptes vus le même soir sur le même réseau — pas dans l'absolu.
class PlaybackHealthService {
  PlaybackHealthService._();

  static const String _key = 'playback_health_v1';

  /// Bump à chaque écriture → les cartes de comptes se rafraîchissent.
  static final ValueNotifier<int> version = ValueNotifier(0);

  static final Map<String, AccountPlaybackHealth> _byAccount = {};

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _byAccount
        ..clear()
        ..addAll(map.map((k, v) => MapEntry(
            k, AccountPlaybackHealth.fromJson(v as Map<String, dynamic>))));
      debugPrint('✅ §stallCount — santé de lecture restaurée '
          'pour ${_byAccount.length} compte(s)');
    } catch (e) {
      debugPrint('⚠️ §stallCount — lecture impossible : $e');
    }
  }

  /// Bilan d'un compte, ou `null` s'il n'a jamais été mesuré.
  static AccountPlaybackHealth? forAccount(String accountId) =>
      _byAccount[accountId];

  /// Enregistre une session terminée.
  ///
  /// [accountId] peut être vide (lecture d'un fichier local, source inconnue) :
  /// on ne fabrique alors aucune statistique plutôt que d'en attribuer une au
  /// hasard.
  static Future<void> record({
    required String accountId,
    required int stalls,
    required Duration stalled,
    required Duration watched,
    Duration? startup,
  }) async {
    if (accountId.isEmpty || watched.inSeconds < 10) return;
    final prev = _byAccount[accountId] ?? const AccountPlaybackHealth();
    _byAccount[accountId] = prev.plus(
      stalls: stalls,
      stalled: stalled,
      watched: watched,
      startup: startup,
    );
    version.value++;
    await _persist();
    debugPrint('📊 §stallCount — $accountId : +$stalls blocage(s) sur '
        '${watched.inMinutes} min → ${_byAccount[accountId]!.summary}');
  }

  /// Remise à zéro d'un compte (bouton « Réinitialiser les données d'usage »,
  /// ou quand l'utilisateur veut repartir d'une mesure propre).
  static Future<void> clear([String? accountId]) async {
    if (accountId == null) {
      _byAccount.clear();
    } else {
      _byAccount.remove(accountId);
    }
    version.value++;
    await _persist();
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key, jsonEncode(_byAccount.map((k, v) => MapEntry(k, v.toJson()))));
    } catch (e) {
      debugPrint('⚠️ §stallCount — écriture impossible : $e');
    }
  }
}

/// Cumul par compte. Immuable : chaque session produit un nouvel objet.
@immutable
class AccountPlaybackHealth {
  final int sessions;
  final int stalls;
  final Duration stalled;
  final Duration watched;

  /// Somme des délais de démarrage mesurés, et leur nombre — pour en donner la
  /// moyenne sans garder tout l'historique.
  final Duration startupTotal;
  final int startupSamples;

  const AccountPlaybackHealth({
    this.sessions = 0,
    this.stalls = 0,
    this.stalled = Duration.zero,
    this.watched = Duration.zero,
    this.startupTotal = Duration.zero,
    this.startupSamples = 0,
  });

  AccountPlaybackHealth plus({
    required int stalls,
    required Duration stalled,
    required Duration watched,
    Duration? startup,
  }) =>
      AccountPlaybackHealth(
        sessions: sessions + 1,
        stalls: this.stalls + stalls,
        stalled: this.stalled + stalled,
        watched: this.watched + watched,
        startupTotal: startup == null ? startupTotal : startupTotal + startup,
        startupSamples: startup == null ? startupSamples : startupSamples + 1,
      );

  /// **La mesure comparable** : blocages par heure de lecture.
  ///
  /// Un total brut favorise le compte le moins regardé — il faut rapporter au
  /// temps vu pour que deux abonnements soient comparables.
  double? get stallsPerHour {
    final h = watched.inSeconds / 3600.0;
    if (h <= 0.05) return null; // moins de 3 min : pas assez pour conclure
    return stalls / h;
  }

  /// Démarrage moyen, ou `null` si jamais mesuré.
  Duration? get averageStartup => startupSamples == 0
      ? null
      : Duration(
          milliseconds: startupTotal.inMilliseconds ~/ startupSamples);

  /// Résumé d'une ligne : « 3 blocages · 1,2/h · 2 h 10 vues ».
  String get summary {
    final parts = <String>[
      stalls == 0 ? 'aucun blocage' : '$stalls blocage${stalls > 1 ? 's' : ''}',
      if (stallsPerHour != null) '${stallsPerHour!.toStringAsFixed(1)}/h',
      '${_hm(watched)} vues',
    ];
    return parts.join(' · ');
  }

  static String _hm(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '$m min';
  }

  Map<String, dynamic> toJson() => {
        's': sessions,
        'b': stalls,
        'bm': stalled.inMilliseconds,
        'wm': watched.inMilliseconds,
        'sm': startupTotal.inMilliseconds,
        'sn': startupSamples,
      };

  factory AccountPlaybackHealth.fromJson(Map<String, dynamic> j) =>
      AccountPlaybackHealth(
        sessions: j['s'] as int? ?? 0,
        stalls: j['b'] as int? ?? 0,
        stalled: Duration(milliseconds: j['bm'] as int? ?? 0),
        watched: Duration(milliseconds: j['wm'] as int? ?? 0),
        startupTotal: Duration(milliseconds: j['sm'] as int? ?? 0),
        startupSamples: j['sn'] as int? ?? 0,
      );
}
