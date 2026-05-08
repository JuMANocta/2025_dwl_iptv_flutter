import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/widgets/media_card.dart';
import 'package:aetherStream/widgets/media_action_sheet.dart';
import 'package:aetherStream/feature/search/details_page.dart';
import 'package:aetherStream/data/services/tmdb_api_service.dart';

// ── Données pour l'isolate de filtrage ──────────────────────────────────────

class _FilterParams {
  final List<M3uEntry> films;
  final List<M3uEntry> series;
  final List<M3uEntry> tv;
  final String query;
  final bool showFilms;
  final bool showSeries;
  final bool showTv;
  final String? categoryFilter;
  const _FilterParams({
    required this.films, required this.series, required this.tv,
    required this.query,
    required this.showFilms, required this.showSeries, required this.showTv,
    this.categoryFilter,
  });
}

class _FilterResult {
  final Map<String, List<M3uEntry>> groupedFilms;
  final Map<String, Map<String, List<M3uEntry>>> groupedSeries;
  final Map<String, List<M3uEntry>> groupedTv;
  const _FilterResult({
    required this.groupedFilms,
    required this.groupedSeries,
    required this.groupedTv,
  });
}

/// Fonction top-level exécutée dans un isolate séparé via compute().
_FilterResult _computeFilter(_FilterParams p) {
  final query = p.query.toLowerCase();
  bool matches(M3uEntry e) => query.isEmpty ||
      e.rawTitle.toLowerCase().contains(query) ||
      e.displayName.toLowerCase().contains(query);
  bool matchesCat(M3uEntry e) =>
      p.categoryFilter == null || e.category == p.categoryFilter;

  final groupedFilms  = <String, List<M3uEntry>>{};
  final groupedSeries = <String, Map<String, List<M3uEntry>>>{};
  final groupedTv     = <String, List<M3uEntry>>{};

  if (p.showFilms) {
    for (final e in p.films) {
      if (matches(e) && matchesCat(e)) groupedFilms.putIfAbsent(contentGroupKey(e), () => []).add(e);
    }
  }
  if (p.showSeries) {
    for (final e in p.series) {
      if (matches(e) && matchesCat(e)) {
        final key = contentGroupKey(e);
        groupedSeries.putIfAbsent(key, () => {});
        groupedSeries[key]!.putIfAbsent(e.saison ?? '00', () => []).add(e);
      }
    }
  }
  if (p.showTv) {
    for (final e in p.tv) {
      if (matches(e) && !isHiddenTvVariant(e.title.rawTitle)) {
        groupedTv.putIfAbsent(tvGroupKey(e.displayName), () => []).add(e);
      }
    }
  }

  for (final list in groupedFilms.values) { list.sort((a, b) => a.rawTitle.compareTo(b.rawTitle)); }
  for (final list in groupedTv.values)    { list.sort((a, b) => a.rawTitle.compareTo(b.rawTitle)); }
  for (final seasons in groupedSeries.values) {
    for (final eps in seasons.values) { eps.sort((a, b) => a.rawTitle.compareTo(b.rawTitle)); }
  }

  return _FilterResult(groupedFilms: groupedFilms, groupedSeries: groupedSeries, groupedTv: groupedTv);
}

class RechercheM3U extends StatefulWidget {
  final String accountId;
  final String accountName;
  final String m3uPath;
  const RechercheM3U({
    super.key,
    required this.accountId,
    required this.accountName,
    required this.m3uPath,
  });

  @override
  State<RechercheM3U> createState() => _RechercheM3UState();
}

class _RechercheM3UState extends State<RechercheM3U> {
  // ── UI State ────────────────────────────────────────────────────────────────
  bool _showFilms  = true;
  bool _showSeries = true;
  bool _showTv     = true;
  String? _categoryFilter;
  List<String> _filmCategories   = [];
  List<String> _seriesCategories = [];
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searchFocused = false;
  Timer? _debounce;

  // ── Data ────────────────────────────────────────────────────────────────────
  final List<M3uEntry> _filmsList  = [];
  final List<M3uEntry> _seriesList = [];
  final List<M3uEntry> _tvList     = [];

