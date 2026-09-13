part of 'home_page.dart';

// ─── Carte poster avec overlay gradient + titre ─────────────────────────────

/// R38 — `true` quand [entry] est le **stub** d'une série : l'unique entrée que
/// le catalogue Xtream porte pour la série entière
/// (`/series/{user}/{pass}/{series_id}`, sans extension).
///
/// ⛔ **Ce n'est PAS un endpoint de stream.** Le parseur le dit déjà en toutes
/// lettres (`xtream_catalog_parser`) : cette URL n'est qu'un marqueur, dont la
/// fiche extrait le `series_id` pour aller chercher les épisodes à la demande.
///
/// **Le défaut qu'elle corrige.** La feuille d'appui long n'avait aucune garde
/// de type : sa tuile « Lire » poussait `PlayerPage(path: entry.url)` avec ce
/// stub — une lecture qui ne peut pas aboutir. Le tap simple, lui, gardait
/// déjà la série pour la fiche. §heroSeriesResume l'a rendu VISIBLE : la
/// progression d'un épisode s'écrit désormais AUSSI sous le stub, donc la même
/// tuile se mettait à proposer « Reprendre · mm:ss » sur un chemin injouable.
///
/// ⚠️ Une série ne se reconnaît PAS à son type : une liste M3U porte ses
/// épisodes comme autant d'entrées `series` à l'URL bien réelle (§Ultimate,
/// `SxxExx`), et leur appui long doit continuer de lire. C'est la FORME de
/// l'URL qui tranche, avec la règle EXACTE de
/// `DetailsPage._extractSeriesIdFromUrl` — celle qui décide partout ailleurs
/// qu'une entrée est un stub d'API (une entrée que cette règle ne reconnaît
/// pas est aussi une entrée dont la fiche ne saurait pas tirer d'épisodes).
///
/// ⛔ **Cette règle est une COPIE de `DetailsPage._extractSeriesIdFromUrl`** :
/// les deux doivent être tenues d'accord. Si l'une change, l'autre change —
/// sinon l'accueil et la fiche ne s'entendront plus sur ce qu'est un stub.
/// C'est §tourFix (deux copies d'une règle divergent toujours ; le projet l'a
/// déjà payé sur `redactUrl`) : l'unification en un prédicat unique est un
/// ticket ouvert, volontairement différé — un refactor inter-fichiers dans un
/// arbre où plusieurs lots avancent en parallèle casserait plus qu'il ne règle.
///
/// Fonction pure : c'est elle qu'on teste.
bool isSeriesStubEntry(M3uEntry entry) {
  if (entry.type != M3uContentType.series) return false;
  // Épisode numéroté (liste M3U) : son URL est jouable telle quelle.
  //
  // ⚠️ **Ce court-circuit ne protège d'aucun cas mesuré** : sur les 231 252 URL
  // `/series/` des deux M3U réels, aucune ne porte à la fois une numérotation
  // et une URL sans extension — le test d'extension plus bas les attrape déjà
  // toutes. Sa valeur est la PARITÉ avec la fiche : `_buildSeasonEpisodes`
  // (`details_page.dart:739-745`) teste lui aussi le TITRE avant l'URL. Le
  // retirer ferait diverger l'accueil de la fiche sur ce qu'est un stub,
  // c'est-à-dire aggraver la dette R44 au lieu de la contenir.
  if (entry.title.isSeriesEpisode) return false;
  try {
    final List<String> segments = Uri.parse(entry.url).pathSegments;
    if (segments.length < 4 || segments.first.toLowerCase() != 'series') {
      return false;
    }
    final String last = segments.last;
    if (last.contains('.')) return false; // une extension = URL d'épisode
    return int.tryParse(last) != null;
  } catch (_) {
    return false;
  }
}

