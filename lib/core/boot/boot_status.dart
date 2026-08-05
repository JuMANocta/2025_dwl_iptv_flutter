import 'package:flutter/foundation.dart';

/// §bootStatus — Étape de démarrage en cours, publiée vers `_LoadingScreen`.
///
/// **Problème résolu** : l'écran de lancement affichait un texte FIGÉ
/// `'// initialisation…'` alors que le boot enchaîne des phases de durées très
/// différentes (vérification du compte, téléchargement réseau, parsing d'un
/// catalogue de plusieurs centaines de milliers d'entrées). Sur une grosse
/// playlist, l'utilisateur ne savait pas si ça travaillait ou si c'était bloqué.
class BootStep {
  /// Texte affiché, style terminal (`// …`).
  final String label;

  /// `null` = progression indéterminée (barre animée) ; `0..1` = déterminée.
  final double? progress;

  const BootStep(this.label, {this.progress});
}

abstract final class BootStatus {
  static const BootStep _initial = BootStep('// initialisation…');

  /// Écouté par l'écran de chargement via `ValueListenableBuilder`.
  static final ValueNotifier<BootStep> step = ValueNotifier<BootStep>(_initial);

  static String _label = _initial.label;

  /// Dernier palier NOTIFIÉ (-1 = aucun). Sert de throttle : voir [report].
  static int _lastBucket = -1;

  /// Palier de notification d'une progression : le pourcentage entier, avec un
  /// palier **101 réservé à la complétion exacte**.
  ///
  /// Sans ce palier dédié, la fin de parsing n'était jamais publiée : le
  /// dernier lot partage presque toujours le même pourcentage entier que le
  /// précédent (0,995 et 1,0 arrondissent tous deux à 100), donc la barre
  /// restait figée à 99,x % au lieu d'atteindre 100 %.
  static int _bucketOf(double v) => v >= 1.0 ? 101 : (v * 100).round();

  /// Passe à une nouvelle étape. [progress] `null` → barre indéterminée.
  static void set(String label, {double? progress}) {
    _label = label;
    _lastBucket =
        progress == null ? -1 : _bucketOf(progress.clamp(0.0, 1.0));
    step.value = BootStep(label, progress: progress);
  }

  /// Met à jour la progression de l'étape courante.
  ///
  /// **Throttle indispensable** : le `onProgress` des parsers tombe très
  /// souvent (par lot d'entrées) et chaque notification déclenche un rebuild.
  /// On ne notifie donc qu'au changement de palier → une centaine de rebuilds
  /// au maximum pour tout le parsing, quelle que soit la taille de la playlist.
  static void report(double value) {
    final v = value.clamp(0.0, 1.0);
    final bucket = _bucketOf(v);
    if (bucket == _lastBucket) return;
    _lastBucket = bucket;
    step.value = BootStep(_label, progress: v);
  }

  /// Remet à l'état initial — le boot peut être rejoué (« Réessayer », fin
  /// d'onboarding, changement de compte).
  static void reset() {
    _label = _initial.label;
    _lastBucket = -1;
    step.value = _initial;
  }
}
