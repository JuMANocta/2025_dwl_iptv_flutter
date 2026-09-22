import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/settings/perf_config.dart';
import 'hidden_regions_service.dart';
import 'visual_language_service.dart';
import '../../core/utils/user_error.dart' show UserFacingException;
import '../../core/settings/performance_settings_service.dart';
import '../../core/themes/app_theme_config.dart';
import '../../core/themes/saved_themes_service.dart';
import '../../core/themes/theme_service.dart';
import '../../feature/player/video_fit.dart';
import '../../feature/player/video_stats.dart';
import '../models/stream_account.dart';
import 'favorites_service.dart';
import 'parsed_playlist_service.dart';
import 'stream_account_service.dart';
import 'subtitle_api_service.dart';
import 'tmdb_api_service.dart';
import 'tmdb_poster_cache.dart';
import 'tmdb_service.dart';
import 'track_preferences_service.dart';
import 'watch_progress_service.dart';
import '../../l10n/l10n_ext.dart';

/// Sauvegarde / restauration de la configuration (§10).
///
/// **Format du fichier `.aether`** (binaire, AES-256-GCM + PBKDF2-SHA256) :
/// ```
///   [4 bytes "AETH"] [1 byte version=1]
///   [16 bytes salt]  [12 bytes nonce]
///   [N bytes ciphertext]
///   [16 bytes mac (auth tag GCM)]
/// ```
/// Le `mac` est validé au déchiffrement : un mot de passe incorrect ou un
/// fichier altéré lève une `FormatException`.
///
/// **Contenu sauvegardé** : comptes IPTV, clé TMDB, clé du fournisseur de
/// sous-titres en ligne, thème (+ thèmes enregistrés), réglages
/// d'optimisation, langues/régions masquées, langue des visuels, mémoire des
/// pistes audio/sous-titres, format d'image et affichage des infos vidéo du
/// lecteur, favoris, progression de lecture.
///
/// **Exclus, propre à l'APPAREIL ou au FLUX** (jamais portable d'un appareil
/// à l'autre) : capacités mesurées du décodeur, qualité mesurée, santé de
/// lecture (blocages par abonnement), caches (affiches TMDB, playlists),
/// jeton de la console web. **Exclus, ÉPHÉMÈRE** : dernière chaîne regardée.
/// **Exclus, VOLUMINEUX** : téléchargements. **Décidé avec l'utilisateur**
/// (audit §playerPanel, 2026-09-22) : historique de recherche — propre à
/// l'appareil ; alertes d'expiration déjà acquittées — un avertissement
/// réaffiché après restauration est légitime (le compte reste proche de
/// l'échéance).
///
/// **Stockage** : `/storage/emulated/0/Download/AetherStream/backup_*.aether`
/// via `media_store_plus`. Survit à l'uninstall, visible dans le file manager.

/// §langRegion — Lit une liste de chaînes sans jamais lever : tout ce qui
/// n'est pas une liste rend `null`, et les éléments non-textuels sont écartés.
List<String>? _readStringList(Object? raw) {
  if (raw is! List) return null;
  return raw.whereType<String>().toList(growable: false);
}

class BackupContent {
  final String appVersion;
  final DateTime exportedAt;
  final List<Map<String, dynamic>> accounts;
  final String? activeAccountId;
  final String? tmdbKey;
  final Map<String, dynamic>? theme;

  /// §themeStudio — Les thèmes ENREGISTRÉS (« Mes thèmes »), chacun
  /// `{n: nom, c: {…}}`. ⚠️ Même règle que [hiddenRegions] : `null` (clé
  /// absente d'une sauvegarde antérieure) ne veut pas dire « aucun » — on ne
  /// touche alors PAS à la liste locale de la cible. Une liste VIDE, elle, est
  /// un choix explicite.
  final List<Map<String, dynamic>>? savedThemes;

  /// §perfSettings — réglages d'optimisation (null sur les vieux backups).
  final Map<String, dynamic>? perf;

