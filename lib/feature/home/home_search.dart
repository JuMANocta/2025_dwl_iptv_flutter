part of 'home_page.dart';

// ─── Vue résultats de recherche ──────────────────────────────────────────────

class _SearchView extends StatelessWidget {
  /// Texte saisi (déjà debouncé par le parent).
  final String query;

  /// Toutes les entrées splittées par type — réutilisées pour le filtrage.
  final Map<M3uContentType, List<M3uEntry>> byType;
  /// §1i — Appelé quand l'utilisateur tape sur une suggestion d'historique.
  /// Le parent met à jour le contrôleur de recherche avec la valeur choisie.
  final ValueChanged<String>? onSelectSuggestion;

  const _SearchView({
    required this.query,
    required this.byType,
    this.onSelectSuggestion,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (query.trim().isEmpty) {
      return _SearchEmptyState(
        cs: cs,
        onSelectSuggestion: onSelectSuggestion,
      );
    }

    final q = query.trim().toLowerCase();

    // §searchMinLen — En dessous du seuil, on ne balaie PAS les films et les
    // séries. Avec quatre listes, chaque frappe parcourait 323 373 entrées
    // trois fois pour un résultat qui ne veut rien dire.
    //
    // ⚠️ **Les chaînes sont exemptées** : « TF1 », « M6 », « W9 », « C8 » font
    // deux ou trois caractères et sont des recherches parfaitement légitimes.
    // Aucun titre de film utile ne tient en deux lettres — l'asymétrie est
    // voulue, pas un oubli.
    //
    // ⚠️ L'incohérence historique était dans ce fichier : la rangée
    // « Personnes » s'imposait déjà `q.length < 2` (partie RÉSEAU), alors que
    // le balayage LOCAL, bien plus coûteux, ne se protégeait pas.
    final deepSearch = q.length >= _kMinQueryLength;
    final filmsHits = deepSearch
        ? _filterAndGroup(byType[M3uContentType.movie]!, q, M3uContentType.movie)
        : const <List<M3uEntry>>[];
    final seriesHits = deepSearch
        ? _filterAndGroup(byType[M3uContentType.series]!, q, M3uContentType.series)
        : const <List<M3uEntry>>[];
    final tvHits = _filterAndGroup(byType[M3uContentType.tv]!, q, M3uContentType.tv);

    final totalGroups = filmsHits.length + seriesHits.length + tvHits.length;

    // §personSearch — La rangée Personnes se gère seule (async TMDB) et se
    // masque si elle n'a rien. On la monte TOUJOURS quand une requête est en
    // cours : sinon, chercher un réalisateur absent de la playlist afficherait
    // « Aucun résultat » alors que TMDB a bien trouvé quelqu'un.
    final persons = _PersonSection(query: query);

    final sections = <Widget>[persons];
    if (filmsHits.isNotEmpty) {
      sections.add(_ResultSection(
        title: 'Films',
        icon: Icons.movie_outlined,
        groups: filmsHits,
        type: M3uContentType.movie,
        query: query,
      ));
    }
    if (seriesHits.isNotEmpty) {
      sections.add(_ResultSection(
        title: 'Séries',
        icon: Icons.tv_outlined,
        groups: seriesHits,
        type: M3uContentType.series,
        query: query,
      ));
    }
    if (tvHits.isNotEmpty) {
      sections.add(_ResultSection(
        title: 'Chaînes',
        icon: Icons.live_tv_outlined,
        groups: tvHits,
        type: M3uContentType.tv,
        query: query,
      ));
    }

    // §searchByPerson — « Films de X dans tes listes ». Rangée EN PLUS, jamais
    // à la place de la recherche par titre : « Ford » doit continuer à trouver
    // *Ford v Ferrari*. Placée après les résultats par titre (ce que la requête
    // demande littéralement) et avant les indisponibles.
    if (deepSearch) {
      sections.add(_PersonTitlesSection(query: query));
    }

    // §searchTmdb — Ce qui existe sur TMDB mais n'est dans AUCUNE liste.
    // ⚠️ Placée en DERNIER, toujours : ce qu'on peut regarder passe avant ce
    // qu'on ne peut pas. Une rangée de titres injouables en tête des résultats
    // serait une régression, pas une fonctionnalité.
    if (deepSearch) {
      sections.add(_TmdbOnlySection(
        query: query,
        // Les clés déjà trouvées localement, pour ne montrer que le MANQUANT.
        localKeys: {
          for (final g in [...filmsHits, ...seriesHits])
            contentGroupKey(g.first),
        },
      ));
    }

    if (totalGroups == 0) {
      // §searchMinLen — Sous le seuil, ne PAS afficher « aucun résultat » :
      // l'utilisateur croirait que ses listes ne contiennent rien, alors qu'on
      // n'a simplement pas encore cherché. On dit ce qu'il se passe.
      sections.add(Padding(
        padding: const EdgeInsets.only(top: 32),
        child: deepSearch
            ? EmptyState(
                icon: Icons.search_off,
                title: 'Aucun titre trouvé',
                subtitle:
                    'Rien dans vos listes pour "$query". Essaie un autre '
                    'mot-clé ou vérifie l\'orthographe.',
              )
            : const EmptyState(
                icon: Icons.keyboard_outlined,
                title: 'Continue à taper…',
                subtitle:
                    'Au moins $_kMinQueryLength lettres pour chercher un film '
                    'ou une série. Les chaînes, elles, se cherchent dès la '
                    'première lettre.',
              ),
      ));
    }

    // §searchGap — Top à 0 : le champ de recherche est posé DANS la Column de
    // `searchBody` (home_page.dart), donc cette liste commence déjà sous lui.
    // L'ancien `padding.top + 76` datait de l'époque où le champ flottait par
    // -dessus en AppBar : la hauteur était comptée deux fois, d'où le grand
    // vide entre l'input et le premier résultat. Le seul espace restant vient
    // du `top: 4` de `_SearchSectionHeader`.
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      // §searchKeyboard — Le clavier occupait environ 60 % de la zone de
      // résultats et ne se fermait jamais : on ne voyait que deux rangées.
      // ⚠️ `onDrag` et pas `onDrag`-au-changement-de-texte : l'utilisateur
      // affine souvent sa requête après un coup d'œil, fermer le clavier à la
      // frappe l'obligerait à le rouvrir sans arrêt.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: sections,
    );
  }

