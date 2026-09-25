import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/diagnostics/log_buffer.dart';

/// §homeVertical (R2, 2026-09-25) — ↑/↓ sur l'accueil TV : de rangée en
/// rangée, arrivée TOUJOURS sur l'élément le plus à gauche.
///
/// **Le défaut (R2), rejoué sur l'AVD TV le 2026-09-25.** Une rangée Favoris
/// à UNE carte était inatteignable à la verticale, dans les DEUX sens : onglet
/// Films ↓ → 1re carte de New, 1re carte de New ↑ → onglet Films. La cause est
/// dans `dpad` (`DpadTraversalPolicy._bestCandidate`) : un candidat « dans le
/// faisceau » (simple chevauchement de COLONNE) gagne catégoriquement sur un
/// candidat hors faisceau, quelle que soit la distance. Une carte seule, calée
/// à gauche, n'est dans le faisceau de presque rien — et les onglets, dans le
/// même `ListView` vertical, le sont presque toujours.
///
/// **La décision (utilisateur, 2026-09-25).** ↑/↓ vont d'un emplacement
/// vertical au suivant (hero, onglets, dernière chaîne, rangées) et arrivent
/// sur l'élément le plus à GAUCHE — la 1re affiche, sans mémoire de colonne ;
/// ↓ depuis les onglets → la 1re rangée ; ↑ depuis la 1re rangée → l'onglet
/// de la PAGE COURANTE ; hero ↔ onglets inchangé.
///
/// **Le moyen, sans fork de `dpad` ni retrait des régions.** Chaque
/// emplacement est enveloppé d'un [HomeNavSlot] : un nœud de focus MARQUEUR
/// (jamais focalisable, hors traversée) qui voit passer les touches de ses
/// descendants AVANT les raccourcis racine de `dpad`. Il résout ↑/↓ par
/// [homeVerticalTarget] (pure, testée) et consomme la touche ; quand la
/// politique ne sait pas (emplacement pas construit, hero), la touche
/// continue vers `dpad`, comme avant. Les `DpadRegion` par rangée restent
/// (§carouselScrollDir) ; le téléphone n'a aucun emplacement (`PlatformTv.isTv`).

/// Genre d'un emplacement vertical de l'accueil.
enum HomeSlotKind {
  /// Le carrousel « en avant » : ni cible ni source — hero ↔ onglets reste
  /// à `dpad`.
  hero,

  /// Séries / Films / Chaînes. Cible : l'onglet de la page courante.
  tabs,

  /// « Reprendre la chaîne » (page Chaînes).
  lastWatched,

  /// Une catégorie : carrousel (une ligne) ou grille des chaînes (plusieurs).
  row,
}

/// Un emplacement tel que la politique le voit : son genre et les rectangles
/// de ses focusables construits (vide = rien à focaliser, on le saute).
@immutable
class HomeNavSlotShape {
  const HomeNavSlotShape(this.kind, this.items, {this.preferred = 0});

  final HomeSlotKind kind;
  final List<Rect> items;

  /// Onglets seulement : rang, de gauche à droite, de l'onglet de la page.
  final int preferred;
}

/// Cible d'un ↑/↓ : l'emplacement et l'élément (indice dans ses `items`).
/// [HomeNavTarget.stay] : la touche est consommée, le focus ne bouge pas.
@immutable
class HomeNavTarget {
  const HomeNavTarget(this.slot, this.item);
  const HomeNavTarget.stay()
      : slot = -1,
        item = -1;

  final int slot;
  final int item;

  bool get isStay => slot < 0;

  @override
  bool operator ==(Object other) =>
      other is HomeNavTarget && other.slot == slot && other.item == item;

  @override
  int get hashCode => Object.hash(slot, item);

  @override
  String toString() =>
      isStay ? 'HomeNavTarget.stay' : 'HomeNavTarget($slot, $item)';
}

