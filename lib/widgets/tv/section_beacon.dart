import 'package:flutter/material.dart';

import '../../core/themes/colors.dart';
import '../../core/utils/platform_tv.dart';

/// §navBlind — « On ne sait plus OÙ on est dans les pages longues. »
///
/// **Le principe tranché** (2026-09-04) : *un seul repère, au même endroit sur
/// toutes les pages longues, qui nomme la section qu'on regarde.* Pas une
/// solution par page — l'entrée de roadmap avertissait qu'en corrigeant page
/// par page on produirait quatre réponses différentes.
///
/// **Pourquoi le défilement et pas le focus** : sur téléviseur les deux
/// coïncident (l'auto-scroll D-pad gare l'élément focalisé dans le viewport),
/// mais le défilement se lit sur une structure PLATE — un `Column` de sections
/// séparées par des libellés, ce que sont réellement ces pages. Se brancher sur
/// le focus aurait obligé à ré-emboîter chaque page dans des sections, pour le
/// même résultat.
///
/// **Pourquoi seulement sur TV** : le défaut est celui d'un utilisateur assis à
/// trois mètres qui pilote à l'aveugle. Au doigt, on voit le pouce et la page
/// ne bouge que quand on la pousse. Le bandeau ne s'affiche donc que si
/// [PlatformTv.isTv] — ou si [forceVisible] le demande (tests).
///
/// **Usage** :
/// ```dart
/// SectionBeacon(
///   pageTitle: 'Optimisation',
///   child: SingleChildScrollView(child: Column(children: [
///     SectionMark('Profils'), ...,
///     SectionMark('Mémoire & usage'), ...,
///   ])),
/// )
/// ```
/// [SectionMark] remplace le libellé de section : il l'affiche ET s'inscrit.
class SectionBeacon extends StatefulWidget {
  const SectionBeacon({
    super.key,
    required this.child,
    this.pageTitle,
    this.forceVisible,
    this.floating = false,
    this.floatingTop = 8,
    this.thresholdFraction = 0,
  });

  /// Le corps défilant de la page, inchangé.
  final Widget child;

  /// Nom de la page, affiché avant la section (« Optimisation · Mémoire »).
  /// `null` = seule la section est nommée.
  final String? pageTitle;

  /// Force l'affichage (tests). `null` = décidé par [PlatformTv.isTv].
  final bool? forceVisible;

  /// Mode **flottant** : une pastille superposée, qui n'apparaît qu'une fois
  /// entré dans une section, au lieu d'un bandeau qui pousse le contenu.
  ///
  /// ⚠️ Indispensable sur l'accueil : son en-tête est un hero plein cadre sous
  /// la barre d'état. Un bandeau y volerait 26 px en permanence et casserait
  /// le seul écran vraiment immersif de l'app.
  final bool floating;

  /// Décalage vertical de la pastille flottante (sous la barre d'état).
  final double floatingTop;

  /// Où lire la « section courante », en fraction de la hauteur du viewport.
  ///
  /// `0` = juste sous le repère (bon pour une page de réglages, dont les
  /// lignes sont courtes : ce qui vient de passer en haut est bien ce qu'on
  /// regarde).
  ///
  /// ⚠️ Sur l'accueil il FAUT descendre cette ligne. Vérifié à l'AVD TV : avec
  /// `0`, la pastille affichait « FILMS · COUP DE CŒUR » alors que la carte
  /// focalisée était dans « Sélection » — un carrousel fait 400 px de haut,
  /// donc l'en-tête resté au-dessus du bord n'est pas celui de la rangée qu'on
  /// pilote. Le repère aurait alors reproduit le défaut qu'il corrige.
  final double thresholdFraction;

  @override
  State<SectionBeacon> createState() => _SectionBeaconState();
}

class _SectionBeaconState extends State<SectionBeacon> {
  final SectionBeaconController _controller = SectionBeaconController();

  @override
  void initState() {
    super.initState();
    // §navBlind — ⚠️ Corrigé APRÈS mesure à l'AVD : se fier au seul
    // défilement fait MENTIR le repère. Deux contre-exemples relevés à
    // l'écran, le même jour :
    //   • accueil — pastille « COUP DE CŒUR » alors que la carte focalisée
    //     était dans « Sélection » (une rangée fait ~400 px) ;
    //   • Optimisation — « RANGÉES DE CATÉGORIES » alors que le focus était
    //     sur « Listes », deux sections plus bas.
    // La cause est la même : l'auto-scroll D-pad gare l'élément focalisé où il
    // tient, souvent près du BAS du viewport — la position de défilement n'est
    // donc pas un substitut de la position du focus. On écoute donc le focus,
    // et le défilement ne sert plus que de repli (tactile, où rien n'a le
    // focus par construction — §touchNoFocus).
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    _controller.dispose();
    super.dispose();
  }