  /// §searchMinLen — Longueur minimale d'une requête avant de balayer les
  /// films et les séries.
  ///
  /// Trois caractères : en dessous, le résultat est un bruit de milliers de
  /// groupes qui n'apprend rien, pour un balayage complet de la playlist à
  /// chaque frappe.
  static const int _kMinQueryLength = 3;

  /// §searchCount + §searchMore — Nombre de groupes AFFICHÉS d'emblée par
  /// type.
  ///
  /// ⚠️ Ce n'est plus un plafond de résultats mais une limite d'AFFICHAGE : la
  /// recherche remonte tout, la rangée en montre 30 et propose « Voir tout »
  /// pour le reste. Le compteur de l'en-tête peut donc redevenir un vrai
  /// total, au lieu du « 30+ » approximatif qu'imposait la troncature.
  static const int _kMaxGroupsPerType = 30;

  /// Filtre par texte + regroupe par titre (= toutes variantes d'un même film/série/chaîne).
  /// Limite : [_kMaxGroupsPerType] groupes par type pour éviter les listes interminables.
  List<List<M3uEntry>> _filterAndGroup(
    List<M3uEntry> entries,
    String q,
    M3uContentType type,
  ) {
    // §searchAccents — La requête est repliée une seule fois, et confrontée à
    // `groupKey`, qui est PRÉ-CALCULÉ et désormais lui aussi sans accents.
    // Replier les 320 000 titres à chaque frappe était exclu ; ici le repli ne
    // coûte rien à l'exécution.
    final qFolded = TitleMetadata.foldAccents(q);
    bool match(M3uEntry e) =>
        e.title.groupKey.contains(qFolded) ||
        e.displayName.toLowerCase().contains(q) ||
        e.rawTitle.toLowerCase().contains(q);

    // §23 — contentGroupKey est insensible à la casse (fusion cross-listes).
    String key(M3uEntry e) =>
        type == M3uContentType.tv ? tvGroupKey(e.displayName) : contentGroupKey(e);

    final byGroup = <String, List<M3uEntry>>{};
    for (final e in entries) {
      if (!match(e)) continue;
      byGroup.putIfAbsent(key(e), () => []).add(e);
    }

    // §URGENT — dédup qualité dans les groupes TV (cohérent avec _TypePage)
    if (type == M3uContentType.tv) {
      for (final k in byGroup.keys.toList()) {
        byGroup[k] = dedupeTvVersions(byGroup[k]!);
      }
    }

    // §homonymYear — FILMS et SÉRIES : même split par année que la home.
    final groups = type != M3uContentType.tv
        ? _TypePageState._splitGroupsByYear(byGroup.values)
        : byGroup.values.toList();
    // §searchMore — Plus de troncature ICI : la liste complète remonte, et
    // c'est `_ResultSection` qui décide combien en montrer. Sans ça, il n'y
    // avait aucun moyen d'accéder au-delà des 30 premiers, et le compteur ne
    // pouvait annoncer qu'un « 30+ » approximatif.
    return groups;
  }
}



