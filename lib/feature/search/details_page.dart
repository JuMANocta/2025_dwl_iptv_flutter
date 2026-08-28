import 'package:flutter/material.dart';
import 'package:dpad/dpad.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/themes/colors.dart';
import '../../core/utils/platform_tv.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/tmdb_service.dart';
import '../../data/services/tmdb_api_service.dart';
import '../settings/tmdb_key_page.dart';
import '../../data/services/parsed_playlist_service.dart';
import '../../data/services/stream_account_service.dart';
import '../../data/services/watch_progress_service.dart';
import '../../data/services/xtream_api_service.dart';
import '../../core/utils/app_snackbar.dart';
import '../../data/models/media_model.dart';
import '../player/player_page.dart';
import '../player/player_media.dart';
import '../downloads/logic/download_initiator.dart';
import '../../data/models/m3u_entry.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/tv/focusable_chip.dart';
import '../../widgets/aether_image.dart';
import '../../widgets/playlist_search_sheet.dart';
import '../../widgets/tv/focusable_card.dart';
import 'actor_details_page.dart';
import 'm3u_filter.dart';

Color _qualityColor(String? quality) {
  return switch (quality) {
    '4K'  => kQuality4K,
    'FHD' => kQualityFHD,
    'HD'  => kQualityHD,
    'SD'  => kQualitySD,
    _     => kQualityUnknown, // blanc cassé — plus de gris terne
  };
}

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

class _DetailsPageState extends State<DetailsPage> {
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
  /// §seriesMultiList — Stubs série (1 par compte) à fetcher via la JSON API,
  /// pour que chaque épisode porte les versions de TOUTES les listes qui ont
  /// la série (et pas juste le compte d'origine de la vignette).
  List<M3uEntry> _apiSeriesStubs = const [];

