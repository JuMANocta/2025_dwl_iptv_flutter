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
/// Si tu veux que le PREMIER bouton soit focused à l'ouverture sur TV, place
/// un `Focus(autofocus: true)` ou un `FocusableCard(autofocus: true)` autour
/// de ton premier élément cliquable dans le builder.
Future<T?> showAdaptiveActionSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = true,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  Color? backgroundColor,
}) {
  if (PlatformTv.isTv) {
    return showDialog<T>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final cs = Theme.of(ctx).colorScheme;
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
              child: SingleChildScrollView(
                child: Builder(builder: builder),
              ),
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
