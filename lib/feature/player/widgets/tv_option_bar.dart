import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/themes/aether_theme_extension.dart';
import '../../../core/themes/colors.dart';
import '../../../l10n/app_localizations.dart';

// ─── §tvPlayerPanel — les options du lecteur, DANS la vidéo (TV) ────────────
//
// À la télécommande, les boutons de la barre du lecteur étaient des
// `GestureDetector` non focusables : la seule porte vers les réglages était ↑,
// qui ouvrait un Dialog centré — le film disparaissait derrière, puis un
// second Dialog par réglage. Ici, chaque réglage est un bouton de la barre du
// bas, et sa liste s'ouvre juste au-dessus de lui, dans l'image.
//
// ⛔ Pas de focus `dpad` : toute la vidéo est UN `DpadFocusable` racine
// (`player_page.dart`) qui consomme les touches, et un focusable imbriqué n'y
// serait candidat nulle part (§dpadChildFocus). La navigation est donc un
// AUTOMATE pur ([TvOptionsController]) auquel la racine délègue OK, les
// flèches et Retour ; la rangée et la liste dessinent elles-mêmes l'anneau de
// focus sur l'élément courant.

/// Les boutons de la rangée, dans l'ordre d'affichage.
enum TvOptionKind { nextEpisode, audio, subtitles, speed, fit, quality, stats }

/// Une ligne de liste.
class TvOptionItem {
  const TvOptionItem({
    required this.label,
    required this.onSelect,
    this.detail,
    this.selected = false,
    this.icon,
  });

  final String label;
  final String? detail;

  /// L'état COURANT (coche) : c'est aussi là que la liste s'ouvre.
  final bool selected;
  final IconData? icon;

  /// Applique la ligne. `true` = c'est fait, la liste se referme ; `false` =
  /// elle reste ouverte (échec déjà dit par un toast, ou liste remplacée).
  final Future<bool> Function() onSelect;
}

/// Un bouton de la rangée : soit il ouvre une liste ([items]), soit il agit
/// tout de suite ([onAction]).
class TvOptionButton {
  const TvOptionButton({
    required this.kind,
    required this.icon,
    required this.title,
    this.value,
    this.items,
    this.onAction,
    this.leavesRow = false,
  }) : assert((items == null) != (onAction == null));

  final TvOptionKind kind;
  final IconData icon;
  final String title;

  /// L'état courant, sous le titre (« Français », « 1× », « Coupés »…).
  final String? value;

  /// Relue à chaque image : les coches suivent l'état du lecteur.
  final List<TvOptionItem> Function()? items;
  final VoidCallback? onAction;

  /// L'action ramène à la vidéo (Épisode suivant : le titre change).
  final bool leavesRow;
}

// ─── §tvSeekBar — la barre de progression, à la télécommande ───────────────

/// §tvSeekBar — Le pas d'un appui sur ←/→ quand la barre a le focus, selon
/// depuis combien de temps la touche est MAINTENUE ([held] = zéro pour un
/// appui simple) : 10 s, puis 30 s, puis 1 min, puis 5 min passé 2,5 s. Un
/// film de deux heures se traverse en quelques secondes de maintien, et un
/// appui bref reste précis.
Duration tvSeekStep(Duration held) {
  if (held < const Duration(milliseconds: 500)) return const Duration(seconds: 10);
  if (held < const Duration(milliseconds: 1500)) return const Duration(seconds: 30);
  if (held < const Duration(milliseconds: 2500)) return const Duration(minutes: 1);
  return const Duration(minutes: 5);
}

/// §tvSeekBar — [target] borné à [0, total].
Duration tvSeekClamp(Duration target, Duration total) {
  if (target.isNegative) return Duration.zero;
  if (target > total) return total;
  return target;
}

/// « 42:10 », « 1:02:05 » — même forme que les temps de la barre du lecteur.
String formatPlayerTime(Duration d) {
  final Duration a = d.isNegative ? -d : d;
  final int h = a.inHours;
  final String m = a.inMinutes.remainder(60).toString().padLeft(2, '0');
  final String sec = a.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$sec' : '$m:$sec';
}

