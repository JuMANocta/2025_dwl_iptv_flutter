import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:dpad/dpad.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/themes/theme_service.dart';
import '../../core/themes/colors.dart';
import '../../core/themes/light_palette.dart';
import '../../core/utils/platform_tv.dart';
import '../../core/utils/formatters.dart' show formatCountFor;
import '../../data/services/favorites_service.dart';
import '../../data/services/tmdb_service.dart';
import '../../data/services/tmdb_api_service.dart';
import '../settings/tmdb_key_page.dart';
import '../../data/services/parsed_playlist_service.dart';
import '../../data/services/stream_account_service.dart';
import '../../data/services/watch_progress_service.dart';
import '../../data/services/load_failure.dart';
import '../../data/services/xtream_api_service.dart';
import '../../data/models/quality_scale.dart';
import '../../data/services/measured_quality_service.dart';
import '../../core/utils/app_snackbar.dart';
import '../../widgets/confirm_or_undo.dart';
import '../../data/models/media_model.dart';
import '../player/player_page.dart';
import '../player/player_media.dart';
import '../player/launch_playback.dart';
import '../downloads/logic/download_initiator.dart';
import '../../data/services/download_manager_service.dart'
    show DownloadManagerService;
import '../../data/models/download_task.dart' show DownloadTask;
import '../../data/models/m3u_entry.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/tv/focusable_chip.dart';
import '../../widgets/aether_image.dart';
import '../../widgets/playlist_search_sheet.dart';
import '../../widgets/tv/focusable_card.dart';
import '../../widgets/tv/section_beacon.dart';
import 'actor_details_page.dart';
import 'm3u_filter.dart';
import 'details_facts.dart';
import 'details_header_image.dart';
import 'details_versions.dart';
import 'series_stub.dart';
import '../../widgets/playback_gate.dart';
import '../../widgets/media_chips.dart' show buildDownloadName;
import 'version_dedup.dart';
import 'episodes_failure.dart';
import '../../l10n/l10n_ext.dart';

/// Revue 2026-09-11, D4A-06 — un stub de série interrogé : le résultat du
/// service, et l'échec constaté par la fiche avant tout appel (sinon `null`).
typedef _StubOutcome = ({XtreamEpisodesResult r, EpisodesFailure? local});

Color _qualityColor(String? quality) {
  return switch (quality) {
    '4K'  => kQuality4K,
    'FHD' => kQualityFHD,
    'HD'  => kQualityHD,
    'SD'  => kQualitySD,
    _     => kQualityUnknown, // blanc cassé — plus de gris terne
  };
}

/// §heroSeriesResume — L'URL stub `/series/{user}/{pass}/{id}` sous laquelle la
/// SÉRIE de [episode] est rangée au catalogue, ou `null` quand la question n'a
/// pas de sens (film, chaîne, épisode sans stub API).
///
/// **Pourquoi une clé de plus.** La progression d'un épisode s'écrit sous l'URL
/// de l'ÉPISODE, alors que le catalogue Xtream ne contient qu'UNE entrée par
/// série : son stub (`xtream_catalog_parser`). L'accueil ne résout une reprise
/// qu'en retrouvant son URL dans l'index des entrées (`resumeGroupsFor` : « une
/// URL inconnue est ignorée ») — une série en cours n'y était donc JAMAIS
/// trouvée, ni dans le hero ni dans la barre de sa vignette. Les films
/// marchaient parce que l'URL jouée EST celle de leur entrée.
///
/// **Quel stub.** Celui du compte d'où vient l'épisode joué : c'est le seul
/// dont on sait qu'il est en mémoire tant que cette liste-là est chargée.
/// Repli sur le premier stub connu du titre — l'accueil indexe les stubs de
/// TOUS les comptes vers le MÊME groupe, donc n'importe lequel retrouve la
/// bonne carte.
///
/// ⚠️ Rend `null` plutôt qu'un à-peu-près : sans stub (série d'une liste M3U
/// qui porte directement ses épisodes SxxExx), écrire l'URL d'un épisode
/// n'ajouterait qu'une clé que l'accueil ignore de toute façon.
String? seriesResumeKeyFor({
  required List<M3uEntry> stubs,
  required M3uEntry episode,
}) {
  // Hors série la question ne se pose pas : un film EST déjà son entrée de
  // catalogue, une chaîne n'a pas de reprise.
  if (episode.type != M3uContentType.series) return null;
  // Sans numérotation, ce n'est pas un épisode mais le stub lui-même (fiche
  // ouverte sans sélection) : ne rien écrire plutôt qu'une reprise fantôme.
  if (episode.title.seasonNumber == null ||
      episode.title.episodeNumber == null) {
    return null;
  }
  for (final M3uEntry stub in stubs) {
    if (stub.accountId == episode.accountId) return stub.url;
  }
  return stubs.isEmpty ? null : stubs.first.url;
}

/// §heroSeriesResume — La clé de série à effacer quand on oublie la reprise de
/// l'épisode courant, ou `null` s'il n'y a rien à effacer.
///
/// **Pourquoi ce n'est pas inconditionnel.** « Oublier la reprise » agit sur
/// l'épisode SÉLECTIONNÉ. Si une autre saison est encore en cours, la série est
/// légitimement « en cours » : lui retirer sa clé la ferait disparaître du hero
/// alors qu'il reste quelque chose à reprendre. On n'efface donc la clé de
/// série que lorsque plus AUCUN épisode n'a de reprise.
///
/// ⚠️ [anyEpisodeStillInProgress] se mesure APRÈS l'effacement des clés
/// d'épisode : avant, l'épisode qu'on est en train d'oublier compterait
/// lui-même comme « encore en cours » et la clé de série ne partirait jamais.
String? seriesKeyToForget({
  required String? seriesKey,
  required bool anyEpisodeStillInProgress,
}) =>
    (seriesKey == null || anyEpisodeStillInProgress) ? null : seriesKey;

/// §detailsMore (b) — L'indice « suite plus bas » est visible tant qu'il reste
/// quelque chose dessous ET que la personne n'a pas bougé de plus de 24 points
/// depuis l'ouverture ([baseline], qui n'est PAS zéro sur téléviseur).
bool scrollHintVisibleFor({
  required double pixels,
  required double baseline,
  required double extentAfter,
}) =>
    extentAfter > 24 && (pixels - baseline).abs() < 24;

class DetailsPage extends StatefulWidget {
  final M3uEntry entry;
  final List<M3uEntry> versions;

  const DetailsPage({super.key, required this.entry, this.versions = const []});

  /// §tmdbOnlyDetails — Fiche d'un titre ABSENT des listes, alimentée par TMDB
  /// seul (typiquement depuis une filmographie, où ces titres ne menaient
  /// jusqu'ici nulle part).
  ///
  /// On réutilise volontairement cette page plutôt que d'en écrire une seconde :
  /// tout son rendu (header, tagline, note, section Infos, casting, similaires,
  /// bande-annonce) est déjà piloté par les données TMDB. Une page jumelle
  /// divergerait dès la première retouche visuelle.
  factory DetailsPage.fromTmdb({
    Key? key,
    required int tmdbId,
    required String title,
    required M3uContentType type,
  }) =>
      DetailsPage(
        key: key,
        entry: buildTmdbOnlyEntry(tmdbId: tmdbId, title: title, type: type),
      );

  /// Entrée SYNTHÉTIQUE : `url` vide = marqueur « aucune source jouable », lu
  /// par `_isTmdbOnly`. Le `tmdbId` renseigné fait passer `_loadData` par
  /// `getFullDetailsById` — donc aucune recherche floue, aucun homonyme.
  @visibleForTesting
  static M3uEntry buildTmdbOnlyEntry({
    required int tmdbId,
    required String title,
    required M3uContentType type,
  }) =>
      M3uEntry(
        url: '',
        accountId: '',
        type: type,
        title: TitleMetadata.parse(title),
        tmdbId: tmdbId.toString(),
      );

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _EpGroup {
  final int episodeNumber;
  final List<M3uEntry> versions;
  M3uEntry get best => versions.first;
  _EpGroup(this.episodeNumber, this.versions);
}

class _DetailsPageState extends State<DetailsPage> with WidgetsBindingObserver {
  Media? _tmdbData;
  Map<String, dynamic>? _episodeData;
  bool _isLoading = true;
  /// §quickwin — clé TMDB configurée ? (distinct de `hasTmdb` = données reçues).
  /// `true` par défaut pour éviter un flash du CTA avant le check async.
  bool _hasTmdbKey = true;
  late M3uEntry _selectedEntry;
  late List<M3uEntry> _uniqueVersions;

  // ── Navigation série ────────────────────────────────────────────────────────
  late M3uEntry _currentEpisode;
  bool _episodeSelected = false;
  /// §seriesFavCard — Vrai quand l'épisode courant a été choisi AUTOMATIQUEMENT
  /// par défaut (1er épisode, AUCUNE reprise en cours). Dans ce cas la carte
  /// épisode (favori + lecture) reste affichée, mais le HEADER et le SYNOPSIS
  /// gardent le niveau SÉRIE (moins brutal que de sauter direct sur E01).
  /// Repassé à false dès qu'on tape un épisode/saison, qu'on enchaîne l'épisode
  /// suivant, ou quand la sélection initiale est une vraie reprise / un épisode
  /// explicitement demandé.
  bool _autoDefaultSelection = false;
  Map<int, List<_EpGroup>> _seasonEpisodes = {};
  int? _selectedSeason;
  /// §seriesFlow — Vrai tant que le fetch lazy des épisodes (API Xtream) tourne.
  /// Pilote l'état du navigateur série : spinner pendant le chargement, liste
  /// des saisons une fois prêt, message "aucun épisode" si le fetch ne renvoie
  /// rien. Évite l'ancien double-affichage (fiche en mode FILM avec les
  /// versions provider, puis bascule en mode série).
  bool _episodesLoading = false;

  /// §episodeTruth — Motif du DERNIER échec de chargement des épisodes, ou
  /// `null` si le fetch a réussi (même s'il n'a rien rendu).
  ///
  /// ⚠️ Sans ce champ, « Aucun épisode disponible pour cette série » disait
  /// aussi bien « la série n'a pas d'épisode » que « ton réseau est mort » :
  /// `fetchEpisodes` rendait `const []` dans les deux cas, et rien n'invitait
  /// à réessayer.
  /// Revue 2026-09-11, D4A-06 — la NATURE de l'échec, pas son texte : le
  /// motif se compose à l'affichage, dans la langue de l'écran.
  EpisodesFailure? _episodesFailure;
  /// §seriesMultiList — Stubs série (1 par compte) à fetcher via la JSON API,
  /// pour que chaque épisode porte les versions de TOUTES les listes qui ont
  /// la série (et pas juste le compte d'origine de la vignette).
  List<M3uEntry> _apiSeriesStubs = const [];

  /// §detailsLive — Empreinte de ce que la MÉMOIRE contient pour ce titre.
  /// Comparée à chaque bump de `ParsedPlaylistService.version` pour ne rien
  /// reconstruire quand le changement ne concerne pas cette fiche.
  String _memorySignature = '';

  final ScrollController _episodeScrollController = ScrollController();

  /// Lot 9 (§tmdbPlus) — `true` quand la personne a demandé tout le casting.
  ///
  /// ⚠️ Retombe à `false` à chaque changement d'épisode : la rangée change de
  /// contenu, la demande ne vaut plus pour elle.
  bool _castExpanded = false;

  /// Le nombre d'acteurs montrés avant « Voir plus ». Douze est ce que la
  /// fiche affichait quand c'était aussi tout ce qu'elle CONNAISSAIT.
  static const int _kCastPreview = 12;

  List<CastMember> get _visibleCast {
    final List<CastMember> all =
        _tmdbData?.castMembers ?? const <CastMember>[];
    if (_castExpanded || all.length <= _kCastPreview) return all;
    return all.take(_kCastPreview).toList();
  }

  bool get _castHasMore =>
      !_castExpanded &&
      (_tmdbData?.castMembers.length ?? 0) > _kCastPreview;

  /// §detailsMore (b) — Le défilement de la fiche entière, écouté pour l'indice
  /// « il y a une suite » (cf. `_buildScrollHint`).
  final ScrollController _pageScroll = ScrollController();

  /// §detailsMore (b) — `true` tant que la personne n'a pas bougé et qu'il
  /// reste quelque chose à voir. ⚠️ Un `ValueNotifier` et pas un `setState` :
  /// la fiche est une page lourde, et l'indice change à chaque frame de
  /// défilement — la repeindre entière pour une pastille serait §jankNext en
  /// pire.
  final ValueNotifier<bool> _scrollHintVisible = ValueNotifier<bool>(false);

  /// Position de défilement à l'OUVERTURE (après le focus d'entrée).
  double? _scrollHintBaseline;

  /// Instant d'ouverture de la fiche (cf. `_updateScrollHint`).
  final DateTime _openedAt = DateTime.now();

  /// Vrai seulement si la page DÉBORDE : sur une fiche courte (aucune clé TMDB,
  /// aucun casting), promettre une suite qui n'existe pas serait pire que de se
  /// taire.
  void _updateScrollHint() {
    if (!_pageScroll.hasClients) return;
    final pos = _pageScroll.position;
    // Recette AVD TV du 2026-09-17 — ⚠️ « pixels < 24 » n'était JAMAIS vrai sur
    // téléviseur : le focus d'entrée sur « Lire » fait défiler la page (~90
    // points mesurés) avant tout geste. La référence est donc la position
    // d'OUVERTURE, relevée la première fois que la page déborde.
    if (pos.maxScrollExtent <= 24) {
      _scrollHintVisible.value = false;
      return;
    }
    // ⚠️ Le focus d'entrée défile APRÈS la première image : tant que la fiche
    // vient de s'ouvrir, la référence suit la position (sinon elle resterait à
    // zéro et l'indice serait masqué par ce défilement que personne n'a fait).
    final bool settling =
        DateTime.now().difference(_openedAt) < const Duration(milliseconds: 1200);
    if (_scrollHintBaseline == null || settling) _scrollHintBaseline = pos.pixels;
    _scrollHintVisible.value = scrollHintVisibleFor(
      pixels: pos.pixels,
      baseline: _scrollHintBaseline!,
      extentAfter: pos.extentAfter,
    );
  }

  /// §tmdbOnlyDetails — Aucune source jouable : la fiche vit sur TMDB seul.
  ///
  /// On teste l'entrée RÉELLEMENT sélectionnée plutôt que `widget.entry` : elle
  /// suit la sélection d'épisode et vaut `widget.versions.first` dès qu'une
  /// version existe. C'est donc la seule mesure fiable de « peut-on lire ? ».
  bool get _isTmdbOnly => _selectedEntry.url.isEmpty;

  bool get _isEpisode =>
      _episodeSelected &&
      _currentEpisode.title.isSeriesEpisode &&
      _currentEpisode.title.seasonNumber != null &&
      _currentEpisode.title.episodeNumber != null;

  /// §1i — Calcule l'épisode suivant pour la série en cours :
  /// - prochain épisode de la même saison si présent
  /// - sinon premier épisode de la saison suivante si présente
  /// - sinon null (fin de série).
  /// §nextEpRollover — Robuste aux TROUS de numérotation provider : l'ancien
  /// test strict `episodeNumber == epNum + 1` échouait sur 1,2,4… (le ⏭
  /// sautait alors à la saison suivante, ou rendait null en fin de saison si
  /// la clé de saison suivante n'était pas contiguë). On prend désormais le
  /// PLUS PETIT numéro strictement supérieur (épisodes ET saisons).
  M3uEntry? get _nextEpisode {
    if (!_isEpisode || _seasonEpisodes.isEmpty) return null;
    final season = _currentEpisode.title.seasonNumber!;
    final epNum  = _currentEpisode.title.episodeNumber!;
    // Prochain épisode (numéro > courant, le plus petit) dans la même saison.
    final eps = _seasonEpisodes[season] ?? const [];
    _EpGroup? nextInSeason;
    for (final g in eps) {
      if (g.episodeNumber <= epNum) continue;
      if (nextInSeason == null || g.episodeNumber < nextInSeason.episodeNumber) {
        nextInSeason = g;
      }
    }
    if (nextInSeason != null) return nextInSeason.best;
    // Première saison de numéro > courant (les clés ne sont pas forcément
    // contiguës : specials en 0, saisons manquantes chez le provider).
    int? nextSeason;
    for (final s in _seasonEpisodes.keys) {
      if (s <= season) continue;
      if (nextSeason == null || s < nextSeason) nextSeason = s;
    }
    if (nextSeason != null) {
      final nextSeasonEps = _seasonEpisodes[nextSeason] ?? const [];
      if (nextSeasonEps.isNotEmpty) return nextSeasonEps.first.best;
    }
    // §nextEpRollover — diagnostic device : si un provider éclate les saisons
    // en séries distinctes, la map ne contient qu'UNE saison → visible ici.
    debugPrint('📺 _nextEpisode: fin atteinte après S$season E$epNum — '
        'saisons chargées: ${_seasonEpisodes.keys.toList()..sort()}');
    return null;
  }