  bool get _visible => widget.forceVisible ?? PlatformTv.isTv;

  void _onFocusChanged() {
    if (!_visible || !mounted) return;
    final double? y = _focusedTopY();
    if (y == null) return;
    _controller.recomputeFromScreen(y);
  }

  /// Position verticale, à l'écran, de ce qui a le focus — ou `null` si rien
  /// n'est focalisé, si le nœud n'est pas monté, ou s'il est hors de CE
  /// beacon (une autre page, un dialogue).
  double? _focusedTopY() {
    final FocusNode? node = FocusManager.instance.primaryFocus;
    // ⚠️ `primaryFocus` n'est presque jamais nul : quand rien de réel n'est
    // focalisé, c'est la PORTÉE racine qui l'est, et son rectangle est la page
    // entière — donc `dy == 0`. S'y fier ramenait le repère à la toute
    // première section à chaque fois (constaté en test).
    if (node == null || node is FocusScopeNode) return null;
    final BuildContext? fc = node.context;
    if (fc == null) return null;
    final RenderObject? fo = fc.findRenderObject();
    if (fo is! RenderBox || !fo.hasSize) return null;
    final RenderObject? self = context.findRenderObject();
    if (self is! RenderBox || !self.hasSize) return null;
    // Même garde côté taille : un nœud aussi haut que la page est un ancêtre,
    // pas un élément de la liste.
    if (fo.size.height >= self.size.height) return null;
    final double top = self.localToGlobal(Offset.zero).dy;
    final double y = fo.localToGlobal(Offset.zero).dy;
    // Hors de notre fenêtre : on ne dit rien plutôt que de dire faux.
    if (y < top - 1 || y > top + self.size.height + 1) return null;
    return y;
  }

  @override
  Widget build(BuildContext context) {
    final Widget scrollable = SectionBeaconScope(
      controller: _controller,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          // ⚠️ On ne recalcule QUE si le bandeau est affiché : sur téléphone,
          // ce listener ne doit rien coûter.
          if (_visible && n.metrics.axis == Axis.vertical) {
            // Le focus prime ; le défilement n'est qu'un repli.
            _controller
                .recomputeFromScreen(_focusedTopY() ?? _thresholdY(context));
          }
          return false; // laisse remonter : d'autres écoutent (§rowAnchor).
        },
        child: widget.child,
      ),
    );

    if (!_visible) return scrollable;

    if (widget.floating) {
      return Stack(
        children: [
          Positioned.fill(child: scrollable),
          Positioned(
            top: widget.floatingTop,
            left: 12,
            child: IgnorePointer(
              child: _SectionPill(
                controller: _controller,
                pageTitle: widget.pageTitle,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _SectionBar(controller: _controller, pageTitle: widget.pageTitle),
        Expanded(child: scrollable),
      ],
    );
  }

  /// Ligne de référence : le haut du contenu défilant, en coordonnées écran.
  /// La section « courante » est la dernière dont le libellé est passé
  /// au-dessus de cette ligne.
  double _thresholdY(BuildContext context) {
    final RenderObject? box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      final double base = box.localToGlobal(Offset.zero).dy +
          (widget.floating
              ? widget.floatingTop + _SectionPill.height
              : _SectionBar.height);
      return base + box.size.height * widget.thresholdFraction;
    }
    return 0;
  }
}

/// Le bandeau lui-même. Volontairement discret : une ligne, la couleur
/// d'accent, aucune interaction — ce n'est pas un bouton, c'est un repère.
class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.controller, this.pageTitle});

  final SectionBeaconController controller;
  final String? pageTitle;

  static const double height = 26;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final String? section = controller.current;
        final String text = [
          if (pageTitle != null) pageTitle!,
          if (section != null) section,
        ].join('  ·  ');
        return Container(
          height: height,
          width: double.infinity,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              bottom: BorderSide(color: kAccentPrimary.withAlpha(70)),
            ),
          ),
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: section == null ? cs.onSurfaceVariant : kAccentPrimary,
            ),
          ),
        );
      },
    );
  }
}

