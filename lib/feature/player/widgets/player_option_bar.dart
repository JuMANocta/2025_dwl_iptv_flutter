import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';

import '../../../core/themes/aether_theme_extension.dart';
import '../../../core/themes/colors.dart';
import '../../../core/utils/platform_tv.dart';
import '../../../l10n/app_localizations.dart';

// ─── §tvPlayerPanel + §playerPanel — les options du lecteur, DANS la vidéo ──
//
// À la télécommande, les boutons de la barre du lecteur étaient des
// `GestureDetector` non focusables : la seule porte vers les réglages était ↑,
// qui ouvrait un Dialog centré — le film disparaissait derrière, puis un
// second Dialog par réglage. Ici, chaque réglage est un bouton de la barre du
// bas, et sa liste s'ouvre juste au-dessus de lui, dans l'image.
//
// §playerPanel (2026-09-22) — C'est désormais LE menu du lecteur, sur TV ET au
// doigt (téléphone) : un tap sur un bouton ouvre sa liste au-dessus de lui, un
// tap sur une ligne l'applique et referme, un tap à côté referme. Les boutons
// ont tous la même taille, valeur ou pas ([playerOptionChipSize]), la rangée
// est centrée, et les quatre surfaces peintes sur l'image (bouton, liste,
// ligne, pastille du repère) portent le même rayon planché
// ([playerSurfaceRadius]).
//
// ⛔ Pas de focus `dpad` : toute la vidéo est UN `DpadFocusable` racine
// (`player_page.dart`) qui consomme les touches, et un focusable imbriqué n'y
// serait candidat nulle part (§dpadChildFocus). La navigation est donc un
// AUTOMATE pur ([PlayerOptionsController]) auquel la racine délègue OK, les
// flèches et Retour ; la rangée et la liste dessinent elles-mêmes l'anneau de
// focus sur l'élément courant.
//
// ⛔ Sur TV, rien de tactile n'est ajouté (ni `GestureDetector`, ni `InkWell`,
// ni `Focus`) : un focusable de plus DONNERAIT le focus à la télécommande dès
// que rien n'en a (§touchNoFocus). Les cibles tactiles n'existent qu'au doigt.

/// §tourFix — LA liste des vitesses de lecture, unique pour toute l'app.
///
/// Elle existait en DOUBLE (dans la feuille d'options et dans
/// `PlayerControls._speeds`), chacune alimentant son propre état : le badge
/// inline et la coche du sous-menu pouvaient se contredire (badge TV figé à
/// 1.0×). La vitesse n'a plus qu'un propriétaire (`_PlayerPageState._speed`)
/// et une seule liste — celle-ci.
const List<double> kPlaybackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// Les boutons de la rangée, dans l'ordre d'affichage.
enum PlayerOptionKind { nextEpisode, audio, subtitles, speed, fit, quality, stats }