/// R38 — `true` si le GROUPE de la vignette contient un stub de série.
///
/// ⛔ **La question se pose sur le groupe, pas sur `versions.first`.** Un même
/// titre peut MÉLANGER le stub d'API d'un compte Xtream et les épisodes réels
/// d'une liste M3U : c'est conçu, pas hypothétique — `_buildSeasonEpisodes`
/// sépare précisément les deux familles depuis une seule collecte
/// (`details_page.dart:736-748`, §seriesMultiList). Interroger la seule
/// première version laissait donc le défaut d'origine INTACT dès qu'un épisode
/// M3U se trouvait en tête : « Lire » jouait alors un épisode arbitraire sous
/// le nom de la série.
///
/// ⚠️ `any`, et surtout pas « toutes » : « toutes » rendrait `false` sur un
/// groupe mixte, c'est-à-dire exactement le cas qu'on vient de décrire.
///
/// ⚠️ Le prix est assumé (**R45**) : un groupe mixte perd aussi « Télécharger »
/// alors qu'il contient des épisodes téléchargeables. La bonne réponse est une
/// décision par TUILE, qui demande une mesure préalable sur les dumps — elle ne
/// se bricole pas ici.
///
/// Fonction pure : c'est elle qu'on teste.
bool groupHasSeriesStub(Iterable<M3uEntry> versions) =>
    versions.any(isSeriesStubEntry);

class _HomeCard extends StatefulWidget {
  final List<M3uEntry> versions;
  final M3uContentType type;

  /// Largeur explicite (mode grille). Si null, valeur par défaut selon type
  /// (130 pour films/séries en carousel, 120 pour TV en carousel).
  final double? width;

  /// §dpadRowEntry — `true` pour la 1re carte (gauche) d'un carrousel : point
  /// d'entrée dpad de la rangée → ↓ depuis une rangée du dessus se cale à gauche.
  final bool isEntry;

  /// §posterScope — `true` = l'affiche TMDB passe DEVANT celle des listes
  /// (option « Affiches TMDB en priorité »). Décidé par le PARENT, jamais lu
  /// dans les réglages : l'option ne vaut que pour le carrousel et la rangée
  /// Favoris. Sur toutes les vignettes, elle déclenchait ~450 recherches TMDB
  /// à l'ouverture de l'accueil et le faisait saccader pendant 15 s.
  final bool tmdbFirst;

  const _HomeCard(
      {super.key,
      required this.versions,
      required this.type,
      this.width,
      this.isEntry = false,
      this.tmdbFirst = false});

  @override
  State<_HomeCard> createState() => _HomeCardState();
}

class _HomeCardState extends State<_HomeCard> {
  /// §tabMeter — nombre de builds de cartes depuis le lancement (sonde du
  /// changement d'onglet, relevée par différence dans `_goToPage`).
  static int buildCount = 0;

  bool _pressed = false;

  /// §Ultimate — affiche TMDB résolue à la volée quand le M3U ne fournit aucun
  /// `tvg-logo` (VOD Ultimate). Reste null pour les chaînes TV et les entrées
  /// déjà pourvues d'un logo.
  String? _tmdbPoster;

  /// §logoFallback — Adresses d'image du groupe, dans l'ordre de préférence.
  ///
  /// ⚠️ Remplace l'ancien test `_hasM3uLogo` (« au moins une version porte un
  /// `tvg-logo` »), qui **court-circuitait TMDB dès qu'une seule adresse
  /// existait, même MORTE** : on perdait alors l'affiche ET, depuis
  /// §inferredCat, la catégorie. C'est désormais l'ÉCHEC de chargement qui
  /// décide, pas la simple présence d'une chaîne de caractères.
  List<String> get _logoCandidates =>
      ParsedPlaylistService.logoCandidates(widget.versions);