/// §searchByPerson — « Films de X dans tes listes ».
///
/// **Le manque.** Taper « Nolan » remontait sa vignette de personne, mais aucun
/// de ses films **présents dans les listes** : pour les voir, il fallait ouvrir
/// sa fiche. Or `ActorDetailsPage` sait déjà faire ce rapprochement — il ne
/// manquait qu'un raccourci depuis la recherche.
///
/// ⚠️ **Rangée EN PLUS, jamais à la place de la recherche par titre.**
/// « Ford » doit continuer à trouver *Ford v Ferrari* : une requête est un
/// texte avant d'être un nom propre.
///
/// ⚠️ **Seule la personne la plus probable est exploitée** (le 1er résultat,
/// TMDB triant déjà par pertinence) : une fiche complète par personne, ce
/// serait dix requêtes réseau à chaque frappe.
class _PersonTitlesSection extends StatefulWidget {
  final String query;
  const _PersonTitlesSection({required this.query});

  @override
  State<_PersonTitlesSection> createState() => _PersonTitlesSectionState();
}

class _PersonTitlesSectionState extends State<_PersonTitlesSection> {
  /// Index titre normalisé → entrées, construit UNE fois par version de
  /// playlist et partagé par toutes les instances.
  ///
  /// ⚠️ Statique délibérément : la rangée est reconstruite à chaque frappe, et
  /// indexer 320 000 entrées à chaque fois serait ruineux. Le même motif existe
  /// dans `ActorDetailsPage` (§tmdbOnlyDetails), pour la même raison.
  static Map<String, List<M3uEntry>> _index = const {};
  static int _indexVersion = -1;

  static Map<String, List<M3uEntry>> _lookup() {
    final v = ParsedPlaylistService.version.value;
    if (_indexVersion == v) return _index;
    final map = <String, List<M3uEntry>>{};
    for (final e in ParsedPlaylistService.entries) {
      if (e.type == M3uContentType.tv) continue; // une chaîne n'a pas d'acteurs
      map.putIfAbsent(contentGroupKey(e), () => []).add(e);
    }
    _index = map;
    _indexVersion = v;
    return map;
  }

  String? _personName;
  List<List<M3uEntry>> _groups = const [];
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(covariant _PersonTitlesSection old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _search();
  }

