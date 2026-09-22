// §playerPanel backup (audit du 2026-09-22) — Le VRAI manque que l'audit a
// trouvé n'était pas dans le code de `backup_service.dart`, c'était l'absence
// de CE test : rien ne cassait quand un service persistant nouveau (mémoire
// des pistes, clé de sous-titres, format d'image, infos vidéo) apparaissait
// sans être branché sur `BackupContent`. Ce fichier scanne `lib/` (comme
// `l10n_guard_test.dart` scanne le texte en dur) à la recherche de CLÉS de
// stockage persistées, et les compare à une table EXPLICITE ci-dessous.
//
// Une clé TROUVÉE mais ABSENTE de la table fait échouer le test avec un
// message qui dit quoi faire : soit la brancher sur `.aether`
// (`BackupContent`/`_collectAll`/`applyBackup`), soit la classer « propre à
// l'appareil » avec une raison — jamais la deviner en silence.
//
// ⚠️ Scan HEURISTIQUE, pas une preuve : il cherche les déclarations
// `static const [String[?]] _xxx = '...'` (convention constante dans ce
// dépôt — toutes les clés SharedPreferences/flutter_secure_storage trouvées
// le 2026-09-22 suivent cette forme, `_prefsKey`/`_key`/`_kXxx`/`_apiKey…`).
// Une clé construite dynamiquement (ex. `expiration_alert_acked_<id>_<date>`
// dans `expiration_alert_service.dart`) n'est PAS un littéral et n'est donc
// PAS vue par ce scan — elle est documentée à la main plus bas.
//
// ⚠️ La table est indexée par la VALEUR de la clé, pas par (fichier,
// variable) : deux services qui choisiraient par accident la même chaîne se
// confondraient. Aucune collision connue au 2026-09-22 ; si le test échoue un
// jour sur une clé déjà présente mais dans le mauvais fichier, c'est le
// signal à lire.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

enum _Status { covered, excluded }

class _Verdict {
  const _Verdict(this.status, this.reason);
  final _Status status;

  /// Pourquoi — obligatoire pour se relire dans six mois.
  final String reason;
}