/// « +3:20 » / « -0:40 » : l'écart entre le repère et la lecture. Vide si le
/// repère est sur la lecture (moins d'une seconde).
String formatSeekDelta(Duration delta) {
  if (delta.inSeconds == 0) return '';
  final String sign = delta.isNegative ? '-' : '+';
  final Duration a = delta.isNegative ? -delta : delta;
  final int h = a.inHours;
  final int m = a.inMinutes.remainder(60);
  final String sec = a.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0
      ? '$sign$h:${m.toString().padLeft(2, '0')}:$sec'
      : '$sign$m:$sec';
}

/// §tvSeekBar — Ce que la barre lit et commande. `null` côté lecteur = barre
/// non sélectionnable (un direct sans durée).
class TvSeekSource {
  const TvSeekSource({
    required this.position,
    required this.duration,
    required this.commit,
  });

  final Duration Function() position;
  final Duration Function() duration;

  /// Va à cette position (le point de saut unique du lecteur).
  final void Function(Duration target) commit;
}

/// §tvPlayerPanel — L'automate de la rangée d'options, sans aucun widget.
///
/// Trois niveaux : la VIDÉO (inactif), la RANGÉE (un bouton courant), la
/// LISTE (une ligne courante). Chaque méthode rend `true` si la touche est
/// consommée ; inactif, rien ne l'est — la vidéo garde OK et ←/→.
class TvOptionsController extends ChangeNotifier {
  List<TvOptionButton> _buttons = const [];
  bool _active = false;
  int _index = 0;
  TvOptionKind? _lastUsed;

  bool _listOpen = false;
  int _listIndex = 0;

  /// Liste qui REMPLACE celle du bouton (résultats de la recherche de
  /// sous-titres en ligne), jusqu'à la fermeture.
  List<TvOptionItem>? _override;

  /// Change à chaque ouverture, remplacement ou fermeture de liste : une
  /// application qui aboutit après coup ne referme pas une AUTRE liste.
  int _listToken = 0;

  bool _disposed = false;

  // ── §tvSeekBar — quatrième niveau : la barre de progression ──────────────

  /// Posée par le lecteur à chaque image ; `null` = pas de barre (direct).
  TvSeekSource? seekSource;

  /// Depuis combien de temps ←/→ est maintenue (zéro = appui simple). Le
  /// lecteur la mesure sur les événements clavier : `onDirection` ne
  /// distingue pas un appui d'une répétition.
  Duration Function() heldFor = _noHold;
  static Duration _noHold() => Duration.zero;

  /// Horloge (tests).
  DateTime Function() clock = DateTime.now;

  /// Une touche maintenue répète ~20 fois par seconde : au pas de 5 min, le
  /// repère traverserait un film en une seconde. On n'applique pas plus d'un
  /// pas par [seekRepeatGap] pendant un maintien.
  static const Duration seekRepeatGap = Duration(milliseconds: 110);

  bool _seekOpen = false;
  Duration _seekTarget = Duration.zero;
  DateTime? _lastSeekMove;

  bool get seekOpen => _seekOpen;
  Duration get seekTarget => _seekTarget;

  bool get _seekable {
    final src = seekSource;
    return src != null && src.duration() > Duration.zero;
  }

  List<TvOptionButton> get buttons => _buttons;
  bool get active => _active;
  int get index => _index;
  bool get listOpen => _listOpen;
  int get listIndex => _listIndex;
  TvOptionKind? get lastUsed => _lastUsed;

  TvOptionButton? get current =>
      (_index >= 0 && _index < _buttons.length) ? _buttons[_index] : null;

  /// Les lignes de la liste ouverte (vide si aucune).
  List<TvOptionItem> get items {
    if (!_listOpen) return const [];
    return _override ?? current?.items?.call() ?? const [];
  }

