import 'package:flutter/material.dart';
import '../../core/utils/platform_tv.dart';

/// Helper "bottom sheet vs dialog TV" (§3c-4).
///
/// Sur **mobile** : ouvre un `showModalBottomSheet` standard (comportement
/// historique, drag handle visible, scroll vertical sur tout l'écran).
///
/// Sur **Android TV / Fire TV** (`PlatformTv.isTv` true) : ouvre un `Dialog`
/// centré, encadré à 60% de la largeur d'écran, scrollable, avec un
/// `FocusTraversalGroup` actif pour que la navigation D-pad reste piégée
/// dans le modal. La touche `Back` ferme le dialog (comportement par défaut).
///
/// Le `builder` reçoit le contexte du modal — son contenu (Column, ListTile,
/// etc.) n'a pas à être adapté : il fonctionne dans les deux modes. Tous les
/// `Navigator.pop(ctx, ...)` à l'intérieur fonctionnent à l'identique.
///
/// §3c Phase 3 — Sur TV, le PREMIER élément focusable du modal est
/// automatiquement focusé à l'ouverture (post-frame `nextFocus()`), donc plus
/// besoin d'un `autofocus` manuel dans chaque builder.
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
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: _TvAutofocusFirst(child: content),
            ),
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

/// Donne le focus au premier élément focusable du modal à l'ouverture (TV).
/// 2 post-frames pour laisser le contenu (FutureBuilder TMDB, etc.) se monter.
class _TvAutofocusFirst extends StatefulWidget {
  final Widget child;
  const _TvAutofocusFirst({required this.child});

  @override
  State<_TvAutofocusFirst> createState() => _TvAutofocusFirstState();
}

class _TvAutofocusFirstState extends State<_TvAutofocusFirst> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).nextFocus();
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