  /// §langRegion — Langues / régions masquées. ⚠️ **`null` et liste vide ne
  /// veulent pas dire la même chose et se traitent pourtant pareil** :
  /// absent d'un vieux fichier comme explicitement vide, on ne coche rien.
  /// Une sauvegarde antérieure à ce champ ne doit JAMAIS faire échouer une
  /// restauration ni inventer un masquage.
  final List<String>? hiddenRegions;

  /// §posterLang — Langue des visuels TMDB (`auto|fr|en|original`).
  /// Même règle que [hiddenRegions] : `null` sur une sauvegarde antérieure à
  /// ce champ → on ne touche PAS au réglage local de la cible.
  final String? visualLanguage;

  /// §playerPanel backup (audit du 2026-09-22) — Clé du fournisseur de
  /// sous-titres en ligne (Wyzie), même mécanisme que [tmdbKey] : `''` =
  /// choix explicite « pas de clé » (efface à la restauration), `null` = clé
  /// ABSENTE du fichier (sauvegarde antérieure à ce champ, on ne touche à
  /// rien). ⚠️ Contrairement à [tmdbKey], l'export normalise toujours en
  /// chaîne (jamais `null`) : c'est ce qui rend les deux cas distinguables.
  final String? subtitleApiKey;

  /// §playerPanel backup — Mémoire des pistes (§trackMemory), `{'audio': …,
  /// 'subtitle': …}`. Le champ EXTÉRIEUR suit la règle habituelle (`null` =
  /// sauvegarde antérieure, on ne touche à rien) ; une fois présent, chacune
  /// de ses deux clés s'applique SÉPARÉMENT — `null` explicite = « automatique »
  /// (un vrai choix, à restaurer), une valeur non reconnue = ignorée (la
  /// mémoire locale de cette piste n'est pas touchée). ⛔ Restaurées SANS
  /// validation, elles pourraient réintroduire un numéro de piste ou une
  /// langue en sous-titre (R43) : `applyBackup` repasse par
  /// `TrackPreferencesService.languageKeyFor`/`isValidSubtitleMemory`.
  final Map<String, dynamic>? trackPrefs;

  /// §playerPanel backup — Format d'image du lecteur (`VideoFitMode.name`).
  /// Même règle que [hiddenRegions] : `null` = absent d'une sauvegarde
  /// antérieure ; un nom inconnu (sauvegarde d'une version plus récente) est
  /// ignoré à la restauration plutôt que de faire échouer quoi que ce soit.
  final String? videoFit;

  /// §playerPanel backup — « Infos vidéo » affichées ou non pendant la
  /// lecture. `null` = absent d'une sauvegarde antérieure à ce champ.
  final bool? videoStatsEnabled;
  final List<String> favorites;
  final Map<String, Map<String, dynamic>> watchProgress;

  const BackupContent({
    required this.appVersion,
    required this.exportedAt,
    required this.accounts,
    required this.activeAccountId,
    required this.tmdbKey,
    required this.theme,
    this.savedThemes,
    this.perf,
    this.hiddenRegions,
    this.visualLanguage,
    this.subtitleApiKey,
    this.trackPrefs,
    this.videoFit,
    this.videoStatsEnabled,
    required this.favorites,
    required this.watchProgress,
  });

  Map<String, dynamic> toJson() => {
        'appVersion': appVersion,
        'exportedAt': exportedAt.toIso8601String(),
        'accounts': accounts,
        'activeAccountId': activeAccountId,
        'tmdbKey': tmdbKey,
        'theme': theme,
        'savedThemes': savedThemes,
        'perf': perf,
        'hiddenRegions': hiddenRegions,
        'visualLanguage': visualLanguage,
        'subtitleApiKey': subtitleApiKey,
        'trackPrefs': trackPrefs,
        'videoFit': videoFit,
        'videoStatsEnabled': videoStatsEnabled,
        'favorites': favorites,
        'watchProgress': watchProgress,
      };

