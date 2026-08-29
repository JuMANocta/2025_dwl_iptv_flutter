import 'package:flutter/foundation.dart';

/// §bootStatus — Étape de démarrage en cours, publiée vers l'écran de boot.
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

/// §bootLog — Étape TERMINÉE, avec le temps qu'elle a réellement pris.
///
/// La durée n'est pas décorative : c'est le seul moyen de savoir où partent les
/// secondes du démarrage sur une TV, où il n'y a pas de logcat. On mesure avant
/// d'optimiser.
class BootStepDone {
  final String label;
  final Duration duration;

  const BootStepDone(this.label, this.duration);

  /// « 1,8 s » au-delà d'une seconde, « 240 ms » en dessous — on ne lit pas un
  /// chronomètre de la même façon selon l'ordre de grandeur.
  String get durationLabel {
    if (duration.inMilliseconds >= 1000) {
      return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s';
    }
    return '${duration.inMilliseconds} ms';
  }
}

abstract final class BootStatus {
  static const BootStep _initial = BootStep('// initialisation…');

  /// Écouté par l'écran de chargement via `ValueListenableBuilder`.
  static final ValueNotifier<BootStep> step = ValueNotifier<BootStep>(_initial);

  /// §bootLog — Étapes déjà franchies, dans l'ordre.
  ///
  /// ⚠️ **Notifieur SÉPARÉ de [step]** : la progression du parsing publie
  /// jusqu'à ~101 fois (cf. [report]). Si le journal écoutait le même notifieur,
  /// chaque pourcent reconstruirait toute la liste des étapes. Ici, l'historique
  /// ne bouge qu'au passage d'une étape à la suivante.
  static final ValueNotifier<List<BootStepDone>> history =
      ValueNotifier<List<BootStepDone>>(const <BootStepDone>[]);

  static String _label = _initial.label;

  /// Début de l'étape courante, pour mesurer sa durée à sa clôture.
  static DateTime _startedAt = DateTime.now();

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
  ///
  /// L'étape précédente est **close et horodatée** dans [history] — sauf la
  /// toute première (`// initialisation…`), qui n'est qu'un état d'attente.
  static void set(String label, {double? progress}) {
    final DateTime now = DateTime.now();
    if (_label != _initial.label) {
      history.value = <BootStepDone>[
        ...history.value,
        BootStepDone(_label, now.difference(_startedAt)),
      ];
    }
    _label = label;
    _startedAt = now;
    _lastBucket = progress == null ? -1 : _bucketOf(progress.clamp(0.0, 1.0));
    step.value = BootStep(label, progress: progress);
  }

  /// Met à jour la progression de l'étape courante.
  ///
  /// **Throttle indispensable** : le `onProgress` des parsers tombe très
  /// souvent (par lot d'entrées) et chaque notification déclenche un rebuild.
  /// On ne notifie donc qu'au changement de palier → une centaine de rebuilds
  /// au maximum pour tout le parsing, quelle que soit la taille de la playlist.
  ///
  /// N'ajoute JAMAIS d'entrée à [history] : la progression fait avancer l'étape
  /// courante, elle n'en crée pas de nouvelle.
  static void report(double value) {
    final v = value.clamp(0.0, 1.0);
    final bucket = _bucketOf(v);
    if (bucket == _lastBucket) return;
    _lastBucket = bucket;
    step.value = BootStep(_label, progress: v);
  }

  /// Clôt la dernière étape sans en ouvrir de nouvelle (fin du démarrage).
  static void complete(String label) {
    set(label, progress: 1);
  }

  /// Remet à l'état initial — le boot peut être rejoué (« Réessayer », fin
  /// d'onboarding, changement de compte).
  static void reset() {
    _label = _initial.label;
    _startedAt = DateTime.now();
    _lastBucket = -1;
    history.value = const <BootStepDone>[];
    step.value = _initial;
  }

  /// Temps écoulé depuis le début de l'étape courante — utilisé par le journal
  /// pour afficher la durée totale du démarrage.
  static Duration get elapsedTotal {
    Duration total = Duration.zero;
    for (final BootStepDone d in history.value) {
      total += d.duration;
    }
    return total;
  }
}