/// Pastille flottante — même information que [_SectionBar], mais superposée et
/// invisible tant qu'aucune section n'est atteinte (donc absente en tête de
/// page, là où le hero doit rester seul).
class _SectionPill extends StatelessWidget {
  const _SectionPill({required this.controller, this.pageTitle});

  final SectionBeaconController controller;
  final String? pageTitle;

  static const double height = 24;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final String? section = controller.current;
        final String text = [
          if (pageTitle != null) pageTitle!,
          if (section != null) section,
        ].join('  ·  ');
        return AnimatedOpacity(
          opacity: section == null ? 0 : 1,
          duration: const Duration(milliseconds: 180),
          child: Container(
            height: height,
            constraints: const BoxConstraints(maxWidth: 320),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xCC000000),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kAccentPrimary.withAlpha(110)),
            ),
            child: Text(
              text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: kAccentPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Porte le [SectionBeaconController] jusqu'aux [SectionMark] descendants.
class SectionBeaconScope extends InheritedWidget {
  const SectionBeaconScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final SectionBeaconController controller;

  static SectionBeaconController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SectionBeaconScope>()
      ?.controller;

  @override
  bool updateShouldNotify(SectionBeaconScope oldWidget) =>
      controller != oldWidget.controller;
}

/// État partagé : les sections inscrites, et celle qu'on regarde.
///
/// ⚠️ [recomputeFromScreen] lit la géométrie des marqueurs à chaque
/// notification de défilement. C'est O(nombre de sections) — sept sur la page
/// la plus longue — et rien d'autre ne bouge : pas de `setState` sur la page,
/// seul le bandeau se repeint (`AnimatedBuilder`).
class SectionBeaconController extends ChangeNotifier {
  final List<({String title, GlobalKey key})> _marks = [];
  String? _current;

  /// Section actuellement regardée, ou `null` si on est encore au-dessus de
  /// la première (en-tête de page).
  String? get current => _current;

  /// Nombre de sections inscrites — exposé pour les tests.
  int get markCount => _marks.length;

  void register(String title, GlobalKey key) {
    if (_marks.any((m) => m.key == key)) return;
    _marks.add((title: title, key: key));
  }

  void unregister(GlobalKey key) {
    _marks.removeWhere((m) => m.key == key);
  }

  /// Pose directement la section courante — chemin des tests, et repli pour
  /// une page qui saurait mieux que la géométrie.
  void setCurrent(String? title) {
    if (_current == title) return;
    _current = title;
    notifyListeners();
  }

  /// Recalcule à partir des positions à l'écran : la section courante est la
  /// DERNIÈRE dont le libellé est passé au-dessus de [thresholdY].
  void recomputeFromScreen(double thresholdY) {
    String? found;
    for (final m in _marks) {
      final RenderObject? ro = m.key.currentContext?.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize) continue;
      final double top = ro.localToGlobal(Offset.zero).dy;
      // ⚠️ `<=` et pas `<` : une section calée pile sous le bandeau est bien
      // celle qu'on regarde.
      if (top <= thresholdY) {
        found = m.title;
      } else {
        // Les marqueurs sont inscrits dans l'ordre du document : dès qu'un
        // libellé est SOUS la ligne, les suivants le sont aussi.
        break;
      }
    }
    setCurrent(found);
  }
}

/// Libellé de section — l'affichage d'avant, plus l'inscription au bandeau.
///
/// ⚠️ Le [GlobalKey] est créé UNE fois par instance d'état : le recréer à
/// chaque `build` réinscrirait une section à chaque frame et ferait grossir la
/// liste sans fin.
class SectionMark extends StatefulWidget {
  const SectionMark(this.title, {super.key, this.padding, this.child});

  final String title;
  final EdgeInsets? padding;

  /// Quand la page a DÉJÀ son propre en-tête de section (l'accueil, dont
  /// chaque rangée porte son titre), on ne veut pas d'un second libellé :
  /// on ancre le marqueur sur l'en-tête existant, rendu tel quel.
  final Widget? child;

  @override
  State<SectionMark> createState() => _SectionMarkState();
}

class _SectionMarkState extends State<SectionMark> {
  final GlobalKey _key = GlobalKey();
  SectionBeaconController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = SectionBeaconScope.maybeOf(context);
    if (identical(next, _controller)) return;
    _controller?.unregister(_key);
    _controller = next;
    _controller?.register(widget.title, _key);
  }

  @override
  void dispose() {
    _controller?.unregister(_key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget? given = widget.child;
    if (given != null) return KeyedSubtree(key: _key, child: given);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      key: _key,
      padding: widget.padding ?? const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        widget.title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.8,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