  /// §1i — Sélectionne l'épisode suivant + recharge les métadonnées TMDB +
  /// rebascule sur la fiche détaillée. Utilisé par le bouton "next" du player.

  @override
  void initState() {
    super.initState();
    _currentEpisode = widget.entry;
    // Revue 2026-09-11, D4A-10 — UNE collecte en mémoire à l'ouverture, pas
    // deux : l'empreinte, les versions d'un film et les épisodes d'une série
    // la relisaient chacun (`byTypeWithPriority` concatène tous les comptes,
    // puis `entriesOfTitle` balaie tout le type). Tout se passe dans ce même
    // tour synchrone, la mémoire ne peut pas changer entre-temps : le
    // résultat est celui qu'aurait donné chaque relecture.
    final Stopwatch openSw = Stopwatch()..start();
    final List<M3uEntry> fromMemory = _entriesFromMemory();
    // Sonde D4A-10 : une ligne par ouverture de fiche (geste de l'utilisateur).
    if (!kReleaseMode) {
      debugPrint('⏱️ §detailsOpen : collecte mémoire ${openSw.elapsedMilliseconds} ms (${fromMemory.length} entrées du titre)');
    }
    _memorySignature = versionsSignature(fromMemory);
    ParsedPlaylistService.version.addListener(_onPlaylistChanged);
    // §exitCost — mesure de la rotation. Revue 2026-09-11, D4L-02 — hors
    // release seulement : l'observateur ne sert QU'À ce chrono, et chaque
    // rotation / clavier / PiP ajoutait une ligne au journal persistant
    // (§logPersist), le seul canal de diagnostic d'un téléviseur. Debug et
    // profile gardent la mesure, comme §exitCost la décrit.
    if (!kReleaseMode) WidgetsBinding.instance.addObserver(this);
    // §detailsMore (b) — L'indice n'apparaît qu'une fois la page mesurée : à
    // `initState` le scrollable n'a pas encore d'étendue, et on annoncerait une
    // suite sans savoir s'il y en a une.
    _pageScroll.addListener(_updateScrollHint);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _updateScrollHint());
    _buildSeasonEpisodes(memory: fromMemory);

    if (widget.entry.type == M3uContentType.series) {
      _uniqueVersions = _deduplicateVersions(widget.versions);
      _selectedEntry  = _uniqueVersions.isNotEmpty ? _uniqueVersions.first : widget.entry;
      // Épisodes déjà présents (M3U parsé, fallback get.php) → affichage immédiat.
      if (_seasonEpisodes.isNotEmpty) {
        _applyInitialEpisodeSelection();
        _autoSelectInitialEpisode();
      }
      // §seriesMultiList — Stubs API présents (catalogue §23) → fetch des
      // épisodes de TOUS les comptes en parallèle, mergés avec l'éventuel M3U.
      // `_episodesLoading` → navigateur série EN CHARGEMENT (jamais le layout
      // film + versions provider) tant qu'aucun épisode n'est encore là.
      if (_apiSeriesStubs.isNotEmpty) {
        _episodesLoading = _seasonEpisodes.isEmpty;
        _fetchAllEpisodes();
      }
    } else {
      // §detailsLive — On repart de la MÉMOIRE plutôt que de la liste figée
      // que l'accueil a passée au moment du tap. Repli sur `widget.versions`
      // si le titre n'est pas (ou plus) en mémoire : fiche TMDB seule, liste
      // déchargée, entrée synthétique.
      // D4A-10 — la collecte faite en tête d'`initState`.
      _uniqueVersions = _deduplicateVersions(
          fromMemory.isEmpty ? widget.versions : fromMemory);
      _selectedEntry  = _uniqueVersions.isNotEmpty ? _uniqueVersions.first : widget.entry;
    }

    _loadData();

    // §quickwin — check clé TMDB pour le CTA "Active TMDB" (sans clé, pas
    // d'affiches/synopsis/casting → on incite à en configurer une).
    TmdbApiService.hasApiKey().then((v) {
      if (mounted) setState(() => _hasTmdbKey = v);
    });
  }

  @override
  /// §exitCost — Mesure : la fiche repeinte à sa NOUVELLE taille (retour en
  /// portrait après le lecteur). Horodaté pour être lu face à « retour
  /// demandé » du lecteur.
  @override
  void didChangeMetrics() {
    final Size size = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('\u23F1\uFE0F \u00A7exitCost \u2014 fiche repeinte en ${size.width.toInt()}x${size.height.toInt()}');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ParsedPlaylistService.version.removeListener(_onPlaylistChanged);
    _episodeScrollController.dispose();
    // §detailsMore (b) — D2A-01 : une libération ne se saute jamais.
    _pageScroll.removeListener(_updateScrollHint);
    _pageScroll.dispose();
    _scrollHintVisible.dispose();
    super.dispose();
  }

  /// §detailsLive — Toutes les entrées de la MÉMOIRE qui appartiennent à ce
  /// titre : les versions d'un film, les stubs et épisodes d'une série.
  ///
  /// La règle vit dans `details_versions.dart` : elle était écrite deux fois
  /// (films / séries), et c'est comme ça que les deux chemins ont divergé.
  List<M3uEntry> _entriesFromMemory() => entriesOfTitle(
        ParsedPlaylistService.byTypeWithPriority(
                widget.entry.accountId)[widget.entry.type] ??
            const <M3uEntry>[],
        widget.entry,
      );

  /// §detailsLive — Recale la fiche sur la mémoire quand une liste arrive ou
  /// repart (rechargement, ré-analyse terminée, libération mémoire).
  ///
  /// Sans ça, une fiche de FILM restait figée sur la liste calculée par
  /// l'accueil AU MOMENT DU TAP : les qualités d'une liste revenue
  /// n'apparaissaient qu'après avoir refermé puis rouvert la fiche.
  void _onPlaylistChanged() {
    if (!mounted) return;
    final Stopwatch sw = Stopwatch()..start();
    final entries = _entriesFromMemory();
    final sig = versionsSignature(entries);
    // §exitCost — mesure : ce balayage tourne a chaque bump de version.
    // D4L-02 — le chrono reste, la ligne de journal seulement hors release.
    if (!kReleaseMode) debugPrint('\u23F1\uFE0F \u00A7detailsLive : balayage memoire ${sw.elapsedMilliseconds} ms (${entries.length} entrees du titre, change=${sig != _memorySignature})');
    if (sig == _memorySignature) return; // rien de neuf pour CE titre
    _memorySignature = sig;
    if (widget.entry.type == M3uContentType.series) {
      _resyncSeries(entries);
    } else {
      _resyncMovie(entries);
    }
  }

  /// §detailsLive — Film : on remplace les versions, en gardant celle qui est
  /// sélectionnée si elle existe toujours (cf. `keepSelection`).
  void _resyncMovie(List<M3uEntry> entries) {
    final versions =
        _deduplicateVersions(entries.isEmpty ? widget.versions : entries);
    final kept = keepSelection(versions, _selectedEntry.url);
    if (kept == null) return; // plus aucune source : on garde l'affichage
    debugPrint('\u{1F504} \u00A7detailsLive : film "${widget.entry.displayName}" '
        '${_uniqueVersions.length} -> ${versions.length} version(s)');
    setState(() {
      _uniqueVersions = versions;
      _selectedEntry = kept;
    });
  }

  /// §detailsLive — Série : on relit la mémoire, mais on GARDE les épisodes
  /// déjà rendus par la JSON API (ils ne sont pas dans la mémoire de la
  /// playlist) — sinon la liste des saisons se viderait le temps d'un nouveau
  /// fetch. La saison ouverte et l'épisode choisi sont restaurés.
  void _resyncSeries(List<M3uEntry> memory) {
    final previous = _flattenSeasonEpisodes();
    debugPrint('\u{1F504} \u00A7detailsLive : serie "${widget.entry.displayName}" '
        'relue (${previous.length} version(s) d episode deja affichees)');
    final openSeason = _selectedSeason;
    final wasSelected = _episodeSelected;
    // D4A-10 — la collecte que `_onPlaylistChanged` vient de faire (même tour).
    _buildSeasonEpisodes(memory: memory); // remet `_selectedSeason` à null
    if (previous.isNotEmpty) {
      _seasonEpisodes =
          _regroupEpisodes([...previous, ..._flattenSeasonEpisodes()]);
    }
    setState(() {
      _selectedSeason =
          (openSeason != null && _seasonEpisodes.containsKey(openSeason))
              ? openSeason
              : null;
      _episodeSelected = wasSelected;
      if (wasSelected) _refreshSelectedEpisodeVersions();
    });
    // Une liste qui revient peut apporter un stub de plus : ses épisodes sont
    // mergés par `_fetchAllEpisodes` (qui préserve la sélection lui aussi).
    if (_apiSeriesStubs.isNotEmpty) _fetchAllEpisodes();
  }

  /// §xtreamEpisodes — Applique la sélection initiale d'épisode après que
  /// `_seasonEpisodes` est rempli (que ce soit via le parser M3U OU via le
  /// lazy fetch de la JSON API). Factorisé pour pouvoir être appelé depuis
  /// initState ET depuis `_fetchAllEpisodes`.
  void _applyInitialEpisodeSelection() {
    final season = widget.entry.title.seasonNumber;
    final epNum  = widget.entry.title.episodeNumber;
    if (season != null && epNum != null) {
      final group = _seasonEpisodes[season]
          ?.where((g) => g.episodeNumber == epNum)
          .firstOrNull;
      if (group != null) {
        _episodeSelected = true;
        _autoDefaultSelection = false; // épisode explicitement demandé
        _selectedSeason  = season;
        _currentEpisode  = group.best;
        _uniqueVersions  = _deduplicateVersions(group.versions);
        _selectedEntry   = _uniqueVersions.isNotEmpty
            ? _uniqueVersions.first
            : group.best;
        return;
      }
    }
    _episodeSelected = false;
    _uniqueVersions  = const [];
    _selectedEntry   = widget.entry;
  }

  /// §xtreamEpisodes — Récupère les épisodes via la JSON API Xtream à la
  /// demande (séries listées en stubs au boot, épisodes chargés à l'ouverture).
  /// §seriesMultiList — Fetch les épisodes de TOUS les stubs (un par compte qui
  /// a la série) en parallèle, puis merge avec les épisodes déjà présents (M3U)
  /// → chaque épisode porte les versions de toutes les listes. Remplace
  /// l'ancien fetch mono-compte qui ne montrait qu'un seul provider.
  Future<void> _fetchAllEpisodes() async {
    // Revue 2026-09-11, D4A-06 — chaque stub rend AUSSI l'échec constaté par
    // la fiche elle-même (identifiant illisible, compte introuvable) : la
    // `LoadFailureKind` seule ne distingue pas ces deux cas. Les motifs
    // français restent ceux du JOURNAL (`episodesFailureReason`).
    final futures = _apiSeriesStubs.map<Future<_StubOutcome>>((stub) async {
      final sid = _extractSeriesIdFromUrl(stub.url);
      if (sid == null) {
        return (
          r: (
            episodes: null,
            error: 'identifiant de série illisible',
            kind: LoadFailureKind.badAccount,
          ),
          local: EpisodesFailure.badSeriesId,
        );
      }
      final acc = await StreamAccountService.getAccount(stub.accountId);
      if (acc == null) {
        return (
          r: (
            episodes: null,
            error: 'compte introuvable',
            kind: LoadFailureKind.badAccount,
          ),
          local: EpisodesFailure.noAccount,
        );
      }
      return (r: await XtreamApiService.fetchEpisodes(acc, sid), local: null);
    }).toList();

    final outcomes = await Future.wait(futures);
    if (!mounted) return;
    final results = <XtreamEpisodesResult>[for (final o in outcomes) o.r];
    final apiEpisodes =
        results.expand((r) => r.episodes ?? const <M3uEntry>[]).toList();

    // §episodeTruth — Une liste vide ne veut plus dire la même chose selon
    // qu'AUCUN stub n'a répondu ou que tous ont répondu « rien ». On ne
    // signale une panne que si **aucun** compte n'a rendu de résultat
    // exploitable : qu'une liste secondaire soit injoignable pendant qu'une
    // autre rend les épisodes n'est pas une panne pour l'utilisateur.
    if (apiEpisodes.isEmpty) {
      final String? reason = episodesFailureReason(results);
      if (reason != null) debugPrint('⚠️ Épisodes non chargés : $reason');
      return _finishEpisodesLoading(
        failure: episodesFailureOf(
          results,
          local: <EpisodesFailure?>[for (final o in outcomes) o.local],
        ),
      );
    }

    // Merge épisodes M3U déjà groupés + nouveaux épisodes API → regroupe tout.
    final merged = <M3uEntry>[..._flattenSeasonEpisodes(), ...apiEpisodes];
    final regrouped = _regroupEpisodes(merged);

    final wasSelected = _episodeSelected;
    setState(() {
      _seasonEpisodes = regrouped;
      _episodesLoading = false;
      // Ne ré-applique la sélection auto que si l'utilisateur n'a pas déjà
      // navigué pendant le (bref) chargement.
      if (!_episodeSelected && _selectedSeason == null) {
        _applyInitialEpisodeSelection();
        _autoSelectInitialEpisode();
      } else if (_episodeSelected) {
        // §seriesMultiList — l'épisode courant gagne les versions des autres
        // listes maintenant qu'elles sont mergées.
        _refreshSelectedEpisodeVersions();
      }
    });
    // Si on vient d'auto-sélectionner un épisode (TMDB pas encore chargé pour
    // lui), on (re)charge ses métadonnées.
    if (!wasSelected && _episodeSelected) _loadData();
  }

  /// Aplatit `_seasonEpisodes` en liste d'épisodes bruts (pour re-merger).
  List<M3uEntry> _flattenSeasonEpisodes() => [
        for (final groups in _seasonEpisodes.values)
          for (final g in groups) ...g.versions,
      ];

  /// Regroupe une liste plate d'épisodes en `saison → [épisodes triés]`, chaque
  /// épisode portant ses versions dédupliquées (cross-comptes = plusieurs
  /// listes pour le même S/E).
  Map<int, List<_EpGroup>> _regroupEpisodes(List<M3uEntry> episodes) {
    final tmp = <int, Map<int, List<M3uEntry>>>{};
    for (final ep in episodes) {
      final s = ep.title.seasonNumber;
      final e = ep.title.episodeNumber;
      if (s == null || e == null) continue;
      tmp.putIfAbsent(s, () => {}).putIfAbsent(e, () => []).add(ep);
    }
    final result = <int, List<_EpGroup>>{};
    for (final entry in tmp.entries) {
      final groups = entry.value.entries
          .map((e) => _EpGroup(e.key, _deduplicateVersions(e.value)))
          .toList()
        ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      result[entry.key] = groups;
    }
    final sortedSeasons = result.keys.toList()..sort();
    return {for (final s in sortedSeasons) s: result[s]!};
  }

  /// §seriesFlow — Termine l'état de chargement des épisodes (échec/série
  /// introuvable/aucun épisode). Le navigateur série bascule alors sur le
  /// message "aucun épisode disponible" au lieu d'un spinner infini.
  /// [error] non nul = le chargement a ÉCHOUÉ (§episodeTruth) : la fiche
  /// affiche alors le motif et un bouton « Réessayer », pas « aucun épisode ».
  void _finishEpisodesLoading({EpisodesFailure? failure}) {
    if (!mounted) {
      _episodesLoading = false;
      _episodesFailure = failure;
      return;
    }
    setState(() {
      _episodesLoading = false;
      _episodesFailure = failure;
    });
  }

  /// §episodeTruth — Relance le fetch après un échec. Le cache mémoire ne
  /// garde que les succès, donc il n'y a rien à invalider.
  void _retryEpisodes() {
    if (_episodesLoading || _apiSeriesStubs.isEmpty) return;
    setState(() {
      _episodesLoading = true;
      _episodesFailure = null;
    });
    _fetchAllEpisodes();
  }