/// Lignes d'un emplacement : indices de [items] groupés par hauteur (une
/// ligne = des tops qui diffèrent de moins d'une demi-hauteur — la carte
/// focalisée, agrandie de 5 %, reste sur sa ligne), du haut vers le bas, et
/// de gauche à droite dans chaque ligne.
List<List<int>> homeNavLines(List<Rect> items) {
  final List<int> order = List<int>.generate(items.length, (int i) => i)
    ..sort((int a, int b) {
      final int byTop = items[a].top.compareTo(items[b].top);
      return byTop != 0 ? byTop : items[a].left.compareTo(items[b].left);
    });
  final List<List<int>> lines = <List<int>>[];
  double? lineTop;
  for (final int i in order) {
    final Rect r = items[i];
    if (lineTop == null || r.top - lineTop > r.height / 2) {
      lines.add(<int>[i]);
      lineTop = r.top;
    } else {
      lines.last.add(i);
    }
  }
  for (final List<int> line in lines) {
    line.sort((int a, int b) => items[a].left.compareTo(items[b].left));
  }
  return lines;
}

/// Élément d'arrivée dans un emplacement : l'onglet de la page pour la barre
/// d'onglets, sinon le plus à GAUCHE de la ligne du haut (1re affiche d'un
/// carrousel, 1re tuile d'une grille). **Pure.**
int homeNavEntry(HomeNavSlotShape slot) {
  final List<List<int>> lines = homeNavLines(slot.items);
  if (slot.kind == HomeSlotKind.tabs) {
    final List<int> byLeft = lines.expand((List<int> l) => l).toList()
      ..sort((int a, int b) => slot.items[a].left.compareTo(slot.items[b].left));
    return byLeft[slot.preferred.clamp(0, byLeft.length - 1)];
  }
  return lines.first.first;
}

/// §homeVertical — Où va un ↑ ([down] faux) ou un ↓ depuis l'élément
/// [focusedItem] de l'emplacement [from]. **Pure** — testée
/// (`test/home_vertical_nav_test.dart`).
///
/// [slotAt] rend la forme d'un emplacement par son indice dans la liste
/// verticale, `null` s'il n'est pas construit ; [lastIndex] est le dernier
/// indice de la liste (`null` = inconnu).
///
/// Rend `null` quand la touche doit continuer vers `dpad` (comportement
/// d'avant) : hero, ↑ depuis les onglets, emplacement voisin pas construit
/// (`dpad` sait faire défiler la liste pour le construire), haut de liste.
///
/// Règles :
///   1. Dans une GRILLE (plusieurs lignes), ↑/↓ restent dans la grille tant
///      qu'il y a une ligne voisine : l'élément de cette ligne le plus proche
///      en colonne. (`dpad` aurait pu sauter la dernière ligne, centrée, pour
///      la grille suivante « dans le faisceau ».)
///   2. Sinon, l'emplacement voisin dans le sens demandé, en sautant ceux qui
///      n'ont rien de focalisable ; arrivée par [homeNavEntry].
///   3. Sous la dernière rangée : on reste (avant, `dpad` pouvait partir dans
///      le rail, seul candidat restant « en dessous »).
HomeNavTarget? homeVerticalTarget({
  required HomeNavSlotShape? Function(int index) slotAt,
  required int? lastIndex,
  required int from,
  required int focusedItem,
  required bool down,
}) {
  final HomeNavSlotShape? here = slotAt(from);
  if (here == null || focusedItem < 0 || focusedItem >= here.items.length) {
    return null;
  }
  if (here.kind == HomeSlotKind.hero) return null;
  if (here.kind == HomeSlotKind.tabs && !down) return null;

  // 1. Ligne voisine dans le même emplacement (grille des chaînes).
  final List<List<int>> lines = homeNavLines(here.items);
  final int line =
      lines.indexWhere((List<int> l) => l.contains(focusedItem));
  final int nextLine = down ? line + 1 : line - 1;
  if (line >= 0 && nextLine >= 0 && nextLine < lines.length) {
    final double x = here.items[focusedItem].center.dx;
    int best = lines[nextLine].first;
    double bestDistance = double.infinity;
    for (final int i in lines[nextLine]) {
      final double d = (here.items[i].center.dx - x).abs();
      if (d < bestDistance - 0.5) {
        best = i;
        bestDistance = d;
      }
    }
    return HomeNavTarget(from, best);
  }

  // 2. Emplacement voisin.
  final int step = down ? 1 : -1;
  for (int j = from + step;; j += step) {
    if (j < 0) return null;
    if (lastIndex != null && j > lastIndex) {
      return down ? const HomeNavTarget.stay() : null;
    }
    final HomeNavSlotShape? slot = slotAt(j);
    if (slot == null) return null;
    if (slot.kind == HomeSlotKind.hero) return null;
    if (slot.items.isEmpty) continue;
    return HomeNavTarget(j, homeNavEntry(slot));
  }
}

