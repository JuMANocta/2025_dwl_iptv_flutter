import 'dart:async';
import 'package:flutter/material.dart';

/// §snackTheme — Helper centralisé pour les toasts (SnackBar).
///
/// Trois garanties vs `ScaffoldMessenger.of(context).showSnackBar(...)` brut :
///   1. **Pas d'empilement** : `hideCurrentSnackBar()` avant affichage → un seul
///      toast visible (le dernier gagne).
///   2. **Fermeture garantie** : on récupère le contrôleur retourné et on force
///      `controller.close()` via un `Timer` Dart après `duration`. Indispensable
///      car le timer interne du SnackBar peut être « orphelin » si le Scaffold
///      hôte est reconstruit (ex. rebuild sur un `ValueNotifier`) → toast qui
///      reste affiché indéfiniment.
///   3. **Durée bornée** : 2 s par défaut, jamais plus de 6 s.
///
/// Le rendu visuel (couleurs, forme flottante) vient du `SnackBarThemeData`
/// global de `themes.dart` → ne PAS re-spécifier de couleur ici.
class AppSnackBar {
  AppSnackBar._();

  static const Duration _maxDuration = Duration(seconds: 6);

  /// Affiche un toast simple (texte). Purge le toast courant + fermeture forcée.
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    final capped = duration > _maxDuration ? _maxDuration : duration;
    showCustom(
      context,
      SnackBar(content: Text(message), duration: capped, action: action),
    );
  }

  /// Variante pour un [SnackBar] déjà construit (contenu riche / action UNDO).
  static void showCustom(BuildContext context, SnackBar snackBar) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    showVia(messenger, snackBar);
  }

  /// Variante quand le [ScaffoldMessengerState] a été capturé à l'avance
  /// (ex. avant un `Navigator.pop` qui invalide le contexte de la bottom sheet).
  static void showVia(ScaffoldMessengerState messenger, SnackBar snackBar) {
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(snackBar);
    // Filet de sécurité : ferme CE toast précis après sa durée (+150 ms de
    // marge), même si son timer interne ne se déclenche pas (Scaffold hôte
    // reconstruit → timer orphelin).
    final d = snackBar.duration > _maxDuration ? _maxDuration : snackBar.duration;
    Timer(d + const Duration(milliseconds: 150), () {
      try {
        controller.close();
      } catch (_) {}
    });
  }
}