  /// §seriesFavCard — À l'ouverture d'une série (aucun épisode précis demandé via
  /// `widget.entry`), on **présélectionne** un épisode pour que la carte épisode
  /// — donc le bouton **Favori** + **Lire/Reprendre** — soit disponible d'emblée
  /// (avant, ces boutons n'apparaissaient qu'une fois un épisode tapé). Choix :
  ///   1. l'épisode le PLUS AVANCÉ ayant une reprise en cours (saison puis n°
  ///      d'épisode décroissants) → on retombe pile où on en était ;
  ///   2. sinon le tout premier épisode (S01E01) → favori dispo + lecture au début.
  /// Le favori d'un épisode cible la SÉRIE (clé `series|groupKey|année`), donc
  /// présélectionner E01 = favori de la série, comportement attendu.
  void _autoSelectInitialEpisode() {
    if (_episodeSelected) return; // déjà ciblé via widget.entry
    if (_seasonEpisodes.isEmpty) return;

    final inProgress = _mostAdvancedInProgress();
    final target = inProgress ?? _firstEpisodeGroup();
    if (target == null) return;

    final (season, group) = target;
    _selectedSeason  = season;
    _episodeSelected = true;
    // E01 par défaut (pas de reprise) → on reste en contexte SÉRIE pour le
    // header/synopsis ; une vraie reprise bascule en contexte épisode.
    _autoDefaultSelection = inProgress == null;
    _currentEpisode  = group.best;
    _uniqueVersions  = _deduplicateVersions(group.versions);
    _selectedEntry =
        _uniqueVersions.isNotEmpty ? _uniqueVersions.first : group.best;
  }

  /// Premier épisode disponible (plus petite saison, plus petit n°).
  (int, _EpGroup)? _firstEpisodeGroup() {
    final seasons = _seasonEpisodes.keys.toList()..sort();
    for (final s in seasons) {
      final eps = _seasonEpisodes[s];
      if (eps != null && eps.isNotEmpty) return (s, eps.first);
    }
    return null;
  }

  /// §seriesFavCard — Épisode le plus avancé (saison puis n° max) ayant une
  /// reprise enregistrée sur l'une de ses versions (toutes qualités/listes
  /// confondues via [WatchProgressService.getProgressForAny]). La reprise étant
  /// auto-effacée à >95 % (épisode vu en entier), seul un épisode réellement en
  /// cours ressort ici.
  (int, _EpGroup)? _mostAdvancedInProgress() {
    (int, _EpGroup)? best;
    for (final s in _seasonEpisodes.keys) {
      for (final g in _seasonEpisodes[s]!) {
        final p = WatchProgressService.getProgressForAny(
            g.versions.map((v) => v.url).toList());
        if (p == null || p.position.inSeconds <= 5) continue;
        if (best == null ||
            s > best.$1 ||
            (s == best.$1 && g.episodeNumber > best.$2.episodeNumber)) {
          best = (s, g);
        }
      }
    }
    return best;
  }

  /// §seriesMultiList — Après le merge des épisodes API (cross-comptes), ré-résout
  /// l'épisode courant dans les groupes regroupés pour que sa carte porte les
  /// versions de TOUTES les listes (sinon elle reste sur le seul compte d'origine).
  /// Conserve la version exacte choisie par l'utilisateur si elle existe encore.
  void _refreshSelectedEpisodeVersions() {
    final s = _currentEpisode.title.seasonNumber;
    final e = _currentEpisode.title.episodeNumber;
    if (s == null || e == null) return;
    final group =
        _seasonEpisodes[s]?.where((g) => g.episodeNumber == e).firstOrNull;
    if (group == null) return;
    final keepUrl = _selectedEntry.url;
    _uniqueVersions = _deduplicateVersions(group.versions);
    _currentEpisode = group.best;
    _selectedEntry = _uniqueVersions.firstWhere(
      (v) => v.url == keepUrl,
      orElse: () =>
          _uniqueVersions.isNotEmpty ? _uniqueVersions.first : group.best,
    );
  }

  /// Extrait le `series_id` d'une URL stub `/series/{user}/{pass}/{id}`.
  ///
  /// ✅ **R44 — la règle vit désormais dans `series_stub.dart`**, partagée avec
  /// l'accueil (`isSeriesStubEntry`) : elle était écrite ici ET là-bas, à la
  /// ligne près, c'est-à-dire §tourFix en attente de se produire. Ce qui reste
  /// ici n'est qu'un raccourci de nom pour les deux appels de la fiche.
  static int? _extractSeriesIdFromUrl(String url) => seriesIdFromUrl(url);

  /// [memory] : la collecte `_entriesFromMemory()` que l'appelant vient de
  /// faire dans le MÊME tour synchrone (D4A-10) — identique à celle d'ici,
  /// puisque le type de la fiche EST `series`. Absent : on la fait.
  void _buildSeasonEpisodes({List<M3uEntry>? memory}) {
    if (widget.entry.type != M3uContentType.series) return;
    // §detailsLive — Le rapprochement (§23b clé de groupe normalisée +
    // §homonymYear : on ne mélange pas deux séries homonymes d'époques
    // différentes) vit désormais dans `entriesOfTitle`, PARTAGÉ avec la
    // collecte des versions d'un film. Il était écrit deux fois, et c'est
    // comme ça que les deux chemins avaient divergé.
    // §seriesScan — On part des entrées DÉJÀ splittées par type au lieu de
    // `entriesWithPriority`, qui matérialisait une copie de TOUTES les entrées
    // de TOUS les comptes (`[...priority, ...others]`) avant de filtrer.
    // Mesuré sur l'émulateur avec 4 listes : 323 373 entrées copiées à chaque
    // ouverture d'une fiche de série, pour n'en garder qu'une poignée. Les
    // séries seules en représentent environ un cinquième.
    final all = memory ??
        entriesOfTitle(
          ParsedPlaylistService.byTypeWithPriority(
                  widget.entry.accountId)[M3uContentType.series] ??
              const <M3uEntry>[],
          widget.entry,
        );

    // §seriesMultiList — On sépare : (a) épisodes M3U réels (SxxExx présents)
    // → groupés tout de suite ; (b) stubs série (un par compte, URL
    // `/series/.../id` sans épisode) → à fetcher via la JSON API pour récupérer
    // leurs épisodes. Un stub par compte (dédup accountId).
    final m3uEpisodes = <M3uEntry>[];
    final stubsByAccount = <String, M3uEntry>{};
    for (final e in all) {
      final hasEp =
          e.title.seasonNumber != null && e.title.episodeNumber != null;
      if (hasEp) {
        m3uEpisodes.add(e);
      } else if (_extractSeriesIdFromUrl(e.url) != null) {
        stubsByAccount.putIfAbsent(e.accountId, () => e);
      }
    }

    _apiSeriesStubs = stubsByAccount.values.toList();
    _seasonEpisodes = _regroupEpisodes(m3uEpisodes);
    _selectedSeason = null;
  }

  void _selectSeason(int season) {
    final episodes = _seasonEpisodes[season] ?? [];
    setState(() => _selectedSeason = season);
    if (episodes.isNotEmpty) _selectEpisode(episodes.first);
  }

  void _selectEpisode(_EpGroup group) {
    final versions = _deduplicateVersions(group.versions);
    setState(() {
      _currentEpisode  = group.best;
      _episodeSelected = true;
      _autoDefaultSelection = false; // tap manuel → contexte épisode
      _uniqueVersions  = versions;
      _selectedEntry   = versions.isNotEmpty ? versions.first : group.best;
      _isLoading       = true;
      _episodeData     = null;
      // Lot 9 (§tmdbPlus) — La rangée casting va changer de contenu : la
      // demande « montre-moi tout le monde » portait sur l'épisode précédent.
      _castExpanded    = false;
    });
    _loadData();
    // Auto-scroll vers l'épisode sélectionné
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_episodeScrollController.hasClients) return;
      final episodes = _seasonEpisodes[_selectedSeason] ?? [];
      final idx = episodes.indexWhere((g) => g.episodeNumber == group.episodeNumber);
      if (idx < 0) return;
      final target = (idx * 58.0).clamp(
          0.0, _episodeScrollController.position.maxScrollExtent);
      _episodeScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  /// §23c — ID TMDB fourni par le provider (catalogue JSON v5), scanné sur
  /// l'entrée + toutes les versions. Null si aucun (fallback get.php, vieux
  /// caches, provider sans tmdb_id).
  int? _providerTmdbId() {
    for (final e in [widget.entry, ..._uniqueVersions, _currentEpisode]) {
      final id = int.tryParse(e.tmdbId ?? '');
      if (id != null && id > 0) return id;
    }
    return null;
  }

  /// Revue 2026-09-11, D4A-05 — Jeton du dernier `_loadData` lancé. OK sur
  /// E03 puis tout de suite sur E04 : si la réponse E03 arrivait APRÈS celle
  /// de E04, la fiche montrait titre, synopsis et image de E03 sous la puce
  /// E04 — et « LIRE » ouvrait E04 avec le titre de E03 dans le lecteur et la
  /// notification. Seule la réponse du DERNIER chargement s'applique.
  int _loadSeq = 0;

  Future<void> _loadData() async {
    final int seq = ++_loadSeq;
    final service  = TmdbService.instance;
    final isSeries = widget.entry.type == M3uContentType.series;

    // §23c — PRIORITÉ à l'ID TMDB exact du provider : zéro recherche floue,
    // zéro homonyme verrouillé ("Michael" → "Michael Collins"). Fallback
    // smart search par titre si pas d'ID ou ID invalide côté TMDB.
    Future<Media?> fetchFull({required bool isTv}) async {
      final pid = _providerTmdbId();
      Media? data;
      if (pid != null) {
        data = await service.getFullDetailsById(pid, isTv: isTv);
      }
      return data ??
          await service.getFullDetails(
            isSeries ? widget.entry.displayName : _currentEpisode.displayName,
            isTv: isTv,
            explicitYear: isSeries
                ? widget.entry.title.year
                : _currentEpisode.title.year,
            groupTitle: isSeries
                ? widget.entry.groupTitle
                : _currentEpisode.groupTitle,
          );
    }

    if (_isEpisode) {
      // §seriesFetchOnce (2026-09-06) — Les données de la SÉRIE (crédits,
      // vidéos, recommandations, réseaux…) ne changent pas d'un épisode à
      // l'autre : on ne les redemande pas. Vu sur le téléviseur réel : 17
      // appels `/tv/1639` en 27 s en parcourant les épisodes d'une seule
      // série — un appel complet par épisode sélectionné. Seul l'épisode est
      // redemandé ; la série ne l'est que si son premier chargement a échoué.
      final Media? seriesAlready = _tmdbData;
      final results = await Future.wait([
        service.getEpisodeDetails(
          widget.entry.displayName,
          _currentEpisode.title.seasonNumber!,
          _currentEpisode.title.episodeNumber!,
          // §epSynopsis — id TMDB exact du provider (comme fetchFull/§23c) :
          // la recherche floue par nom rendait null sur homonyme/année fausse
          // → synopsis d'épisode vide.
          tmdbId: _providerTmdbId(),
          yearFilter: widget.entry.title.year,
          groupTitle: widget.entry.groupTitle,
        ),
        if (seriesAlready == null) fetchFull(isTv: true),
      ]);
      if (mounted && seq == _loadSeq) {
        setState(() {
          _episodeData = results[0] as Map<String, dynamic>?;
          if (seriesAlready == null) _tmdbData = results[1] as Media?;
          _isLoading   = false;
        });
        // Les rangées Saga / Similaires dépendent de la série : inchangées.
        if (seriesAlready == null) _computeRelated();
      }
    } else {
      final data = await fetchFull(isTv: isSeries || _currentEpisode.isSerie);
      if (mounted && seq == _loadSeq) {
        setState(() {
          _tmdbData  = data;
          _isLoading = false;
        });
        _computeRelated();
      }
    }
  }

  // ── §tmdbReco — Saga + titres similaires disponibles dans la playlist ──────
  /// Groupes de la saga (collection) présents chez l'utilisateur, ordre TMDB.
  List<List<M3uEntry>> _collection = const [];
  String? _collectionName;
  /// Recommandations TMDB présentes dans la playlist.
  List<List<M3uEntry>> _similar = const [];

  /// Calcule les rangées « Saga » et « Similaires » à partir de `_tmdbData`
  /// (recommandations incluses dans la réponse, saga via un appel caché) en les
  /// croisant avec la playlist du compte. Tolère l'absence de clé/données.
  Future<void> _computeRelated() async {
    final data = _tmdbData;
    if (data == null) return;
    final similar = _matchRefs(data.recommendations);
    List<List<M3uEntry>> collection = const [];
    String? collName;
    if (data.collectionId != null) {
      final parts =
          await TmdbService.instance.getCollectionTitles(data.collectionId!);
      final matched = _matchRefs(parts, max: 30);
      if (matched.isNotEmpty) {
        collection = matched;
        collName = data.collectionName;
      }
    }
    if (mounted) {
      setState(() {
        _similar = similar;
        _collection = collection;
        _collectionName = collName;
      });
    }
  }

  /// Croise une liste de refs TMDB (titre + année) avec les groupes de la
  /// playlist (même type), via `computeGroupKey` (la clé de regroupement de
  /// l'app) + proximité d'année (anti-homonyme). Exclut le titre courant.
  List<List<M3uEntry>> _matchRefs(List<MediaRef> refs, {int max = 18}) {
    if (refs.isEmpty) return const [];
    final Stopwatch sw = Stopwatch()..start();
    final type = widget.entry.type;
    final entries =
        ParsedPlaylistService.byTypeWithPriority(widget.entry.accountId)[type] ??
            const <M3uEntry>[];
    final byKey = <String, List<M3uEntry>>{};
    for (final e in entries) {
      byKey.putIfAbsent(contentGroupKey(e), () => []).add(e);
    }
    // Revue 2026-09-11, D4A-10 (b) — DIFFÉRÉ, sonde seulement. Partager cet
    // index entre « Similaires » et « Saga » l'obligerait à survivre à l'appel
    // réseau de la saga (`await getCollectionTitles`) : tout le catalogue du
    // type retenu pendant une attente réseau, là où il était libéré aussitôt.
    // Une ligne par rangée croisée (chargement TMDB d'une fiche), jamais par
    // frame : elle donne le coût à comparer à cette rétention sur appareil.
    if (!kReleaseMode) {
      debugPrint('⏱️ §detailsRelated : index ${sw.elapsedMilliseconds} ms (${entries.length} entrées, ${byKey.length} groupes, ${refs.length} refs)');
    }
    final out = <List<M3uEntry>>[];
    final seen = <String>{contentGroupKey(widget.entry)};
    for (final ref in refs) {
      final key = TitleMetadata.computeGroupKey(ref.title);
      if (seen.contains(key)) continue;
      final g = byKey[key];
      if (g == null || g.isEmpty) continue;
      // Proximité d'année (±1) si les deux années sont connues.
      final ry = int.tryParse(ref.year ?? '');
      final gy = int.tryParse(g.first.title.year ?? '');
      if (ry != null && gy != null && (ry - gy).abs() > 1) continue;
      out.add(g);
      seen.add(key);
      if (out.length >= max) break;
    }
    return out;
  }