  @override
  void initState() {
    super.initState();
    // §logoFallback — Sans aucune adresse, inutile d'attendre un échec de
    // chargement qui n'arrivera jamais : on résout tout de suite. Sinon on
    // laisse `AetherImage` essayer les adresses, et son `onAllFailed` nous
    // rappellera si toutes échouent.
    // §posterLang — Option « Affiches TMDB en priorité » (défaut OFF) : dans
    // ce mode on ne peut PAS attendre l'échec des adresses du fournisseur, il
    // faut résoudre dès le départ pour que l'affiche TMDB passe devant.
    // §posterScope — C'est le PARENT qui décide (`widget.tmdbFirst`).
    if (_logoCandidates.isEmpty || widget.tmdbFirst) {
      _resolveTmdbPosterIfNeeded();
    }
  }

  @override
  void didUpdateWidget(covariant _HomeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Le recyclage des cartes (ListView/Grid) réutilise l'élément avec d'autres
    // versions → on relance la résolution si le groupe a changé.
    if (oldWidget.versions.first.url != widget.versions.first.url) {
      _tmdbPoster = null;
      if (_logoCandidates.isEmpty || widget.tmdbFirst) {
        _resolveTmdbPosterIfNeeded();
      }
    } else if (widget.tmdbFirst && !oldWidget.tmdbFirst) {
      // §posterScope — L'option vient d'être activée : la carte existe déjà,
      // elle va chercher son affiche TMDB maintenant.
      _resolveTmdbPosterIfNeeded();
    }
  }

  /// §logoFallback — Repli TMDB : soit aucune adresse n'existe, soit toutes ont
  /// échoué à charger. Films et séries uniquement.
  ///
  /// ⚠️ Idempotent : `TmdbPosterCache` dédoublonne les appels concurrents et
  /// met même les résultats négatifs en cache, donc être rappelé plusieurs fois
  /// pour un même titre ne coûte rien. (Revue 2026-09-11, D1B-01 : négatifs
  /// DÉFINITIFS seulement — une panne ou l'absence de clé se retente, la
  /// présence de la clé étant mémorisée côté cache.)
  void _resolveTmdbPosterIfNeeded() {
    if (_tmdbPoster != null) return;
    if (widget.type == M3uContentType.tv) return; // les chaînes ont leur logo
    final entry = widget.versions.first;
    final query = entry.displayName;
    if (query.trim().isEmpty) return;
    final isTv = widget.type == M3uContentType.series;
    final year = entry.title.year;

    // Cache déjà résolu → consommation synchrone, pas de setState inutile.
    if (TmdbPosterCache.isResolved(query, isTv, year)) {
      _tmdbPoster = TmdbPosterCache.cached(query, isTv, year);
      return;
    }

    TmdbPosterCache.resolve(
      query: query,
      isTv: isTv,
      year: year,
      groupTitle: entry.groupTitle,
      // §inferredCat — Même clé que le regroupement de l'accueil : la catégorie
      // apprise ici s'applique donc à TOUTES les variantes du titre, quel que
      // soit le compte d'où elles viennent.
      categoryKey: contentGroupKey(entry),
    ).then((url) {
      // Revue 2026-09-11, D4A-04 — la carte a pu être RECYCLÉE pour un autre
      // titre pendant la résolution (recherche qui change à chaque frappe,
      // « Voir tout ») : `didUpdateWidget` a relancé la sienne, parfois servie
      // en synchrone par le cache, puis cette réponse-ci arrivait et posait
      // l'affiche de l'ANCIEN titre sous le nouveau libellé (§posterFlash :
      // une mauvaise image est pire que rien).
      if (!mounted || url == null) return;
      if (widget.versions.isEmpty || widget.versions.first.url != entry.url) {
        return;
      }
      setState(() => _tmdbPoster = url);
    });
  }