  /// Pose les boutons du moment (appelé pendant le `build` du lecteur : ne
  /// notifie pas). Le bouton courant est suivi par son GENRE : l'apparition de
  /// « Qualité » ne déplace pas le focus.
  void syncButtons(List<TvOptionButton> next) {
    final TvOptionKind? kind = current?.kind;
    _buttons = next;
    // §tvSeekBar — la barre n'est plus sélectionnable (flux sans durée) :
    // on revient à la rangée.
    if (_seekOpen && !_seekable) _seekOpen = false;
    if (next.isEmpty) {
      if (_active) {
        _reset();
        // Hors du build : le lecteur écoute pour relancer son minuteur.
        scheduleMicrotask(_notifyLater);
      }
      return;
    }
    final int i = kind == null ? -1 : next.indexWhere((b) => b.kind == kind);
    if (i >= 0) {
      _index = i;
    } else {
      _index = _index.clamp(0, next.length - 1);
      // Le bouton dont la liste était ouverte a disparu : la liste aussi.
      if (_listOpen) _closeList();
    }
  }

  /// ↓ / ↑ / appui long depuis la vidéo : la rangée, sur le dernier bouton
  /// utilisé, sinon « Audio », sinon le premier.
  bool open() {
    if (_buttons.isEmpty) return false;
    int i = _lastUsed == null
        ? -1
        : _buttons.indexWhere((b) => b.kind == _lastUsed);
    if (i < 0) i = _buttons.indexWhere((b) => b.kind == TvOptionKind.audio);
    _index = i < 0 ? 0 : i;
    _active = true;
    _closeList();
    notifyListeners();
    return true;
  }

  bool move(TraversalDirection dir) {
    if (!_active) return false;
    if (_seekOpen) return _moveSeek(dir);
    if (_listOpen) {
      final int n = items.length;
      if (n == 0) return true;
      final int next = switch (dir) {
        TraversalDirection.up => _listIndex - 1,
        TraversalDirection.down => _listIndex + 1,
        _ => _listIndex,
      };
      final int bounded = next.clamp(0, n - 1);
      if (bounded != _listIndex) {
        _listIndex = bounded;
        notifyListeners();
      }
      return true;
    }
    switch (dir) {
      case TraversalDirection.left:
      case TraversalDirection.right:
        final int next = (_index + (dir == TraversalDirection.left ? -1 : 1))
            .clamp(0, _buttons.length - 1);
        if (next != _index) {
          _index = next;
          notifyListeners();
        }
      case TraversalDirection.up:
        // ↑ depuis la rangée = retour à la vidéo (la liste, elle, s'ouvre
        // par OK : ↑ ne peut pas vouloir dire les deux).
        _reset();
        notifyListeners();
      case TraversalDirection.down:
        // §tvSeekBar — ↓ depuis la rangée : la barre de progression, repère
        // posé sur la lecture en cours.
        if (_seekable) {
          _seekOpen = true;
          _seekTarget = seekSource!.position();
          _lastSeekMove = null;
          notifyListeners();
        }
    }
    return true;
  }

  bool _moveSeek(TraversalDirection dir) {
    switch (dir) {
      case TraversalDirection.up:
        // Retour à la rangée ; le déplacement non validé est abandonné.
        _seekOpen = false;
        notifyListeners();
      case TraversalDirection.down:
        break;
      case TraversalDirection.left:
      case TraversalDirection.right:
        final src = seekSource;
        if (src == null) return true;
        final Duration held = heldFor();
        final DateTime now = clock();
        if (held > Duration.zero &&
            _lastSeekMove != null &&
            now.difference(_lastSeekMove!) < seekRepeatGap) {
          return true; // répétition trop rapprochée : consommée, sans effet
        }
        _lastSeekMove = now;
        final Duration step = tvSeekStep(held);
        final Duration next = tvSeekClamp(
          dir == TraversalDirection.left ? _seekTarget - step : _seekTarget + step,
          src.duration(),
        );
        if (next != _seekTarget) {
          _seekTarget = next;
          notifyListeners();
        }
    }
    return true;
  }