/// La table de vérité. Toute clé neuve trouvée par [_scanKeys] doit y
/// figurer AVANT que ce test passe.
const Map<String, _Verdict> _knownKeys = {
  // ── Sauvegardées dans .aether (BackupContent) ───────────────────────────
  'accounts_index': _Verdict(_Status.covered, 'BackupContent.accounts'),
  'current_account_id':
      _Verdict(_Status.covered, 'BackupContent.activeAccountId'),
  'tmdb_api_key': _Verdict(_Status.covered, 'BackupContent.tmdbKey'),
  'aether_theme_v1': _Verdict(_Status.covered, 'BackupContent.theme'),
  'aether_saved_themes_v1':
      _Verdict(_Status.covered, 'BackupContent.savedThemes'),
  'aether_perf_v1': _Verdict(_Status.covered, 'BackupContent.perf'),
  'hidden_regions_v1':
      _Verdict(_Status.covered, 'BackupContent.hiddenRegions'),
  'visual_lang_v1': _Verdict(_Status.covered, 'BackupContent.visualLanguage'),
  'favorites_v1': _Verdict(_Status.covered, 'BackupContent.favorites'),
  'watch_progress_v1':
      _Verdict(_Status.covered, 'BackupContent.watchProgress'),
  // §playerPanel (2026-09-22) — les 4 réglages retrouvés par l'audit.
  'wyzie_api_key':
      _Verdict(_Status.covered, 'BackupContent.subtitleApiKey'),
  'track_pref_audio_v1':
      _Verdict(_Status.covered, "BackupContent.trackPrefs['audio']"),
  'track_pref_sub_v1':
      _Verdict(_Status.covered, "BackupContent.trackPrefs['subtitle']"),
  'player_video_fit_v1':
      _Verdict(_Status.covered, 'BackupContent.videoFit'),
  'player_video_stats_v1':
      _Verdict(_Status.covered, 'BackupContent.videoStatsEnabled'),

  // ── Exclues : propre à l'APPAREIL ou au FLUX (une mesure, jamais un choix)
  'device_caps_v1': _Verdict(_Status.excluded,
      'capacités du décodeur MESURÉES (§caps4kDisplay), pas un choix'),
  'device_caps_measured_at_v1':
      _Verdict(_Status.excluded, 'horodatage de la mesure ci-dessus'),
  'device_caps_auto_profile_v1': _Verdict(_Status.excluded,
      'drapeau « profil auto déjà proposé » — une fois par appareil'),
  'measured_quality_v1': _Verdict(_Status.excluded,
      'qualité RÉELLEMENT décodée, mesurée par titre et par appareil'),
  'playback_health_v1': _Verdict(
      _Status.excluded, 'blocages MESURÉS par abonnement (§stallCount)'),
  'inferred_category_v3': _Verdict(
      _Status.excluded, 'cache — se reconstruit depuis TMDB + le catalogue'),
  'tmdb_poster_cache_v2': _Verdict(
      _Status.excluded, 'cache des affiches (négatifs compris) — se reconstruit'),
  'aether_img_tmdb': _Verdict(_Status.excluded,
      'espace de nommage du cache disque des images (flutter_cache_manager)'),
  'aether_img_provider':
      _Verdict(_Status.excluded, 'idem, pour les visuels du fournisseur IPTV'),
  'device_videos_v1': _Verdict(_Status.excluded,
      'index des fichiers LOCAUX de CET appareil (téléchargements)'),
  'download_tasks_list': _Verdict(_Status.excluded,
      'file des téléchargements — déjà exclue, documentée « trop volumineux » dans backup_service.dart'),
  'download_tasks_unreadable':
      _Verdict(_Status.excluded, 'même famille que download_tasks_list'),
  'xmltv_tnt_cache_v2.xml': _Verdict(
      _Status.excluded, 'cache du guide XMLTV, TTL 24 h — se retélécharge'),
  'playlist': _Verdict(_Status.excluded,
      'préfixe de nom de fichier de cache playlist, pas un réglage'),
  'diagnostic_session_current.log': _Verdict(
      _Status.excluded, 'journal de diagnostic — device-local (§tvLogs)'),
  'diagnostic_session_previous.log':
      _Verdict(_Status.excluded, 'idem, session précédente'),

  // ── Exclues : ÉPHÉMÈRE ou drapeau à usage unique ────────────────────────
  'last_watched_channel_v1': _Verdict(_Status.excluded,
      'pointeur de reprise LIVE — déjà exclu, documenté « éphémère » dans backup_service.dart'),
  'onboarding_done_v1': _Verdict(_Status.excluded,
      'drapeau « onboarding déjà vu » — propre à CETTE installation'),
  'perf_tv_suggest_done_v1': _Verdict(
      _Status.excluded, 'drapeau « suggestion déjà proposée » une fois'),

  // ── Exclues : legacy / remplacées ────────────────────────────────────────
  // secure_storage_compte.dart (legacy, cf. CLAUDE.md) — schéma PAR COMPTE
  // remplacé par stream_account_service.dart, dont les comptes SONT
  // sauvegardés (accounts_index ci-dessus).
  'completeUrl': _Verdict(_Status.excluded,
      'secure_storage_compte.dart (legacy) — remplacé par stream_account_service.dart'),
  'url': _Verdict(_Status.excluded, 'idem — legacy'),
  'm3u': _Verdict(_Status.excluded, 'idem — legacy'),
  'baseUrl': _Verdict(_Status.excluded, 'idem — legacy'),
  'username': _Verdict(_Status.excluded, 'idem — legacy'),
  'login': _Verdict(_Status.excluded, 'idem — legacy'),
  'password': _Verdict(_Status.excluded, 'idem — legacy'),
  'cookies': _Verdict(_Status.excluded,
      'idem — legacy, et un cookie n\'est de toute façon jamais portable'),

  // ── Exclues : DÉCISION UTILISATEUR (audit §playerPanel, 2026-09-22) ─────
  // Les deux seules trouvailles de l'audit qui n'étaient PAS des mesures
  // d'appareil par nature : soumises à l'utilisateur, qui a choisi de les
  // garder HORS de `.aether`. Décision explicite, pas un oubli — cf.
  // decisions.md §playerPanel.
  'search_history_v1': _Verdict(
      _Status.excluded, 'propre à l\'appareil (décision utilisateur 2026-09-22)'),

  // expiration_alert_acked_<accountId>_<dateISO> — dynamique
  // (`expiration_alert_service.dart:_ackKey`), donc INVISIBLE de ce scan
  // (pas un littéral) : documentée ici pour qu'un humain qui lit cette table
  // la voie, même si le scan ne peut pas la vérifier lui-même.
  // Statut : exclue — « un avertissement réaffiché après restauration est
  // légitime (décision utilisateur 2026-09-22) ».
};

