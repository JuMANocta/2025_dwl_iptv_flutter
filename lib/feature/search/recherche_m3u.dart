import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/feature/search/m3u_parser.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/widgets/media_card.dart';
import 'package:aetherStream/widgets/media_action_sheet.dart';

class RechercheM3U extends StatefulWidget {
  final String filePath;
  const RechercheM3U({super.key, required this.filePath});

  @override
  State<RechercheM3U> createState() => _RechercheM3UState();
}

class _RechercheM3UState extends State<RechercheM3U> {
  // ── UI State ────────────────────────────────────────────────────────────────
  bool _showFilms  = true;
  bool _showSeries = true;
  bool _showTv     = true;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  // ── Data ────────────────────────────────────────────────────────────────────
  final List<M3uEntry> _filmsList  = [];
  final List<M3uEntry> _seriesList = [];
  final List<M3uEntry> _tvList     = [];

  Map<String, Map<String, List<M3uEntry>>> _groupedSeries = {};
  Map<String, List<M3uEntry>>              _groupedFilms  = {};
  Map<String, List<M3uEntry>>              _groupedTv     = {};
  List<dynamic> _flatList      = [];
  bool   _isProcessing  = true;
  double _loadingProgress = 0.0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (_searchQuery != _searchController.text) {
        setState(() {
          _searchQuery = _searchController.text;
          _filterAndGroupResults();
        });
      }
    });
    _processFile();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Parsing ─────────────────────────────────────────────────────────────────

  Future<void> _processFile() async {
    try {
      await M3uParser.parseFile(
        widget.filePath,
        _filmsList,
        _seriesList,
        _tvList,
        onProgress: (p) {
          if (mounted) setState(() => _loadingProgress = p);
        },
      );
      if (mounted) {
        setState(() => _loadingProgress = 1.0);
        await Future.delayed(Duration.zero);
        _filterAndGroupResults();
        setState(() => _isProcessing = false);
      }
    } catch (e) {
      if (mounted) setState(() { _isProcessing = false; _errorMessage = e.toString(); });
    }
  }

  // ── Filtrage / Regroupement ─────────────────────────────────────────────────

  void _filterAndGroupResults() {
    final query = _searchQuery.toLowerCase();

    final newGroupedSeries = <String, Map<String, List<M3uEntry>>>{};
    final newGroupedFilms  = <String, List<M3uEntry>>{};
    final newGroupedTv     = <String, List<M3uEntry>>{};

    bool matches(M3uEntry e) => query.isEmpty ||
        e.rawTitle.toLowerCase().contains(query) ||
        e.displayName.toLowerCase().contains(query);

    if (_showFilms) {
      for (var e in _filmsList) {
        if (matches(e)) newGroupedFilms.putIfAbsent(contentGroupKey(e), () => []).add(e);
      }
    }
    if (_showSeries) {
      for (var e in _seriesList) {
        if (matches(e)) {
          final key = contentGroupKey(e);
          newGroupedSeries.putIfAbsent(key, () => {});
          newGroupedSeries[key]!.putIfAbsent(e.saison ?? '00', () => []).add(e);
        }
      }
    }
    if (_showTv) {
      for (var e in _tvList) {
        if (matches(e) && !isHiddenTvVariant(e.title.rawTitle)) {
          newGroupedTv.putIfAbsent(tvGroupKey(e.displayName), () => []).add(e);
        }
      }
    }

    for (var list in newGroupedFilms.values) { list.sort((a, b) => a.rawTitle.compareTo(b.rawTitle)); }
    for (var list in newGroupedTv.values) { list.sort((a, b) => a.rawTitle.compareTo(b.rawTitle)); }
    for (var seasons in newGroupedSeries.values) {
      for (var episodes in seasons.values) { episodes.sort((a, b) => a.rawTitle.compareTo(b.rawTitle)); }
    }

    setState(() {
      _groupedSeries = newGroupedSeries;
      _groupedFilms  = newGroupedFilms;
      _groupedTv     = newGroupedTv;
      _flatList = [..._groupedFilms.keys, ..._groupedSeries.keys, ..._groupedTv.keys];
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
      M3uEntry selected = entry;
      if (versions.length > 1) {
        final choice = await showVersionSelector(context, versions);
        if (choice == null) return;
        selected = choice;
      }
      if (!mounted) return;
      await showMediaActionSheet(context, selected);
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

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverAppBar(
          elevation: innerBoxIsScrolled ? 4.0 : 0.0,
          title: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(200),
              borderRadius: BorderRadius.circular(25.0),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              decoration: InputDecoration(
                hintText: l10n.searchFieldHint,
                hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurfaceVariant),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        onPressed: () => _searchController.clear())
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 10.0),
              ),
            ),
          ),
          pinned: true,
          floating: true,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(kToolbarHeight + 12),
            child: _buildFilterChips(l10n),
          ),
        ),
      ],
      body: _flatList.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.search_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isNotEmpty ? l10n.searchNoResults : l10n.searchNoContent,
                style: const TextStyle(color: Colors.grey, fontSize: 16, fontStyle: FontStyle.italic),
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
    );
  }

  // ── Loading screen ──────────────────────────────────────────────────────────

  Widget _buildLoadingScreen() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _loadingProgress,
                  minHeight: 3,
                  backgroundColor: onSurface.withAlpha(30),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                _loadingLabel('Films', _filmsList.isNotEmpty),
                const SizedBox(width: 16),
                _loadingLabel('Séries', _seriesList.isNotEmpty),
                const SizedBox(width: 16),
                _loadingLabel('Chaînes', _tvList.isNotEmpty),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadingLabel(String label, bool active) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 400),
      style: TextStyle(
        color: active ? onSurface.withAlpha(180) : onSurface.withAlpha(60),
        fontSize: 13,
        fontWeight: active ? FontWeight.w600 : FontWeight.normal,
      ),
      child: Text(label),
    );
  }

  // ── Filter chips ─────────────────────────────────────────────────────────────

  Widget _buildFilterChips(AppLocalizations l10n) {
    const Color selectedBg      = kAetherPrimaryPurple;
    const Color selectedLabel   = kTextDarkPrimary;
    const Color unselectedBg    = kContainerDark;
    const Color unselectedBorder = kAetherSecondaryCyan;
    const Color unselectedLabel = kTextDarkSecondary;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        FilterChip(
          label: Text(l10n.searchFilterFilms),
          selected: _showFilms,
          onSelected: (s) => setState(() { _showFilms = s; _filterAndGroupResults(); }),
          selectedColor: selectedBg,
          backgroundColor: unselectedBg,
          labelStyle: _showFilms ? const TextStyle(color: selectedLabel, fontWeight: FontWeight.bold) : const TextStyle(color: unselectedLabel),
          side: _showFilms ? BorderSide.none : BorderSide(color: unselectedBorder.withAlpha(100)),
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: Text(l10n.searchFilterSeries),
          selected: _showSeries,
          onSelected: (s) => setState(() { _showSeries = s; _filterAndGroupResults(); }),
          selectedColor: selectedBg,
          backgroundColor: unselectedBg,
          labelStyle: _showSeries ? const TextStyle(color: selectedLabel, fontWeight: FontWeight.bold) : const TextStyle(color: unselectedLabel),
          side: _showSeries ? BorderSide.none : BorderSide(color: unselectedBorder.withAlpha(100)),
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: Text(l10n.searchFilterTv),
          selected: _showTv,
          onSelected: (s) => setState(() { _showTv = s; _filterAndGroupResults(); }),
          selectedColor: selectedBg,
          backgroundColor: unselectedBg,
          labelStyle: _showTv ? const TextStyle(color: selectedLabel, fontWeight: FontWeight.bold) : const TextStyle(color: unselectedLabel),
          side: _showTv ? BorderSide.none : BorderSide(color: unselectedBorder.withAlpha(100)),
        ),
      ]),
    );
  }
}
