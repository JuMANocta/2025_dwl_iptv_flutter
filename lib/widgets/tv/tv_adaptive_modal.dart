import 'package:flutter/material.dart';
import 'package:dpad/dpad.dart';
import '../../core/utils/platform_tv.dart';

/// Helper "bottom sheet vs dialog TV" (§3c-4).
///
/// Sur **mobile** : ouvre un `showModalBottomSheet` standard (comportement
/// historique, drag handle visible, scroll vertical sur tout l'écran).
///
/// Sur **Android TV / Fire TV** (`PlatformTv.isTv` true) : ouvre un `Dialog`
/// centré, encadré à 60% de la largeur d'écran, scrollable, dans une
/// [DpadRegion] à bords `stop` pour que la navigation D-pad reste piégée dans le
/// modal. La touche `Back` ferme le dialog (comportement par défaut).
///
/// Le `builder` reçoit le contexte du modal — son contenu (Column, ListTile,
/// etc.) n'a pas à être adapté : il fonctionne dans les deux modes. Tous les
/// `Navigator.pop(ctx, ...)` à l'intérieur fonctionnent à l'identique.
///
/// §3c Phase 3 — Sur TV, le PREMIER élément focusable du modal est
/// automatiquement focusé à l'ouverture ([TvAutofocusFirst]), donc plus besoin
/// d'un `autofocus` manuel dans chaque builder.
///
/// `scrollable` (défaut true) : sur TV, enveloppe le contenu dans un
/// `SingleChildScrollView`. À passer à **false** si le `builder` fournit déjà
/// son propre scroll (ex: `EditAccountSheet`) — sinon double scroll = hauteur
/// non bornée.
Future<T?> showAdaptiveActionSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = true,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool scrollable = true,
  Color? backgroundColor,
}) {
  if (PlatformTv.isTv) {
    return showDialog<T>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final cs = Theme.of(ctx).colorScheme;
        Widget content = Builder(builder: builder);
        if (scrollable) {
          content = SingleChildScrollView(child: content);
        }
        return Dialog(
          backgroundColor: backgroundColor ?? cs.surface,
          insetPadding: EdgeInsets.symmetric(
            horizontal: size.width * 0.15,
            vertical: size.height * 0.08,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: size.width * 0.7,
              maxHeight: size.height * 0.85,
            ),
            child: DpadModalRegion(debugLabel: 'sheet', child: content),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: showDragHandle,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    backgroundColor: backgroundColor,
    builder: builder,
  );
}

/// §dpadAlign — Remplace `showDialog` pour tous les dialogs de l'application.
///
/// Les 21 `showDialog`/`AlertDialog` bruts du projet n'avaient **ni focus
/// initial, ni navigation D-pad correcte** : sur TV, l'utilisateur ouvrait une
/// confirmation sans savoir quel bouton était sélectionné. Ce wrapper leur donne
/// le même traitement que les action sheets — région D-pad à bords `stop` +
/// focus sur le premier élément — sans rien changer au contenu passé.
///
/// Sur mobile, le rendu est strictement celui de `showDialog` (l'autofocus est
/// réservé à la TV : un anneau de focus au tactile serait un artefact).
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useRootNavigator = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    useRootNavigator: useRootNavigator,
    builder: (ctx) => DpadModalRegion(
      debugLabel: 'dialog',
      child: Builder(builder: builder),
    ),
  );
}

/// §dpadAlign — Enveloppe commune des modals : focus piégé + focus initial.
///
/// `DpadEdgeBehavior.stop` consomme les touches directionnelles au bord de la
/// région : le focus ne peut pas s'échapper vers l'arrière-plan. C'est l'idiome
/// prévu par le package — l'ancien `FocusTraversalGroup(OrderedTraversalPolicy())`
/// piégeait bien le focus, mais au prix de la **traversée géométrique** : à
/// l'intérieur d'un modal, ←/→/↑/↓ retombaient sur un simple ordre de lecture.
class DpadModalRegion extends StatelessWidget {
  final Widget child;
  final String? debugLabel;

  const DpadModalRegion({super.key, required this.child, this.debugLabel});

  @override
  Widget build(BuildContext context) {
    return DpadRegion(
      debugLabel: debugLabel,
      horizontalEdge: DpadEdgeBehavior.stop,
      verticalEdge: DpadEdgeBehavior.stop,
      child: TvAutofocusFirst(child: child),
    );
  }
}

/// §dpadAlign — Donne le focus au premier élément focusable à l'ouverture (TV).
///
/// Deux post-frames pour laisser le contenu asynchrone (FutureBuilder TMDB,
/// listes chargées à l'ouverture…) se monter avant de chercher une cible.
///
/// Remplace les 18 copies de ce même `postFrame → FocusScope.nextFocus()` qui
/// avaient essaimé dans les pages de réglages.
/// §dpadAlign — Le focus courant appartient-il au sous-arbre de [context] ?
///
/// ⚠️ **Ne PAS remplacer par « quelque chose a-t-il le focus ? »** — c'était le
/// premier jet, et il cassait un cas réel : quand le panneau d'options du player
/// se ferme pour ouvrir le sélecteur de pistes, les deux opérations ont lieu
/// dans la même frame. L'ancien dialog est encore vivant pendant son animation
/// de sortie et détient encore le focus, donc le nouveau panneau croyait « il y
/// a déjà un focus, je ne le vole pas » et ne focalisait rien : plus rien ne
/// répondait à la télécommande.
///
/// La bonne question n'est pas « y a-t-il un focus ? » mais « le focus est-il
/// CHEZ MOI ? ».
bool hasFocusInside(BuildContext context) {
  final FocusNode? current = FocusManager.instance.primaryFocus;
  if (current == null || current is FocusScopeNode) return false;
  final FocusScopeNode scope = FocusScope.of(context);
  return identical(current.enclosingScope, scope) ||
      current.ancestors.contains(scope);
}

class TvAutofocusFirst extends StatefulWidget {
  final Widget child;

  /// Force le comportement hors TV (tests, ou écran qu'on veut focusable au
  /// clavier sur mobile). Par défaut, l'autofocus est réservé à la TV.
  final bool? enabled;

  const TvAutofocusFirst({super.key, required this.child, this.enabled});

  @override
  State<TvAutofocusFirst> createState() => _TvAutofocusFirstState();
}

class _TvAutofocusFirstState extends State<TvAutofocusFirst> {
  @override
  void initState() {
    super.initState();
    if (!(widget.enabled ?? PlatformTv.isTv)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (hasFocusInside(context)) return;
        FocusScope.of(context).nextFocus();
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