/// §homeVertical — Registre des emplacements CONSTRUITS d'une page de
/// l'accueil, par indice dans sa liste verticale.
///
/// Une instance par page (Séries, Films, Chaînes), détenue par la HomePage :
/// c'est aussi par elle que R51 retrouve l'onglet de la page qu'on vient
/// d'ouvrir ([entryNodeOf]).
class HomeVerticalNav {
  final Map<int, _HomeNavSlotState> _slots = <int, _HomeNavSlotState>{};

  /// Dernier indice de la liste verticale (posé au build de la page) ;
  /// `null` = inconnu (état vide) : on ne bloque jamais le bas.
  int? lastIndex;

  void _register(int index, _HomeNavSlotState slot) => _slots[index] = slot;

  void _unregister(int index, _HomeNavSlotState slot) {
    if (identical(_slots[index], slot)) _slots.remove(index);
  }

  /// Le nœud d'arrivée du premier emplacement de genre [kind] qui a quelque
  /// chose à focaliser (onglets : l'onglet de la page), sinon `null`.
  FocusNode? entryNodeOf(HomeSlotKind kind) {
    final List<int> indices = _slots.keys.toList()..sort();
    for (final int i in indices) {
      final _HomeNavSlotState slot = _slots[i]!;
      if (slot.widget.kind != kind) continue;
      final _SlotSnapshot snap = slot._snapshot();
      if (snap.nodes.isEmpty) continue;
      return snap.nodes[homeNavEntry(snap.shape)];
    }
    return null;
  }

  /// Résout et exécute un ↑/↓ parti de l'emplacement [from]. `true` = touche
  /// consommée.
  bool _move({required int from, required bool down}) {
    final FocusNode? primary = FocusManager.instance.primaryFocus;
    final _HomeNavSlotState? here = _slots[from];
    if (primary == null || here == null) return false;
    final BuildContext? primaryContext = primary.context;
    if (primaryContext != null &&
        primaryContext.findAncestorStateOfType<EditableTextState>() != null) {
      return false; // un champ de saisie garde ses flèches
    }
    final Map<int, _SlotSnapshot?> snaps = <int, _SlotSnapshot?>{};
    _SlotSnapshot? snap(int i) =>
        snaps.putIfAbsent(i, () => _slots[i]?._snapshot());
    final int focused = snap(from)!.nodes.indexOf(primary);
    if (focused < 0) return false;
    final HomeNavTarget? target = homeVerticalTarget(
      slotAt: (int i) => snap(i)?.shape,
      lastIndex: lastIndex,
      from: from,
      focusedItem: focused,
      down: down,
    );
    if (target == null) return false;
    if (target.isStay) {
      DiagnosticLog.trace('🧭 §homeVertical : ${down ? '↓' : '↑'} en bout de liste, le focus reste');
      return true;
    }
    DiagnosticLog.trace('🧭 §homeVertical : ${down ? '↓' : '↑'} emplacement $from → ${target.slot} (item ${target.item})');
    _slots[target.slot]!._arrive(snap(target.slot)!.nodes[target.item]);
    return true;
  }
}

class _SlotSnapshot {
  _SlotSnapshot(this.nodes, this.shape);
  final List<FocusNode> nodes;
  final HomeNavSlotShape shape;
}

/// §homeVertical — Enveloppe d'un emplacement vertical de l'accueil (TV
/// seulement : ne l'installer que si `PlatformTv.isTv`).
class HomeNavSlot extends StatefulWidget {
  const HomeNavSlot({
    super.key,
    required this.nav,
    required this.index,
    required this.kind,
    this.preferred = 0,
    required this.child,
  });

  final HomeVerticalNav nav;

