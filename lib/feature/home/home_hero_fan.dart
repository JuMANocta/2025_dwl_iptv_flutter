part of 'home_page.dart';

// ─── Hero "fan" — empilement carte de jeu (§heroFan) ─────────────────────────
//
// Affiche jusqu'à 10 cartes empilées en éventail. Auto-rotation 6s qui fait
// défiler les cartes (chaque tick = la carte suivante devient active). Les
// premières cartes sont en cours de lecture (`WatchProgressService`, triées
// par `lastWatched` desc), suivies par les nouveautés prioritaires. Tap sur
// la carte centrale → ouverture du media ; tap sur une carte secondaire →
// elle vient prendre la position centrale.

class _HeroFanBanner extends StatefulWidget {
  final List<List<M3uEntry>> featured;
  final M3uContentType type;

  const _HeroFanBanner({required this.featured, required this.type});

  @override
  State<_HeroFanBanner> createState() => _HeroFanBannerState();
}

class _HeroFanBannerState extends State<_HeroFanBanner>
    with SingleTickerProviderStateMixin, RouteAware {
  static const _autoDuration = Duration(seconds: 6);
  static const _animDuration = Duration(milliseconds: 520);

  late final AnimationController _animCtrl;
  Timer? _timer;

  /// §3c Phase 2 — Sur TV, quand le hero est focusé au D-pad, on met l'auto-
  /// rotation en pause : sinon la rotation 6 s ferait basculer la carte active
  /// sous le focus (perte/saut de focus). Reprend dès qu'on quitte le hero.
  bool _focusPaused = false;

  /// §perfBg — Mis à `true` quand une route est poussée par-dessus la home
  /// (ex. player). Le `Timer` continuait à tourner en arrière-plan → repaints
  /// invisibles = saccades sur TV.
  bool _bgPaused = false;

  /// Position lissée (peut être fractionnaire). On ne wrap PAS sur [0, N) :
  /// la valeur incrémente continument et chaque carte calcule son `delta`
  /// modulo N avec le plus court chemin → wrap visuel naturel.
  double _from = 0;
  double _to = 0;
  double _current = 0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: _animDuration)
      ..addListener(_onTick);
    // §perfSettings — le toggle « Rotation automatique » (Paramètres →
    // Optimisation) rallume/coupe le timer en live.
    PerformanceSettingsService.config.addListener(_onPerfChanged);
    _scheduleNext();
  }

  void _onPerfChanged() {
    if (!mounted) return;
    _scheduleNext(); // re-court-circuite (ou relance) selon heroAutoRotate
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    PerformanceSettingsService.config.removeListener(_onPerfChanged);
    _timer?.cancel();
    _animCtrl
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  @override
  void didPushNext() {
    _bgPaused = true;
    _timer?.cancel();
    // §perfBgFull — Une animation lancée par `_advance()` continue de ticer
    // jusqu'à sa fin (520 ms) même après cancel du timer → `_onTick`
    // setState invisible derrière le player → contention CPU. Stop net.
    if (_animCtrl.isAnimating) _animCtrl.stop();
  }

  @override
  void didPopNext() {
    _bgPaused = false;
    _scheduleNext();
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {
      final t = Curves.easeOutCubic.transform(_animCtrl.value);
      _current = _from + (_to - _from) * t;
    });
  }

  void _scheduleNext() {
    _timer?.cancel();
    // §perfSettings — 3e gate (avec _focusPaused/_bgPaused) : rotation coupée
    // par l'utilisateur → le swipe/tap manuel reste actif (les handlers
    // rappellent _scheduleNext, re-court-circuité ici à chaque fois).
    if (widget.featured.length <= 1 ||
        _focusPaused ||
        _bgPaused ||
        !PerformanceSettingsService.config.value.heroAutoRotate) {
      return;
    }
    _timer = Timer.periodic(_autoDuration, (_) {
      if (!mounted) return;
      _advance();
    });
  }

  /// Met en pause / reprend l'auto-rotation selon l'état de focus (TV).
  void _setFocusPaused(bool paused) {
    if (_focusPaused == paused) return;
    _focusPaused = paused;
    if (paused) {
      _timer?.cancel();
    } else {
      _scheduleNext();
    }
  }

  void _advance() {
    _from = _current;
    _to = _from + 1;
    _animCtrl.forward(from: 0);
  }

  /// Anime jusqu'à la carte `targetIdx` en empruntant le plus court chemin
  /// circulaire (gauche ou droite).
  void _gotoCard(int targetIdx) {
    final n = widget.featured.length.toDouble();
    final currentMod = _current % n;
    double delta = targetIdx - currentMod;
    delta = delta % n;
    if (delta > n / 2) delta -= n;
    _from = _current;
    _to = _current + delta;
    _animCtrl.forward(from: 0);
    _scheduleNext();
  }

  double _shortestDelta(int i) {
    final n = widget.featured.length.toDouble();
    double delta = i - _current;
    delta = delta % n;
    if (delta > n / 2) delta -= n;
    return delta;
  }

  Future<void> _openItem(BuildContext context, List<M3uEntry> versions) async {
    if (versions.isEmpty) return;
    final entry = versions.first;
    // §heroUnify — Le fan sert aussi aux Chaînes : une chaîne ouvre l'action
    // sheet TV (qualités + EPG), pas DetailsPage.
    if (widget.type == M3uContentType.tv) {
      await showTvActionSheet(context, versions);
      return;
    }
    final hasTmdb = await TmdbApiService.hasApiKey();
    if (!context.mounted) return;
    // §bugfix — Les séries vont toujours sur DetailsPage (picker saison/épisode
    // construit depuis la playlist), même sans clé TMDB : sinon l'action sheet
    // ne lit que le 1er épisode et l'utilisateur ne peut pas choisir.
    if (hasTmdb || entry.type == M3uContentType.series) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DetailsPage(entry: entry, versions: versions),
      ));
    } else {
      await showMediaActionSheet(context, entry);
    }
  }

  void _onCardTap(BuildContext context, int i) {
    final n = widget.featured.length;
    final currentIdx = ((_current.round() % n) + n) % n;
    if (i == currentIdx) {
      _openItem(context, widget.featured[i]);
    } else {
      _gotoCard(i);
    }
  }

  // ── Swipe manuel (§heroFan ergo) ───────────────────────────────────────────
  // Le `GestureDetector` au niveau du Stack capture les drags horizontaux
  // AVANT que la PageView parent (Séries/Films/Chaînes) puisse les revendiquer.
  // → swipe sur le hero = navigation entre cartes uniquement, jamais switch
  // de type. Le tap reste géré par l'InkWell de la carte (gestures distincts).

  void _onDragStart(DragStartDetails details) {
    _timer?.cancel();
    if (_animCtrl.isAnimating) _animCtrl.stop();
  }

  void _onDragUpdate(DragUpdateDetails details, double cardSpacing) {
    if (cardSpacing <= 0) return;
    setState(() {
      _current -= details.delta.dx / cardSpacing;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (widget.featured.length <= 1) {
      _scheduleNext();
      return;
    }
    final v = details.primaryVelocity ?? 0;
    // Vélocité forte → bias dans la direction du swipe ; faible → snap nearest.
    int target;
    if (v.abs() > 300) {
      target = (v < 0) ? _current.floor() + 1 : _current.ceil() - 1;
    } else {
      target = _current.round();
    }
    _from = _current;
    _to = target.toDouble();
    _animCtrl.forward(from: 0);
    _scheduleNext();
  }

  void _onDragCancel() {
    // Annulation (ex: bascule app) → snap nearest pour rester aligné.
    _from = _current;
    _to = _current.round().toDouble();
    _animCtrl.forward(from: 0);
    _scheduleNext();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.featured.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final screenW = constraints.maxWidth;
        final screenH = MediaQuery.sizeOf(context).height;
        final isTv = PlatformTv.isTv;
        // §responsiveHero — La carte active vise ~58 % (TV) / ~42 % (mobile) de la
        // hauteur d'écran (proportionnel → scale tout seul, pas de pixels fixes).
        // Le conteneur n'ajoute qu'une marge BASSE fixe (inclinaison des cartes
        // ~42 px + dots) ; combiné au Stack aligné en haut, le carrousel remonte
        // au plus près du status bar (zéro vide en haut, §heroLift).
        final maxCardH = isTv ? screenH * 0.58 : screenH * 0.42;
        final cardWByH = maxCardH / 1.45;
        // Sécurité largeur (écrans larges / ultra-wide) : la carte ne dépasse
        // pas 40 % (TV) / 55 % (mobile) de la largeur dispo.
        final cardW = math.min(cardWByH, screenW * (isTv ? 0.40 : 0.55));
        final cardH = cardW * 1.45;
        final containerH = cardH + 52;
        // 1 carte d'écart visuel = ~22 % de la largeur d'une carte.
        // Sensibilité du drag : 1 unité de `_current` = `cardSpacing` pixels.
        final cardSpacing = cardW * 0.22;

        // Pour le z-order : on trie par |delta| desc → grandes valeurs au début
        // de la liste = dessinées en premier = derrière.
        final cards = <({int i, double delta})>[];
        for (var i = 0; i < widget.featured.length; i++) {
          final d = _shortestDelta(i);
          if (d.abs() <= 3) cards.add((i: i, delta: d));
        }
        cards.sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));

        final Widget fan = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: (d) => _onDragUpdate(d, cardSpacing),
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: _onDragCancel,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 14),
            child: SizedBox(
              height: containerH,
              // §heroLift — Cartes alignées EN HAUT (au lieu de centrées) : la
              // carte active touche le haut du conteneur, la marge basse (52 px)
              // accueille l'inclinaison des cartes + les dots. Supprime le ~11 %
              // de vide qui existait au-dessus du carrousel.
              child: Stack(
                alignment: Alignment.topCenter,
                clipBehavior: Clip.none,
                children: [
                  for (final c in cards)
                    _buildFannedCard(context, c.i, c.delta, cardW, cardH),
                  Positioned(bottom: 4, child: _buildDots()),
                ],
              ),
            ),
          ),
        );

        // §3c Phase 2 — Sur TV, le hero "fan" devient une cible de focus UNIQUE
        // et stable (les InkWell internes sont exclus du focus dans
        // `_buildFannedCard`). OK ouvre la carte active ; le focus met l'auto-
        // rotation en pause pour ne pas faire glisser la carte sous le D-pad.
        if (!PlatformTv.isTv) return fan;
        final n = widget.featured.length;
        final activeIndex = n == 0 ? 0 : ((_current.round() % n) + n) % n;
        return FocusableChip(
          onTap: () => _onCardTap(context, activeIndex),
          onFocusChange: _setFocusPaused,
          // §heroFanDpad — ←/→ télécommande font tourner le fan (avant : le hero
          // ne réagissait qu'au tap OK et on ne pouvait pas changer de carte).
          onArrowLeft: n <= 1 ? null : () => _gotoCard((activeIndex - 1 + n) % n),
          onArrowRight: n <= 1 ? null : () => _gotoCard((activeIndex + 1) % n),
          borderRadius: BorderRadius.circular(16),
          child: fan,
        );
      },
    );
  }

  Widget _buildFannedCard(
    BuildContext context,
    int i,
    double delta,
    double w,
    double h,
  ) {
    final absDelta = delta.abs();
    final isActive = absDelta < 0.5;

    final rotation = delta * 0.08; // ~4.5° par rang
    final offsetX = delta * (w * 0.22);
    final offsetY = math.min(absDelta * 14.0, 42.0);
    final scale = math.max(0.55, 1.0 - absDelta * 0.07);
    final opacity = math.max(0.0, 1.0 - absDelta * 0.32).clamp(0.0, 1.0);

    return Transform(
      transform: Matrix4.identity()
        ..translateByDouble(offsetX, offsetY, 0, 1)
        ..rotateZ(rotation)
        ..scaleByDouble(scale, scale, 1, 1),
      alignment: Alignment.bottomCenter,
      child: Opacity(
        opacity: opacity,
        // §heroSwipePerf — RepaintBoundary : chaque carte est mise en cache en
        // texture. Le Transform (translate/rotate/scale) + l'Opacity
        // s'appliquent alors sur la texture (GPU) au lieu de re-peindre image +
        // ombres floutées à chaque frame du glissement.
        child: RepaintBoundary(
          child: SizedBox(
            width: w,
            height: h,
            // §3c Phase 2 — Sur TV, les InkWell des cartes empilées sont exclus
            // du focus : seule la cible unique (FocusableChip du build) est
            // focusable.
            child: ExcludeFocus(
              excluding: PlatformTv.isTv,
              child: _HeroFanCard(
                versions: widget.featured[i],
                type: widget.type,
                isActive: isActive,
                onTap: () => _onCardTap(context, i),
                width: w,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDots() {
    final n = widget.featured.length;
    final currentIdx = ((_current.round() % n) + n) % n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(n, (i) {
        final active = i == currentIdx;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? kAccentPrimary : Colors.white.withAlpha(120),
            borderRadius: BorderRadius.circular(3),
            boxShadow: active
                ? [BoxShadow(color: kAccentPrimary.withAlpha(180), blurRadius: 6)]
                : null,
          ),
        );
      }),
    );
  }
}

class _HeroFanCard extends StatelessWidget {
  final List<M3uEntry> versions;
  final M3uContentType type;
  final bool isActive;
  final VoidCallback onTap;

  /// §imgThrash — Largeur de rendu, pour caler le décodage de l'affiche dessus
  /// (elle était figée à 320 px quelle que soit la taille réelle de la carte).
  final double width;

  const _HeroFanCard({
    required this.versions,
    required this.type,
    required this.isActive,
    required this.onTap,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final entry = versions.first;
    final progress = WatchProgressService.getProgressForAny(
      versions.map((e) => e.url),
    );
    final hasResume = progress != null && progress.ratio < 0.95;
    // §23 — politique image « plus grosse liste ».
    final logoUrl = ParsedPlaylistService.bestLogoUrl(versions);

    final fallbackIcon = switch (type) {
      M3uContentType.movie => Icons.movie_outlined,
      M3uContentType.series => Icons.tv_outlined,
      M3uContentType.tv => Icons.live_tv_outlined,
    };

    // §heroFan 3D — fond blanc visible comme tranche de carte (padding 3 px)
    // + box-shadow stack pour simuler l'épaisseur "papier empilé" sur la carte
    // active (les voisines gardent une ombre douce simple pour ne pas saturer).
    final shadows = isActive
        ? const <BoxShadow>[
            // Tranche : 5 ombres "dures" (blurRadius=0) qui s'enchaînent en
            // diagonale → tranche d'une carte épaisse vue de 3/4.
            BoxShadow(color: Color(0xFFEDEDED), offset: Offset(1, 1.5), blurRadius: 0),
            BoxShadow(color: Color(0xFFD2D2D2), offset: Offset(2, 3), blurRadius: 0),
            BoxShadow(color: Color(0xFFA8A8A8), offset: Offset(3, 4.5), blurRadius: 0),
            BoxShadow(color: Color(0xFF7E7E7E), offset: Offset(4, 6), blurRadius: 0),
            BoxShadow(color: Color(0xFF4A4A4A), offset: Offset(5, 7.5), blurRadius: 0),
            // Ombre portée principale (douce, sous le stack).
            BoxShadow(
              color: Color(0xCC000000),
              offset: Offset(8, 14),
              blurRadius: 24,
            ),
          ]
        : <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(140),
              offset: const Offset(4, 6),
              blurRadius: 12,
            ),
          ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white, // → visible en tranche grâce au padding 3 px.
        borderRadius: BorderRadius.circular(14),
        boxShadow: shadows,
      ),
      padding: const EdgeInsets.all(3),
      child: ClipRRect(
        // Rayon intérieur (= 14 - 3) pour des coins concentriques propres.
        borderRadius: BorderRadius.circular(11),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
            if (logoUrl != null && logoUrl.isNotEmpty)
              // §heroUnify — Chaînes : logo (souvent carré/transparent) en
              // `contain` sur fond sombre → rendu "tuile chaîne" propre, pas de
              // crop/étirement. Films/séries : poster en `cover` (inchangé).
              // §imgDiskCache — cache disque partagé.
              // §imgThrash — décodage calé sur la largeur RÉELLE de la carte
              // (était figé à 320 px). Plafond plus haut que les vignettes : le
              // hero est la plus grande image de l'accueil.
              type == M3uContentType.tv
                  ? Container(
                      color: const Color(0xFF15171C),
                      padding: const EdgeInsets.all(16),
                      alignment: Alignment.center,
                      child: AetherImage(
                        url: logoUrl,
                        fit: BoxFit.contain,
                        cacheWidth: decodeWidthFor(context, width, max: 640),
                        fallback: (_) => _fallback(fallbackIcon),
                      ),
                    )
                  : AetherImage(
                      url: logoUrl,
                      fit: BoxFit.cover,
                      cacheWidth: decodeWidthFor(context, width, max: 640),
                      fallback: (_) => _fallback(fallbackIcon),
                    )
            else
              _fallback(fallbackIcon),
            // Gradient sombre en bas pour la lisibilité du titre.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withAlpha(210),
                  ],
                ),
              ),
            ),
            if (hasResume)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: kAccentSecondary.withAlpha(230),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: kAccentSecondary.withAlpha(120),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.play_arrow, size: 14, color: Colors.black),
                      SizedBox(width: 2),
                      Text(
                        'REPRENDRE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: hasResume ? 12 : 10,
              child: Text(
                entry.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  shadows: [
                    Shadow(
                        blurRadius: 4,
                        color: Colors.black.withAlpha(220)),
                  ],
                ),
              ),
            ),
            if (hasResume)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress.ratio,
                  backgroundColor: Colors.black.withAlpha(130),
                  valueColor: AlwaysStoppedAnimation(kAccentSecondary),
                  minHeight: 4,
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallback(IconData icon) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kAccentPrimary.withAlpha(35),
            kAccentSecondary.withAlpha(35),
          ],
        ),
      ),
      child: Center(
        child: Icon(icon, size: 70, color: Colors.white.withAlpha(80)),
      ),
    );
  }
}