  Widget _badge(String text, Color color,
      {bool filled = false, IconData? icon}) {
    // §lightTheme — Même idiome que la chip des comptes : le contraste se
    // dérive du fond de la pastille, jamais un noir en dur.
    final fg = filled ? onColorFor(color) : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(filled ? 235 : 36),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(filled ? 235 : 120)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2)),
        ],
      ),
    );
  }

  /// §tmdbReco — Rangée horizontale de titres liés (saga / similaires).
  Widget _relatedRow(
      String title, List<List<M3uEntry>> groups, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: cs.onSurfaceVariant)),
        Divider(color: cs.outlineVariant),
        SizedBox(
          // poster 104×156 + gap + titre 2 lignes + marge textScaler TV ×1.3.
          height: 230,
          // §dpadRowEntry — Région propre à la rangée : en descendant depuis le
          // bloc du dessus, le focus se cale sur la 1re carte au lieu de tomber
          // au milieu (le repli géométrique atterrissait sous la colonne d'où
          // l'on venait, donc en pleine rangée).
          // ⚠️ Pas de `memoryKey` ici : c'est une mémoire STATIQUE GLOBALE au
          // package, partagée entre toutes les fiches — la colonne mémorisée
          // sur un film serait rejouée sur le suivant, dont le casting n'a rien
          // à voir. La mémoire d'instance (une région par fiche montée) est
          // exactement ce qu'on veut.
          child: DpadRegion(
            debugLabel: 'detailsRelated',
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              // §rowFocusFit (2026-09-06) — Marge HORIZONTALE aussi : au focus,
              // la carte grossit de 5 % et porte un contour ; sans marge, le
              // bord gauche de la PREMIÈRE carte était rogné par la fenêtre du
              // ListView (« position négative », signalement utilisateur sur
              // téléviseur). 6 px suffisent pour +2,6 px d'échelle et le trait.
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              // ignore: deprecated_member_use
              cacheExtent: 600,
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) =>
                  _RelatedCard(group: groups[i], isEntry: i == 0),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _searchActor(String actorName) async {
    final personId = await TmdbService.instance.getPersonId(actorName);
    if (!mounted) return;
    if (personId != null) {
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ActorDetailsPage(personId: personId)));
    } else {
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
        SnackBar(content: Text(context.l10n.detActorNotFound(actorName))),
      );
    }
  }

  /// Ouvre la bande-annonce dans l'app YouTube / le navigateur externe.
  /// (Lecteur in-app §trailerInApp retiré : beaucoup de trailers de studios
  /// désactivent l'embedding → injouables dans un lecteur tiers.)
  Future<void> _launchTrailer() async {
    final key = _tmdbData?.trailerKey;
    if (key == null || key.isEmpty) return;
    final url = Uri.parse('https://www.youtube.com/watch?v=$key');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // §quickwin — Bandeau incitant à configurer TMDB (affiché si pas de clé).
  Widget _buildTmdbCta(ColorScheme cs) {
    return Material(
      color: kAccentPrimary.withAlpha(20),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TmdbKeyPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.movie_filter_outlined, color: kAccentPrimary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.detEnableTmdb,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.detTmdbPitch,
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 12, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  // §tvDetailsShrink — Réglages de réduction de la fiche sur TV (faciles à
  // ajuster d'un seul nombre) :
  //   - backdrop : fraction de la hauteur écran (clamp 180-300) vs 360 fixe mobile
  //   - largeur max de la colonne d'infos (centrée) → évite le texte étalé
  //   - échelle du texte de la fiche (0.85 = -15%) pour réduire "toute la partie infos"
  /// §detailsHero — La fraction a grandi (0,42 -> 0,62) le 2026-09-06 : l'image
  /// ne partage plus l'écran avec le bloc titre, elle le PORTE.
  static const double _kTvBackdropFraction = 0.72;
  static const double _kTvContentMaxWidth = 820.0;
  static const double _kTvContentTextScale = 0.85;

  /// Enveloppe le contenu de la fiche pour le réduire sur TV : largeur max
  /// centrée + texte mis à l'échelle. Neutre sur mobile.
  Widget _tvShrinkContent(BuildContext context, bool isTv, Widget child) {
    if (!isTv) return child;
    final mq = MediaQuery.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kTvContentMaxWidth),
        child: MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(_kTvContentTextScale),
          ),
          child: child,
        ),
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n    = AppLocalizations.of(context)!;
    final cs      = Theme.of(context).colorScheme;
    final hasTmdb = _tmdbData != null;
    // §seriesFlow — basé sur le TYPE (pas sur `_seasonEpisodes.isNotEmpty`) :
    // une série rend TOUJOURS le navigateur série dès la 1re frame (en
    // chargement si les épisodes arrivent en lazy), jamais le layout film +
    // versions provider. Supprime le double-affichage.
    final isSeries = widget.entry.type == M3uContentType.series;

    // §seriesFavCard — Contexte ÉPISODE pour le visuel/synopsis : on n'y bascule
    // PAS pour une sélection auto-par-défaut (E01 sans reprise) → le header et le
    // synopsis restent au niveau SÉRIE (la carte épisode, elle, reste affichée).
    final bool showEpisodeContext = _episodeSelected && !_autoDefaultSelection;

    // Image header : still épisode (si contexte épisode) > backdrop série
    final String? stillPath    = _episodeData?['still_path'] as String?;
    final String? headerPath   = (showEpisodeContext && stillPath != null)
        ? stillPath
        : _tmdbData?.backdropPath;
    // §quickwin — fallback affiche playlist quand pas de backdrop TMDB.
    // §posterFlash — ⚠️ L'ordre a CHANGÉ le 2026-09-10, sur mesure appareil :
    // le décor du fournisseur passait devant (format paysage, idéal pour un
    // en-tête) et affichait donc un champ que la vignette d'accueil ne regarde
    // JAMAIS — sur « Heroes », c'était l'affiche de Speed 2. Voir
    // `details_header_image.dart` pour le récit et l'interdiction associée.
    final String? playlistPoster = playlistHeaderImage(
      groupLogo: ParsedPlaylistService.bestLogoUrl(_uniqueVersions),
      episodeLogo: _currentEpisode.logoUrl,
      entryLogo: widget.entry.logoUrl,
      groupBackdrop: ParsedPlaylistService.bestBackdropUrl(_uniqueVersions),
      entryBackdrop: widget.entry.backdropUrl,
    );
    // §imgDiskCache — le backdrop demandait `original` (2000-3800 px, plusieurs
    // Mo) alors qu'il s'affiche sur 360 px de haut max (180-300 sur TV). Avec
    // un cache DISQUE, chaque fiche visitée serait stockée en pleine résolution
    // → `w1280`, largement au-dessus du besoin, ~5× plus léger.
    final String? headerUrl    = headerPath != null
        ? TmdbService.getPosterUrl(headerPath,
            size: (showEpisodeContext && stillPath != null) ? 'w780' : 'w1280')
        : playlistPoster;

    // §epTitleProvider — nom d'épisode : TMDB prioritaire, sinon le titre
    // fourni par le panel (mappé par fetchEpisodes).
    final String? tmdbEpName = _episodeData?['name'] as String?;
    final String? epName     = (tmdbEpName?.isNotEmpty == true)
        ? tmdbEpName
        : _currentEpisode.episodeTitle;
    final String? epOverview = _episodeData?['overview'] as String?;
    final String? epAirDate  = _episodeData?['air_date'] as String?;
    final double? epRating   = (_episodeData?['vote_average'] as num?)?.toDouble();

    // §23 — Métadonnées PROVIDER (catalogue JSON v5) en fallback de TMDB :
    // sans clé TMDB, la fiche affiche quand même synopsis/note/genre/année
    // venus de la playlist (séries surtout — la JSON API les transporte).
    T? fromVersions<T>(T? Function(M3uEntry) pick) {
      for (final e in [widget.entry, ..._uniqueVersions]) {
        final v = pick(e);
        if (v != null) return v;
      }
      return null;
    }

    // Titre et métadonnées : épisode prioritaire sur série, TMDB puis provider
    final double  rating      = epRating ?? _tmdbData?.voteAverage
        ?? fromVersions((e) => e.rating) ?? 0.0;
    final String? releaseDate = epAirDate?.split('-').first
        ?? _tmdbData?.releaseDate?.split('-').first
        ?? fromVersions((e) => e.releaseDate)?.split('-').first;

    // Titre affiché : nom épisode si sélectionné, sinon nom série/film
    final String seriesTitle = (_tmdbData?.title.isNotEmpty == true)
        ? _tmdbData!.title
        : widget.entry.displayName;
    final bool showEpTitle =
        showEpisodeContext && epName != null && epName.isNotEmpty;

    // Synopsis : épisode si contexte épisode, sinon série/film (TMDB → provider §23)
    // §epSynopsis — en contexte épisode, fallback sur le plot PROVIDER de
    // l'épisode courant (mappé par fetchEpisodes) quand TMDB n'a rien rendu,
    // AVANT de retomber sur le synopsis de la série.
    final String? providerEpPlot =
        (_currentEpisode.plot?.trim().isNotEmpty == true)
            ? _currentEpisode.plot
            : null;
    final String? displayOverview = showEpisodeContext &&
            (epOverview?.isNotEmpty == true || providerEpPlot != null)
        ? (epOverview?.isNotEmpty == true ? epOverview : providerEpPlot)
        : ((_tmdbData?.overview.isNotEmpty == true)
            ? _tmdbData!.overview
            : fromVersions((e) => e.plot));

    // §23 — Genres : TMDB prioritaire, sinon champ provider ("Action / Drame").
    final List<String> displayGenres = (_tmdbData?.genres.isNotEmpty == true)
        ? _tmdbData!.genres
        : (fromVersions((e) => e.genre)
                ?.split(RegExp(r'\s*[/,]\s*'))
                .where((g) => g.trim().isNotEmpty)
                .toList() ??
            const []);

    // §tvDetailsShrink — Sur TV, la fiche paraissait énorme : backdrop fixe 360px
    // (énorme part d'un écran à hauteur logique courte) + colonne d'infos étalée
    // sur toute la largeur + texte natif. On réduit les 3 leviers, uniquement sur
    // TV (mobile inchangé). Tunables ci-dessous.
    final bool isTvPlatform = PlatformTv.isTv;
    final double screenH = MediaQuery.sizeOf(context).height;
    final double headerHeight = isTvPlatform
        ? (screenH * _kTvBackdropFraction).clamp(260.0, 520.0)
        : 440.0;

    // §detailsHero (2026-09-06) — Le bloc titre (titre, accroche,
    // année/durée/âge, note) passe SUR l'image, porté par le dégradé.
    // L'affiche gagne toute la hauteur qu'il occupait : sur TÉLÉVISEUR elle
    // était réduite à un ruban, coupée net sur du noir (constaté avec
    // l'utilisateur le 2026-09-06, émulateur TV).
    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // TITRE — breadcrumb série + nom épisode quand épisode sélectionné
        if (showEpTitle) ...[
          Text(
            seriesTitle,
            style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          showEpTitle ? epName : seriesTitle,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            // §detailsHero — Posé sur l'image : blanc + ombre portée, et non la
            // couleur de texte du thème. Une affiche claire (fond crème) le
            // faisait disparaître quel que soit le dégradé.
            color: Colors.white,
            letterSpacing: 0.3,
            shadows: [
              Shadow(blurRadius: 14, color: Colors.black87, offset: Offset(0, 2)),
            ],
          ),
        ),
        // §tmdbMore — Accroche officielle sous le titre (italique).
        if (_tmdbData?.tagline?.isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text(
            _tmdbData!.tagline!,
            style: const TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: Colors.white70,
              shadows: [
                Shadow(blurRadius: 10, color: Colors.black87),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 6),

        // MÉTADONNÉES
        Row(
          children: [
            if (releaseDate != null)
              _buildMetaTag(releaseDate, cs.onSurfaceVariant),
            // §tmdbMore — la durée était CALCULÉE puis masquée pour
            // les séries (`&& !isSeries`) : « 45m/épisode » est une
            // info utile, on l'affiche aussi.
            // Revue 2026-09-11, D1A-10 — la durée se compose ici, dans la
            // langue de l'écran (« 45m/épisode » était écrit par le modèle).
            if (_tmdbData?.runtimeLabel(context.l10n) case final String runtime)
            ...[
              const SizedBox(width: 8),
              Text('•', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(width: 8),
              _buildMetaTag(runtime, cs.onSurfaceVariant),
            ],
            // §tmdbBadges — Certification d'âge (PEGI/CSA) au même
            // niveau que la date / durée / note.
            if (_tmdbData?.certification?.trim().isNotEmpty == true) ...[
              const SizedBox(width: 10),
              _badge(_tmdbData!.certification!.trim(), kWarning,
                  filled: true, icon: Icons.shield_outlined),
            ],
            const Spacer(),
            if (rating > 0) ...[
              Icon(Icons.star_rounded, color: kWarning, size: 18),
              const SizedBox(width: 3),
              Text(
                rating.toStringAsFixed(1),
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: kWarning, fontSize: 14),
              ),
              // §tmdbMore — nombre de votes : crédibilise la note.
              if ((_tmdbData?.voteCount ?? 0) > 0)
                Text(
                  ' · ${_formatCount(_tmdbData!.voteCount!)}',
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurfaceVariant),
                ),
            ],
          ],
        ),
      ],
    );

    return Scaffold(
      backgroundColor: cs.surface,
      // §beaconScope (2026-09-05) — **La pastille flottante de §navBlind a été
      // RETIRÉE d'ici.** Signalement utilisateur : « il y a des badges ajoutés
      // dans les fiches comme SYNOPSIS, ils sont en surplus ».
      //
      // Le repère répond à « où suis-je dans une page longue » quand
      // l'auto-scroll D-pad gare le focus près du bord bas — un vrai problème
      // sur l'ACCUEIL, où il reste. Sur cette fiche il n'annonçait que trois
      // sections (Synopsis, Casting principal, Infos) sur une page courte :
      // il coûtait un bandeau permanent par-dessus l'affiche pour une
      // information que le défilement donne déjà.
      //
      // ⚠️ Les `SectionMark` ci-dessous sont CONSERVÉS : `SectionMark` passe
      // par `SectionBeaconScope.maybeOf` (null-safe) — sans portée, il rend
      // simplement son enfant et n'inscrit rien. Remettre le repère = remettre
      // cette enveloppe, rien d'autre.
      body: Stack(
        children: [
          CustomScrollView(
            controller: _pageScroll,
            slivers: [
          // ── HEADER ────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: headerHeight,
            pinned: true,
            stretch: true,
            backgroundColor: cs.surface,
            // §detailsHero — ⚠️ Le bloc titre NE PEUT PAS vivre dans
            // `FlexibleSpaceBar.background` : ce dernier applique une PARALLAXE
            // (il décale son enfant vers le bas et le laisse déborder), et le
            // titre sortait de l'en-tête, coupé net à mi-hauteur — constaté sur
            // l'émulateur TV le 2026-09-06. Il vit donc dans une pile POSÉE
            // par-dessus, dont `LayoutBuilder` connaît la hauteur courante :
            // c'est aussi ce qui permet de l'effacer quand l'en-tête se replie,
            // au lieu de l'écraser sur la flèche de retour.
            flexibleSpace: LayoutBuilder(
              builder: (context, constraints) {
                final double collapsed =
                    kToolbarHeight + MediaQuery.paddingOf(context).top;
                final double span = (headerHeight - collapsed).abs() < 1
                    ? 1.0
                    : headerHeight - collapsed;
                final double open =
                    ((constraints.maxHeight - collapsed) / span).clamp(0.0, 1.0);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    FlexibleSpaceBar(
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (headerUrl != null)
                            AetherImage(
                              url: headerUrl,
                              fit: BoxFit.cover,
                              // §imgPerf — cap de DÉCODAGE uniquement. Le poids
                              // stocké est déjà borné par la taille demandée
                              // dans l'URL (`w1280`) : cf. l'avertissement sur
                              // `AetherImage` quant à `maxWidthDiskCache`, qui
                              // cassait cette image.
                              cacheWidth: 720,
                              fallback: (_) =>
                                  Container(color: cs.surfaceContainerHighest),
                            )
                          else
                            Container(color: cs.surfaceContainerHighest),
                          // §detailsHero — Le dégradé ne sert plus seulement à
                          // finir l'image : il doit RENDRE LISIBLE le titre posé
                          // dessus. D'où une zone haute laissée nue (l'image se
                          // voit vraiment) et une descente franche vers la
                          // couleur de fond.
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.transparent,
                                  Colors.black45,
                                  Colors.black87,
                                  cs.surface,
                                ],
                                // La moitie haute reste nue (l'image se voit),
                                // puis la descente est franche : le titre se
                                // pose vers 70 % de l'en-tete, il lui faut la.
                                stops: const [0.0, 0.22, 0.52, 0.84, 1.0],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        ignoring: open < 0.1,
                        child: Opacity(
                          opacity: open,
                          child: _tvShrinkContent(
                            context,
                            isTvPlatform,
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                              child: titleBlock,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // §detailsHero — Le titre REVIENT dans la barre quand
                    // l'en-tête se replie : le bloc du bas s'efface avec
                    // l'image, et on ne saurait plus quel film on regarde en
                    // parcourant le casting ou les versions.
                    //
                    // ⚠️ Il vit ici et pas dans `SliverAppBar.title`, qui est
                    // toujours peint : sans le taux de repli (`open`), connu du
                    // seul `LayoutBuilder`, on aurait le titre EN DOUBLE avec
                    // celui posé sur l'image.
                    // ⚠️ Pas `1 - open` tel quel : au repos, `open` vaut
                    // ~0,95 et non 1,0 (la barre d'état grignote la hauteur
                    // mesurée) → un titre FANTÔME à 5 % restait visible en
                    // haut à gauche, constaté sur l'émulateur TV. On ne fait
                    // apparaître le titre qu'une fois l'en-tête bien engagé.
                    if (open < 0.85)
                      Positioned(
                        top: MediaQuery.paddingOf(context).top,
                        left: 56,
                        right: 16,
                        height: kToolbarHeight,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: ((0.85 - open) / 0.85).clamp(0.0, 1.0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                showEpTitle ? epName : seriesTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  // Replié, la barre laisse encore voir le haut
                                  // de l'image : blanc + ombre, comme le titre
                                  // du bas, sinon une affiche claire l'avale.
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                        blurRadius: 12, color: Colors.black87),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

          // ── CONTENU ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _tvShrinkContent(
              context,
              isTvPlatform,
              Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // §detailsHero (2026-09-06) — **La ligne « De <réalisateur> »
                  // a été RETIRÉE d'ici.** Signalement utilisateur : « il y a un
                  // doublon, le nom du réalisateur est aussi dans les infos
                  // affichées plus bas ». C'était vrai depuis §tmdbMore : la
                  // section « Infos » porte une ligne `Réalisateur` / `Créateur`
                  // — elle était simplement MORTE (texte brut). C'est elle qui
                  // est devenue cliquable ; la place va à l'affiche.

                  // §detailsHero (2026-09-06) — **La rangée de badges de langue
                  // a été RETIRÉE d'ici.** Question de l'utilisateur devant la
                  // fiche « Little Brother » sur TÉLÉVISEUR : « c'est quoi le
                  // tag MULTI, je ne sais pas s'il sert vraiment ».
                  //
                  // Mesuré sur les six vraies versions du film : le badge
                  // réunissait les langues des TITRES et ne connaissait que
                  // MULTI/VF/VOSTFR/LEG. Il affichait donc « MULTI » alors que
                  // quatre versions sur six sont IT, FR, FR et ESP — des
                  // marqueurs fournisseur, invisibles pour lui. Il répétait en
                  // plus les pastilles de version juste dessous, qui portent la
                  // langue ET le nom de la liste, et il confondait `[MULTI-SUB]`
                  // (sous-titres, 10 331 titres) avec du multi-audio.
                  //
                  // La place gagnée va à l'affiche (`_kTvBackdropFraction`).
                  // ⚠️ Les mêmes badges de langue existent AILLEURS, avec leur
                  // propre rendu : `lib/widgets/media_chips.dart`, utilisé par
                  // les feuilles d'action. Ils n'ont PAS été touchés — là-bas
                  // il n'y a pas de pastilles de version pour les répéter.

                  // §quickwin — CTA discret si aucune clé TMDB configurée.
                  if (!_hasTmdbKey) ...[
                    _buildTmdbCta(cs),
                    const SizedBox(height: 16),
                  ],

                  // §detailsLayout — SYNOPSIS REMONTÉ : on lit de quoi ça parle
                  // AVANT de décider (ordre Netflix/Disney+). Il passe donc
                  // aussi devant le navigateur de saisons, ce qui est cohérent :
                  // on choisit son épisode après avoir lu le pitch.
                  if (displayOverview?.isNotEmpty == true) ...[
                    SectionMark('Synopsis',
                        child: Text(context.l10n.detSynopsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: cs.onSurfaceVariant))),
                    const SizedBox(height: 8),
                    Text(
                      displayOverview!,
                      style: TextStyle(
                          color: cs.onSurfaceVariant, height: 1.55, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // §tmdbOnlyDetails — Titre absent des listes : on remplace
                  // TOUTE la zone d'actions (et le navigateur série, qui n'a
                  // aucune saison à lister) par le panneau d'indisponibilité.
                  // Indispensable : `_buildActionButtons` câble « Lire » et
                  // « Télécharger » sur `_selectedEntry.url`, ici vide.
                  if (_isTmdbOnly) ...[
                    _buildUnavailablePanel(cs),
                    if (_tmdbData?.trailerKey != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: SizedBox(
                            width: double.infinity, child: _buildTrailerButton()),
                      ),
                    const SizedBox(height: 16),
                  ],

                  // ── SÉRIES : navigation immédiate ──────────────────────────
                  if (isSeries && !_isTmdbOnly) ...[
                    _buildSeriesNavigator(cs, l10n),
                    const SizedBox(height: 16),
                  ],

                  // ── FILMS : qualités + actions ──────────────────────────────
                  if (!isSeries && !_isTmdbOnly) ...[
                    if (_uniqueVersions.isNotEmpty) ...[
                      _buildQualityChips(cs),
                      const SizedBox(height: 12),
                    ],
                    _buildActionButtons(l10n),
                    if (_tmdbData?.trailerKey != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: SizedBox(
                            width: double.infinity, child: _buildTrailerButton()),
                      ),
                    const SizedBox(height: 16),
                  ],

                  // BANDE-ANNONCE — série tant qu'on est en contexte SÉRIE
                  // (aucun épisode en contexte épisode : défaut E01 inclus).
                  // (`!_isTmdbOnly` : le panneau d'indisponibilité porte déjà
                  // son propre bouton bande-annonce → évite le doublon.)
                  if (isSeries &&
                      !_isTmdbOnly &&
                      !showEpisodeContext &&
                      _tmdbData?.trailerKey != null) ...[
                    SizedBox(width: double.infinity, child: _buildTrailerButton()),
                    const SizedBox(height: 16),
                  ],

                  // CASTING — vignettes acteurs avec photo (carrousel horizontal)
                  if (hasTmdb && _tmdbData!.castMembers.isNotEmpty) ...[
                    SectionMark(context.l10n.detMainCast,
                        child: Text(context.l10n.detMainCast,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(color: cs.onSurfaceVariant))),
                    Divider(color: cs.outlineVariant),
                    SizedBox(
                      // §castPhotos — hauteur = photo portrait 2:3 (92×138) + nom
                      // (2 lignes) + rôle + marge pour le textScaler TV ×1.3.
                      height: 218,
                      // §dpadRowEntry — Sans région propre, descendre depuis la
                      // bande-annonce atterrissait sur le 3e acteur (repli
                      // géométrique) ; repartir vers la gauche faisait alors
                      // sauter toute la rangée d'un coup.
                      child: DpadRegion(
                        debugLabel: 'detailsCast',
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          // §rowFocusFit — cf. la rangée des similaires.
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          // §focusScroll — cache plus large pour que la nav D-pad
                          // trouve toujours la card suivante dans l'arbre de focus.
                          // ignore: deprecated_member_use
                          cacheExtent: 600,
                          // Lot 9 (§tmdbPlus) — 12 visibles, puis une tuile
                          // « Voir plus » qui déplie le reste DANS la même
                          // rangée. ⚠️ Pas de nouvelle route : sur TV, une
                          // page de plus est une sortie de plus à gérer
                          // (§tvOptionsBack), pour une liste qui tient dans
                          // un carrousel qu'on sait déjà parcourir.
                          itemCount: _visibleCast.length +
                              (_castHasMore ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, i) {
                            if (i == _visibleCast.length) {
                              return _MoreCastCard(
                                  onTap: () => setState(
                                      () => _castExpanded = true));
                            }
                            return _CastCard(
                                member: _visibleCast[i], isEntry: i == 0);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ]
                  // Fallback : anciens noms seuls si pas de casting enrichi.
                  else if (hasTmdb && _tmdbData!.cast.isNotEmpty) ...[
                    SectionMark(context.l10n.detMainCast,
                        child: Text(context.l10n.detMainCast,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(color: cs.onSurfaceVariant))),
                    Divider(color: cs.outlineVariant),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tmdbData!.cast
                          .map((a) => ActionChip(
                                avatar: Icon(Icons.person,
                                    size: 16, color: kAccentSecondary),
                                label: Text(a),
                                onPressed: () => _searchActor(a),
                                backgroundColor: cs.surfaceContainerHighest,
                                labelStyle: TextStyle(
                                    color: cs.onSurface,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // §infoGenre — Les genres ne forment plus une rangée de chips
                  // isolée ici : ils sont devenus la 1re ligne de « Infos »
                  // (voir `_buildInfoSection`), où ils sont enfin étiquetés.

                  // §tmdbInfo (2026-09-06) — **Ce bloc ne DEVINE plus.**
                  //
                  // Il lisait le suffixe entre parenthèses du `group-title` du
                  // fournisseur. Or §catFix a mesuré que CE fournisseur suffixe
                  // **tous** ses group-titles de séries par
                  // `( NETFLIX| PRIME | HBO | APPLE TV+ | STARZ | PARAMOUNT+ )` :
                  // la fiche annonçait donc SIX plateformes sur des milliers de
                  // séries, sans qu'aucune soit vérifiée. Ce n'était pas une
                  // approximation, c'était du bruit.
                  //
                  // Il affiche maintenant `networks` (TMDB) : le ou les
                  // diffuseurs réels.
                  //
                  // ✅ **Lot 9 (§tmdbPlus)** — Et, pour un FILM, les vraies
                  // plateformes de `watch/providers` : TMDB ne rend jamais de
                  // `networks` pour un film, et le bloc disparaissait alors
                  // complètement alors que la donnée existait. Elle vient dans
                  // la MÊME réponse (`append_to_response`), donc toujours sans
                  // requête de plus.
                  Builder(builder: (context) {
                    // ⚠️ **Plafonné à 4.** TMDB liste TOUTES les stations
                    // affiliées : « Jujutsu Kaisen » en rend **31** (MBS, TBS,
                    // CBC, Tulip Television, tys…), soit trois rangées de
                    // pastilles illisibles — mesuré sur l'émulateur TV le
                    // 2026-09-06. Les premières sont les diffuseurs principaux.
                    //
                    // ⚠️ `networks` D'ABORD quand il existe : pour une série,
                    // le diffuseur d'origine dit mieux « d'où ça vient » que
                    // le catalogue où elle est rangée aujourd'hui. Les
                    // plateformes ne prennent la place que là où `networks`
                    // est vide — c'est-à-dire sur les films.
                    final List<String> source =
                        (_tmdbData?.networks ?? const <String>[]).isNotEmpty
                            ? _tmdbData!.networks
                            : (_tmdbData?.watchProviders ?? const <String>[]);
                    final platforms = source.take(4).toList();
                    if (platforms.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.infoNetwork,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: platforms.map((p) {
                            // Les noms viennent de TMDB (« Amazon Prime Video »,
                            // « MBS »…) : on les NORMALISE pour la couleur de
                            // marque seulement, et on affiche le nom d'origine.
                            // Revue 2026-09-11, D4A-08 — rendue LISIBLE sur
                            // la surface : Canal+/Peacock sont noirs, donc
                            // noir sur noir en thème sombre (≈ 1:1).
                            final color = brandReadableOn(
                                platformBrandColor(_normalizePlatform(p)),
                                cs.surface);
                            return Chip(
                              label: Text(p),
                              backgroundColor: color.withAlpha(40),
                              labelStyle: TextStyle(
                                  color: color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold),
                              side: BorderSide(color: color.withAlpha(100)),
                              padding: EdgeInsets.zero,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  }),

                  // §tmdbMore — Section « Infos » (remplace l'ancienne ligne
                  // brute « Production: A, B, C ») : genre, réalisateur, pays,
                  // studios, statut, durée.
                  _buildInfoSection(cs, isSeries, displayGenres),

                  // ── À DÉCOUVRIR (en fin de fiche) ──────────────────────────
                  // §tmdbReco — Saga (collection) puis titres similaires dispo :
                  // placés APRÈS toutes les infos du film pour ne pas couper le
                  // bloc d'identité (synopsis/casting/genres/prod).
                  if (_collection.isNotEmpty)
                    _relatedRow(
                      _collectionName != null
                          ? context.l10n.detSaga(_collectionName!)
                          : context.l10n.detSameSaga,
                      _collection,
                      cs,
                    ),
                  if (_similar.isNotEmpty)
                    _relatedRow(
                        context.l10n.detSimilarAvailable, _similar, cs),

                  // LOADING
                  if (_isLoading && !isSeries)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
            ),
          ),
            ],
          ),
          // §detailsMore (b) — L'indice de défilement, TV seulement.
          if (isTvPlatform) _buildScrollHint(context),
        ],
      ),
    );
  }

  /// §detailsMore (b) — « les fiches TV ont une partie manquante des détails ».
  ///
  /// **Rien ne manque : tout est plus bas, et rien ne le dit.** Vérifié dans le
  /// code — sur téléviseur l'en-tête occupe `_kTvBackdropFraction` de la
  /// hauteur d'écran, soit **72 %** (`headerHeight = screenH * 0.72`, borné
  /// 260-520). Casting, saga, similaires et bloc Infos commencent donc sous les
  /// 28 % restants, et l'affiche pleine largeur ne laisse rien dépasser qui
  /// suggère une suite. Au doigt on descend par réflexe ; à la télécommande on
  /// ne descend que si on sait qu'il y a quelque chose.
  ///
  /// ⛔ **Ne PAS re-cadrer l'affiche pour régler ça** : la fraction a été
  /// choisie avec l'utilisateur le 2026-09-06 (§detailsHero), l'image « ne
  /// partage plus l'écran avec le bloc titre, elle le PORTE ». Et ⛔ §posterFlash
  /// interdit de toucher à la composition de l'en-tête. On ajoute donc un
  /// indice PAR-DESSUS, qui s'efface au premier mouvement.
  ///
  /// ⚠️ Non focusable : il ne doit être ni une étape de la traversée D-pad
  /// (§dpadChildFocus), ni une cible ; il n'existe que pour être vu.
  Widget _buildScrollHint(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Recette AVD TV du 2026-09-17 — l'indice n'apparaissait JAMAIS : il
    // n'était calculé qu'à la première image, quand la fiche est encore courte
    // (le contenu TMDB n'est pas arrivé), puis seulement sur un défilement. Or
    // c'est l'arrivée du casting qui fait déborder la page, sans qu'aucun
    // défilement n'ait lieu. On recalcule donc après CHAQUE reconstruction.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollHint();
    });
    return Positioned(
      left: 0,
      right: 0,
      bottom: 12,
      child: IgnorePointer(
        child: ValueListenableBuilder<bool>(
          valueListenable: _scrollHintVisible,
          builder: (context, visible, child) => AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            child: child,
          ),
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surface.withAlpha(220),
                // §btnShape — le rayon du thème, pas une pilule.
                borderRadius: BorderRadius.circular(
                    ThemeService.config.value.borderRadius),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.keyboard_arrow_down,
                      size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.detMoreBelow,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Navigateur série ────────────────────────────────────────────────────────

  Widget _buildSeriesNavigator(ColorScheme cs, AppLocalizations l10n) {
    final hasSeasons = _seasonEpisodes.isNotEmpty;
    final totalSeasons = _seasonEpisodes.length;
    final totalEpisodes =
        _seasonEpisodes.values.fold<int>(0, (acc, eps) => acc + eps.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── §seasonsUI — En-tête de section "Saisons" + total ────────────────
        // §beaconScope (2026-09-05) — Ce titre était le SEUL de la fiche à être
        // stylé comme un badge (majuscules, lettres espacées, couleur d'accent,
        // barre verticale dégradée) alors que « Synopsis », « Casting
        // principal » et « Infos » sont de simples titres. Aligné sur eux : une
        // page ne doit pas avoir deux grammaires de titre.
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(
                context.l10n.detSeasons,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (hasSeasons) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    totalSeasons == 1
                        ? context.l10n.detSeasonsCountOne(totalSeasons, totalEpisodes)
                        : context.l10n.detSeasonsCountMany(totalSeasons, totalEpisodes),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── SAISONS (chips contour néon cohérent avec le style fiche) ────────
        if (!hasSeasons && _episodesLoading)
          // §seriesFlow — chargement lazy des épisodes (XtreamApiService).
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(kAccentPrimary),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  context.l10n.detLoadingEpisodes,
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          )
        else if (!hasSeasons && _episodesFailure != null)
          // §episodeTruth — Le fetch a ÉCHOUÉ : on dit pourquoi, et on offre
          // de réessayer. Confondre ce cas avec « aucun épisode » laissait
          // l'utilisateur devant une série vide sans rien à tenter.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(Icons.cloud_off_outlined, size: 18, color: kWarning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.detEpisodesError(
                        episodesFailureText(context.l10n, _episodesFailure!)),
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),
                FocusableChip(
                  onTap: _retryEpisodes,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kWarning.withAlpha(120)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, size: 16, color: kWarning),
                        const SizedBox(width: 6),
                        Text(context.l10n.playerRetry,
                            style: TextStyle(
                                fontSize: 13,
                                color: kWarning,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (!hasSeasons)
          // §seriesFlow — fetch terminé, réussi, et le panel n'a réellement
          // aucun épisode pour cette série. Plus de spinner infini.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(Icons.tv_off_outlined,
                    size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.detNoEpisodes,
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          )
        else
          // §dpadRowEntry — Région propre : on entre par la 1re saison.
          DpadRegion(
            debugLabel: 'detailsSeasons',
            child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _seasonEpisodes.entries.toList().asMap().entries.map((e) {
                final entry = e.value;
                final sNum = entry.key;
                final epCount = entry.value.length;
                final isSelected = sNum == _selectedSeason;
                final accent = isSelected ? kAccentPrimary : cs.onSurfaceVariant;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  // §rowAnchorDetails — utile sur les séries à 10+ saisons.
                  child: FocusableChip(
                    onTap: () => _selectSeason(sNum),
                    anchorRowStart: true,
                    entry: e.key == 0,
                    borderRadius: BorderRadius.circular(14),
                    child: GestureDetector(
                      onTap: isSelected ? null : () => _selectSeason(sNum),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? kAccentPrimary.withAlpha(28)
                              : cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? kAccentPrimary
                                : cs.outline.withAlpha(40),
                            width: isSelected ? 1.8 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: kAccentPrimary.withAlpha(70),
                                    blurRadius: 12,
                                    spreadRadius: -2,
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.l10n.detSeasonNumber(
                                  sNum.toString().padLeft(2, '0')),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? kAccentPrimary.withAlpha(45)
                                    : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                context.l10n.detEpisodesShort(epCount),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            ),
          ),

        // ÉPISODES (scroll horizontal, apparaît dès qu'une saison est choisie)
        if (_selectedSeason != null &&
            _seasonEpisodes[_selectedSeason] != null) ...[
          const SizedBox(height: 12),
          // §dpadRowEntry — Région propre : on entre par le 1er épisode.
          // La `key` sur la saison recrée la région à chaque changement de
          // saison : sans elle, la région resterait montée avec la mémoire de
          // l'ancienne saison et ferait atterrir le focus en plein milieu.
          DpadRegion(
            key: ValueKey<int?>(_selectedSeason),
            debugLabel: 'detailsEpisodes',
            child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _episodeScrollController,
            // §dlPlayLocal — La rangée d'épisodes écoute les téléchargements :
            // un épisode qui finit pendant qu'on regarde la fiche doit se
            // marquer tout de suite.
            child: ValueListenableBuilder<List<DownloadTask>>(
              valueListenable: DownloadManagerService().tasksNotifier,
              builder: (context, tasks, _) => Row(
              children: _seasonEpisodes[_selectedSeason]!
                  .asMap()
                  .entries
                  .map((e) {
                final group = e.value;
                // §dlPlayLocal — CET épisode est-il sur l'appareil ? On
                // interroge TOUTES ses versions (le groupe d'un épisode, pas
                // celui de la série) : téléchargé en HD ou en 4K, il est
                // téléchargé.
                final bool isLocal = hasLocalFileFor(
                  networkPath: group.best.url,
                  groupUrls: [for (final v in group.versions) v.url],
                  tasks: tasks,
                );
                final isCurrent = _episodeSelected &&
                    group.episodeNumber ==
                        _currentEpisode.title.episodeNumber &&
                    _selectedSeason == _currentEpisode.title.seasonNumber;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  // §3c Phase 1 — FocusableChip : l'épisode devient sélectionnable
                  // au D-pad (avant : GestureDetector tap-only). onTap toujours
                  // défini → l'épisode courant garde le focus.
                  // §rowAnchorDetails — chip focusé calé à gauche de la rangée.
                  child: FocusableChip(
                    onTap: () => _selectEpisode(group),
                    anchorRowStart: true,
                    entry: e.key == 0,
                    borderRadius: BorderRadius.circular(8),
                    child: GestureDetector(
                    onTap: isCurrent ? null : () => _selectEpisode(group),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 52,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? cs.primary.withAlpha(40)
                            : cs.surfaceContainerHighest,
                        border: Border.all(
                          color: isCurrent
                              ? cs.primary
                              : cs.outlineVariant,
                          width: isCurrent ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      // §dlPlayLocal — La puce fait 52x40 : « Téléchargé » n'y
                      // tient pas. L'information passe par une marque, et le
                      // MOT est porté par `Semantics` pour que TalkBack le
                      // lise (§l10nAll : la clé existe, elle est simplement
                      // dite au lieu d'être écrite).
                      //
                      // ⚠️ Rien de focalisable ici : la puce EST déjà l'arrêt
                      // D-pad (§dpadChildFocus).
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Text(
                            'E${group.episodeNumber.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCurrent
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                          if (isLocal)
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Semantics(
                                label: L10n.current.dlBadgeDownloaded,
                                child: Icon(Icons.download_done_rounded,
                                    size: 11, color: kSuccess),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  ),
                );
              }).toList(),
            ),
            ),
            ),
          ),
        ],

        // CARD ÉPISODE SÉLECTIONNÉ
        if (_episodeSelected) ...[
          const SizedBox(height: 16),
          _buildEpisodeCard(cs, l10n),
        ],
      ],
    );
  }

  Widget _buildEpisodeCard(ColorScheme cs, AppLocalizations l10n) {
    final epDate   = _episodeData?['air_date'] as String?;
    final epRating = (_episodeData?['vote_average'] as num?)?.toDouble();

    final sNum = _currentEpisode.title.seasonNumber;
    final eNum = _currentEpisode.title.episodeNumber;
    final label = (sNum != null && eNum != null)
        ? 'S${sNum.toString().padLeft(2, '0')}  E${eNum.toString().padLeft(2, '0')}'
        : '';

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label + titre épisode
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.primary.withAlpha(80)),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                    letterSpacing: 1,
                  ),
                ),
              ),
              if (epDate != null) ...[
                const SizedBox(width: 10),
                Text(
                  epDate,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
              if (epRating != null && epRating > 0) ...[
                const Spacer(),
                Icon(Icons.star_rounded, color: kWarning, size: 14),
                const SizedBox(width: 2),
                Text(
                  epRating.toStringAsFixed(1),
                  style: TextStyle(
                      fontSize: 12, color: kWarning, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),

          // Barre de chargement TMDB
          if (_isLoading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              minHeight: 2,
              borderRadius: BorderRadius.circular(2),
              color: cs.primary.withAlpha(120),
              backgroundColor: cs.outlineVariant,
            ),
          ],

          const SizedBox(height: 14),

          // QUALITÉS
          if (_uniqueVersions.isNotEmpty) ...[
            _buildQualityChips(cs),
            const SizedBox(height: 12),
          ],

          // PLAY + DOWNLOAD
          _buildActionButtons(l10n),
        ],
      ),
    );
  }

  // ── Widgets partagés ───────────────────────────────────────────────────────

  Widget _buildQualityChips(ColorScheme cs) {
    // §qualityTruth — Une mesure peut tomber pendant qu'on est DANS le lecteur,
    // fiche encore montée derrière : sans cet abonnement, la vraie qualité
    // n'apparaîtrait qu'à la réouverture de la fiche.
    return ValueListenableBuilder<int>(
      valueListenable: MeasuredQualityService.version,
      // §dlPlayLocal — La pastille « Téléchargé » doit apparaître dès que le
      // fichier est là, sans refermer la fiche : un téléchargement peut finir
      // pendant qu'on la regarde.
      builder: (_, __, ___) => ValueListenableBuilder<List<DownloadTask>>(
        valueListenable: DownloadManagerService().tasksNotifier,
        builder: (_, tasks, __) => _buildQualityChipsInner(cs, tasks),
      ),
    );
  }

  Widget _buildQualityChipsInner(ColorScheme cs, List<DownloadTask> tasks) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: _uniqueVersions.asMap().entries.map((e) {
        final v        = e.value;
        final label    = _qualityLabel(v, e.key);
        final color    = _qualityColor(v.title.quality);
        final selected = _selectedEntry == v;
        // §lightTheme (2026-09-16) — ⚠️ La version NON choisie s'écrivait à
        // coups d'opacité (16 / 60 / 90) sur une couleur de qualité qui n'est
        // pas dérivée : sur le fond blanc du thème clair, la pastille
        // « FHD VOD » n'était tout simplement plus à l'écran (mesuré sur la
        // planche, captures `light_57` et `light_62`). L'atténuation est
        // maintenant DÉRIVÉE, avec un plancher de contraste : 3:1 pour la
        // bordure et la pastille, 4,5:1 pour le texte qu'il faut lire.
        // ⛔ Le code couleur des qualités, lui, ne bouge pas : la version
        // CHOISIE porte toujours la teinte brute.
        final Color faded     = mutedOn(color, cs.surface);
        final Color fadedText =
            mutedOn(color, cs.surface, minRatio: kMinTextContrast);
        // §3c Phase 1 — FocusableChip : la version FHD/HD devient sélectionnable
        // au D-pad (avant : GestureDetector tap-only).
        return FocusableChip(
          onTap: () => setState(() => _selectedEntry = v),
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
          onTap: () => setState(() => _selectedEntry = v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            // §versionSelected — La sélection ne peut PAS reposer sur la seule
            // couleur. Elle s'exprimait par un fond à 21 % d'opacité contre
            // 8 %, une bordure un peu plus dense et une graisse : à trois
            // mètres d'un téléviseur, ces trois écarts sont invisibles.
            //
            // ⚠️ Pire : sur TV, `FocusableChip` peint un anneau vert vif autour
            // de la puce FOCALISÉE. Focus et sélection partageaient donc le même
            // canal — la puce sous le curseur avait l'air choisie, et la vraie
            // sélection se noyait. « Où je suis » et « ce qui va être lu » sont
            // deux informations différentes : la première garde l'anneau, la
            // seconde prend un marqueur EXPLICITE et non chromatique.
            decoration: BoxDecoration(
              color: selected ? color.withAlpha(70) : faded.withAlpha(20),
              border: Border.all(
                color: selected ? color : faded,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Même motif que le sélecteur de pistes (`_TrackRow`) :
                    // pastille cochée / cercle vide. L'emplacement est TOUJOURS
                    // réservé, donc rien ne se décale quand on change de choix.
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      size: 13,
                      color: selected ? color : faded,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                        color: selected ? color : fadedText,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
                // §qualityTruth — Ce que ce flux a RÉELLEMENT servi la
                // dernière fois qu'on l'a lu. Rien tant qu'il n'a pas été
                // mesuré : mieux vaut ne rien dire qu'affirmer sans preuve.
                ..._measuredSuffix(v),
                // §dlPlayLocal — CETTE version-là est sur l'appareil. La
                // question se pose PAR VERSION : un titre peut être
                // téléchargé en HD et pas en 4K, et la feuille de l'accueil
                // ne répond que pour le groupe.
                //
                // ⚠️ `groupUrls` vide À DESSEIN : `hasLocalFileFor` accepte
                // n'importe quelle URL du groupe, ce qui rendrait `true` pour
                // TOUTES les pastilles dès qu'UNE version est sur le disque —
                // exactement le contraire de ce qu'on veut dire ici.
                //
                // ⚠️ Non focalisable : c'est une information, pas une cible.
                // La puce qui la porte est déjà un arrêt D-pad
                // (§dpadChildFocus : jamais un second arrêt à l'intérieur).
                if (hasLocalFileFor(
                  networkPath: v.url,
                  groupUrls: const <String>[],
                  tasks: tasks,
                )) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download_done_rounded,
                          size: 11, color: kSuccess),
                      const SizedBox(width: 3),
                      Text(
                        L10n.current.dlBadgeDownloaded,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: kSuccess,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          ),
        );
      }).toList(),
    );
  }

  /// §qualityTruth — Ligne « mesuré » sous la pastille de version.
  ///
  /// Trois écritures, parce que les trois situations n'ont pas la même valeur
  /// pour l'utilisateur : une liste qui **survend** est une alerte, une liste
  /// conforme est une confirmation discrète, une liste qui sous-estime est une
  /// bonne surprise. Un flux jamais lu n'affiche rien.
  ///
  /// ⚠️ Une mesure existe aussi quand la qualité annoncée n'est PAS une
  /// définition (`CAM`, ou aucune) : on affiche alors la résolution seule, sans
  /// verdict — il n'y a rien à confronter (cf. [QualityScale.rankOf]).
  List<Widget> _measuredSuffix(M3uEntry v) {
    final measured = MeasuredQualityService.get(v.url);
    if (measured == null) return const [];

    final verdict = measured.verdictFor(v.title.quality);
    final (String text, Color tint) = switch (verdict) {
      QualityVerdict.survendu =>
        (L10n.current.detRealOversold(measured.definitionLabel), kError),
      QualityVerdict.sousEstime =>
        (L10n.current.detReal(measured.definitionLabel), kAccentSecondary),
      QualityVerdict.conforme => ('✓ ${measured.height}p', kSuccess),
      QualityVerdict.unknown => ('${measured.height}p', kQualityUnknown),
    };

    return [
      const SizedBox(height: 2),
      Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          fontWeight: verdict == QualityVerdict.survendu
              ? FontWeight.bold
              : FontWeight.w500,
          color: tint,
          height: 1.1,
        ),
      ),
    ];
  }

  /// Format Duration → "1h23" ou "12:34" pour libellé court de reprise.
  String _formatResumeShort(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    // Revue 2026-09-11, lot 7 (recette en anglais) — « RESUME · 1h00 » : la
    // forme française sur un écran anglais. Même clé que les autres durées
    // courtes (« 1h00 » en français, inchangé ; « 1h 00m » en anglais).
    if (h > 0) {
      return context.l10n.durationHoursMinutes(h, m.toString().padLeft(2, '0'));
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // §watchContext — Infos contextuelles passées à l'overlay du player.
  bool get _isSeriesPlayback => _selectedEntry.type == M3uContentType.series;

  /// Nom de la série (breadcrumb au-dessus du titre) — séries uniquement.
  String? get _playerSeriesName {
    if (!_isSeriesPlayback) return null;
    final t = _tmdbData?.title;
    return (t != null && t.isNotEmpty) ? t : widget.entry.displayName;
  }

  /// Titre principal du player : nom de l'épisode (TMDB) pour une série, sinon
  /// le nom de l'entrée (film, ou série sans données épisode).
  String get _playerTitle {
    if (_isSeriesPlayback) {
      final ep = _episodeData?['name'] as String?;
      if (ep != null && ep.isNotEmpty) return ep;
      // §epTitleProvider — fallback titre panel quand TMDB n'a rien rendu.
      final provider = _currentEpisode.episodeTitle;
      if (provider != null && provider.isNotEmpty) return provider;
    }
    return _selectedEntry.displayName;
  }

  /// Synopsis affiché dans l'overlay : épisode (TMDB) > œuvre (TMDB) > provider.
  String? get _playerSynopsis {
    if (_isSeriesPlayback) {
      final epo = _episodeData?['overview'] as String?;
      if (epo != null && epo.isNotEmpty) return epo;
    }
    final ov = _tmdbData?.overview;
    if (ov != null && ov.isNotEmpty) return ov;
    for (final e in [widget.entry, ..._uniqueVersions]) {
      final p = e.plot;
      if (p != null && p.isNotEmpty) return p;
    }
    return null;
  }

  Future<void> _launchSelected({Duration? from}) async {
    // §deviceCaps — la porte : une version que l'appareil ne peut pas lire est
    // refusée ICI, avec la raison mesurée, avant d'ouvrir quoi que ce soit.
    if (!await PlaybackGate.allow(context, _selectedEntry)) return;
    if (!mounted) return;
    // Auto-ajout favoris au play, cohérent avec le reste de l'app (§1d)
    FavoritesService.addEntry(_selectedEntry);
    // §1i — Si on lance un épisode et qu'il existe un suivant, on passe le
    // callback au player pour exposer le bouton "épisode suivant" (▶▶).
    final hasNext = _isEpisode && _nextEpisode != null;
    // §dlPlayLocal — un film ou un épisode DÉJÀ TÉLÉCHARGÉ se lit depuis le
    // disque, sous la même clé de reprise que son flux. Le choix se fait ici,
    // pour les quatre points de lancement à la fois.
    await launchPlayback(
      context,
      networkPath: _selectedEntry.url,
      groupUrls: _resumeUrls(),
      // R23 — avertir quand l'abonnement n'a plus de connexion libre.
      accountId: _selectedEntry.accountId,
      build: (src) => PlayerPage(
        path: src.path,
        progressKey: src.progressKey,
        title: _playerTitle,
        // §stallCount — rattache les blocages au fournisseur.
        accountId: _selectedEntry.accountId,
        // §watchContext a/b — badges qualité + saison/épisode dans le player.
        qualityTag: _selectedEntry.title.qualityOrDefault,
        episodeTag: _selectedEntry.title.seasonEpisodeLabel,
        // §watchContext — nom série + synopsis (si dispo) dans l'overlay.
        seriesName: _playerSeriesName,
        synopsis: _playerSynopsis,
        sourceType: src.sourceType,
        badgeType: _selectedEntry.type == M3uContentType.series
            ? PlayerBadgeType.series
            : PlayerBadgeType.movie,
        startPosition: from,
        // §endOfMovie — toutes les versions du titre s'effacent à la fin.
        siblingResumeKeys: _resumeUrls(),
        // §heroSeriesResume — la clé au niveau SÉRIE, pour que l'accueil
        // retrouve une série en cours (l'URL d'un épisode n'est pas au
        // catalogue). ⛔ Jamais dans `_resumeUrls()` : ces clés-là s'effacent
        // à la fin de l'épisode, ce qui effacerait la reprise de la série.
        seriesResumeKey: seriesResumeKeyFor(
          stubs: _apiSeriesStubs,
          episode: _selectedEntry,
        ),
        seasonNumber: _selectedEntry.title.seasonNumber,
        // §nowPlaying — affiche TMDB pour l'écran verrouillé, logo en repli.
        posterUrl: TmdbService.getPosterUrl(_tmdbData?.posterPath) ??
            _selectedEntry.logoUrl,
        // §episodeMeta — Le player ne pousse plus de nouvelle route pour changer
        // d'épisode : il demande le contenu suivant et bascule en place.
        onRequestNext: hasNext ? _prepareNextEpisode : null,
      ),
    );
  }

  /// §episodeMeta — Prépare l'épisode suivant **métadonnées comprises**.
  ///
  /// L'ancien chemin (`_goToNextEpisode` + pop/push) lançait la lecture à la
  /// frame suivante, bien avant que `_loadData()` — qui interroge TMDB — n'ait
  /// résolu : le nouveau player naissait donc avec le titre et le synopsis de
  /// l'épisode **précédent**, et ses champs étant `final`, ils ne pouvaient plus
  /// jamais être corrigés.
  ///
  /// Ici on **attend** le chargement avant de rendre la main. Le player couvre
  /// cette latence par son décompte de fin d'épisode (ou un bref « chargement… »
  /// sur un appui manuel).
  Future<PlayerMedia?> _prepareNextEpisode() async {
    final next = _nextEpisode;
    if (next == null) return null;
    final epNum = next.title.episodeNumber;
    final season = next.title.seasonNumber;
    if (epNum == null || season == null) return null;
    final group = _seasonEpisodes[season]
        ?.where((g) => g.episodeNumber == epNum)
        .firstOrNull;
    if (group == null) return null;

    setState(() {
      _selectedSeason = season;
      _episodeSelected = true;
      _autoDefaultSelection = false; // enchaînement épisode suivant
      _currentEpisode = group.best;
      _uniqueVersions = _deduplicateVersions(group.versions);
      _selectedEntry = _uniqueVersions.isNotEmpty
          ? _uniqueVersions.first
          : group.best;
      _isLoading = true;
      // LA correction : sans ça, `_playerTitle`/`_playerSynopsis` reliraient les
      // données TMDB de l'épisode précédent. `_selectEpisode` le faisait déjà,
      // ce chemin-ci l'avait oublié.
      _episodeData = null;
    });

    await _loadData();
    if (!mounted) return null;

    FavoritesService.addEntry(_selectedEntry);
    // §dlPlayLocal — l'épisode suivant se lit lui aussi depuis le disque
    // quand il y est : l'enchaînement automatique ne doit pas repasser au flux
    // pour un épisode déjà téléchargé.
    return resolvePlayableMedia(
      networkPath: _selectedEntry.url,
      groupUrls: _resumeUrls(),
      build: (source) => PlayerMedia(
        path: source.path,
        progressKey: source.progressKey,
        title: _playerTitle,
        qualityTag: _selectedEntry.title.qualityOrDefault,
        episodeTag: _selectedEntry.title.seasonEpisodeLabel,
        seriesName: _playerSeriesName,
        synopsis: _playerSynopsis,
        sourceType: source.sourceType,
        badgeType: PlayerBadgeType.series,
        seasonNumber: season,
        siblingResumeKeys: _resumeUrls(), // §endOfMovie
        // §heroSeriesResume — la clé au niveau SÉRIE, pour que l'accueil retrouve
        // une série en cours (l'URL d'un épisode n'est pas au catalogue).
        // ⛔ Jamais dans `_resumeUrls()` : ces clés-là s'effacent à la fin de
        // l'épisode, ce qui effacerait la reprise de TOUTE la série.
        seriesResumeKey: seriesResumeKeyFor(
          stubs: _apiSeriesStubs,
          episode: _selectedEntry,
        ),
        // §nowPlaying — l'épisode suivant garde une image dans la notification.
        posterUrl: TmdbService.getPosterUrl(_tmdbData?.posterPath) ??
            _selectedEntry.logoUrl,
      ),
    );
  }

  Widget _buildActionButtons(AppLocalizations l10n) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        FavoritesService.version,
        WatchProgressService.version,
        // §dlPlayLocal — le bouton change de mot quand le téléchargement se
        // termine ou que le fichier est supprimé, sans rouvrir la fiche.
        localFilesListenable,
      ]),
      builder: (ctx, _) {
        final isFav = FavoritesService.isEntryFavorite(_selectedEntry);
        // §dlPlayLocal — « Lire hors ligne » dit le RÉSULTAT (§clientText) :
        // ce titre se lit sans réseau parce qu'il est sur l'appareil.
        final bool hasLocal = hasLocalFileFor(
          networkPath: _selectedEntry.url,
          groupUrls: _resumeUrls(),
        );
        // §resumeUnify — La reprise est partagée entre TOUTES les versions
        // (qualités ET listes) du contenu courant : on lit la plus récente
        // parmi toutes les URLs, pas seulement la qualité sélectionnée.
        final progress = WatchProgressService.getProgressForAny(
            _resumeUrls());
        final hasResume = progress != null && progress.position.inSeconds > 5;

        // §detailsActions — Deux lignes au même gabarit 75/25 : action principale
        // (75 %) + action secondaire (25 %, même taille de chaque côté).
        //   Ligne 1 : Lire/Reprendre + Oublier la reprise (si reprise).
        //   Ligne 2 : Télécharger + Favori.
        // Boutons pleins avec bordure fine + glow coloré (cf. _glowButton).
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Ligne 1 : Lire / Reprendre (75 %) + Oublier (25 %) ──────────
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _glowButton(
                    color: kAccentPrimary,
                    // §detailsPlayFocus — Sur TV, l'ordre de traversée donnait le
                    // focus d'entrée au bouton RETOUR de l'AppBar : le réflexe
                    // télécommande (OK pour lancer) REFERMAIT la fiche, et le
                    // bouton de lecture était 3 crans plus bas, derrière une carte
                    // secondaire. `DetailsPage` était la seule page TV sans focus
                    // d'entrée maîtrisé — et `TvInitialFocus` n'aurait pas suffi :
                    // son `nextFocus()` reprend l'ordre de traversée, donc le
                    // bouton retour. Il faut nommer explicitement la cible.
                    // ⚠️ TV uniquement (§touchNoFocus : au tactile, donner un
                    // focus fait apparaître un « faux focus »).
                    autofocus: PlatformTv.isTv,
                    onPressed: () => _launchSelected(
                        from: hasResume ? progress.position : null),
                    child: _btnContent(
                      Icons.play_arrow_rounded,
                      hasResume
                          ? l10n.detResumeAt(
                              _formatResumeShort(progress.position))
                          : (hasLocal
                              ? l10n.playOffline.toUpperCase()
                              : l10n.actionSheetPlay.toUpperCase()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Slot droit TOUJOURS présent (gabarit 75/25 constant, aligné
                // avec la ligne Télécharger/Favori). Actif = Oublier la reprise ;
                // sans reprise = placeholder désactivé "vide" (comme un favori
                // inactif) → évite que "Lire" s'étire à 100 %.
                Expanded(
                  flex: 1,
                  child: _glowButton(
                    color: kWarning,
                    onPressed: hasResume ? () => _forgetResume(progress) : null,
                    child: const Icon(Icons.history_toggle_off),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Ligne 2 : Télécharger (75 %) + Favori (25 %) ────────────────
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _glowButton(
                    color: kAccentSecondary,
                    // §dlEpisode — `buildDownloadName`, comme les TROIS autres
                    // points de téléchargement (feuille d'action, carte de
                    // l'accueil). Celui-ci passait `displayName`, c'est-à-dire
                    // `title.baseTitle` : le seul nom de la SÉRIE, sans saison
                    // ni épisode. Or c'est LE chemin par lequel on télécharge un
                    // épisode. Ce nom devient la notification, la tuile de la
                    // liste ET le nom de fichier : tous les épisodes visaient
                    // donc le même `finalPath` et s'écrasaient l'un l'autre
                    // (`_finalizeDownload` fait un `rename`, qui remplace sa
                    // cible en silence).
                    onPressed: () => verifierEtTelecharger(
                        url: _selectedEntry.url,
                        nom: buildDownloadName(_selectedEntry),
                        releaseYear: _selectedEntry.type == M3uContentType.movie
                            ? _selectedEntry.title.year
                            : null,
                        // R39 — La fiche est le SEUL endroit qui connaisse le
                        // stub de la série : la clé se pose ici, avec le
                        // fichier. Plus tard, personne ne saura la retrouver
                        // depuis l'URL de l'épisode (§heroSeriesResume).
                        seriesKey: seriesResumeKeyFor(
                          stubs: _apiSeriesStubs,
                          episode: _selectedEntry,
                        ),
                        context: context),
                    child: _btnContent(
                        Icons.download_rounded, l10n.download.toUpperCase()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: _glowButton(
                    color: kFavorite,
                    active: isFav,
                    onPressed: () async {
                      final added =
                          await FavoritesService.toggleEntry(_selectedEntry);
                      if (!mounted) return;
                      AppSnackBar.show(
                        context,
                        added
                            ? context.l10n.detFavoriteAdded(
                                _selectedEntry.displayName)
                            : context.l10n.detFavoriteRemoved(
                                _selectedEntry.displayName),
                      );
                    },
                    child: Icon(isFav ? Icons.favorite : Icons.favorite_border),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// §detailsActions + §detailsFocusFill — Bouton d'action **contour néon au
  /// repos, plein au focus**. Cf. [_ActionButton].
  Widget _glowButton({
    required Color color,
    required VoidCallback? onPressed,
    required Widget child,
    bool active = true,
    bool autofocus = false,
  }) =>
      _ActionButton(
        color: color,
        onPressed: onPressed,
        active: active,
        autofocus: autofocus,
        child: child,
      );

  /// Contenu icône + libellé centré pour un [_glowButton] (le texte s'ellipse).
  Widget _btnContent(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );

  /// §resumeUnify — Toutes les URLs du contenu courant (versions = qualités +
  /// listes, + épisode courant) → reprise partagée entre toutes.
  List<String> _resumeUrls() {
    final urls = <String>{
      for (final v in _uniqueVersions) v.url,
      _selectedEntry.url,
      _currentEpisode.url,
    };
    return urls.toList();
  }

  /// §forgetResume + §undoTv — Efface la reprise du contenu en cours (TOUTES
  /// ses versions). Au doigt : snackbar UNDO 5 s. À la télécommande :
  /// confirmation AVANT — l'action d'une snackbar n'est pas atteignable au
  /// D-pad. Dans les deux cas, la restauration passe par `saveProgress` du
  /// snapshot capturé par l'appelant.
  Future<void> _forgetResume(WatchProgress snapshot) async {
    // §heroSeriesResume — Une série en cours vit sous DEUX clés : celle de
    // l'épisode (la position exacte) et celle de la série (sa présence au
    // hero de l'accueil). N'effacer que la première laissait la série dans
    // « Reprendre » alors que l'utilisateur venait de demander le contraire.
    // ⛔ Le stub ne rejoint pas `_resumeUrls()` pour autant : cette liste part
    // aussi en `siblingResumeKeys`, où la FIN d'un épisode l'effacerait.
    final String? seriesKey = seriesResumeKeyFor(
      stubs: _apiSeriesStubs,
      episode: _selectedEntry,
    );
    // La clé de série réellement effacée, donc à rendre en cas d'annulation.
    String? forgottenSeriesKey;
    // 🔴 R46 — Capturé AVANT, et pour TOUTES les versions : `action` efface
    // `_resumeUrls()` en entier (qualités + listes, §resumeUnify) alors que
    // l'annulation ne rendait que `snapshot.url`. Sur un titre présent sur
    // plusieurs comptes, les autres reprises disparaissaient sans retour.
    final List<WatchProgress> avant =
        WatchProgressService.snapshotFor(_resumeUrls());
    await confirmOrUndo(
      context,
      title: context.l10n.cardForgetResumeTitle,
      question: context.l10n.cardForgetResumeQuestion,
      confirmLabel: context.l10n.cardForgetConfirm,
      doneMessage: context.l10n.cardResumeForgotten,
      action: () async {
        for (final u in _resumeUrls()) {
          await WatchProgressService.clearProgress(u);
        }
        // Mesuré APRÈS l'effacement : sinon l'épisode qu'on oublie compterait
        // lui-même comme « encore en cours ».
        final String? toForget = seriesKeyToForget(
          seriesKey: seriesKey,
          anyEpisodeStillInProgress: _mostAdvancedInProgress() != null,
        );
        if (toForget != null) {
          await WatchProgressService.clearProgress(toForget);
          forgottenSeriesKey = toForget;
        }
      },
      // §heroSeriesResume — rendre AUSSI la série au hero quand on l'en a
      // retirée : une annulation qui n'en rend que la moitié ment. La clé de
      // série ne part qu'à la PREMIÈRE écriture (une seule réécriture du stub).
      // 🔴 R46 — et rendre TOUTES les versions, pas seulement `snapshot`.
      onUndo: () => WatchProgressService.restoreAll(
        avant.isEmpty ? <WatchProgress>[snapshot] : avant,
        seriesKey: forgottenSeriesKey,
      ),
    );
  }

  Widget _buildTrailerButton() {
    // §detailsActions — Aligné sur le style des autres boutons (_glowButton :
    // plein + bordure + glow). Couleur du thème (tertiaire) au lieu du rouge
    // hors-thème, pour rester cohérent (vert=Lire, cyan=Télécharger, magenta=BA).
    return _glowButton(
      color: kAccentTertiary,
      onPressed: _launchTrailer,
      child: _btnContent(
          Icons.play_circle_outline, context.l10n.detTrailerButton),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// §reloadScope — La liste d'origine fait TOUJOURS partie de la clé (cf.
  /// `dedupeVersions`) : elle en sortait dès qu'une seule liste était chargée
  /// en mémoire, et des versions disparaissaient de la fiche.
  static List<M3uEntry> _deduplicateVersions(List<M3uEntry> versions) =>
      dedupeVersions(versions, _buildQualityLabel);

  String _qualityLabel(M3uEntry v, int index) {
    final base = _buildQualityLabel(v, index);
    if (ParsedPlaylistService.isMultiAccount && v.accountId.isNotEmpty) {
      final name = ParsedPlaylistService.accountName(v.accountId);
      if (name != null) return '$base\n$name';
    }
    return base;
  }

  /// §versionLabel — Ce que la pastille doit répondre : **« qu'est-ce que je
  /// vais obtenir ? »**
  ///
  /// Ordre imposé : qualité → langue → marqueur fournisseur. Constaté sur
  /// appareil avec 4 listes, un même film affichait 7 pastilles dont trois
  /// n'annonçaient qu'un pays (`FR`, `DE`) : impossible de choisir. Un pays
  /// n'est pas une qualité, il ne doit jamais tenir la place principale tant
  /// qu'une qualité est connue.
  ///
  /// §qualityTruth — Quand la liste n'annonce AUCUNE qualité, on utilise celle
  /// qu'on a **mesurée** à la lecture. C'est la seule information certaine dont
  /// on dispose, et elle vient précisément combler le cas où le fournisseur
  /// reste muet. La mesure est marquée d'un `~` : elle décrit ce que ce flux a
  /// servi la dernière fois, pas une promesse du fournisseur.
  ///
  /// ⚠️ On ne remplace JAMAIS une qualité annoncée par la mesure ici : la
  /// confrontation des deux est le rôle de la ligne « Annoncé » (§qualityTruth),
  /// qui l'affiche avec son verdict. Écraser l'annonce ferait disparaître le
  /// mensonge au lieu de le montrer.
  static String _buildQualityLabel(M3uEntry v, int index) {
    final q = v.title.quality;
    if (q != null) {
      final lang = v.title.languages.isNotEmpty ? v.title.languages.first : null;
      final extra = lang ?? v.title.versionLabel ?? v.title.providerTag;
      return extra != null ? '$q · $extra' : q;
    }

    // Pas de qualité annoncée → la mesure prend le relais.
    final measured = MeasuredQualityService.get(v.url);
    if (measured != null) {
      final extra = v.title.languages.isNotEmpty
          ? v.title.languages.first
          : (v.title.versionLabel ?? v.title.providerTag);
      final label = '~${measured.definitionLabel}';
      return extra != null ? '$label · $extra' : label;
    }

    // Ni annonce ni mesure : la langue reste plus parlante qu'un code pays.
    if (v.title.languages.isNotEmpty) return v.title.languages.first;
    final vl = v.title.versionLabel ?? v.title.providerTag;
    if (vl != null) return vl;
    // §watchContext — défaut « FHD » (au lieu de « Standard ») : plus parlant.
    return 'FHD';
  }

  static String _normalizePlatform(String raw) {
    final r = raw.toUpperCase();
    if (r.contains('NETFLIX'))   return 'Netflix';
    if (r.contains('PRIME'))     return 'Prime Video';
    if (r.contains('HBO'))       return 'HBO Max';
    if (r.contains('APPLE'))     return 'Apple TV+';
    if (r.contains('STARZPLAY') || r.contains('STARZ')) return 'Starz';
    if (r.contains('PARAMOUNT')) return 'Paramount+';
    if (r.contains('DISNEY'))    return 'Disney+';
    if (r.contains('PEACOCK'))   return 'Peacock';
    if (r.contains('CANAL'))     return 'Canal+';
    if (r.contains('DAZN'))      return 'DAZN';
    if (r.contains('HULU'))      return 'Hulu';
    if (r.contains('RAKUTEN'))   return 'Rakuten TV';
    return '';
  }

  Widget _buildMetaTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(
            color: Theme.of(context).colorScheme.outline.withAlpha(80)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  /// §tmdbMore — « 12 400 votes » (séparateur d'espace, comme MemoryStatsCard).
  ///
  /// Revue 2026-09-11, D4B-05 — pluriel ICU, plus le « s » français en dur ;
  /// et (relecture) le groupement suit la langue : « 12,400 votes » en
  /// anglais, le français est inchangé.
  String _formatCount(int n) {
    final l10n = context.l10n;
    return l10n.detVotes(n, formatCountFor(n, l10n));
  }

  /// §tmdbMore — Section « Infos » : remplace l'ancienne ligne brute
  /// `Production: A, B, C` (texte 12 px sans titre de section) par une grille
  /// libellé/valeur, alignée sur le style des autres sections de la fiche.
  /// Chaque ligne absente est omise ; la section disparaît si tout est vide.
  /// §tmdbOnlyDetails — Zone d'actions d'un titre absent des listes.
  ///
  /// Sans issue, cette fiche ne serait que décorative : le bouton de recherche
  /// est ce qui la rend utile. Le repérage automatique
  /// (`ActorDetailsPage._findMatches`) est **exact par choix**, pour ne jamais
  /// produire de faux positif — il rate donc les titres présents sous une autre
  /// graphie. On laisse l'utilisateur chercher et trancher lui-même.
  Widget _buildUnavailablePanel(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.video_library_outlined,
                  size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.detNotInPlaylists,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _glowButton(
          color: kAccentSecondary,
          onPressed: _searchInPlaylists,
          child: _btnContent(Icons.search, context.l10n.detSearchInPlaylists),
        ),
      ],
    );
  }

  /// Ouvre la recherche manuelle ; un résultat choisi rouvre la fiche NORMALE
  /// (entrée réelle + versions), donc avec lecture et téléchargement.
  Future<void> _searchInPlaylists() async {
    final group = await PlaylistSearchSheet.show(
      context,
      title: _tmdbData?.title.isNotEmpty == true
          ? _tmdbData!.title
          : widget.entry.displayName,
      originalTitle: _tmdbData?.originalTitle,
      type: widget.entry.type,
    );
    if (group == null || group.isEmpty || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DetailsPage(entry: group.first, versions: group),
      ),
    );
  }

  Widget _buildInfoSection(
    ColorScheme cs,
    bool isSeries,
    List<String> genres,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final m = _tmdbData;
    // §detailsHero — Une ligne peut désormais MENER quelque part : le troisième
    // champ porte l'identifiant TMDB de la personne, `null` pour du texte brut.
    final rows = <(String, String, int?)>[];

    // §infoGenre — Le genre ouvre la section : c'est la classification la plus
    // parlante. Il vivait avant en rangée de chips ISOLÉE entre le casting et
    // « Infos », ce qui en faisait un bloc orphelin sans libellé.
    if (genres.isNotEmpty) {
      rows.add((l10n.infoGenre, genres.take(4).join(', '), null));
    }

    final d = m?.director;
    if (d != null && d.name.trim().isNotEmpty) {
      rows.add((
        // ⚠️ `character` porte le mot FRANÇAIS 'Créateur' : c'est une valeur
        // produite par `TmdbService`, pas un texte d'interface. On la teste,
        // on ne l'affiche pas.
        (d.character == 'Créateur') ? l10n.infoCreator : l10n.infoDirector,
        d.name,
        d.id,
      ));
    }
    // §detailsHero — Champ DÉJÀ récupéré par la recherche TMDB et que la fiche
    // n'affichait nulle part. Zéro appel réseau de plus.
    final String? orig = m?.originalTitle?.trim();
    if (orig != null &&
        orig.isNotEmpty &&
        orig.toLowerCase() != m!.title.trim().toLowerCase()) {
      rows.add((l10n.infoOriginalTitle, orig, null));
    }
    // §tmdbInfo (2026-09-06) — Cinq champs que la réponse TMDB portait déjà et
    // que la fiche jetait. Aucun appel réseau de plus : `append_to_response`
    // emballe tout dans la même requête.
    if (isSeries) {
      final int? seasons = m?.numberOfSeasons;
      final int? episodes = m?.numberOfEpisodes;
      if (seasons != null && seasons > 0) {
        rows.add((
          l10n.infoSeasons,
          episodes != null && episodes > 0
              ? l10n.infoSeasonsValue(seasons, episodes)
              : '$seasons',
          null,
        ));
      }
      // ⚠️ Une DIFFUSION annoncée, pas une disponibilité : la ligne ne mène
      // nulle part, et ne doit pas laisser croire qu'on peut la lancer.
      final String? next =
          nextEpisodeLabel(m?.nextEpisode, lang: l10n.localeName);
      if (next != null) rows.add((l10n.infoNextEpisode, next, null));
      // ⚠️ Pas de ligne « Diffusé par » ici : le bloc de chips au-dessus
      // l'affiche déjà, et c'est exactement le doublon qu'on vient de retirer
      // pour le réalisateur. Une information, un endroit.
    } else {
      // ⚠️ TMDB met **0** quand il ne sait pas, jamais `null`.
      final String lang = l10n.localeName;
      final String? budget = moneyLabel(m?.budget, lang: lang);
      if (budget != null) rows.add((l10n.infoBudget, budget, null));
      final String? revenue = moneyLabel(m?.revenue, lang: lang);
      if (revenue != null) rows.add((l10n.infoRevenue, revenue, null));
      final String? salle = shortDate(m?.theatricalDate, lang: lang);
      if (salle != null) rows.add((l10n.infoTheatrical, salle, null));
      final String? numerique = shortDate(m?.digitalDate, lang: lang);
      if (numerique != null) rows.add((l10n.infoDigital, numerique, null));
    }
    if (m?.productionCountries.isNotEmpty == true) {
      rows.add((l10n.infoCountry, m!.productionCountries.take(3).join(', '), null));
    }
    if (m?.productionCompanies?.trim().isNotEmpty == true) {
      rows.add((l10n.infoStudios, m!.productionCompanies!.trim(), null));
    }
    if (m?.status?.trim().isNotEmpty == true) {
      rows.add((l10n.infoStatus, _statusLabel(m!.status!), null));
    }
    final String? runtime = m?.runtimeLabel(l10n);
    if (runtime != null) {
      rows.add((
        isSeries ? l10n.infoEpisodeLength : l10n.infoRuntime,
        runtime,
        null,
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionMark('Infos',
            child: Text(l10n.infoSectionTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold))),
        Divider(color: cs.outlineVariant),
        const SizedBox(height: 4),
        for (final r in rows) _infoRow(cs, r.$1, r.$2, personId: r.$3),
        const SizedBox(height: 12),
      ],
    );
  }

  /// §detailsHero — Une ligne de l'encadré « Infos ». Avec [personId], elle
  /// mène à la fiche de la personne et à ses autres titres disponibles : c'est
  /// ce que faisait la ligne « De `<réalisateur>` » du haut, qui doublonnait avec
  /// celle-ci. ⚠️ `FocusableCard` = un arrêt de plus à la télécommande, mais on
  /// en a retiré un au même moment : le compte est neutre.
  Widget _infoRow(ColorScheme cs, String label, String value, {int? personId}) {
    final Widget line = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ),
        // R17 — La colonne de libellés est à largeur FIXE : un libellé court
        // (« Sortie salle ») laissait du blanc, mais un libellé long
        // (« Theatrical release » sur un écran anglais) la remplissait
        // exactement et sa valeur commençait au pixel suivant, collée. La
        // gouttière appartient à la mise en page, pas au libellé : elle vaut
        // pour TOUTES les lignes de l'encadré, dans toutes les langues.
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: personId == null ? cs.onSurface : kAccentSecondary,
              fontWeight: personId == null ? null : FontWeight.w600,
            ),
          ),
        ),
        if (personId != null)
          Icon(Icons.chevron_right, size: 14, color: kAccentSecondary),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: personId == null
          ? line
          : FocusableCard(
              scaleOnFocus: false,
              borderRadius: BorderRadius.circular(6),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => ActorDetailsPage(personId: personId)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: line,
              ),
            ),
    );
  }

  /// Traduit le `status` TMDB (anglais) pour l'affichage.
  String _statusLabel(String raw) => switch (raw) {
        'Released' => L10n.current.detStatusReleased,
        'Post Production' => L10n.current.detStatusPostProduction,
        'In Production' => L10n.current.detStatusInProduction,
        'Planned' => L10n.current.detStatusPlanned,
        'Returning Series' => L10n.current.detStatusReturning,
        'Ended' => L10n.current.detStatusEnded,
        'Canceled' => L10n.current.detStatusCanceled,
        _ => raw,
      };
}

/// §castPhotos — Vignette d'acteur (photo + nom + rôle) du carrousel casting de
/// la fiche détail. Tap → [ActorDetailsPage] (id direct, sans recherche par nom).
/// Mobile + TV (focus glow via [FocusableCard], sans scale pour ne pas déborder
/// la rangée à hauteur fixe).
/// §detailsFocusFill — Bouton d'action de la fiche : **vide au repos, plein au
/// focus**.
///
/// Avant, les 4 boutons (Lire / Oublier / Télécharger / Favori) portaient tous
/// un voile teinté permanent : à la télécommande, on ne distinguait pas celui
/// qui était sélectionné de ses voisins. Ils sont désormais en contour pur, et
/// **seul le bouton focusé se remplit** — le déplacement ⬆⬇ devient lisible à
/// 3 m d'un coup d'œil.
///
/// L'état éteint ([active] `false` ou `onPressed` nul) reste gris et sans glow,
/// tout en gardant le gabarit : il sert aussi d'indicateur (favori allumé /
/// éteint).
class _ActionButton extends StatefulWidget {
  final Color color;
  final VoidCallback? onPressed;
  final Widget child;
  final bool active;

  /// §detailsPlayFocus — Réservé au bouton PRINCIPAL de la fiche. Un seul
  /// bouton doit le porter : deux `autofocus` dans le même scope se disputent
  /// le focus d'entrée.
  final bool autofocus;

  const _ActionButton({
    required this.color,
    required this.onPressed,
    required this.child,
    this.active = true,
    this.autofocus = false,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lit = widget.active && widget.onPressed != null;
    // Revue 2026-09-11, D4A-16 — mêmes valeurs, constantes nommées.
    final dimmed = isDark ? kDisabledOnDark : kDisabledOnLight;
    final filled = _focused && lit;

    // Rempli : fond à la couleur pleine, contenu en négatif pour le contraste.
    // Au repos : fond transparent, contour et texte colorés.
    final fg = filled
        ? (isDark ? kBlack : kWhite)
        : (lit ? widget.color : dimmed);
    final bg = filled ? widget.color : Colors.transparent;
    final border = lit ? widget.color : dimmed;

    return FocusableChip(
      onTap: widget.onPressed,
      enabled: widget.onPressed != null,
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(14),
      onFocusChange: (f) {
        if (mounted) setState(() => _focused = f);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: lit
              ? [
                  BoxShadow(
                    color: widget.color.withAlpha(filled ? 120 : 70),
                    blurRadius: filled ? 20 : 14,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            foregroundColor: fg,
            disabledForegroundColor: dimmed,
            backgroundColor: bg,
            side: BorderSide(color: border, width: 1.6),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: widget.onPressed,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Lot 9 (§tmdbPlus) — La tuile de fin de rangée qui déplie le reste du
/// casting.
///
/// ⚠️ Elle vit DANS la rangée, en dernier : c'est une carte comme les autres
/// pour la traversée D-pad (→ l'atteint en continuant), et elle n'ouvre aucune
/// route — donc aucune sortie de plus à prévoir sur téléviseur
/// (§tvOptionsBack). ⛔ Jamais en TÊTE : le point d'entrée de la rangée doit
/// rester un acteur, pas un bouton.
class _MoreCastCard extends StatelessWidget {
  final VoidCallback onTap;
  const _MoreCastCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topLeft,
      child: FocusableCard(
        scaleOnFocus: false,
        anchorRowStart: true,
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 92,
                height: 138,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Icon(Icons.more_horiz,
                    color: cs.onSurfaceVariant, size: 32),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                child: Text(
                  context.l10n.detSeeMoreCast,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CastCard extends StatelessWidget {
  final CastMember member;

  /// §dpadRowEntry — 1re carte de la rangée = point d'entrée vertical.
  final bool isEntry;
  const _CastCard({required this.member, this.isEntry = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final photoUrl = TmdbService.getPosterUrl(member.profilePath, size: 'w185');

    // §castPhotos — portrait 2:3 (92×138) : les photos TMDB sont des portraits ;
    // un cadre quasi carré + BoxFit.cover recadrait sur la bouche.
    Widget placeholder() => Container(
          width: 92,
          height: 138,
          color: cs.surfaceContainerHighest,
          child: Icon(Icons.person, color: cs.onSurfaceVariant, size: 36),
        );

    // §rowAnchorDetails — carte focusée calée à gauche de la rangée casting.
    // §rowFocusFit — cf. _RelatedCard : hauteur naturelle, pas celle de la rangée.
    return Align(
      alignment: Alignment.topLeft,
      child: FocusableCard(
      scaleOnFocus: false,
      anchorRowStart: true,
      entry: isEntry,
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ActorDetailsPage(personId: member.id)),
      ),
      child: SizedBox(
        width: 92,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              // §imgDiskCache — cache disque ; §imgThrash — décodage calé sur
              // les 92 px réels (rangée de casting = beaucoup d'images d'un
              // coup, donc le sur-décodage y coûtait cher).
              child: AetherImage(
                url: photoUrl,
                width: 92,
                height: 138,
                fit: BoxFit.cover,
                cacheWidth: decodeWidthFor(context, 92),
                // Cadre sur le haut → garde le visage (yeux) plutôt que de
                // recentrer sur le bas (bouche/menton).
                alignment: Alignment.topCenter,
                fallback: (_) => placeholder(),
              ),
            ),
            const SizedBox(height: 6),
            // §tvRails — Le texte est mis en retrait (horizontal + bas) pour ne
            // pas coller à la bordure/glow de focus de la FocusableCard.
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface),
                  ),
                  if (member.character != null && member.character!.isNotEmpty)
                    Text(
                      member.character!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

/// §tmdbReco — Vignette d'un titre lié (saga / similaire) : affiche 2:3 + titre,
/// tap → ouvre la fiche du titre. Focusable au D-pad.
class _RelatedCard extends StatelessWidget {
  final List<M3uEntry> group;

  /// §dpadRowEntry — 1re carte de la rangée = point d'entrée vertical.
  final bool isEntry;
  const _RelatedCard({required this.group, this.isEntry = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entry = group.first;
    final poster = ParsedPlaylistService.bestLogoUrl(group) ??
        ParsedPlaylistService.bestBackdropUrl(group);
    // Poster à TAILLE FIXE (pas d'AspectRatio dépendant de la largeur) : évite
    // l'overflow vertical de la Column quand le titre prend 2 lignes (TV ×1.3).
    const double w = 104, h = 156;
    Widget placeholder() => Container(
          width: w,
          height: h,
          color: cs.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(Icons.movie_outlined, color: cs.onSurfaceVariant),
        );
    // §rowFocusFit — Un enfant de ListView horizontal reçoit une hauteur
    // IMPOSÉE (celle de la rangée, 230) : la carte focusée peignait donc son
    // fond et son contour sur toute cette hauteur, bien en dessous du titre
    // (« encart trop haut », signalement utilisateur sur téléviseur). `Align`
    // rend à la carte sa hauteur naturelle : affiche + titre, rien de plus.
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
      width: w,
      // §rowAnchorDetails — carte focusée calée à gauche (saga/similaires).
      child: FocusableCard(
        anchorRowStart: true,
        entry: isEntry,
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetailsPage(entry: entry, versions: group),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              // §imgDiskCache — cache disque partagé (AetherImage).
              child: AetherImage(
                url: poster,
                width: w,
                height: h,
                fit: BoxFit.cover,
                // §imgThrash — largeur de rendu réelle.
                cacheWidth: decodeWidthFor(context, w),
                fallback: (_) => placeholder(),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                entry.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