  Future<void> _search() async {
    final token = ++_requestId;
    final q = widget.query.trim();
    void clear() {
      if (mounted && _groups.isNotEmpty) {
        setState(() {
          _groups = const [];
          _personName = null;
        });
      }
    }

    if (q.length < 3) return clear();
    if (!await TmdbApiService.hasApiKey()) return;

    final persons = await TmdbService.instance.searchPersons(q, limit: 1);
    if (!mounted || token != _requestId) return;
    if (persons.isEmpty) return clear();

    final person = await TmdbService.instance.getPersonDetails(persons.first.id);
    if (!mounted || token != _requestId) return;
    if (person == null || person.filmography.isEmpty) return clear();

    // Rapprochement par clé de groupe — même règle que partout ailleurs.
    final index = _lookup();
    final found = <List<M3uEntry>>[];
    final seen = <String>{};
    for (final f in person.filmography) {
      final k = TitleMetadata.computeGroupKey(f.title);
      if (k.isEmpty || !seen.add(k)) continue;
      final hit = index[k];
      if (hit != null && hit.isNotEmpty) found.add(hit);
    }
    if (found.isEmpty) return clear();

    setState(() {
      _personName = persons.first.name;
      _groups = found;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_groups.isEmpty || _personName == null) return const SizedBox.shrink();
    return _ResultSection(
      title: 'De $_personName, dans tes listes',
      icon: Icons.person_search_outlined,
      groups: _groups,
      type: M3uContentType.movie,
      query: widget.query,
    );
  }
}

/// §searchTmdb — Rangée « Sur TMDB, absent de tes listes ».
///
/// **Ce qu'elle répond.** Jusqu'ici, un titre introuvable ne disait rien : on
/// ne savait pas si le film n'existait pas, ou si aucun fournisseur ne le
/// proposait. La rangée tranche, et donne accès à la fiche complète (synopsis,
/// casting, bande-annonce) via `DetailsPage.fromTmdb` (§tmdbOnlyDetails), dont
/// les boutons de lecture sont déjà neutralisés pour une entrée sans source.
///
/// ⚠️ **Le rapprochement passe par `computeGroupKey`, jamais par une
/// comparaison de chaînes.** Un titre présent sous une variante
/// (`|FR| Le Titre (2024) MULTI`) serait sinon annoncé comme absent —
/// exactement le genre d'erreur que §cleanQuery vient de coûter cher.
///
/// ⚠️ On compare AUSSI le titre original : un fournisseur peut lister la VO
/// (« The Handmaid's Tale ») là où TMDB rend le titre français. Sans ça, on
/// présenterait comme manquant un titre qu'on possède.
///
/// Se retire complètement sans clé TMDB : l'app reste pleinement utilisable
/// sans elle.
class _TmdbOnlySection extends StatefulWidget {
  final String query;

  /// Clés de groupe DÉJÀ trouvées dans les listes — le complément de ce que la
  /// rangée doit montrer.
  final Set<String> localKeys;

  const _TmdbOnlySection({required this.query, required this.localKeys});

  @override
  State<_TmdbOnlySection> createState() => _TmdbOnlySectionState();
}

class _TmdbOnlySectionState extends State<_TmdbOnlySection> {
  List<TmdbTitleHit> _hits = const [];
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(covariant _TmdbOnlySection old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _search();
  }

  Future<void> _search() async {
    // Même garde-fou que §personSearch : un jeton par requête, pour jeter les
    // réponses qui arrivent dans le désordre pendant que l'utilisateur tape.
    final token = ++_requestId;
    final q = widget.query.trim();
    if (q.length < 3) {
      if (_hits.isNotEmpty && mounted) setState(() => _hits = const []);
      return;
    }
    if (!await TmdbApiService.hasApiKey()) return;
    final res = await TmdbService.instance.searchTitles(q);
    if (!mounted || token != _requestId) return;
    setState(() => _hits = res);
  }