/// Une ligne de liste.
class PlayerOptionItem {
  const PlayerOptionItem({
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
class PlayerOptionButton {
  const PlayerOptionButton({
    required this.kind,
    required this.icon,
    required this.title,
    this.value,
    this.items,
    this.onAction,
    this.leavesRow = false,
  }) : assert((items == null) != (onAction == null));

  final PlayerOptionKind kind;
  final IconData icon;
  final String title;

  /// L'état courant, sous le titre (« Français », « 1× », « Coupés »…).
  final String? value;

  /// Relue à chaque image : les coches suivent l'état du lecteur.
  final List<PlayerOptionItem> Function()? items;
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
Duration playerSeekStep(Duration held) {
  if (held < const Duration(milliseconds: 500)) return const Duration(seconds: 10);
  if (held < const Duration(milliseconds: 1500)) return const Duration(seconds: 30);
  if (held < const Duration(milliseconds: 2500)) return const Duration(minutes: 1);
  return const Duration(minutes: 5);
}

/// §tvSeekBar — [target] borné à [0, total].
Duration playerSeekClamp(Duration target, Duration total) {
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
class PlayerSeekSource {
  const PlayerSeekSource({
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
///
/// §playerPanel — Au doigt, [tapButton], [tapItem] et [dismiss] passent par
/// les MÊMES chemins que OK et Retour ; seule différence : il n'y a pas de
/// niveau RANGÉE (voir [byTouch]).
class PlayerOptionsController extends ChangeNotifier {
  List<PlayerOptionButton> _buttons = const [];
  bool _active = false;
  int _index = 0;
  PlayerOptionKind? _lastUsed;

  /// §playerPanel — La rangée a été ouverte AU DOIGT.
  bool _byTouch = false;

  bool _listOpen = false;
  int _listIndex = 0;

  /// Liste qui REMPLACE celle du bouton (résultats de la recherche de
  /// sous-titres en ligne), jusqu'à la fermeture.
  List<PlayerOptionItem>? _override;

  /// Change à chaque ouverture, remplacement ou fermeture de liste : une
  /// application qui aboutit après coup ne referme pas une AUTRE liste.
  int _listToken = 0;

  bool _disposed = false;

  // ── §tvSeekBar — quatrième niveau : la barre de progression ──────────────

  /// Posée par le lecteur à chaque image ; `null` = pas de barre (direct).
  PlayerSeekSource? seekSource;

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

  List<PlayerOptionButton> get buttons => _buttons;
  bool get active => _active;
  int get index => _index;
  bool get listOpen => _listOpen;
  int get listIndex => _listIndex;
  PlayerOptionKind? get lastUsed => _lastUsed;

  /// §playerPanel — Vrai quand la rangée a été ouverte au doigt. Au toucher
  /// il n'existe pas d'état « rangée focalisée » : toute fermeture rend la
  /// vidéo ([active] faux), sinon le `PopScope(canPop: !active)` du lecteur
  /// avalerait le Retour suivant ; et l'anneau de focus ne se dessine pas
  /// (rien n'a le focus au toucher). Une touche ([open], [move], [select])
  /// rend la main à l'automate de la télécommande (clavier, manette).
  bool get byTouch => _byTouch;

  PlayerOptionButton? get current =>
      (_index >= 0 && _index < _buttons.length) ? _buttons[_index] : null;

  /// Les lignes de la liste ouverte (vide si aucune).
  List<PlayerOptionItem> get items {
    if (!_listOpen) return const [];
    return _override ?? current?.items?.call() ?? const [];
  }

  /// Pose les boutons du moment (appelé pendant le `build` du lecteur : ne
  /// notifie pas). Le bouton courant est suivi par son GENRE : l'apparition de
  /// « Qualité » ne déplace pas le focus.
  void syncButtons(List<PlayerOptionButton> next) {
    final PlayerOptionKind? kind = current?.kind;
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
    if (i < 0) i = _buttons.indexWhere((b) => b.kind == PlayerOptionKind.audio);
    _index = i < 0 ? 0 : i;
    _active = true;
    _byTouch = false;
    _closeList();
    notifyListeners();
    return true;
  }

  bool move(TraversalDirection dir) {
    if (!_active) return false;
    _leaveTouch();
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
        final Duration step = playerSeekStep(held);
        final Duration next = playerSeekClamp(
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
    _leaveTouch();
    return _select();
  }

  /// OK, commun à la télécommande et au doigt ([tapButton], [tapItem]).
  bool _select() {
    if (_seekOpen) {
      // OK = aller au repère ; le focus RESTE sur la barre.
      seekSource?.commit(_seekTarget);
      notifyListeners();
      return true;
    }
    final PlayerOptionButton? b = current;
    if (b == null) return true;
    _lastUsed = b.kind;
    if (_listOpen) {
      final List<PlayerOptionItem> list = items;
      if (list.isEmpty) return true;
      final PlayerOptionItem item = list[_listIndex.clamp(0, list.length - 1)];
      final int token = _listToken;
      item.onSelect().catchError((Object e) {
        debugPrint('⚠️ §tvPlayerPanel — ligne non appliquée : $e');
        return false;
      }).then((bool done) {
        if (_disposed || !done) return;
        if (_listOpen && token == _listToken) {
          // Au doigt, pas de rangée focalisée : appliquer rend la vidéo.
          if (_byTouch) {
            _reset();
          } else {
            _closeList();
          }
          notifyListeners();
        }
      });
      return true;
    }
    if (b.items != null) {
      final List<PlayerOptionItem> list = b.items!();
      _listOpen = true;
      _override = null;
      _listToken++;
      final int sel = list.indexWhere((it) => it.selected);
      _listIndex = sel < 0 ? 0 : sel;
      notifyListeners();
      return true;
    }
    b.onAction?.call();
    if (b.leavesRow || _byTouch) _reset();
    notifyListeners();
    return true;
  }

  /// Retour : referme la liste (focus rendu au bouton), sinon quitte la
  /// rangée — ou la barre de progression, en ABANDONNANT le déplacement non
  /// validé (§tvSeekBar). ⛔ Jamais au-delà : quitter le film n'est possible que depuis la
  /// vidéo (§tvOptionsBack). §playerPanel — au doigt, un seul niveau : la
  /// liste refermée, c'est la vidéo.
  bool back() {
    if (!_active) return false;
    if (_listOpen && !_byTouch) {
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

  /// §playerPanel — Au doigt : un tap sur le bouton [i]. Un bouton à liste
  /// l'ouvre, sur la ligne cochée (comme OK) ; celui dont la liste est déjà
  /// ouverte la referme ; un bouton à action agit tout de suite (comme OK),
  /// puis la vidéo reprend la main.
  void tapButton(int i) {
    if (i < 0 || i >= _buttons.length) return;
    if (_active && _listOpen && i == _index) {
      dismiss();
      return;
    }
    _active = true;
    _byTouch = true;
    _seekOpen = false;
    _lastSeekMove = null;
    if (_listOpen) _closeList();
    _index = i;
    _select();
  }

  /// §playerPanel — Au doigt : un tap sur la ligne [j] de la liste ouverte,
  /// appliquée par le chemin de OK. Aboutie, elle referme la liste ET rend la
  /// vidéo ; un échec (déjà dit par un toast) ou une liste remplacée (résultats
  /// des sous-titres en ligne, [replaceList]) la laisse ouverte.
  void tapItem(int j) {
    if (!_active || !_listOpen || j < 0 || j >= items.length) return;
    _byTouch = true;
    _listIndex = j;
    _select();
  }

  /// §playerPanel — Au doigt : un tap à côté de la liste. Referme sans rien
  /// appliquer et rend la vidéo.
  void dismiss() => close();

  /// Remplace la liste ouverte du bouton [kind] (résultats d'une recherche).
  /// Sans effet si cette liste n'est plus ouverte.
  void replaceList(PlayerOptionKind kind, List<PlayerOptionItem> next) {
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
    _byTouch = false;
    _seekOpen = false;
    _lastSeekMove = null;
    _closeList();
  }

  /// Une touche après un tap (clavier, manette sur un téléphone) : l'anneau
  /// revient, et Retour retrouve ses deux niveaux.
  void _leaveTouch() {
    if (!_byTouch) return;
    _byTouch = false;
    notifyListeners();
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
String playerSpeedLabel(double speed, AppLocalizations l10n) =>
    l10n.tvOptSpeedValue(NumberFormat.decimalPattern(l10n.localeName)
        .format(speed));

// ─── §playerPanel — la forme : taille commune, rayon planché ────────────────

/// §playerPanel — Écart constant entre deux boutons de la rangée.
const double kPlayerOptionGap = 8;

/// §playerPanel — Plancher du rayon des surfaces peintes sur la vidéo.
const double kPlayerSurfaceMinRadius = 12;

/// Taille PRÉFÉRÉE d'un bouton. Mesurée en Roboto (la police de l'app) :
/// TV, 98 px de texte = « Format d'image » relevé à 13,75 px par
/// `TvSmallTextScaler` (96 px) ; au doigt, 78 px = « Format d'image » à 11 px
/// (77) et « Automatique » à 13 px gras (75). À 104 px de large, la valeur la
/// plus fréquente se lisait « Automa… ».
const Size _kTvChip = Size(146, 58);
const Size _kTouchChip = Size(120, 52);

/// Au doigt, un bouton ne rétrécit pas en dessous : au-delà, la rangée défile.
const double _kTouchChipMinWidth = 104;

/// Emplacement FIXE de l'icône : les textes commencent au même x partout.
const double _kChipIconSlot = 26;

/// Au doigt, l'échelle de texte du système est bornée DANS un bouton : sa
/// taille est fixe, il ne grandit pas avec le texte. (Sur TV, le plancher
/// §tvSmallText monte au plus de ×1,25 : jamais touché par cette borne.)
const double _kChipMaxTextScale = 1.3;

/// Métrique de texte EXPLICITE dans un bouton : hérité, le `bodyMedium` M3 du
/// thème (interligne 1,43, approche 0,25) faisait 19 px de haut pour un texte
/// de 13 px, et coupait « Automatique » à 76 px. Ici, deux lignes tiennent
/// toujours (au pire 2 × 13 × 1,3 × 1,2 = 41 px sur 44 au doigt).
const double _kChipLineHeight = 1.2;

/// Écart entre le haut du bouton et le bas de sa liste, et marge minimale de
/// la liste aux bords de l'écran.
const double _kListLift = 10;
const double _kListEdge = 8;
const double _kListWidth = 340;

/// §playerPanel — Le rayon des surfaces peintes SUR la vidéo (bouton, liste,
/// ligne, pastille et repère §tvSeekBar) : celui du thème, jamais sous
/// [kPlayerSurfaceMinRadius].
///
/// 5 thèmes sur 9 ont un rayon de 2 à 8 px : sur une image, ça lit « carré ».
/// Un PLANCHER, jamais un rayon imposé (même logique que `TvSmallTextScaler`,
/// §tvSmallText) : le thème garde la main dès qu'il atteint 12. ⛔ Entorse
/// ASSUMÉE à §btnShape (bouton = rayon du thème) : ici on peint sur une image.
double playerSurfaceRadius(BuildContext context) => math.max(
      Theme.of(context).extension<AetherThemeExtension>()?.borderRadius ??
          kPlayerSurfaceMinRadius,
      kPlayerSurfaceMinRadius,
    );

/// §playerPanel — La taille COMMUNE des [count] boutons de la rangée, valeur
/// ou pas (avant, un bouton sans valeur — « Épisode suivant » — était plus
/// petit que les autres).
///
/// La taille préférée, réduite juste ce qu'il faut pour que la rangée tienne
/// dans [maxWidth]. Sur TV elle tient TOUJOURS, sans défilement (960 dp de
/// large : sept boutons passent à 126) ; au doigt, jamais sous 104 — au-delà,
/// la rangée défile.
Size playerOptionChipSize({
  required bool isTv,
  int count = 0,
  double maxWidth = double.infinity,
}) {
  final Size pref = isTv ? _kTvChip : _kTouchChip;
  if (count <= 0 || !maxWidth.isFinite) return pref;
  final double fit = (maxWidth - kPlayerOptionGap * (count - 1)) / count;
  final double width = isTv
      ? math.max(0.0, math.min(pref.width, fit))
      : fit.clamp(_kTouchChipMinWidth, pref.width);
  // Arrondi vers le bas : la somme ne dépasse jamais la largeur donnée.
  return Size(width.floorToDouble(), pref.height);
}

Color _ringColor(BuildContext context) =>
    Theme.of(context).extension<AetherThemeExtension>()?.focusGlowColor ??
    kAccentPrimary;

/// §playerPanel — La cible tactile d'un bouton ou d'une ligne, AU DOIGT
/// seulement ([onTap] nul sur TV) : ⛔ ni `InkWell` ni `Focus` — un focusable
/// de plus donnerait un faux focus à la télécommande (§touchNoFocus).
Widget _touchTarget({required VoidCallback? onTap, required Widget child}) {
  if (onTap == null) return child;
  return Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    ),
  );
}

/// §tvPlayerPanel — La rangée de boutons et, au-dessus du bouton courant, sa
/// liste. Rien n'y est focusable : l'anneau se DESSINE sur l'élément courant
/// de [controller].
///
/// §playerPanel — La même rangée sert au doigt : chaque bouton et chaque
/// ligne y devient une cible tactile, et un tap à côté de la liste la referme.
/// La liste est rendue dans l'`Overlay` (`OverlayPortal`) : posée hors des
/// bornes de la rangée, elle n'y recevrait aucun tap.
class PlayerOptionBar extends StatefulWidget {
  const PlayerOptionBar({super.key, required this.controller, this.isTv});

  final PlayerOptionsController controller;

  /// `null` = [PlatformTv.isTv], la seule porte TV. Forcé par les tests —
  /// même idiome que `confirmOrUndo(isTv:)` : `PlatformTv.isTv` est un cache
  /// statique, toujours faux sous `flutter test`.
  final bool? isTv;

  /// Posée sur l'élément qui porte l'anneau (tests).
  static const Key focusRingKey = ValueKey<String>('tv_option_focus_ring');

  /// Posée sur le bouton de ce genre (tests : taille, position).
  static Key chipKey(PlayerOptionKind kind) =>
      ValueKey<String>('player_option_chip_${kind.name}');

  @override
  State<PlayerOptionBar> createState() => _PlayerOptionBarState();
}

class _PlayerOptionBarState extends State<PlayerOptionBar> {
  final List<LayerLink> _links = [];
  final List<GlobalKey> _chipKeys = [];
  final List<GlobalKey> _itemKeys = [];
  final ScrollController _listScroll = ScrollController();
  final OverlayPortalController _portal = OverlayPortalController();
  int _shownListIndex = -1;

  bool get _isTv => widget.isTv ?? PlatformTv.isTv;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncPortal);
    _syncPortal();
  }

  @override
  void didUpdateWidget(PlayerOptionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncPortal);
      widget.controller.addListener(_syncPortal);
      _syncPortal();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncPortal);
    _listScroll.dispose();
    super.dispose();
  }

  /// La liste n'est dans l'`Overlay` que lorsqu'elle est ouverte. Suivi sur
  /// les notifications de l'automate, jamais pendant un `build` (l'`Overlay`
  /// l'interdit) : une notification tombée en plein build est reportée à la
  /// fin de l'image. Une liste refermée sans notification (`syncButtons`, le
  /// bouton a disparu) ne dessine rien jusqu'à la suivante.
  void _syncPortal() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncPortal());
      return;
    }
    final c = widget.controller;
    final bool want = c.active && c.listOpen;
    if (want == _portal.isShowing) return;
    if (want) {
      _portal.show();
    } else {
      _portal.hide();
    }
  }

  LayerLink _linkAt(int i) {
    while (_links.length <= i) {
      _links.add(LayerLink());
    }
    return _links[i];
  }

  GlobalKey _chipKeyAt(int i) {
    while (_chipKeys.length <= i) {
      _chipKeys.add(GlobalKey());
    }
    return _chipKeys[i];
  }

  GlobalKey _itemKeyAt(int i) {
    while (_itemKeys.length <= i) {
      _itemKeys.add(GlobalKey());
    }
    return _itemKeys[i];
  }

  /// Le bouton [i] à l'écran, tel que posé à l'image précédente (sa taille
  /// est fixe : ouvrir sa liste ne le déplace pas). `null` s'il n'est pas
  /// encore posé.
  Rect? _chipRect(int i) {
    final BuildContext? ctx =
        i < _chipKeys.length ? _chipKeys[i].currentContext : null;
    final RenderObject? box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
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
        final buttons = c.buttons;
        if (buttons.isEmpty) return const SizedBox.shrink();
        if (!c.listOpen) _shownListIndex = -1;
        final bool isTv = _isTv;
        final Color ring = _ringColor(context);
        final double radius = playerSurfaceRadius(context);

        return OverlayPortal(
          controller: _portal,
          overlayChildBuilder: _buildList,
          child: LayoutBuilder(builder: (context, constraints) {
            final Size chip = playerOptionChipSize(
              isTv: isTv,
              count: buttons.length,
              maxWidth: constraints.maxWidth,
            );
            final Widget row = MediaQuery.withClampedTextScaling(
              maxScaleFactor: _kChipMaxTextScale,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < buttons.length; i++) ...[
                    if (i > 0) const SizedBox(width: kPlayerOptionGap),
                    CompositedTransformTarget(
                      key: _chipKeyAt(i),
                      link: _linkAt(i),
                      child: _OptionChip(
                        button: buttons[i],
                        size: chip,
                        isTv: isTv,
                        // Au doigt, rien n'a le focus : pas d'anneau.
                        focused: !c.byTouch &&
                            c.active &&
                            i == c.index &&
                            !c.listOpen &&
                            !c.seekOpen,
                        // La liste est ouverte AU-DESSUS de ce bouton : il le
                        // dit, sans porter l'anneau (c'est la ligne qui l'a).
                        holdsList: c.active && i == c.index && c.listOpen,
                        ring: ring,
                        radius: radius,
                        onTap: isTv ? null : () => c.tapButton(i),
                      ),
                    ),
                  ],
                ],
              ),
            );
            // Centrée ; au doigt, elle défile si elle déborde (téléphone en
            // portrait, sept boutons), et reste centrée quand elle tient.
            if (isTv || !constraints.hasBoundedWidth) return Center(child: row);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Center(child: row),
              ),
            );
          }),
        );
      },
    );
  }

  /// La liste ouverte, dans l'`Overlay`, au-dessus de son bouton. Au doigt,
  /// une barrière transparente derrière elle : un tap à côté la referme sans
  /// rien appliquer.
  Widget _buildList(BuildContext context) {
    final c = widget.controller;
    if (!c.active || !c.listOpen || c.buttons.isEmpty) {
      return const SizedBox.shrink();
    }
    final bool isTv = _isTv;
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    final double width = math.min(_kListWidth, screen.width - 2 * _kListEdge);
    final Rect? chip = _chipRect(c.index);
    // Moitié gauche : la liste s'aligne sur le bord gauche du bouton ;
    // moitié droite : sur son bord droit — elle ne sort pas de l'écran.
    final bool leftHalf = chip == null
        ? c.index < c.buttons.length / 2
        : chip.center.dx < screen.width / 2;
    double dx = 0;
    double maxHeight = screen.height * 0.55;
    if (chip != null) {
      // Un bouton près du bord (rangée qui défile au doigt) : la liste est
      // ramenée dans l'écran.
      final double natural = leftHalf ? chip.left : chip.right - width;
      final double lo = pad.left + _kListEdge;
      final double hi = screen.width - pad.right - _kListEdge - width;
      dx = (hi < lo ? lo : natural.clamp(lo, hi)) - natural;
      maxHeight = math.min(maxHeight, chip.top - _kListLift - pad.top - _kListEdge);
    }
    _revealCurrent(c.listIndex);
    return Stack(
      children: [
        if (!isTv)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: c.dismiss,
            ),
          ),
        Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _linkAt(c.index),
            showWhenUnlinked: false,
            targetAnchor: leftHalf ? Alignment.topLeft : Alignment.topRight,
            followerAnchor:
                leftHalf ? Alignment.bottomLeft : Alignment.bottomRight,
            offset: Offset(dx, -_kListLift),
            child: _OptionList(
              title: c.current?.title ?? '',
              items: c.items,
              current: c.listIndex,
              showRing: !c.byTouch,
              ring: _ringColor(context),
              radius: playerSurfaceRadius(context),
              width: width,
              maxHeight: math.max(80, maxHeight),
              scroll: _listScroll,
              keyAt: _itemKeyAt,
              onTapItem: isTv ? null : c.tapItem,
            ),
          ),
        ),
      ],
    );
  }
}