  factory BackupContent.fromJson(Map<String, dynamic> j) => BackupContent(
        appVersion: j['appVersion'] as String? ?? '?',
        exportedAt: DateTime.tryParse(j['exportedAt'] as String? ?? '') ??
            DateTime.now(),
        // revue 2026-09-11, D1B-05 — `cast` était PARESSEUX : un élément qui
        // n'est pas un objet levait au moment de l'itérer, en pleine
        // restauration. Chaque élément est désormais converti ici ; un
        // élément illisible devient un objet vide, qui échouera à la lecture
        // du compte et sera COMPTÉ comme illisible (cf. `applyBackup`) au lieu
        // de disparaître. ⚠️ Un champ qui n'est pas une liste lève toujours,
        // comme avant : la sauvegarde est alors refusée avant tout effacement.
        accounts: [
          for (final Object? e in (j['accounts'] as List?) ?? const [])
            e is Map ? e.cast<String, dynamic>() : <String, dynamic>{},
        ],
        activeAccountId: j['activeAccountId'] as String?,
        tmdbKey: j['tmdbKey'] as String?,
        theme: j['theme'] as Map<String, dynamic>?,
        // §themeStudio — ⚠️ Jamais `as List?` : il LÈVE sur une chaîne, et une
        // sauvegarde bricolée à la main ferait échouer toute la restauration
        // pour un accessoire (même piège que `hiddenRegions`). Le tri des
        // entrées illisibles est fait plus loin, par `SavedThemesService`.
        savedThemes: j['savedThemes'] is List
            ? [
                for (final Object? e in j['savedThemes'] as List)
                  if (e is Map) e.cast<String, dynamic>()
              ]
            : null,
        perf: j['perf'] as Map<String, dynamic>?,
        // ⚠️ Tolérant pour de vrai : un `as List?` LÈVE sur une chaîne. On
        // teste le type au lieu de le supposer — champ absent, nul ou
        // inattendu donne `null`, donc « rien de coché », jamais une
        // restauration qui échoue pour un champ accessoire.
        hiddenRegions: _readStringList(j['hiddenRegions']),
        visualLanguage: j['visualLanguage'] as String?,
        // §playerPanel backup — `as String?` suffit : l'export normalise
        // toujours en chaîne (jamais `null`), donc `null` ici ne peut venir
        // que d'une clé ABSENTE (sauvegarde antérieure à ce champ).
        subtitleApiKey: j['subtitleApiKey'] is String
            ? j['subtitleApiKey'] as String
            : null,
        // ⚠️ Jamais `as Map<String, dynamic>?` direct sur une valeur qui
        // pourrait être une chaîne (même piège que `hiddenRegions`) : on
        // teste le type au lieu de le supposer.
        trackPrefs: j['trackPrefs'] is Map
            ? (j['trackPrefs'] as Map).cast<String, dynamic>()
            : null,
        // Type testé, jamais supposé : un champ accessoire mal typé ne doit
        // pas faire échouer toute la restauration (il vaut alors `null`).
        videoFit: j['videoFit'] is String ? j['videoFit'] as String : null,
        videoStatsEnabled: j['videoStatsEnabled'] is bool
            ? j['videoStatsEnabled'] as bool
            : null,
        favorites: (j['favorites'] as List?)?.cast<String>() ?? const [],
        watchProgress: ((j['watchProgress'] as Map?)
                ?.cast<String, Map<String, dynamic>>()) ??
            const {},
      );