  /// Ne garde que ce qui n'est dans aucune liste.
  List<TmdbTitleHit> get _missing => _hits.where((h) {
        final k = TitleMetadata.computeGroupKey(h.title);
        if (widget.localKeys.contains(k)) return false;
        final orig = h.originalTitle;
        if (orig != null && orig.isNotEmpty) {
          if (widget.localKeys.contains(TitleMetadata.computeGroupKey(orig))) {
            return false;
          }
        }
        return true;
      }).toList();

  @override
  Widget build(BuildContext context) {
    final missing = _missing;
    if (missing.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SearchSectionHeader(
            title: 'Sur TMDB, absent de tes listes',
            icon: Icons.cloud_off_outlined,
            count: missing.length,
          ),
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: missing.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _TmdbOnlyCard(hit: missing[i]),
            ),
          ),
        ],
      ),
    );
  }
}

/// §searchTmdb — Vignette d'un titre NON disponible.
///
/// ⚠️ Volontairement **assombrie et marquée** : sans distinction visuelle, elle
/// se confondrait avec les résultats jouables et l'utilisateur cliquerait en
/// s'attendant à regarder. Le code couleur de l'app est déjà pris pour la
/// qualité ; on passe donc par l'opacité et une étiquette explicite.
class _TmdbOnlyCard extends StatelessWidget {
  final TmdbTitleHit hit;
  const _TmdbOnlyCard({required this.hit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final poster = TmdbService.getPosterUrl(hit.posterPath, size: 'w342');

    return FocusableCard(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DetailsPage.fromTmdb(
            tmdbId: hit.id,
            title: hit.title,
            type: hit.isTv ? M3uContentType.series : M3uContentType.movie,
          ),
        ),
      ),
      child: SizedBox(
        width: 124,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Opacity(
                      opacity: 0.45,
                      child: AetherImage(
                        url: poster,
                        fit: BoxFit.cover,
                        cacheWidth: decodeWidthFor(context, 124),
                        fallback: (_) => Container(
                          color: cs.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(Icons.movie_outlined,
                              color: cs.onSurfaceVariant.withAlpha(120)),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(190),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: kWarning.withAlpha(140)),
                      ),
                      child: Text(
                        'NON DISPO',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: kWarning,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hit.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withAlpha(190),
                height: 1.2,
              ),
            ),
            if (hit.year != null)
              Text(
                hit.year!,
                style: TextStyle(
                    fontSize: 10, color: cs.onSurfaceVariant.withAlpha(160)),
              ),
          ],
        ),
      ),
    );
  }
}

/// §personSearch — Rangée « Personnes » (acteurs / réalisateurs) en tête des
/// résultats, alimentée par TMDB.
///
/// **Seul bloc ASYNC de la recherche** (le reste filtre la playlist en
/// mémoire, de façon synchrone) → widget dédié pour ne pas rendre tout
/// `_SearchView` stateful. La requête part sur changement de `query` (déjà
/// debouncée à 220 ms par `_HomePageState`), et un **token de requête** ignore
/// les réponses arrivées dans le désordre.
///
/// Se retire complètement (`SizedBox.shrink`) sans clé TMDB ou sans résultat :
/// l'app doit rester pleinement utilisable sans TMDB.
class _PersonSection extends StatefulWidget {
  final String query;
  const _PersonSection({required this.query});

  @override
  State<_PersonSection> createState() => _PersonSectionState();
}

class _PersonSectionState extends State<_PersonSection> {
  List<PersonHit> _hits = const [];
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(covariant _PersonSection old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _search();
  }

  Future<void> _search() async {
    final token = ++_requestId;
    final q = widget.query.trim();
    if (q.length < 2) {
      if (_hits.isNotEmpty && mounted) setState(() => _hits = const []);
      return;
    }
    if (!await TmdbApiService.hasApiKey()) return;
    final res = await TmdbService.instance.searchPersons(q);
    // Réponse obsolète (l'utilisateur a continué à taper) → on jette.
    if (!mounted || token != _requestId) return;
    setState(() => _hits = res);
  }