  bool select() {
    if (!_active) return false;
    if (_seekOpen) {
      // OK = aller au repère ; le focus RESTE sur la barre.
      seekSource?.commit(_seekTarget);
      notifyListeners();
      return true;
    }
    final TvOptionButton? b = current;
    if (b == null) return true;
    _lastUsed = b.kind;
    if (_listOpen) {
      final List<TvOptionItem> list = items;
      if (list.isEmpty) return true;
      final TvOptionItem item = list[_listIndex.clamp(0, list.length - 1)];
      final int token = _listToken;
      item.onSelect().catchError((Object e) {
        debugPrint('⚠️ §tvPlayerPanel — ligne non appliquée : $e');
        return false;
      }).then((bool done) {
        if (_disposed || !done) return;
        if (_listOpen && token == _listToken) {
          _closeList();
          notifyListeners();
        }
      });
      return true;
    }
    if (b.items != null) {
      final List<TvOptionItem> list = b.items!();
      _listOpen = true;
      _override = null;
      _listToken++;
      final int sel = list.indexWhere((it) => it.selected);
      _listIndex = sel < 0 ? 0 : sel;
      notifyListeners();
      return true;
    }
    b.onAction?.call();
    if (b.leavesRow) _reset();
    notifyListeners();
    return true;
  }

  /// Retour : referme la liste (focus rendu au bouton), sinon quitte la
  /// rangée — ou la barre de progression, en ABANDONNANT le déplacement non
  /// validé (§tvSeekBar). ⛔ Jamais au-delà : quitter le film n'est possible que depuis la
  /// vidéo (§tvOptionsBack).
  bool back() {
    if (!_active) return false;
    if (_listOpen) {
      _closeList();
    } else {
      _reset();
    }
    notifyListeners();
    return true;
  }

  /// Ferme tout, sans condition (verrou, diffusion, fin de lecture).
  void close() {
    if (!_active) return;
    _reset();
    notifyListeners();
  }

  /// Remplace la liste ouverte du bouton [kind] (résultats d'une recherche).
  /// Sans effet si cette liste n'est plus ouverte.
  void replaceList(TvOptionKind kind, List<TvOptionItem> next) {
    if (!_active || !_listOpen || current?.kind != kind) return;
    _override = next;
    _listIndex = 0;
    _listToken++;
    notifyListeners();
  }

  /// Un libellé a changé (recherche en cours…) : redessiner.
  void refresh() {
    if (!_disposed) notifyListeners();
  }

  void _closeList() {
    _listOpen = false;
    _override = null;
    _listIndex = 0;
    _listToken++;
  }

  void _reset() {
    _active = false;
    _seekOpen = false;
    _lastSeekMove = null;
    _closeList();
  }

  void _notifyLater() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// « 1× », « 1,5× » : le séparateur décimal de la langue de l'interface.
String tvSpeedLabel(double speed, AppLocalizations l10n) =>
    l10n.tvOptSpeedValue(NumberFormat.decimalPattern(l10n.localeName)
        .format(speed));

/// §tvPlayerPanel — La rangée de boutons et, au-dessus du bouton courant, sa
/// liste. Rien n'y est focusable : l'anneau se DESSINE sur l'élément courant
/// de [controller].
class TvOptionBar extends StatefulWidget {
  const TvOptionBar({super.key, required this.controller});

  final TvOptionsController controller;

  /// Posée sur l'élément qui porte l'anneau (tests).
  static const Key focusRingKey = ValueKey<String>('tv_option_focus_ring');

  @override
  State<TvOptionBar> createState() => _TvOptionBarState();
}

class _TvOptionBarState extends State<TvOptionBar> {
  final List<LayerLink> _links = [];
  final List<GlobalKey> _itemKeys = [];
  final ScrollController _listScroll = ScrollController();
  int _shownListIndex = -1;

  @override
  void dispose() {
    _listScroll.dispose();
    super.dispose();
  }