  /// Résumé court pour les dialogs (affiché à l'utilisateur).
  String summary() {
    final parts = <String>[];
    if (accounts.isNotEmpty) {
      parts.add(L10n.current.bkPartAccounts(accounts.length));
    }
    if ((tmdbKey ?? '').isNotEmpty) parts.add(L10n.current.bkPartTmdbKey);
    if ((subtitleApiKey ?? '').isNotEmpty) {
      parts.add(L10n.current.bkPartSubtitleKey);
    }
    if (theme != null) parts.add(L10n.current.bkPartTheme);
    final int saved = savedThemes?.length ?? 0;
    if (saved > 0) parts.add(L10n.current.bkPartSavedThemes(saved));
    if (perf != null) parts.add(L10n.current.bkPartOptimization);
    final int regions = hiddenRegions?.length ?? 0;
    if (regions > 0) {
      parts.add(L10n.current.bkPartHiddenRegions(regions));
    }
    // §playerPanel backup — Une seule ligne de résumé pour les deux réglages
    // du lecteur : personne ne veut lire « Format d'image » ET « Infos
    // vidéo » séparément dans un résumé qui reste une phrase.
    if (videoFit != null || videoStatsEnabled != null) {
      parts.add(L10n.current.bkPartPlayerSettings);
    }
    final hasTrackMemory =
        trackPrefs != null &&
        (trackPrefs!['audio'] != null || trackPrefs!['subtitle'] != null);
    if (hasTrackMemory) parts.add(L10n.current.bkPartTrackMemory);
    if (favorites.isNotEmpty) {
      parts.add(L10n.current.bkPartFavorites(favorites.length));
    }
    if (watchProgress.isNotEmpty) {
      parts.add(L10n.current.bkPartProgress(watchProgress.length));
    }
    if (parts.isEmpty) return L10n.current.bkEmpty;
    return parts.join(' · ');
  }
}

class BackupService {
  static const List<int> _magic = [0x41, 0x45, 0x54, 0x48]; // "AETH"
  static const int _formatVersion = 1;
  static const int _saltLen = 16;
  static const int _nonceLen = 12;
  static const int _macLen = 16;
  static const int _headerLen = 4 + 1 + _saltLen + _nonceLen;
  // PBKDF2 — 100k itérations = ~250 ms sur smartphone moderne. Bon compromis
  // sécurité / latence (l'utilisateur ne saisit son mot de passe qu'à
  // l'export / import, pas à chaque opération).
  static const int _pbkdf2Iterations = 100000;

  static final Random _rng = Random.secure();

  // ── EXPORT ────────────────────────────────────────────────────────────────

  /// Collecte toute la configuration, la chiffre avec [password], et sauvegarde
  /// le fichier `.aether` dans `Download/AetherStream/`. Retourne le nom du
  /// fichier généré (le chemin complet dépend du device).
  static Future<String> exportAll(String password) async {
    if (password.isEmpty) {
      throw ArgumentError(L10n.current.bkPasswordEmptyError);
    }
    debugPrint('📤 BackupService: collecte des données…');
    final content = await _collectAll();
    final jsonStr = jsonEncode(content.toJson());
    final encrypted = await _encrypt(utf8.encode(jsonStr), password);

    // Écrit d'abord dans le cache privé.
    final cacheDir = await getTemporaryDirectory();
    final fileName = _buildBackupFileName();
    final tempPath = '${cacheDir.path}/$fileName';
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(encrypted, flush: true);

    // Déplace vers Download/AetherStream/ via MediaStore (le sous-dossier
    // "AetherStream" est défini globalement par MediaStore.appFolder dans main.dart).
    try {
      final mediaStore = MediaStore();
      await mediaStore.saveFile(
        tempFilePath: tempPath,
        dirType: DirType.download,
        dirName: DirName.download,
        relativePath: null,
      );
    } catch (e) {
      debugPrint(
          '💀 BackupService: MediaStore a échoué — $e (le fichier reste en cache privé).');
      // On laisse le fichier dans le cache plutôt que de le perdre.
      rethrow;
    }

    // Le déplacement a fait une copie côté MediaStore → on peut effacer le temp.
    try {
      if (await tempFile.exists()) await tempFile.delete();
    } catch (_) {}

    debugPrint('✅ BackupService: export terminé — $fileName');
    return fileName;
  }

  /// Variante de [exportAll] qui retourne directement les octets chiffrés
  /// `.aether` SANS écrire de fichier (utilisée par la console web pour
  /// proposer le téléchargement au navigateur). Retourne aussi le nom suggéré.
  static Future<({String fileName, Uint8List bytes})> exportToBytes(
      String password) async {
    if (password.isEmpty) {
      throw ArgumentError(L10n.current.bkPasswordEmptyError);
    }
    final content = await _collectAll();
    final jsonStr = jsonEncode(content.toJson());
    final encrypted = await _encrypt(utf8.encode(jsonStr), password);
    return (fileName: _buildBackupFileName(), bytes: encrypted);
  }