/// L'anneau de focus, dessiné : bordure + halo à la couleur du thème, au
/// rayon planché (§playerPanel) — la même forme que ce qu'il entoure. Sert
/// aussi, sans focus, de décor aux surfaces posées sur la vidéo.
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
    required this.size,
    required this.isTv,
    required this.focused,
    required this.holdsList,
    required this.ring,
    required this.radius,
    required this.onTap,
  });

  final PlayerOptionButton button;
  final Size size;
  final bool isTv;
  final bool focused;
  final bool holdsList;
  final Color ring;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String? value = button.value;
    return _touchTarget(
      onTap: onTap,
      child: SizedBox.fromSize(
        key: PlayerOptionBar.chipKey(button.kind),
        size: size,
        // `DecoratedBox` + `Padding`, pas `Container` : celui-ci ajoute la
        // bordure à la marge intérieure, et le texte bougeait (et se coupait)
        // quand l'anneau passe de 1 à 2,6 px.
        child: DecoratedBox(
          key: focused ? PlayerOptionBar.focusRingKey : null,
          // Sur la vidéo : voile sombre, texte blanc (légitime, §lightTheme).
          decoration: _ringDecoration(
            focused: focused,
            ring: ring,
            radius: radius,
            fill: kImageScrim.withAlpha(focused || holdsList ? 170 : 110),
            idleBorder: holdsList ? ring.withAlpha(140) : kOnImageSubtle,
          ),
          child: Padding(
            padding:
                EdgeInsets.symmetric(horizontal: isTv ? 8 : 6, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: _kChipIconSlot,
                  child: Icon(button.icon, color: kOnImage, size: 22),
                ),
                SizedBox(width: isTv ? 6 : 4),
                Expanded(
                  child: Column(
                    // Sans valeur, le titre est centré dans la même hauteur.
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        button.title,
                        // Seul, le titre peut prendre deux lignes (« Épisode
                        // suivant » au doigt).
                        maxLines: value == null ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: kOnImage.withAlpha(value == null ? 255 : 180),
                          fontSize: value == null ? 13 : 11,
                          fontWeight:
                              value == null ? FontWeight.w700 : FontWeight.w500,
                          height: _kChipLineHeight,
                          letterSpacing: 0,
                        ),
                      ),
                      if (value != null)
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: kOnImage,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: _kChipLineHeight,
                            letterSpacing: 0,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
    required this.showRing,
    required this.ring,
    required this.radius,
    required this.width,
    required this.maxHeight,
    required this.scroll,
    required this.keyAt,
    required this.onTapItem,
  });

  final String title;
  final List<PlayerOptionItem> items;
  final int current;
  final bool showRing;
  final Color ring;
  final double radius;
  final double width;
  final double maxHeight;
  final ScrollController scroll;
  final GlobalKey Function(int) keyAt;

  /// Au doigt seulement (nul sur TV).
  final ValueChanged<int>? onTapItem;

  @override
  Widget build(BuildContext context) {
    final ValueChanged<int>? onTapItem = this.onTapItem;
    return Container(
      width: width,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      decoration: _ringDecoration(
        focused: false,
        ring: ring,
        radius: radius,
        fill: kImageScrim.withAlpha(215),
        idleBorder: kOnImageSubtle,
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
                      child: _touchTarget(
                        onTap: onTapItem == null ? null : () => onTapItem(i),
                        child: _OptionLine(
                          item: items[i],
                          focused: showRing && i == current,
                          ring: ring,
                          radius: radius,
                          // Cible tactile de 48 dp au doigt.
                          minHeight: onTapItem == null ? 0 : 48,
                        ),
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
    required this.minHeight,
  });

  final PlayerOptionItem item;
  final bool focused;
  final Color ring;
  final double radius;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: focused ? PlayerOptionBar.focusRingKey : null,
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: _ringDecoration(
        focused: focused,
        ring: ring,
        radius: radius,
        fill: focused ? kOnImage.withAlpha(28) : Colors.transparent,
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
                    : Icon(item.icon, color: kOnImage.withAlpha(179), size: 18)),
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
                    color: kOnImage,
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
                    style: TextStyle(
                        color: kOnImage.withAlpha(153), fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// §tvSeekBar — Écart entre le repère et sa pastille d'heure.
const double _kSeekPillGap = 6;

/// §tvSeekBar — Largeur maximale de la pastille (« 1:02:05  +1:02:05 »
/// tient) : c'est la place qu'on exige d'un côté avant d'y poser la pastille.
const double _kSeekPillMaxWidth = 160;

/// §tvSeekBar — Le repère de la barre de progression : un anneau autour de
/// la position visée (couleur de focus du thème, rayon planché — §playerPanel)
/// et, À CÔTÉ, l'heure visée avec l'écart à la lecture (« 42:10  +3:20 »).
///
/// §playerPanel — La pastille était posée AU-DESSUS du repère : elle
/// recouvrait le bas du bouton de la rangée d'options, 6 px plus haut
/// (recette TV du 2026-09-22 : « Hidden » masqué sous « 00:52 »). Elle reste
/// désormais DANS la hauteur de la barre, à la hauteur du repère : ni la
/// rangée au-dessus, ni le temps et le cadenas au-dessous ne peuvent être
/// recouverts, quelle que soit leur mise en page. Elle se pose du côté opposé
/// à la lecture en cours (le curseur blanc reste visible), et change de côté
/// si la place manque.
///
/// Posé PAR-DESSUS la barre de `PlayerControls` (même largeur) ; rien n'y est
/// focusable, tout vient de [controller]. La lecture continue pendant qu'on
/// déplace le repère : seul OK la déplace.
class PlayerSeekMarker extends StatelessWidget {
  const PlayerSeekMarker({
    super.key,
    required this.controller,
    required this.position,
    required this.duration,
    this.trackInset = 14,
  });

  final PlayerOptionsController controller;
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
        final Color ring = _ringColor(context);
        final double radius = playerSurfaceRadius(context);
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
          // Du côté opposé à la lecture ; de l'autre si la place manque.
          final double reach = size / 2 + _kSeekPillGap + _kSeekPillMaxWidth;
          bool right = target >= position;
          if (right && x + reach > w) right = false;
          if (!right && x - reach < 0) right = true;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: x - size / 2,
                top: (h - size) / 2,
                child: Container(
                  key: PlayerOptionBar.focusRingKey,
                  width: size,
                  height: size,
                  // Le repère est plus petit que le rayon : borné à un cercle.
                  decoration: _ringDecoration(
                    focused: true,
                    ring: ring,
                    radius: radius.clamp(0, size / 2),
                    fill: Colors.transparent,
                  ),
                ),
              ),
              // Même hauteur et même ligne que le repère : jamais hors de la
              // barre.
              Positioned(
                left: right ? x + size / 2 + _kSeekPillGap : null,
                right: right ? null : w - x + size / 2 + _kSeekPillGap,
                top: (h - size) / 2,
                height: size,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: _kChipMaxTextScale,
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: _kSeekPillMaxWidth),
                    child: DecoratedBox(
                      decoration: _ringDecoration(
                        focused: false,
                        ring: ring,
                        radius: radius,
                        fill: kImageScrim.withAlpha(200),
                        idleBorder: ring.withAlpha(160),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: kOnImage,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              // Métrique explicite, comme dans les boutons :
                              // une ligne tient dans les 22 px du repère.
                              height: _kChipLineHeight,
                              letterSpacing: 0,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
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