  @override
  Widget build(BuildContext context) {
    if (_hits.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SearchSectionHeader(
            title: 'Personnes',
            icon: Icons.person_outline,
            count: _hits.length,
          ),
          SizedBox(
            // photo ronde 72 + nom (2 lignes) + métier + marge textScaler TV.
            height: 148,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _hits.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _PersonCard(hit: _hits[i]),
            ),
          ),
        ],
      ),
    );
  }
}

/// §personSearch — Vignette de personne : photo RONDE (code visuel qui la
/// distingue immédiatement des affiches rectangulaires) + nom + métier.
class _PersonCard extends StatelessWidget {
  final PersonHit hit;
  const _PersonCard({required this.hit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final photo = TmdbService.getPosterUrl(hit.profilePath, size: 'w185');
    final role = hit.roleLabel;

    return FocusableCard(
      scaleOnFocus: false,
      anchorRowStart: true, // §rowAnchorDetails
      borderRadius: BorderRadius.circular(40),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ActorDetailsPage(personId: hit.id)),
      ),
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: SizedBox(
                width: 72,
                height: 72,
                child: AetherImage(
                  url: photo,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  // §imgThrash — 72 px réels, décodés à la densité de l'écran.
                  cacheWidth: decodeWidthFor(context, 72),
                  alignment: Alignment.topCenter,
                  fallback: (_) => Container(
                    color: cs.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: Icon(Icons.person,
                        size: 32, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hit.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (role != null)
              Text(
                role,
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

/// §personSearch — En-tête de section de résultats (barre gradient + icône +
/// titre + compteur), extrait de `_ResultSection` pour être partagé avec la
/// rangée « Personnes » → zéro divergence visuelle entre les sections.
class _SearchSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;

  const _SearchSectionHeader({
    required this.title,
    required this.icon,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              gradient: kAetherGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 18, color: kAccentPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: cs.onSurface,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<List<M3uEntry>> groups;
  final M3uContentType type;

  /// §searchMore — Sert à titrer la page « Voir tout » : « Films · "dune" ».
  final String query;

  const _ResultSection({
    required this.title,
    required this.icon,
    required this.groups,
    required this.type,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // §personSearch — en-tête factorisé (partagé avec _PersonSection).
          // §searchMore — Vrai total : la liste n'est plus tronquée en amont.
          _SearchSectionHeader(title: title, icon: icon, count: groups.length),
          // §tvZoom — Largeur de vignette + hauteur pilotées par la largeur
          // réelle (poster 2:3 ou logo carré pour les chaînes).
          LayoutBuilder(
            builder: (ctx, constraints) {
              final channel = type == M3uContentType.tv;
              final cardW =
                  _responsiveTileWidth(constraints.maxWidth, channel: channel);
              // §searchMore — On n'affiche que les premiers, et on offre une
              // porte de sortie vers la liste complète. Le plafond reste utile
              // (une rangée de 4 000 vignettes ne sert personne) ; c'est
              // l'ABSENCE de « Voir tout » qui était le vrai défaut.
              const max = _SearchView._kMaxGroupsPerType;
              final shown = groups.length > max ? max : groups.length;
              final hasMore = groups.length > shown;
              return SizedBox(
                height: (channel ? cardW : cardW * 1.5) + 20,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: shown + (hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (ctx, i) {
                    if (hasMore && i == shown) {
                      // Réutilise la tuile de l'accueil : même geste, même
                      // rendu, et `CategoryListPage` fait déjà tout le travail.
                      return _SeeAllTile(
                        type: type,
                        remaining: groups.length - shown,
                        width: cardW,
                        onTap: () => Navigator.of(ctx).push(
                          MaterialPageRoute(
                            builder: (_) => CategoryListPage(
                              category: '$title · "$query"',
                              groups: groups,
                              type: type,
                              icon: icon,
                            ),
                          ),
                        ),
                      );
                    }
                    return _HomeCard(
                      versions: groups[i],
                      type: type,
                      width: cardW,
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Physics : swipe gauche/droite plus court (-20%) ─────────────────────────

/// `PageScrollPhysics` plus sensible : amplifie la vélocité au moment du release
/// → un **swipe court et rapide** suffit à changer de page (plus besoin de
/// traverser tout l'écran). Le seuil de distance (~50 %) reste celui de Flutter
/// pour les drags lents ; c'est le flick qu'on rend sensible.
///
/// `_kPageFlickBoost` ×1.8 (au lieu de ×1.15) : compromis sensibilité / pas de
/// secousse. Un seul chiffre à ajuster (monter = plus sensible).
class _FastPageScrollPhysics extends PageScrollPhysics {
  const _FastPageScrollPhysics({super.parent});

  // §pageSmooth — Seuil de bascule ABAISSÉ : un glissement d'environ 1/3 de
  // l'écran (au lieu des 50 % par défaut) suffit à passer à la page suivante.
  // On décide la page cible selon le SENS du geste (signe de la vélocité au
  // relâché) → fini le "retour à la page d'origine" quand on relâche vers la
  // moitié. Ressort par défaut conservé (snap net, pas le ressort mou précédent).
  static const double _kCommitBias = 0.18; // 0.5 - 0.18 ≈ bascule dès ~32 %

  @override
  _FastPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _FastPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    final tol = toleranceFor(position);
    final vp = position.viewportDimension;
    if (vp <= 0) return super.createBallisticSimulation(position, velocity);
    final page = position.pixels / vp;

    double targetPage;
    if (velocity.abs() < tol.velocity) {
      // Relâché quasi immobile → arrondi standard (nearest, seuil 0.5).
      targetPage = page.roundToDouble();
    } else if (velocity > 0) {
      // Geste vers la page suivante → bascule dès ~32 % de glissement.
      targetPage = (page + _kCommitBias).roundToDouble();
    } else {
      // Geste vers la page précédente.
      targetPage = (page - _kCommitBias).roundToDouble();
    }

    final target = (targetPage * vp)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < tol.distance) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity,
        tolerance: tol);
  }
}


// ─── §1i État vide de la recherche : suggestions d historique ────────────────

class _SearchEmptyState extends StatelessWidget {
  final ColorScheme cs;
  final ValueChanged<String>? onSelectSuggestion;

  const _SearchEmptyState({required this.cs, this.onSelectSuggestion});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SearchHistoryService.version,
      builder: (_, __, ___) {
        final history = SearchHistoryService.all;
        return SingleChildScrollView(
          // §searchGap — Même vestige que dans `_SearchView` (ex-`+ 80`) : les
          // suggestions d'historique étaient poussées loin sous le champ.
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (history.isEmpty) ...[
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.search,
                          size: 56,
                          color: cs.onSurfaceVariant.withAlpha(120)),
                      const SizedBox(height: 12),
                      Text(
                        "Tapez pour chercher dans votre playlist",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Films · Séries · Chaînes",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: cs.onSurfaceVariant.withAlpha(150),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Icon(Icons.history, size: 18, color: kAccentSecondary),
                    const SizedBox(width: 8),
                    Text(
                      "Recherches récentes",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      // §undoClear + §undoTv — Effacer l'historique reste
                      // réversible, mais la forme dépend de l'appareil : au
                      // doigt une snackbar « Annuler » 5 s, à la télécommande
                      // une confirmation AVANT (la snackbar n'est pas
                      // atteignable au D-pad). Dans les deux cas, le snapshot
                      // est pris AVANT l'effacement, puis « Annuler » rejoue
                      // `record()` du plus ANCIEN au plus récent (record insère
                      // en tête, donc l'ordre d'origine est reconstitué).
                      // `version` bumpe à chaque appel → la liste se redessine
                      // d'elle-même.
                      onPressed: () async {
                        final List<String> snapshot = SearchHistoryService.all;
                        if (snapshot.isEmpty) return;
                        await confirmOrUndo(
                          context,
                          title: 'Effacer l\'historique ?',
                          question: snapshot.length == 1
                              ? 'La dernière recherche sera supprimée.'
                              : 'Les ${snapshot.length} dernières recherches seront supprimées.',
                          confirmLabel: 'Effacer',
                          doneMessage: 'Historique effacé',
                          action: () => SearchHistoryService.clear(),
                          onUndo: () async {
                            for (final q in snapshot.reversed) {
                              await SearchHistoryService.record(q);
                            }
                          },
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        "Effacer",
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant.withAlpha(180)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: history
                      .map((q) => _HistoryChip(
                            query: q,
                            cs: cs,
                            onTap: () => onSelectSuggestion?.call(q),
                            onDismiss: () => SearchHistoryService.remove(q),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HistoryChip extends StatelessWidget {
  final String query;
  final ColorScheme cs;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _HistoryChip({
    required this.query,
    required this.cs,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: kAccentSecondary.withAlpha(60), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history,
                size: 14, color: cs.onSurfaceVariant.withAlpha(180)),
            const SizedBox(width: 6),
            Text(
              query,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            // §touchTarget — La croix faisait 22x22 a QUATRE pixels d'un tap
            // qui RELANCE la recherche : viser mal ne coutait pas rien. La
            // zone tactile passe a 44 dp de large (la hauteur du chip borne le
            // reste) et s'ecarte du libelle.
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: SizedBox(
                width: 44,
                height: 40,
                child: Center(
                  child: Icon(Icons.close,
                      size: 14, color: cs.onSurfaceVariant.withAlpha(160)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── §1i Tuile "Reprendre la chaîne" en tête de la page Chaînes ──────────────

class _LastWatchedTvTile extends StatelessWidget {
  /// Entrées TV disponibles dans la playlist actuelle — utilisé pour vérifier
  /// que la dernière chaîne regardée existe toujours avant d affiché la tuile.
  final List<M3uEntry> entries;
  const _LastWatchedTvTile({required this.entries});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: LastWatchedChannelService.version,
      builder: (_, __, ___) {
        final last = LastWatchedChannelService.current;
        if (last == null) return const SizedBox.shrink();

        // Cherche l entrée actuelle correspondante dans la playlist (pour
        // récupérer logo / displayName à jour si renommé côté provider).
        final match = entries.firstWhere(
          (e) => e.url == last.url,
          orElse: () => M3uEntry(
            url: last.url,
            type: M3uContentType.tv,
            tvgId: last.tvgId,
            logoUrl: last.logoUrl,
            title: TitleMetadata(rawTitle: last.title, baseTitle: last.title),
            accountId: "",
          ),
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => showTvActionSheet(context, [match]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    kAccentSecondary.withAlpha(40),
                    kAccentPrimary.withAlpha(20),
                  ],
                ),
                border: Border.all(
                    color: kAccentSecondary.withAlpha(120), width: 1),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 48,
                      height: 48,
                      color: Colors.black26,
                      // §imgDiskCache — cache disque partagé (AetherImage).
                      child: AetherImage(
                        url: last.logoUrl,
                        fit: BoxFit.contain,
                        // §imgThrash — 48 px réels.
                        cacheWidth: decodeWidthFor(context, 48),
                        fallback: (_) =>
                            const Icon(Icons.live_tv, color: Colors.white54),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "REPRENDRE LA CHAÎNE",
                          style: TextStyle(
                            color: kAccentSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          last.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: kAetherGradient,
                      boxShadow: [
                        BoxShadow(
                            color: kAccentPrimary.withAlpha(150),
                            blurRadius: 10),
                      ],
                    ),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.black, size: 22),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