  // ── IMPORT ────────────────────────────────────────────────────────────────

  /// Comme [readBackup] mais à partir d'octets en mémoire (upload console web).
  static Future<BackupContent> readBackupBytes(
      Uint8List bytes, String password) async {
    final plain = await _decrypt(bytes, password);
    final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    return BackupContent.fromJson(json);
  }

  /// Lit + décrypte un fichier `.aether`. Retourne le contenu sans l'appliquer
  /// (utile pour afficher un résumé à l'utilisateur avant confirmation).
  ///
  /// Throws :
  ///   - [FormatException] si le fichier n'est pas un `.aether` valide ou si
  ///     le mot de passe est incorrect (le MAC GCM ne valide pas).
  static Future<BackupContent> readBackup(
      String filePath, String password) async {
    final bytes = await File(filePath).readAsBytes();
    final plain = await _decrypt(bytes, password);
    final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    return BackupContent.fromJson(json);
  }

  /// revue 2026-09-11, D1B-05 — Phase 1 de la restauration : lit TOUS les
  /// comptes d'une sauvegarde sans rien écrire. Un compte illisible est écarté
  /// et journalisé ; c'est à l'appelant de décider si « aucun lisible » doit
  /// arrêter la restauration (cf. [applyBackup]).
  @visibleForTesting
  static List<StreamAccount> readAccounts(List<Map<String, dynamic>> raw) {
    final List<StreamAccount> out = <StreamAccount>[];
    for (final Map<String, dynamic> json in raw) {
      try {
        out.add(StreamAccount.fromJson(json));
      } catch (e) {
        debugPrint('⚠️ Compte ignoré (parse fail) — $e');
      }
    }
    return out;
  }