  /// Indice de l'emplacement dans la liste verticale de la page.
  final int index;
  final HomeSlotKind kind;

  /// Onglets : rang de l'onglet de la page (Séries 0, Films 1, Chaînes 2).
  final int preferred;
  final Widget child;

  @override
  State<HomeNavSlot> createState() => _HomeNavSlotState();
}

class _HomeNavSlotState extends State<HomeNavSlot> {
  /// Marqueur, comme celui de `DpadRegion` : jamais focalisable, hors
  /// traversée — il ne sert qu'à voir passer les touches et à énumérer les
  /// focusables de l'emplacement.
  final FocusNode _marker = FocusNode(
    debugLabel: 'HomeNavSlot',
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    widget.nav._register(widget.index, this);
  }

  @override
  void didUpdateWidget(covariant HomeNavSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.nav, widget.nav) ||
        oldWidget.index != widget.index) {
      oldWidget.nav._unregister(oldWidget.index, this);
      widget.nav._register(widget.index, this);
    }
  }

  @override
  void dispose() {
    widget.nav._unregister(widget.index, this);
    _marker.dispose();
    super.dispose();
  }

  static Rect? _rectOf(FocusNode node) {
    final BuildContext? context = node.context;
    if (context == null || !context.mounted) return null;
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return MatrixUtils.transformRect(
        box.getTransformTo(null), Offset.zero & box.size);
  }

  _SlotSnapshot _snapshot() {
    final List<FocusNode> nodes = <FocusNode>[];
    final List<Rect> rects = <Rect>[];
    for (final FocusNode node in _marker.traversalDescendants) {
      final Rect? rect = _rectOf(node);
      if (rect == null || rect.isEmpty) continue;
      nodes.add(node);
      rects.add(rect);
    }
    return _SlotSnapshot(
      nodes,
      HomeNavSlotShape(widget.kind, rects, preferred: widget.preferred),
    );
  }

  /// Une rangée HORIZONTALE (pas la `PageView` des onglets, horizontale elle
  /// aussi — même discriminant que §pageViewRewind).
  static bool _isRow(ScrollableState s) =>
      axisDirectionToAxis(s.axisDirection) == Axis.horizontal &&
      s.position.hasPixels &&
      s.position.hasContentDimensions &&
      s.position is! PageMetrics;

  /// Pose le focus sur [node]. Un carrousel qui n'est pas à son début (retour
  /// arrière encore en cours) y est ramené d'abord : l'arrivée se fait sur la
  /// 1re affiche, pas sur la plus à gauche des cartes encore construites.
  void _arrive(FocusNode node) {
    final BuildContext? context = node.context;
    final ScrollableState? row =
        context == null ? null : Scrollable.maybeOf(context);
    if (row != null &&
        _isRow(row) &&
        row.position.pixels > row.position.minScrollExtent + 0.5) {
      row.position.jumpTo(row.position.minScrollExtent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final _SlotSnapshot again = _snapshot();
        if (again.nodes.isEmpty) return;
        _request(again.nodes[homeNavEntry(again.shape)]);
      });
      return;
    }
    _request(node);
  }

  void _request(FocusNode node) {
    final BuildContext? context = node.context;
    final DpadController? dpad = context == null ? null : Dpad.maybeOf(context);
    if (dpad != null) {
      dpad.requestFocus(node);
    } else {
      node.requestFocus();
    }
    // Les cartes et les onglets font défiler la page eux-mêmes à la prise de
    // focus (§rowAnchor / auto-scroll `dpad`) ; la tuile « Reprendre la
    // chaîne » est un `InkWell` nu : on la montre ici, comme `dpad` le fait
    // pour un nœud qu'il ne gère pas.
    if (widget.kind == HomeSlotKind.lastWatched) DpadScroll.ensureVisible(node);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final TraversalDirection? direction =
        Dpad.keySetOf(context).directionOf(event.logicalKey);
    if (direction != TraversalDirection.up &&
        direction != TraversalDirection.down) {
      return KeyEventResult.ignored;
    }
    return widget.nav._move(
      from: widget.index,
      down: direction == TraversalDirection.down,
    )
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _marker,
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: _onKey,
        child: widget.child,
      );
}