  Future<void> _onTap() async {
    if (widget.versions.isEmpty) return;
    final entry = widget.versions.first;
    if (widget.type == M3uContentType.tv) {
      await showTvActionSheet(context, widget.versions);
      return;
    }
    final hasTmdb = await TmdbApiService.hasApiKey();
    if (!mounted) return;
    // §bugfix — voir _openItem : une série va sur DetailsPage même sans TMDB
    // (sinon l'action sheet ne lit que le 1er épisode, pas de choix possible).
    if (hasTmdb || entry.type == M3uContentType.series) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DetailsPage(entry: entry, versions: widget.versions),
      ));
    } else {
      await showMediaActionSheet(context, entry);
    }
  }

  /// Menu contextuel sur appui long — actions rapides sans passer par la fiche.
  Future<void> _onLongPress() async {
    if (widget.versions.isEmpty) return;
    HapticFeedback.mediumImpact();
    final entry = widget.versions.first;
    // R38 — Décidé UNE fois, sur TOUT le groupe (cf. `groupHasSeriesStub` : un
    // épisode M3U en tête d'un groupe mixte laissait passer la lecture du
    // stub) : trois tuiles de la feuille en dépendent.
    final bool isSeriesStub = groupHasSeriesStub(widget.versions);

    // §3c-4 — bifurque mobile/TV pour le menu contextuel long-press.
    await showAdaptiveActionSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // En-tête : poster + titre
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 50,
                      height: widget.type == M3uContentType.tv ? 50 : 75,
                      // §imgDiskCache — cache disque partagé (AetherImage).
                      // §imgThrash — décodage calé sur les 50 px réels.
                      child: AetherImage(
                        url: entry.logoUrl,
                        fit: BoxFit.cover,
                        cacheWidth: decodeWidthFor(context, 50),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.displayName,
                      style: Theme.of(sheetCtx).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ── Lire (direct, avec reprise §1e si dispo) ──────────────────
            ValueListenableBuilder<int>(
              valueListenable: WatchProgressService.version,
              builder: (_, __, ___) {
                // Reprise impossible sur TV live → on garde le simple "Lire".
                final progress = widget.type == M3uContentType.tv
                    ? null
                    : WatchProgressService.getProgressForAny(
                        widget.versions.map((e) => e.url),
                      );
                final hasResume = progress != null && progress.position.inSeconds > 5;

                // R38 — ⛔ Le stub d'une série ne se lit pas : l'appui long
                // mène au choix saison/épisode, comme le tap simple. La barre
                // dit qu'elle est en cours (§heroSeriesResume écrit bien une
                // reprise sous cette clé) sans promettre une lecture directe,
                // qui n'existe qu'épisode par épisode.
                if (isSeriesStub) {
                  return Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.playlist_play),
                        title: Text(sheetCtx.l10n.cardChooseEpisode),
                        subtitle: hasResume
                            ? LinearProgressIndicator(
                                value: progress.ratio,
                                minHeight: 3,
                                backgroundColor: kOnImageFaint,
                                valueColor:
                                    AlwaysStoppedAnimation(kAccentSecondary),
                              )
                            : null,
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          _onTap();
                        },
                      ),
                      // R38 — La SEULE façon de retirer une série de
                      // « Reprendre » depuis l'accueil : sa clé de reprise EST
                      // le stub, donc l'oubli porte bien sur elle.
                      if (hasResume)
                        _forgetResumeTile(sheetCtx, progress, isSeries: true),
                    ],
                  );
                }

                final badge = switch (widget.type) {
                  M3uContentType.movie  => PlayerBadgeType.movie,
                  M3uContentType.series => PlayerBadgeType.series,
                  M3uContentType.tv     => PlayerBadgeType.live,
                };

                Future<void> play({Duration? from}) async {
                  Navigator.pop(sheetCtx);
                  // §deviceCaps — la porte, même règle que la fiche.
                  if (!await PlaybackGate.allow(context, entry)) return;
                  if (!mounted) return;
                  FavoritesService.addEntry(entry);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerPage(
                    path: entry.url,
                    title: entry.displayName,
                    // §stallCount — rattache les blocages au fournisseur.
                    accountId: entry.accountId,
                    // §watchContext a/b — badges qualité + saison/épisode.
                    qualityTag: entry.title.qualityOrDefault,
                    episodeTag: entry.title.seasonEpisodeLabel,
                    sourceType: VideoSourceType.network,
                    badgeType: badge,
                    startPosition: from,
                    // §endOfMovie — toutes les versions du titre s'effacent à la fin.
                    siblingResumeKeys: [for (final v in widget.versions) v.url],
                    // §nowPlaying — la même image que la vignette.
                    posterUrl: _tmdbPoster ??
                        (_logoCandidates.isEmpty ? null : _logoCandidates.first),
                  )));
                }

                if (!hasResume) {
                  return ListTile(
                    leading: const Icon(Icons.play_arrow),
                    title: Text(sheetCtx.l10n.cardPlay),
                    onTap: () => play(),
                  );
                }

                final mm = progress.position.inMinutes.remainder(60);
                final ss = progress.position.inSeconds.remainder(60);
                final hh = progress.position.inHours;
                final label = hh > 0
                    ? '${hh}h${mm.toString().padLeft(2, '0')}'
                    : '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';

                return Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.play_arrow, color: kAccentSecondary),
                      title: Text(
                        sheetCtx.l10n.cardResumeFrom(label),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: kAccentSecondary,
                        ),
                      ),
                      subtitle: LinearProgressIndicator(
                        value: progress.ratio,
                        minHeight: 3,
                        backgroundColor: kOnImageFaint, // D4A-16 (= white12)
                        valueColor: AlwaysStoppedAnimation(kAccentSecondary),
                      ),
                      onTap: () => play(from: progress.position),
                    ),
                    ListTile(
                      leading: const Icon(Icons.restart_alt),
                      title: Text(sheetCtx.l10n.cardPlayFromStart),
                      dense: true,
                      onTap: () {
                        // §resumeUnify — clear sur toutes les versions.
                        for (final v in widget.versions) {
                          WatchProgressService.clearProgress(v.url);
                        }
                        play();
                      },
                    ),
                    _forgetResumeTile(sheetCtx, progress, isSeries: false),
                  ],
                );
              },
            ),
            // ── Voir les détails (action sheet ou fiche TMDB) ─────────────
            // R38 — Muette pour un stub de série : « Choisir un épisode »
            // ouvre DÉJÀ cette même fiche, deux tuiles pour une seule
            // destination ne feraient qu'hésiter.
            if (!isSeriesStub)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(sheetCtx.l10n.cardDetails),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _onTap();
                },
              ),
            // ── Télécharger (films/séries uniquement) ─────────────────────
            // R38 — Le stub n'est pas plus téléchargeable que lisible : c'est
            // la MÊME URL qui partirait au gestionnaire, sous le seul nom de
            // la série (§dlEpisode : tous les épisodes viseraient ce fichier).
            // Le téléchargement d'un épisode vit dans la fiche, qui sait
            // lequel.
            if (widget.type != M3uContentType.tv && !isSeriesStub)
              ListTile(
                leading: const Icon(Icons.download),
                title: Text(sheetCtx.l10n.download),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  final releaseYear = widget.type == M3uContentType.movie ? entry.title.year : null;
                  verifierEtTelecharger(
                    url: entry.url,
                    nom: buildDownloadName(entry),
                    releaseYear: releaseYear,
                    context: context,
                  );
                },
              ),
            // ── Toggle favori ─────────────────────────────────────────────
            ValueListenableBuilder<int>(
              valueListenable: FavoritesService.version,
              builder: (ctx, _, __) {
                final isFav = FavoritesService.isEntryFavorite(entry);
                return ListTile(
                  // §themePlus — couleur favori unifiée (kFavorite partout).
                  leading: Icon(
                    isFav ? Icons.favorite : Icons.favorite_border,
                    color: isFav ? kFavorite : null,
                  ),
                  title: Text(
                    isFav
                        ? sheetCtx.l10n.favoriteRemove
                        : sheetCtx.l10n.favoriteAdd,
                    style: TextStyle(color: isFav ? kFavorite : null),
                  ),
                  onTap: () async {
                    await FavoritesService.toggleEntry(entry);
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  },
                );
              },
            ),
            // §tvOptionsBack — le menu d'appui long est le raccourci PRINCIPAL
            // de l'app : sans ligne neutre, en sortir demandait la touche
            // Retour, qui est justement le geste en défaut sur TV.
            const SheetCloseTile(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// §forgetResume — Efface la reprise sans lancer la lecture. Clear sur toutes
  /// les variantes du groupe (FHD + HD…) pour que le titre disparaisse vraiment
  /// de la pile « Reprendre ».
  ///
  /// R38 — Extraite parce qu'une SÉRIE en a besoin elle aussi : depuis
  /// §heroSeriesResume, le stub porte une clé de reprise légitime, et cette
  /// tuile est le seul endroit de l'accueil d'où l'on peut la retirer. Sur une
  /// série, les URLs effacées sont donc les stubs du groupe ; la position de
  /// l'ÉPISODE reste, la fiche sait toujours où reprendre.
  ///
  /// 🔴 **[isSeries] change la QUESTION posée, parce que l'ancienne mentait.**
  /// « La position de lecture de ce titre sera oubliée » est vrai d'un film et
  /// faux d'une série : c'est justement la position de l'épisode qui survit, et
  /// la fiche l'affiche encore juste après. Qui voulait faire disparaître un
  /// titre d'un téléviseur partagé croyait avoir effacé, alors qu'il n'avait
  /// que caché. La question de la série dit donc le RÉSULTAT (§clientText) :
  /// elle sort de « Reprendre », l'épisode garde sa position.
  ///
  /// ⚠️ **Portée volontairement plus large que celle de la fiche, et inverse.**
  /// `seriesKeyToForget` (`details_page.dart:110-114`) REFUSE d'effacer la clé
  /// de série tant qu'un épisode est en cours ; ici on l'efface toujours. Deux
  /// gestes du même nom qui font le contraire — c'est voulu, les portées
  /// diffèrent (« retire-la de mon accueil » contre « oublie CET épisode »), et
  /// l'accueil ne peut de toute façon pas faire mieux : pour un compte Xtream
  /// pur, le groupe ne contient que des stubs, aucune URL n'y permet de
  /// dériver les clés d'épisode. ⛔ Ne pas « corriger » l'un vers l'autre en
  /// croyant lire un oubli.
  /// ⛔ R46 — Plus d'`entry` ici : l'ancienne version s'en servait pour
  /// `clearedUrl`, la SEULE URL que l'annulation restaurait — c'est-à-dire la
  /// cause même de la perte de données. Le laisser inviterait à s'en resservir.
  /// La capture porte désormais sur `widget.versions` en entier.
  Widget _forgetResumeTile(BuildContext sheetCtx, WatchProgress progress,
      {required bool isSeries}) {
    return ListTile(
      leading: Icon(Icons.history_toggle_off, color: kWarning),
      title: Text(
        sheetCtx.l10n.cardForgetResume,
        style: TextStyle(fontSize: 13, color: kWarning),
      ),
      dense: true,
      // §undoTv — On demande AVANT de fermer la feuille : sur TV
      // `confirmOrUndo` ouvre un dialogue, qui exige un contexte encore monté.
      // Le `pop` passe après, et seulement si l'oubli a bien eu lieu.
      onTap: () async {
        // 🔴 R46 — Capturé AVANT l'effacement, et pour TOUTES les versions.
        // L'action efface la reprise de chaque version du groupe ; l'annulation
        // n'en rendait qu'une, et les autres étaient perdues pour de bon
        // (mesuré sur appareil le 2026-09-13, deux comptes, une seule rendue).
        final List<WatchProgress> avant = WatchProgressService.snapshotFor(
          <String>[for (final v in widget.versions) v.url],
        );
        final done = await confirmOrUndo(
          sheetCtx,
          title: sheetCtx.l10n.cardForgetResumeTitle,
          question: isSeries
              ? sheetCtx.l10n.cardForgetResumeSeriesQuestion
              : sheetCtx.l10n.cardForgetResumeQuestion,
          confirmLabel: sheetCtx.l10n.cardForgetConfirm,
          // 🔴 R46 — Au doigt, `confirmOrUndo` n'affiche QUE ce message : la
          // question ci-dessus ne se voit QUE sur téléviseur. Sans un message
          // qui dise lui aussi le résultat, la personne lisait « Reprise
          // oubliée » alors que l'épisode garde sa position (§clientText).
          doneMessage: isSeries
              ? sheetCtx.l10n.cardResumeForgottenSeries
              : sheetCtx.l10n.cardResumeForgotten,
          action: () async {
            for (final v in widget.versions) {
              await WatchProgressService.clearProgress(v.url);
            }
          },
          // Repli sur la progression affichée si le cache n'a rien rendu : une
          // annulation ne doit jamais être un no-op silencieux.
          onUndo: () => WatchProgressService.restoreAll(
            avant.isEmpty ? <WatchProgress>[progress] : avant,
          ),
        );
        if (done && sheetCtx.mounted) Navigator.pop(sheetCtx);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    buildCount++;
    final cs = Theme.of(context).colorScheme;
    final entry = widget.versions.first;
    // §23 — politique image « plus grosse liste ».
    // §Ultimate — fallback affiche TMDB quand le M3U ne fournit aucun tvg-logo.
    // §logoFallback — Toutes les adresses du groupe, puis l'affiche TMDB une
    // fois résolue. `AetherImage` descend la liste à chaque échec.
    // §posterLang — L'ordre des candidats EST la politique d'affiche.
    // Par défaut le fournisseur passe devant (§23, « plus grosse liste ») et
    // TMDB ne sert qu'en repli ; l'option inverse les deux pour qui préfère des
    // affiches homogènes, dans la langue choisie.
    // §posterScope — Portée décidée par le parent (carrousel + Favoris).
    final bool tmdbFirst = widget.tmdbFirst;
    final logoCandidates = <String>[
      if (tmdbFirst && _tmdbPoster != null) _tmdbPoster!,
      ..._logoCandidates,
      if (!tmdbFirst && _tmdbPoster != null) _tmdbPoster!,
    ];
    final logoUrl = logoCandidates.isEmpty ? null : logoCandidates.first;

    final isTv = widget.type == M3uContentType.tv;
    final cardWidth = widget.width ?? (isTv ? 120.0 : 130.0);
    final imageAspectRatio = isTv ? 1.0 : 2 / 3;

    final fallbackIcon = switch (widget.type) {
      M3uContentType.movie  => Icons.movie_outlined,
      M3uContentType.series => Icons.tv_outlined,
      M3uContentType.tv     => Icons.live_tv_outlined,
    };

    // §3c-3 — Wrap focus TV (decorateOnly = la card garde son GestureDetector
    // et son anim _pressed). Sur TV, la bordure glow + scale 1.05 sont gérés
    // par FocusableCard ; sur mobile, FocusableCard est neutre.
    // §rowAnchor — dans un carrousel horizontal, la carte focusée se cale à
    // GAUCHE du viewport (la suite de la rangée défile devant, façon Netflix)
    // au lieu de rester collée au bord droit. Sans effet dans les grilles
    // (pas de scrollable horizontal ancêtre).
    return FocusableCard(
      decorateOnly: true,
      entry: widget.isEntry,
      anchorRowStart: true,
      onTap: _onTap,
      onLongPress: _onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _onTap,
        onLongPress: _onLongPress,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: SizedBox(
            width: cardWidth,
            child: AspectRatio(
              aspectRatio: imageAspectRatio,
              child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: cs.surfaceContainerHighest,
                border: Border.all(
                  color: kAccentPrimary.withAlpha(40),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: kImageScrim.withAlpha(80),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Image — §imgDiskCache : cache DISQUE (les vignettes se
                    // re-téléchargeaient à chaque affichage, le cache mémoire
                    // étant évincé sous pression sur box faible).
                    // §imgPerf — cap de décodage conservé à 360 px (carte
                    // poster ~120-200 px).
                    AetherImage(
                      url: logoUrl,
                      alternates: logoCandidates.skip(1).toList(),
                      // §logoFallback — Toutes les adresses du fournisseur ont
                      // échoué : c'est le moment de demander l'affiche à TMDB
                      // (et, au passage, la catégorie — cf. §inferredCat).
                      onAllFailed: _resolveTmdbPosterIfNeeded,
                      fit: isTv ? BoxFit.contain : BoxFit.cover,
                      // §imgThrash — était 360 en dur, pour une vignette qui
                      // mesure ~120-145 px logiques : ~3× de RAM gaspillée par
                      // image, d'où la saturation du cache et le re-décodage
                      // permanent sur TV.
                      cacheWidth: decodeWidthFor(context, cardWidth),
                      fallback: (_) => _fallback(fallbackIcon, cs),
                      showFallbackWhileLoading: true,
                    ),
                    // Gradient bottom overlay pour la lisibilité du titre
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.55, 1.0],
                            colors: [
                              Colors.transparent,
                              kImageScrim.withAlpha(220),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Titre en surimpression bas (+ année pour films/séries →
                    // distingue les homonymes/remakes séparés par §homonymYear).
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: kOnImage,
                              height: 1.2,
                              shadows: [
                                Shadow(color: kImageScrim, blurRadius: 4),
                              ],
                            ),
                          ),
                          if (widget.type != M3uContentType.tv &&
                              entry.title.year != null)
                            Text(
                              entry.title.year!,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: kOnImage.withAlpha(190),
                                height: 1.3,
                                shadows: const [
                                  Shadow(color: kImageScrim, blurRadius: 4),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    // §qualityTruth — Pastille « qualité réellement servie »,
                    // en haut à droite. Muette tant que le contenu n'a jamais
                    // été lu. Vaut aussi pour les chaînes TV : une chaîne
                    // annoncée FHD qui sert du 720p se voit ici.
                    Positioned(
                      top: 6,
                      right: 6,
                      child: MeasuredQualityBadge(versions: widget.versions),
                    ),
                    // §menuHint — Le menu d'appui long est le raccourci
                    // principal de l'app : Lire, Reprendre, Oublier la
                    // reprise, Télécharger et Favoris n'existent QUE là. Rien
                    // ne l'annonçait — ni « ⋯ », ni coin corné, ni un mot dans
                    // l'accueil guidé (§audit0903 n° 17).
                    //
                    // ⚠️ **Non focusable, volontairement** : un focusable
                    // imbriqué dans une `FocusableCard` n'est candidat dans
                    // AUCUNE direction depuis dpad 3.0 (§dpadChildFocus) — il
                    // serait donc décoratif à la télécommande. D'où l'affichage
                    // au tactile seul, là où il est réellement utilisable ; sur
                    // téléviseur, l'appui long sur OK reste la voie d'accès.
                    if (!PlatformTv.isTv)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _onLongPress,
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: kImageScrim70,
                                  shape: BoxShape.circle,
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.more_horiz,
                                      size: 16, color: kOnImage),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // §1e — Barre de progression "reprendre depuis…" :
                    // visible si l'utilisateur a regardé l'une des variantes du
                    // groupe sans aller jusqu'au bout (TV exclu — pas de durée).
                    if (!isTv)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ValueListenableBuilder<int>(
                          valueListenable: WatchProgressService.version,
                          builder: (_, __, ___) {
                            final p = WatchProgressService.getProgressForAny(
                              widget.versions.map((e) => e.url),
                            );
                            if (p == null || p.ratio <= 0) {
                              return const SizedBox.shrink();
                            }
                            return LinearProgressIndicator(
                              value: p.ratio,
                              minHeight: 3,
                              backgroundColor: kOnImageSubtle, // = white24
                              valueColor: AlwaysStoppedAnimation(kAccentSecondary),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _fallback(IconData icon, ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(icon, size: 36, color: cs.onSurfaceVariant.withAlpha(120)),
    );
  }
}