  /// Applique un [BackupContent] en ÉCRASANT l'état courant.
  /// L'appelant DOIT avoir confirmé l'action côté UI (dialog de confirmation).
  static Future<void> applyBackup(BackupContent content) async {
    debugPrint('📥 BackupService: application — ${content.summary()}');

    // 1. Comptes IPTV — wipe puis re-create, en DEUX phases.
    //
    // §acctPurge + §restoreOnboarding — revue 2026-09-11, D1B-05 — L'ordre
    // était « tout effacer, puis relire » : `deleteAccount` purge aussi les
    // FICHIERS du compte (§acctPurge), et chaque échec de lecture était avalé
    // ensuite. Une sauvegarde mal formée — ou écrite par une version future
    // (format v1 identique, donc acceptée) — effaçait tous les comptes, n'en
    // recréait aucun, et l'écran annonçait une restauration RÉUSSIE : les
    // identifiants étaient perdus si le fichier source n'était plus là.
    // Phase 1 : TOUT lire. Phase 2 seulement : effacer puis écrire.
    final List<StreamAccount> incoming = readAccounts(content.accounts);
    if (content.accounts.isNotEmpty && incoming.isEmpty) {
      debugPrint('🛑 D1B-05 : aucun des ${content.accounts.length} compte(s) de la sauvegarde n\'est lisible → restauration refusée AVANT tout effacement.');
      throw UserFacingException(L10n.current.bkNoReadableAccount);
    }
    final existing = await StreamAccountService.listAccounts();
    for (final acc in existing) {
      await StreamAccountService.deleteAccount(acc.id);
    }
    for (final acc in incoming) {
      try {
        await StreamAccountService.saveAccount(acc);
      } catch (e) {
        debugPrint('⚠️ Compte non enregistré (${acc.label}) — $e');
      }
    }
    if ((content.activeAccountId ?? '').isNotEmpty) {
      try {
        await StreamAccountService.setCurrentAccount(content.activeAccountId!);
      } catch (e) {
        debugPrint('⚠️ Compte actif non restauré — $e');
      }
    }

    // 2. Clé TMDB
    final String? previousTmdbKey = await TmdbApiService.getApiKey();
    if ((content.tmdbKey ?? '').isNotEmpty) {
      await TmdbApiService.saveApiKey(content.tmdbKey!);
      // Revue 2026-09-11, D1B-01 — une clé NOUVELLE : les titres mémorisés
      // « introuvables » ont pu l'être sans clé valide (onboarding parcouru
      // avant la restauration) ; on les laisse se rechercher à nouveau.
      if (previousTmdbKey != content.tmdbKey) {
        await TmdbPosterCache.forgetNegatives();
      }
    } else {
      await TmdbApiService.deleteApiKey();
    }
    TmdbService.resetInstance();

    // 2b. §playerPanel backup — Clé du fournisseur de sous-titres en ligne,
    // MÊME schéma que la clé TMDB ci-dessus : `null` = clé ABSENTE du fichier
    // (sauvegarde antérieure à ce champ, on ne touche à rien) ; `''` ou une
    // clé = un choix EXPLICITE (efface ou remplace). Accessoire : son échec
    // ne doit jamais faire capoter le reste de la restauration.
    if (content.subtitleApiKey != null) {
      try {
        if (content.subtitleApiKey!.isNotEmpty) {
          await SubtitleApiService.saveApiKey(content.subtitleApiKey!);
        } else {
          await SubtitleApiService.deleteApiKey();
        }
      } catch (e) {
        debugPrint('⚠️ Clé des sous-titres en ligne ignorée (restauration) — $e');
      }
    }

    // 3. Thème
    if (content.theme != null) {
      try {
        final cfg = AppThemeConfig.fromJson(content.theme!);
        await ThemeService.save(cfg);
      } catch (e) {
        debugPrint('⚠️ Thème ignoré (parse fail) — $e');
      }
    }
    // 3a. §themeStudio — « Mes thèmes ». ⚠️ Dans le MÊME `try` d'esprit que
    // le thème : un fichier bricolé ne doit pas faire échouer la restauration.
    // ⚠️ `null` (clé absente) ≠ liste vide : on ne touche à la liste locale
    // que si la sauvegarde en portait une.
    if (content.savedThemes != null) {
      try {
        await SavedThemesService.replaceAll(
            SavedThemesService.fromList(content.savedThemes));
      } catch (e) {
        debugPrint('⚠️ Thèmes enregistrés ignorés (parse fail) — $e');
      }
    }

    // 3b. §perfSettings — Réglages d'optimisation (absents des vieux backups).
    if (content.perf != null) {
      try {
        await PerformanceSettingsService.save(
            PerfConfig.fromJson(content.perf!));
      } catch (e) {
        debugPrint('⚠️ Réglages optimisation ignorés (parse fail) — $e');
      }
    }

    // 3c. §langRegion — Langues / régions masquées. Absent d'un vieux
    // fichier : on ne touche à rien (l'utilisateur garde son réglage local)
    // plutôt que d'imposer un masquage vide venu de nulle part.
    final List<String>? regions = content.hiddenRegions;
    if (regions != null) {
      try {
        await HiddenRegionsService.setHidden(regions.toSet());
      } catch (e) {
        debugPrint('⚠️ Langues/régions ignorées (restauration) — $e');
      }
    }

    // 3d. §posterLang — Langue des visuels. Même règle que ci-dessus : `null`
    // (sauvegarde antérieure au champ) ou code inconnu → on ne touche pas au
    // réglage local, plutôt que d'imposer un défaut venu de nulle part.
    final VisualLanguage? visual =
        VisualLanguageService.fromCode(content.visualLanguage);
    if (visual != null) {
      try {
        await VisualLanguageService.set(visual);
      } catch (e) {
        debugPrint('⚠️ Langue des visuels ignorée (restauration) — $e');
      }
    }

    // 3e. §playerPanel backup — Mémoire des pistes (§trackMemory). Le champ
    // EXTÉRIEUR absent = sauvegarde antérieure, on ne touche à rien. Présent,
    // ses deux clés s'appliquent CHACUNE séparément, et il faut distinguer
    // trois cas — même règle que `visualLanguage` (« un code inconnu → on ne
    // touche pas au réglage local ») étendue à un champ à deux valeurs :
    //   - `null` explicite (JSON) → « automatique », un choix réel → appliqué.
    //   - une valeur VALIDE (`languageKeyFor`/`isValidSubtitleMemory`) → appliquée.
    //   - une valeur qui ne passe NI l'un ni l'autre (fichier bricolé, ou une
    //     forme future que cette version ne connaît pas) → ignorée, la
    //     mémoire locale de CETTE piste n'est pas touchée (⛔ jamais une valeur
    //     brute non validée, R43 : ni un numéro de piste, ni une langue en
    //     sous-titre).
    final Map<String, dynamic>? trackPrefs = content.trackPrefs;
    if (trackPrefs != null) {
      try {
        final Object? rawAudio = trackPrefs['audio'];
        if (rawAudio == null) {
          await TrackPreferencesService.setAudio(null);
        } else if (rawAudio is String) {
          final String? key = TrackPreferencesService.languageKeyFor(rawAudio);
          if (key != null) await TrackPreferencesService.setAudio(key);
        }
        final Object? rawSub = trackPrefs['subtitle'];
        if (rawSub == null) {
          await TrackPreferencesService.setSubtitle(null);
        } else if (rawSub is String &&
            TrackPreferencesService.isValidSubtitleMemory(rawSub)) {
          await TrackPreferencesService.setSubtitle(rawSub);
        }
      } catch (e) {
        debugPrint('⚠️ Mémoire des pistes ignorée (restauration) — $e');
      }
    }

    // 3f. §playerPanel backup — Format d'image du lecteur. Nom inconnu (ou
    // champ absent d'un vieux fichier) → `fromName` rend `null`, on ne touche
    // à rien.
    final VideoFitMode? fit = VideoFitPreference.fromName(content.videoFit);
    if (fit != null) {
      try {
        VideoFitPreference.set(fit);
      } catch (e) {
        debugPrint('⚠️ Format d\'image ignoré (restauration) — $e');
      }
    }

    // 3g. §playerPanel backup — « Infos vidéo » affichées ou non.
    if (content.videoStatsEnabled != null) {
      try {
        VideoStatsPreference.set(content.videoStatsEnabled!);
      } catch (e) {
        debugPrint('⚠️ Réglage des infos vidéo ignoré (restauration) — $e');
      }
    }

    // 4. Favoris
    await FavoritesService.replaceAll(content.favorites);

    // 5. Progressions de lecture
    final wp = <String, WatchProgress>{};
    for (final entry in content.watchProgress.entries) {
      try {
        wp[entry.key] = WatchProgress.fromJson(entry.key, entry.value);
      } catch (_) {}
    }
    await WatchProgressService.replaceAll(wp);

    // 6. Hub mémoire playlist : on invalide tout. Les playlists seront
    //    re-téléchargées au prochain switch / démarrage.
    final newAccounts = await StreamAccountService.listAccounts();
    for (final acc in newAccounts) {
      ParsedPlaylistService.invalidate(acc.id);
    }

    debugPrint('✅ BackupService: restauration terminée.');
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  static Future<BackupContent> _collectAll() async {
    final accounts = await StreamAccountService.listAccounts();
    final currentAccount = await StreamAccountService.getCurrentAccount();
    final tmdbKey = await TmdbApiService.getApiKey();
    // §playerPanel backup — Toujours normalisée en chaîne (jamais `null`) :
    // c'est ce qui permet à `fromJson` de distinguer « pas de clé » (``, un
    // choix) de « champ absent » (`null`, une vieille sauvegarde) à la
    // lecture d'un fichier plus ancien que ce champ.
    final subtitleApiKey = (await SubtitleApiService.getApiKey()) ?? '';
    final theme = ThemeService.config.value;
    // §themeStudio — ⚠️ Sans ça, exporter sans avoir ouvert la page des thèmes
    // depuis le démarrage écrirait une liste VIDE dans le `.aether`, ce qui
    // EFFACERAIT les thèmes enregistrés à la restauration. Le chargement est
    // idempotent (un drapeau), il ne coûte rien aux exports suivants.
    await SavedThemesService.load();
    final favorites = FavoritesService.all.toList();
    final wp = WatchProgressService.all;
    final wpMap = <String, Map<String, dynamic>>{
      for (final p in wp) p.url: p.toJson(),
    };

    final info = await PackageInfo.fromPlatform();

    return BackupContent(
      appVersion: '${info.version}+${info.buildNumber}',
      exportedAt: DateTime.now(),
      accounts: accounts.map((a) => a.toJson()).toList(),
      activeAccountId: currentAccount?.id,
      tmdbKey: tmdbKey,
      theme: theme.toJson(),
      savedThemes: SavedThemesService.toJsonList(SavedThemesService.themes.value),
      perf: PerformanceSettingsService.config.value.toJson(),
      hiddenRegions: HiddenRegionsService.hidden.toList(growable: false),
      visualLanguage: VisualLanguageService.value.name,
      subtitleApiKey: subtitleApiKey,
      // §playerPanel backup — `TrackPreferencesService.init()` a déjà tourné
      // au boot (`main.dart`) : lecture SYNCHRONE des deux champs statiques,
      // comme le fait le lecteur lui-même.
      trackPrefs: <String, dynamic>{
        'audio': TrackPreferencesService.audio,
        'subtitle': TrackPreferencesService.subtitle,
      },
      videoFit: VideoFitPreference.current.name,
      videoStatsEnabled: VideoStatsPreference.enabled,
      favorites: favorites,
      watchProgress: wpMap,
    );
  }

  static String _buildBackupFileName() {
    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    return 'backup_'
        '${now.year}-${pad(now.month)}-${pad(now.day)}_'
        '${pad(now.hour)}${pad(now.minute)}.aether';
  }

  // ── Crypto ────────────────────────────────────────────────────────────────

  static Future<Uint8List> _encrypt(List<int> plain, String password) async {
    final salt = _randomBytes(_saltLen);
    final key = await _deriveKey(password, salt);
    final nonce = _randomBytes(_nonceLen);
    final algo = AesGcm.with256bits();
    final box = await algo.encrypt(plain, secretKey: key, nonce: nonce);
    final out = BytesBuilder()
      ..add(_magic)
      ..addByte(_formatVersion)
      ..add(salt)
      ..add(nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  static Future<List<int>> _decrypt(Uint8List bytes, String password) async {
    // §userErrorOwn — [UserFacingException] et non `FormatException` : ces
    // messages sont écrits pour l'utilisateur, et `describeError` traduisait
    // toute `FormatException` par « Réponse illisible du serveur (format
    // inattendu) » — une phrase qui parle d'un SERVEUR alors qu'il s'agit
    // d'un fichier local et, le plus souvent, d'un mot de passe mal tapé.
    if (bytes.length < _headerLen + _macLen) {
      throw UserFacingException(
          L10n.current.bkFileTooShort);
    }
    for (int i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw UserFacingException(
            L10n.current.bkNotAnAetherFile);
      }
    }
    final version = bytes[4];
    if (version != _formatVersion) {
      throw UserFacingException(
          L10n.current.bkNewerVersion);
    }
    final salt = bytes.sublist(5, 5 + _saltLen);
    final nonce = bytes.sublist(5 + _saltLen, 5 + _saltLen + _nonceLen);
    final macStart = bytes.length - _macLen;
    final cipherText = bytes.sublist(_headerLen, macStart);
    final macBytes = bytes.sublist(macStart);

    final key = await _deriveKey(password, salt);
    final algo = AesGcm.with256bits();
    try {
      return await algo.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: key,
      );
    } on SecretBoxAuthenticationError {
      // Le cas de LOIN le plus fréquent : le MAC GCM ne valide pas parce que
      // le mot de passe est faux. Le dire en premier, et sans jargon.
      throw UserFacingException(
          L10n.current.bkWrongPassword);
    }
  }

  static Future<SecretKey> _deriveKey(String password, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  static List<int> _randomBytes(int n) =>
      List<int>.generate(n, (_) => _rng.nextInt(256));
}