  final ScrollController _episodeScrollController = ScrollController();

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
    _buildSeasonEpisodes();

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
      _uniqueVersions = _deduplicateVersions(widget.versions);
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
  void dispose() {
    _episodeScrollController.dispose();
    super.dispose();
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
    final futures = _apiSeriesStubs.map((stub) async {
      final sid = _extractSeriesIdFromUrl(stub.url);
      if (sid == null) return const <M3uEntry>[];
      final acc = await StreamAccountService.getAccount(stub.accountId);
      if (acc == null) return const <M3uEntry>[];
      return XtreamApiService.fetchEpisodes(acc, sid);
    }).toList();

    final lists = await Future.wait(futures);
    if (!mounted) return;
    final apiEpisodes = lists.expand((e) => e).toList();
    if (apiEpisodes.isEmpty) return _finishEpisodesLoading();

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
  void _finishEpisodesLoading() {
    if (!mounted) {
      _episodesLoading = false;
      return;
    }
    setState(() => _episodesLoading = false);
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

  /// Extrait le `series_id` d'une URL stub `/series/{user}/{pass}/{id}`
  /// (sans extension). Retourne `null` si :
  /// - URL pas de format `series`
  /// - dernier segment a une extension (= URL d'épisode, pas un stub)
  /// - dernier segment pas un entier
  static int? _extractSeriesIdFromUrl(String url) {
    try {
      final segments = Uri.parse(url).pathSegments;
      if (segments.length < 4 || segments[0].toLowerCase() != 'series') {
        return null;
      }
      final last = segments.last;
      if (last.contains('.')) return null; // c'est une URL d'épisode
      return int.tryParse(last);
    } catch (_) {
      return null;
    }
  }

  void _buildSeasonEpisodes() {
    if (widget.entry.type != M3uContentType.series) return;
    // §23b — comparaison par clé de regroupement normalisée (casse +
    // ponctuation) pour agréger les épisodes cross-comptes, alignée sur la
    // fusion des vignettes.
    final seriesKey = contentGroupKey(widget.entry);
    // §homonymYear — Si la série ouverte porte une année (homonyme splitté), on
    // ne collecte QUE les stubs/épisodes de la MÊME année → on ne mélange pas
    // deux séries de même titre mais d'époques différentes. Si pas d'année, on
    // matche par titre seul (comportement historique).
    final seriesYear = widget.entry.title.year;
    final all = ParsedPlaylistService.entriesWithPriority(widget.entry.accountId)
        .where((e) =>
            e.type == M3uContentType.series &&
            contentGroupKey(e) == seriesKey &&
            (seriesYear == null || e.title.year == null ||
                e.title.year == seriesYear))
        .toList();

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

  Future<void> _loadData() async {
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
        fetchFull(isTv: true),
      ]);
      if (mounted) {
        setState(() {
          _episodeData = results[0] as Map<String, dynamic>?;
          _tmdbData    = results[1] as Media?;
          _isLoading   = false;
        });
        _computeRelated();
      }
    } else {
      final data = await fetchFull(isTv: isSeries || _currentEpisode.isSerie);
      if (mounted) {
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
    final type = widget.entry.type;
    final entries =
        ParsedPlaylistService.byTypeWithPriority(widget.entry.accountId)[type] ??
            const <M3uEntry>[];
    final byKey = <String, List<M3uEntry>>{};
    for (final e in entries) {
      byKey.putIfAbsent(contentGroupKey(e), () => []).add(e);
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

  /// §tmdbBadges — Badges des LANGUES dispo (MULTI/VF/VOSTFR) uniquement.
  /// La certification d'âge est inline dans la rangée métadonnées ; la qualité
  /// est déjà listée dans les chips de version → on ne la reduplique pas ici.
  /// Vide → `SizedBox.shrink` (aucun espace réservé).
  Widget _buildBadges(ColorScheme cs) {
    final vers = _uniqueVersions.isNotEmpty ? _uniqueVersions : widget.versions;
    final langs = <String>{};
    for (final e in vers) {
      langs.addAll(e.title.languages);
    }
    final badges = <Widget>[
      for (final l in const ['MULTI', 'VF', 'VOSTFR'])
        if (langs.contains(l)) _badge(l, _langColor(l)),
    ];
    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: badges),
    );
  }

  /// Pastille de badge : contour teinté (défaut) ou plein (certification).
  Widget _badge(String text, Color color,
      {bool filled = false, IconData? icon}) {
    final fg = filled ? Colors.black : color;
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

  Color _langColor(String l) {
    switch (l) {
      case 'MULTI':
        return kLangMulti;
      case 'VOSTFR':
        return kLangVOSTFR;
      case 'VF':
        return kLangVF;
      default:
        return kAccentSecondary;
    }
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
              padding: const EdgeInsets.symmetric(vertical: 4),
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
        SnackBar(content: Text("TMDB n'a pas trouvé de fiche pour $actorName.")),
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
                    Text('Active TMDB',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      'Affiches, synopsis et casting. Config rapide au QR depuis ton mobile.',
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
  static const double _kTvBackdropFraction = 0.42;
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
    // §23 — priorité au BACKDROP provider (champ v5 du catalogue JSON,
    // format paysage = idéal pour le header), choisi selon la politique
    // « plus grosse liste » ; sinon poster/logo (même politique) ; sinon
    // épisode courant / entrée.
    final String? playlistPoster = <String?>[
      ParsedPlaylistService.bestBackdropUrl(_uniqueVersions),
      widget.entry.backdropUrl,
      ParsedPlaylistService.bestLogoUrl(_uniqueVersions),
      _currentEpisode.logoUrl,
      widget.entry.logoUrl,
    ].firstWhere((l) => l != null && l.isNotEmpty, orElse: () => null);
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
        ? (screenH * _kTvBackdropFraction).clamp(180.0, 300.0)
        : 360.0;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          // ── HEADER ────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: headerHeight,
            pinned: true,
            stretch: true,
            backgroundColor: cs.surface,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (headerUrl != null)
                    AetherImage(
                      url: headerUrl,
                      fit: BoxFit.cover,
                      // §imgPerf — cap de DÉCODAGE uniquement. Le poids stocké
                      // est déjà borné par la taille demandée dans l'URL
                      // (`w1280`) : cf. l'avertissement sur `AetherImage` quant
                      // à `maxWidthDiskCache`, qui cassait cette image.
                      cacheWidth: 720,
                      fallback: (_) =>
                          Container(color: cs.surfaceContainerHighest),
                    )
                  else
                    Container(color: cs.surfaceContainerHighest),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54, cs.surface],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
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
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                      letterSpacing: 0.3,
                    ),
                  ),
                  // §tmdbMore — Accroche officielle sous le titre (italique).
                  if (_tmdbData?.tagline?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      _tmdbData!.tagline!,
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant,
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
                      if (_tmdbData?.runtimeOrEpisodeLength != null) ...[
                        const SizedBox(width: 8),
                        Text('•', style: TextStyle(color: cs.onSurfaceVariant)),
                        const SizedBox(width: 8),
                        _buildMetaTag(_tmdbData!.runtimeOrEpisodeLength!, cs.onSurfaceVariant),
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

                  // §directorView — Réalisateur / créateur sur sa PROPRE ligne :
                  // la Row ci-dessus n'est ni scrollable ni Wrap (elle contient
                  // un Spacer), y glisser un nom long provoquerait un overflow.
                  _buildDirectorLine(cs),
                  const SizedBox(height: 10),

                  // §tmdbBadges — Badges des langues dispo (MULTI/VF/VOSTFR).
                  _buildBadges(cs),

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
                    Text('Synopsis',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: cs.onSurfaceVariant)),
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
                    Text('Casting principal',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
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
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          // §focusScroll — cache plus large pour que la nav D-pad
                          // trouve toujours la card suivante dans l'arbre de focus.
                          // ignore: deprecated_member_use
                          cacheExtent: 600,
                          itemCount: _tmdbData!.castMembers.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, i) => _CastCard(
                              member: _tmdbData!.castMembers[i],
                              isEntry: i == 0),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ]
                  // Fallback : anciens noms seuls si pas de casting enrichi.
                  else if (hasTmdb && _tmdbData!.cast.isNotEmpty) ...[
                    Text('Casting principal',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
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

                  // PLATEFORMES (toujours)
                  Builder(builder: (context) {
                    final platforms = _parsePlatforms(widget.entry.groupTitle);
                    if (platforms.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Disponible sur',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: platforms.map((p) {
                            final color = _platformColor(p);
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
                          ? 'Saga : $_collectionName'
                          : 'Même saga',
                      _collection,
                      cs,
                    ),
                  if (_similar.isNotEmpty)
                    _relatedRow('Titres similaires disponibles', _similar, cs),

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
        // ── §seasonsUI — En-tête de section "SAISONS" + total ────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  gradient: kAetherGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'SAISONS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: kAccentPrimary,
                ),
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
                        ? '$totalSeasons saison · $totalEpisodes épisodes'
                        : '$totalSeasons saisons · $totalEpisodes épisodes',
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
                  'Chargement des épisodes…',
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          )
        else if (!hasSeasons)
          // §seriesFlow — fetch terminé mais aucun épisode (série introuvable
          // côté API, compte non-Xtream, réseau down). Plus de spinner infini.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(Icons.tv_off_outlined,
                    size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Aucun épisode disponible pour cette série.',
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
                              'Saison ${sNum.toString().padLeft(2, '0')}',
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
                                '$epCount ép.',
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
            child: Row(
              children: _seasonEpisodes[_selectedSeason]!
                  .asMap()
                  .entries
                  .map((e) {
                final group = e.value;
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
                      child: Text(
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
                    ),
                  ),
                  ),
                );
              }).toList(),
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
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: _uniqueVersions.asMap().entries.map((e) {
        final v        = e.value;
        final label    = _qualityLabel(v, e.key);
        final color    = _qualityColor(v.title.quality);
        final selected = _selectedEntry == v;
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
            decoration: BoxDecoration(
              color: selected ? color.withAlpha(55) : color.withAlpha(20),
              border: Border.all(
                color: selected ? color.withAlpha(200) : color.withAlpha(60),
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: color,
                height: 1.3,
              ),
            ),
          ),
          ),
        );
      }).toList(),
    );
  }

  /// Format Duration → "1h23" ou "12:34" pour libellé court de reprise.
  String _formatResumeShort(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
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

  void _launchSelected({Duration? from}) {
    // Auto-ajout favoris au play, cohérent avec le reste de l'app (§1d)
    FavoritesService.addEntry(_selectedEntry);
    // §1i — Si on lance un épisode et qu'il existe un suivant, on passe le
    // callback au player pour exposer le bouton "épisode suivant" (▶▶).
    final hasNext = _isEpisode && _nextEpisode != null;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        path: _selectedEntry.url,
        title: _playerTitle,
        // §watchContext a/b — badges qualité + saison/épisode dans le player.
        qualityTag: _selectedEntry.title.qualityOrDefault,
        episodeTag: _selectedEntry.title.seasonEpisodeLabel,
        // §watchContext — nom série + synopsis (si dispo) dans l'overlay.
        seriesName: _playerSeriesName,
        synopsis: _playerSynopsis,
        sourceType: VideoSourceType.network,
        badgeType: _selectedEntry.type == M3uContentType.series
            ? PlayerBadgeType.series
            : PlayerBadgeType.movie,
        startPosition: from,
        seasonNumber: _selectedEntry.title.seasonNumber,
        // §episodeMeta — Le player ne pousse plus de nouvelle route pour changer
        // d'épisode : il demande le contenu suivant et bascule en place.
        onRequestNext: hasNext ? _prepareNextEpisode : null,
      ),
    ));
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
    return PlayerMedia(
      path: _selectedEntry.url,
      title: _playerTitle,
      qualityTag: _selectedEntry.title.qualityOrDefault,
      episodeTag: _selectedEntry.title.seasonEpisodeLabel,
      seriesName: _playerSeriesName,
      synopsis: _playerSynopsis,
      sourceType: VideoSourceType.network,
      badgeType: PlayerBadgeType.series,
      seasonNumber: season,
    );
  }

  Widget _buildActionButtons(AppLocalizations l10n) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [FavoritesService.version, WatchProgressService.version]),
      builder: (ctx, _) {
        final isFav = FavoritesService.isEntryFavorite(_selectedEntry);
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
                    onPressed: () => _launchSelected(
                        from: hasResume ? progress.position : null),
                    child: _btnContent(
                      Icons.play_arrow_rounded,
                      hasResume
                          ? 'REPRENDRE · ${_formatResumeShort(progress.position)}'
                          : l10n.actionSheetPlay.toUpperCase(),
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
                    onPressed: () => verifierEtTelecharger(
                        url: _selectedEntry.url,
                        nom: _selectedEntry.displayName,
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
                            ? '⭐ "${_selectedEntry.displayName}" ajouté aux favoris'
                            : '🗑️ "${_selectedEntry.displayName}" retiré des favoris',
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
  }) =>
      _ActionButton(
        color: color,
        onPressed: onPressed,
        active: active,
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

  /// §forgetResume — Efface la reprise du contenu en cours (TOUTES ses versions)
  /// + snackbar UNDO 4 s (restauration via `saveProgress` du snapshot).
  Future<void> _forgetResume(WatchProgress snapshot) async {
    for (final u in _resumeUrls()) {
      await WatchProgressService.clearProgress(u);
    }
    if (!mounted) return;
    AppSnackBar.showCustom(
      context,
      SnackBar(
        content: const Text('Reprise oubliée'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () {
            WatchProgressService.saveProgress(
              snapshot.url,
              snapshot.position,
              snapshot.duration,
            );
          },
        ),
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
      child: _btnContent(Icons.play_circle_outline, 'BANDE-ANNONCE'),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static List<M3uEntry> _deduplicateVersions(List<M3uEntry> versions) {
    final seen    = <String>{};
    final result  = <M3uEntry>[];
    final isMulti = ParsedPlaylistService.isMultiAccount;
    for (int i = 0; i < versions.length; i++) {
      final v         = versions[i];
      final qualLabel = _buildQualityLabel(v, i);
      final key = isMulti ? '$qualLabel|${v.accountId}' : qualLabel;
      if (seen.add(key)) result.add(v);
    }
    return result;
  }

  String _qualityLabel(M3uEntry v, int index) {
    final base = _buildQualityLabel(v, index);
    if (ParsedPlaylistService.isMultiAccount && v.accountId.isNotEmpty) {
      final name = ParsedPlaylistService.accountName(v.accountId);
      if (name != null) return '$base\n$name';
    }
    return base;
  }

  static String _buildQualityLabel(M3uEntry v, int index) {
    final q  = v.title.quality;
    // §providerTag — Le marqueur (FR, US, IT…) complète la qualité au lieu de
    // s'y substituer : « FHD · FR » se lit, « FR » tout seul se lisait comme
    // une qualité. Il ne sert de libellé PRINCIPAL qu'en dernier recours.
    final vl = v.title.versionLabel ?? v.title.providerTag;
    if (q != null && vl != null) return '$q · $vl';
    if (q != null) return q;
    if (vl != null) return vl;
    // §watchContext — défaut « FHD » (au lieu de « Standard ») : plus parlant.
    return 'FHD';
  }

  static List<String> _parsePlatforms(String? groupTitle) {
    if (groupTitle == null || groupTitle.isEmpty) return [];
    final match = RegExp(r'\(([^)]+)\)').firstMatch(groupTitle);
    if (match == null) return [];
    return match.group(1)!
        .split('|')
        .map((s) => _normalizePlatform(s.trim()))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
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

  static Color _platformColor(String platform) {
    switch (platform) {
      case 'Netflix':      return const Color(0xFFE50914);
      case 'Prime Video':  return const Color(0xFF00A8E1);
      case 'HBO Max':      return const Color(0xFF5B2D8E);
      case 'Apple TV+':    return const Color(0xFF555555);
      case 'Starz':        return const Color(0xFF00B4D8);
      case 'Paramount+':   return const Color(0xFF0064FF);
      case 'Disney+':      return const Color(0xFF0063E5);
      case 'Canal+':       return const Color(0xFF000000);
      case 'Peacock':      return const Color(0xFF000000);
      default:             return Colors.grey;
    }
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
  String _formatCount(int n) {
    final s = n.toString();
    final grouped =
        s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
    return '$grouped vote${n > 1 ? 's' : ''}';
  }

  /// §directorView — « De **Christopher Nolan** » (film) / « Créé par … »
  /// (série), cliquable vers sa fiche et ses autres titres disponibles.
  /// Rien du tout si TMDB ne fournit pas l'info.
  Widget _buildDirectorLine(ColorScheme cs) {
    final d = _tmdbData?.director;
    if (d == null || d.name.trim().isEmpty) return const SizedBox.shrink();
    final label = (d.character == 'Créateur') ? 'Créé par' : 'De';

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: FocusableCard(
        scaleOnFocus: false,
        borderRadius: BorderRadius.circular(6),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ActorDetailsPage(personId: d.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(Icons.movie_creation_outlined,
                  size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('$label ',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              Flexible(
                child: Text(
                  d.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kAccentSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 14, color: kAccentSecondary),
            ],
          ),
        ),
      ),
    );
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
                  'Pas dans vos listes — fiche affichée depuis TMDB.',
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
          child: _btnContent(Icons.search, 'CHERCHER DANS MES LISTES'),
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
    final m = _tmdbData;
    final rows = <(String, String)>[];

    // §infoGenre — Le genre ouvre la section : c'est la classification la plus
    // parlante. Il vivait avant en rangée de chips ISOLÉE entre le casting et
    // « Infos », ce qui en faisait un bloc orphelin sans libellé.
    if (genres.isNotEmpty) {
      rows.add(('Genre', genres.take(4).join(', ')));
    }

    final d = m?.director;
    if (d != null && d.name.trim().isNotEmpty) {
      rows.add(((d.character == 'Créateur') ? 'Créateur' : 'Réalisateur', d.name));
    }
    if (m?.productionCountries.isNotEmpty == true) {
      rows.add(('Pays', m!.productionCountries.take(3).join(', ')));
    }
    if (m?.productionCompanies?.trim().isNotEmpty == true) {
      rows.add(('Studios', m!.productionCompanies!.trim()));
    }
    if (m?.status?.trim().isNotEmpty == true) {
      rows.add(('Statut', _statusLabel(m!.status!)));
    }
    if (m?.runtimeOrEpisodeLength?.trim().isNotEmpty == true) {
      rows.add((isSeries ? 'Épisode' : 'Durée', m!.runtimeOrEpisodeLength!));
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Infos',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        Divider(color: cs.outlineVariant),
        const SizedBox(height: 4),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    r.$1,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: Text(
                    r.$2,
                    style: TextStyle(fontSize: 12, color: cs.onSurface),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// Traduit le `status` TMDB (anglais) pour l'affichage.
  String _statusLabel(String raw) => switch (raw) {
        'Released' => 'Sorti',
        'Post Production' => 'Post-production',
        'In Production' => 'En production',
        'Planned' => 'Annoncé',
        'Returning Series' => 'En cours',
        'Ended' => 'Terminée',
        'Canceled' => 'Annulée',
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

  const _ActionButton({
    required this.color,
    required this.onPressed,
    required this.child,
    this.active = true,
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
    final dimmed = isDark ? Colors.white38 : Colors.black38;
    final filled = _focused && lit;

    // Rempli : fond à la couleur pleine, contenu en négatif pour le contraste.
    // Au repos : fond transparent, contour et texte colorés.
    final fg = filled
        ? (isDark ? Colors.black : Colors.white)
        : (lit ? widget.color : dimmed);
    final bg = filled ? widget.color : Colors.transparent;
    final border = lit ? widget.color : dimmed;

    return FocusableChip(
      onTap: widget.onPressed,
      enabled: widget.onPressed != null,
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
    return FocusableCard(
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
    return SizedBox(
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
    );
  }
}