  LayerLink _linkAt(int i) {
    while (_links.length <= i) {
      _links.add(LayerLink());
    }
    return _links[i];
  }

  GlobalKey _itemKeyAt(int i) {
    while (_itemKeys.length <= i) {
      _itemKeys.add(GlobalKey());
    }
    return _itemKeys[i];
  }

  /// La ligne courante reste dans la partie visible d'une longue liste.
  void _revealCurrent(int i) {
    if (i == _shownListIndex) return;
    _shownListIndex = i;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = i < _itemKeys.length ? _itemKeys[i].currentContext : null;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(ctx,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: const Duration(milliseconds: 120));
      Scrollable.ensureVisible(ctx,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          duration: const Duration(milliseconds: 120));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final ext = Theme.of(context).extension<AetherThemeExtension>();
        final Color ring = ext?.focusGlowColor ?? kAccentPrimary;
        final double radius = ext?.borderRadius ?? 12;
        final buttons = c.buttons;
        if (buttons.isEmpty) return const SizedBox.shrink();
        if (!c.listOpen) _shownListIndex = -1;

        final Widget row = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < buttons.length; i++)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: CompositedTransformTarget(
                    link: _linkAt(i),
                    child: _OptionChip(
                      button: buttons[i],
                      focused: c.active &&
                          i == c.index &&
                          !c.listOpen &&
                          !c.seekOpen,
                      // La liste est ouverte AU-DESSUS de ce bouton : il le
                      // dit, sans porter l'anneau (c'est la ligne qui l'a).
                      holdsList: c.active && i == c.index && c.listOpen,
                      ring: ring,
                      radius: radius,
                    ),
                  ),
                ),
              ),
          ],
        );

        if (!c.active || !c.listOpen) return row;

        final List<TvOptionItem> items = c.items;
        _revealCurrent(c.listIndex);
        // Moitié gauche : la liste s'aligne sur le bord gauche du bouton ;
        // moitié droite : sur son bord droit — elle ne sort pas de l'écran.
        final bool leftHalf = c.index < buttons.length / 2;
        final double maxH = MediaQuery.sizeOf(context).height * 0.55;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            row,
            Positioned(
              left: 0,
              top: 0,
              child: CompositedTransformFollower(
                link: _linkAt(c.index),
                showWhenUnlinked: false,
                targetAnchor:
                    leftHalf ? Alignment.topLeft : Alignment.topRight,
                followerAnchor:
                    leftHalf ? Alignment.bottomLeft : Alignment.bottomRight,
                offset: const Offset(0, -10),
                child: _OptionList(
                  title: c.current?.title ?? '',
                  items: items,
                  current: c.listIndex,
                  ring: ring,
                  radius: radius,
                  maxHeight: maxH,
                  scroll: _listScroll,
                  keyAt: _itemKeyAt,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// L'anneau de focus, dessiné : bordure + halo à la couleur du thème, au
/// rayon du thème (§btnShape — la même forme que les boutons).
BoxDecoration _ringDecoration({
  required bool focused,
  required Color ring,
  required double radius,
  required Color fill,
  Color? idleBorder,
}) =>
    BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: focused ? ring : (idleBorder ?? Colors.transparent),
        width: focused ? 2.6 : 1,
      ),
      boxShadow: focused
          ? [BoxShadow(color: ring.withAlpha(120), blurRadius: 14)]
          : null,
    );

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.button,
    required this.focused,
    required this.holdsList,
    required this.ring,
    required this.radius,
  });

  final TvOptionButton button;
  final bool focused;
  final bool holdsList;
  final Color ring;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final String? value = button.value;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Container(
        key: focused ? TvOptionBar.focusRingKey : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        // Sur la vidéo : voile sombre, texte blanc (légitime, §lightTheme).
        decoration: _ringDecoration(
          focused: focused,
          ring: ring,
          radius: radius,
          fill: Colors.black.withAlpha(focused || holdsList ? 170 : 110),
          idleBorder: holdsList ? ring.withAlpha(140) : Colors.white24,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(button.icon, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    button.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withAlpha(value == null ? 255 : 180),
                      fontSize: value == null ? 13 : 11,
                      fontWeight:
                          value == null ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (value != null)
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
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

class _OptionList extends StatelessWidget {
  const _OptionList({
    required this.title,
    required this.items,
    required this.current,
    required this.ring,
    required this.radius,
    required this.maxHeight,
    required this.scroll,
    required this.keyAt,
  });

  final String title;
  final List<TvOptionItem> items;
  final int current;
  final Color ring;
  final double radius;
  final double maxHeight;
  final ScrollController scroll;
  final GlobalKey Function(int) keyAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(215),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: kAccentPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              controller: scroll,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Padding(
                      key: keyAt(i),
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: _OptionLine(
                        item: items[i],
                        focused: i == current,
                        ring: ring,
                        radius: radius,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionLine extends StatelessWidget {
  const _OptionLine({
    required this.item,
    required this.focused,
    required this.ring,
    required this.radius,
  });

  final TvOptionItem item;
  final bool focused;
  final Color ring;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: focused ? TvOptionBar.focusRingKey : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: _ringDecoration(
        focused: focused,
        ring: ring,
        radius: radius,
        fill: focused ? Colors.white.withAlpha(28) : Colors.transparent,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            // §versionSelected — la SÉLECTION se marque d'une coche (non
            // chromatique, comme la feuille du téléphone) ; le FOCUS, lui, est
            // l'anneau. Deux signaux, jamais confondus.
            child: item.selected
                ? Icon(Icons.check_circle_rounded, color: kAccentPrimary, size: 20)
                : (item.icon == null
                    ? null
                    : Icon(item.icon, color: Colors.white70, size: 18)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight:
                        item.selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (item.detail != null)
                  Text(
                    item.detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// §tvSeekBar — Le repère de la barre de progression : un anneau autour de
/// la position visée (couleur de focus du thème, rayon du thème — §btnShape)
/// et, au-dessus, l'heure visée avec l'écart à la lecture (« 42:10 · +3:20 »).
///
/// Posé PAR-DESSUS la barre de `PlayerControls` (même largeur) ; rien n'y est
/// focusable, tout vient de [controller]. La lecture continue pendant qu'on
/// déplace le repère : seul OK la déplace.
class TvSeekMarker extends StatelessWidget {
  const TvSeekMarker({
    super.key,
    required this.controller,
    required this.position,
    required this.duration,
    this.trackInset = 14,
  });

  final TvOptionsController controller;
  final Duration position;
  final Duration duration;

  /// Marge horizontale de la piste du `Slider` (rayon de son halo).
  final double trackInset;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.seekOpen || duration <= Duration.zero) {
          return const SizedBox.shrink();
        }
        final ext = Theme.of(context).extension<AetherThemeExtension>();
        final Color ring = ext?.focusGlowColor ?? kAccentPrimary;
        final double radius = ext?.borderRadius ?? 12;
        final Duration target = controller.seekTarget;
        final double frac =
            (target.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
        final String delta = formatSeekDelta(target - position);
        final String label = delta.isEmpty
            ? formatPlayerTime(target)
            : '${formatPlayerTime(target)}  $delta';
        return LayoutBuilder(builder: (context, c) {
          final double w = c.maxWidth;
          final double h = c.maxHeight.isFinite ? c.maxHeight : 28;
          final double x = trackInset + frac * (w - 2 * trackInset);
          const double size = 22;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: x - size / 2,
                top: (h - size) / 2,
                child: Container(
                  key: TvOptionBar.focusRingKey,
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(radius.clamp(0, size / 2)),
                    border: Border.all(color: ring, width: 2.6),
                    boxShadow: [
                      BoxShadow(color: ring.withAlpha(140), blurRadius: 12),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: x - 80,
                width: 160,
                bottom: h / 2 + size / 2 + 6,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(200),
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: ring.withAlpha(160)),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        });
      },
    );
  }
}