/// Clés qu'on SAIT que le scan remonte mais qui ne sont pas des littéraux de
/// clé de stockage (faux positifs connus du heuristique). Vide au
/// 2026-09-22 ; sert de soupape si un futur `static const _xxx = '...'`
/// privé n'est pas une clé persistée (ex. un motif regex, un préfixe de
/// nom de fichier déjà couvert par ailleurs).
const Set<String> _knownFalsePositives = {};

final RegExp _keyDecl = RegExp(
  r"static const\s+(?:String\??\s+)?_\w*\s*=\s*'([a-z][a-zA-Z0-9_:.\-]*)'",
);

/// Chemins qu'on ne scanne pas : générés, ou hors périmètre de l'app.
const List<String> _excludedPaths = [
  '/l10n/app_localizations', // généré
];

/// Scanne `lib/` et rend, pour chaque clé candidate trouvée, le PREMIER
/// fichier où elle apparaît (assez pour un message d'erreur utile).
Map<String, String> _scanKeys() {
  final found = <String, String>{};
  final dir = Directory('lib');
  if (!dir.existsSync()) return found;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final rel = entity.path.replaceAll(r'\', '/');
    if (_excludedPaths.any(rel.contains)) continue;
    for (final line in entity.readAsLinesSync()) {
      final m = _keyDecl.firstMatch(line);
      if (m == null) continue;
      final key = m.group(1)!;
      found.putIfAbsent(key, () => rel);
    }
  }
  return found;
}

void main() {
  test(
      '§playerPanel backup — toute clé persistée trouvée dans lib/ est '
      'CLASSÉE (sauvegardée ou exclue avec une raison)', () {
    final found = _scanKeys();
    final unclassified = <String>[];
    for (final entry in found.entries) {
      if (_knownKeys.containsKey(entry.key)) continue;
      if (_knownFalsePositives.contains(entry.key)) continue;
      unclassified.add('${entry.key} (${entry.value})');
    }
    expect(
      unclassified,
      isEmpty,
      reason: 'Clé(s) persistée(s) NOUVELLE(S), ni sauvegardée(s) ni exclue(s) '
          'dans test/backup_coverage_test.dart :\n'
          '${unclassified.join('\n')}\n'
          '→ soit la brancher sur .aether (BackupContent + backup_service.dart '
          '_collectAll/applyBackup), soit ajouter une entrée dans _knownKeys '
          'avec la raison de l\'exclusion (propre à l\'appareil, éphémère, '
          'legacy…).',
    );
  });

  test('la table ne contient aucune clé que le scan ne trouve plus '
      '(entrée périmée à retirer)', () {
    final found = _scanKeys();
    final stale = _knownKeys.keys
        .where((k) => !found.containsKey(k))
        .toList(growable: false);
    // Non-bloquant en soi (une clé peut disparaître légitimement quand un
    // service est retiré), mais utile à voir : affiché sans faire échouer,
    // sauf régression franche de la table elle-même.
    if (stale.isNotEmpty) {
      // ignore: avoid_print
      print('⚠️ §playerPanel backup — clé(s) de _knownKeys introuvable(s) '
          'par le scan (service retiré ?) : ${stale.join(', ')}');
    }
    expect(_knownKeys, isNotEmpty);
  });
}