  Map<String, Map<String, List<M3uEntry>>> _groupedSeries = {};
  Map<String, List<M3uEntry>>              _groupedFilms  = {};
  Map<String, List<M3uEntry>>              _groupedTv     = {};
  List<dynamic> _flatList      = [];
  bool   _isProcessing  = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final text = _searchController.text;
      if (_searchQuery == text) return;
      setState(() => _searchQuery = text);
      // Debounce : attend 250 ms de pause avant de déclencher le filtrage
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), _filterAndGroupResults);
    });
    _searchFocus.addListener(() {
      setState(() => _searchFocused = _searchFocus.hasFocus);
    });
    _processFile();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Parsing ─────────────────────────────────────────────────────────────────

  Future<void> _processFile() async {
    try {
      await ParsedPlaylistService.loadActive(
        widget.accountId,
        widget.accountName,
        widget.m3uPath,
      );
      if (mounted) {
        // Priorité au compte actif → ses entrées arrivent en premier dans putIfAbsent
        final allEntries = ParsedPlaylistService.entriesWithPriority(widget.accountId);
        _filmsList.addAll(allEntries.where((e) => e.type == M3uContentType.movie));
        _seriesList.addAll(allEntries.where((e) => e.type == M3uContentType.series));
        _tvList.addAll(allEntries.where((e) => e.type == M3uContentType.tv));
        _filmCategories = _filmsList
            .map((e) => e.category).where((c) => c != null && c.isNotEmpty)
            .cast<String>().toSet().toList()..sort();
        _seriesCategories = _seriesList
            .map((e) => e.category).where((c) => c != null && c.isNotEmpty)
            .cast<String>().toSet().toList()..sort();
        await _filterAndGroupResults();
        if (mounted) setState(() => _isProcessing = false);
      }
    } catch (e) {
      if (mounted) setState(() { _isProcessing = false; _errorMessage = e.toString(); });
    }
  }

  // ── Filtrage / Regroupement (isolate) ───────────────────────────────────────

  Future<void> _filterAndGroupResults() async {
    final params = _FilterParams(
      films: List.unmodifiable(_filmsList),
      series: List.unmodifiable(_seriesList),
      tv: List.unmodifiable(_tvList),
      query: _searchQuery,
      showFilms: _showFilms,
      showSeries: _showSeries,
      showTv: _showTv,
      categoryFilter: _categoryFilter,
    );
    final result = await compute(_computeFilter, params);
    if (!mounted) return;
    setState(() {
      _groupedFilms  = result.groupedFilms;
      _groupedSeries = result.groupedSeries;
      _groupedTv     = result.groupedTv;
      _flatList = [...result.groupedFilms.keys, ...result.groupedSeries.keys, ...result.groupedTv.keys];
    });
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  Future<void> _onEntrySelected(List<M3uEntry> versions) async {
    if (versions.isEmpty || !mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final entry = versions.first;
    if (entry.type == M3uContentType.tv) {
      await showTvActionSheet(context, versions);
    } else {
      // Si pas de clé TMDB → action sheet directement (pas de page blanche)
      final hasTmdb = await TmdbApiService.hasApiKey();
      if (!mounted) return;
      if (hasTmdb) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DetailsPage(entry: entry, versions: versions),
        ));
      } else {
        await showMediaActionSheet(context, entry);
      }
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_isProcessing) return _buildLoadingScreen();
    if (_errorMessage != null) {
      return Center(child: Text("Erreur critique: $_errorMessage", style: const TextStyle(color: Colors.red)));
    }

    return Column(
      children: [
        Expanded(
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                elevation: 0,
                scrolledUnderElevation: 0,
                titleSpacing: 12,
                title: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _searchFocused
                          ? kAccentSecondary.withAlpha(200)
                          : kAccentSecondary.withAlpha(45),
                      width: _searchFocused ? 1.5 : 1,
                    ),
                    boxShadow: _searchFocused
                        ? [BoxShadow(color: kAccentSecondary.withAlpha(55), blurRadius: 14, spreadRadius: 1)]
                        : null,
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: l10n.searchFieldHint,
                      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(140)),
                      prefixIcon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          _searchFocused ? Icons.search : Icons.search_outlined,
                          key: ValueKey(_searchFocused),
                          color: _searchFocused ? kAccentSecondary : Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 22,
                        ),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              onPressed: () => _searchController.clear(),
                              splashRadius: 18,
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    ),
                  ),
                ),
                pinned: true,
                floating: true,
              ),
            ],
            body: _flatList.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.search_off, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text(
                      _searchQuery.isNotEmpty ? l10n.searchNoResults : l10n.searchNoContent,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16, fontStyle: FontStyle.italic),
                    ),
                  ]))
                : ScrollablePositionedList.builder(
                    itemCount: _flatList.length,
                    itemBuilder: (context, index) {
                      final item = _flatList[index];
                      if (item is! String) return const SizedBox.shrink();
                      if (_groupedTv.containsKey(item)) {
                        return TvCard(displayName: item, versions: _groupedTv[item]!, onTap: _onEntrySelected);
                      }
                      if (_groupedSeries.containsKey(item)) {
                        return SerieCard(seriesKey: item, saisons: _groupedSeries[item]!, onEntrySelected: _onEntrySelected);
                      }
                      if (_groupedFilms.containsKey(item)) {
                        return FilmCard(filmKey: item, versions: _groupedFilms[item]!, onTap: _onEntrySelected);
                      }
                      return const SizedBox.shrink();
                    },
                  ),
          ),
        ),
        _buildFilterBar(context, l10n),
      ],
    );
  }

  // ── Loading screen ──────────────────────────────────────────────────────────

  Widget _buildLoadingScreen() {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: cs.primary),
      ),
    );
  }

  // ── Filter bar (bas de page) ──────────────────────────────────────────────────

  Widget _buildFilterBar(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: kAccentPrimary.withAlpha(40), width: 1),
        ),
        boxShadow: [
          BoxShadow(color: kAccentPrimary.withAlpha(25), blurRadius: 16, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCategoryBar(),
              Row(children: [
            _filterPill(
              icon: Icons.movie_outlined,
              iconActive: Icons.movie,
              label: l10n.searchFilterFilms,
              selected: _showFilms,
              onTap: () { setState(() { _showFilms = !_showFilms; _categoryFilter = null; }); _filterAndGroupResults(); },
            ),
            const SizedBox(width: 8),
            _filterPill(
              icon: Icons.video_library_outlined,
              iconActive: Icons.video_library,
              label: l10n.searchFilterSeries,
              selected: _showSeries,
              onTap: () { setState(() { _showSeries = !_showSeries; _categoryFilter = null; }); _filterAndGroupResults(); },
            ),
            const SizedBox(width: 8),
            _filterPill(
              icon: Icons.live_tv_outlined,
              iconActive: Icons.live_tv,
              label: l10n.searchFilterTv,
              selected: _showTv,
              onTap: () { setState(() { _showTv = !_showTv; _categoryFilter = null; }); _filterAndGroupResults(); },
            ),
          ]),
        ],
      ),
    ),
  ),
  );
  }

  Widget _filterPill({
    required IconData icon,
    required IconData iconActive,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          height: 36,
          decoration: BoxDecoration(
            gradient: selected ? kAetherGradient : null,
            color: selected ? null : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? Colors.transparent : cs.outline.withAlpha(60),
            ),
            boxShadow: selected
                ? [BoxShadow(color: kAccentPrimary.withAlpha(90), blurRadius: 10, spreadRadius: 1)]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? iconActive : icon,
                size: 15,
                color: selected ? Colors.white : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? Colors.white : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Barre de catégories (§1c) ────────────────────────────────────────────────

  Widget _buildCategoryBar() {
    final cats = <String>{};
    if (_showFilms)  cats.addAll(_filmCategories);
    if (_showSeries) cats.addAll(_seriesCategories);
    if (cats.isEmpty) return const SizedBox.shrink();
    final sorted = cats.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _categoryChip(null),
            ...sorted.map((cat) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _categoryChip(cat),
            )),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip(String? category) {
    final cs = Theme.of(context).colorScheme;
    final selected = _categoryFilter == category;
    final label = category ?? 'Tout';
    return GestureDetector(
      onTap: () {
        if (_categoryFilter != category) {
          setState(() => _categoryFilter = category);
          _filterAndGroupResults();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? kAccentSecondary.withAlpha(35) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? kAccentSecondary : cs.outline.withAlpha(45),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? kAccentSecondary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
