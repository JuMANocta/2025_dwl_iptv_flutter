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

  /// §bootPercent — Complément vivant de l'étape : « 34 279 films », « 2/3 ».
  ///
  /// Un pourcentage AFFIRME qu'on avance ; un compteur qui monte le **prouve**.
  /// Sur une étape longue, c'est la seule chose qui distingue « ça travaille »
  /// de « c'est figé » quand la barre progresse lentement.
  final String? detail;

  const BootStep(this.label, {this.progress, this.detail});
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

  /// Progression courante, mémorisée pour que [setDetail] ne l'écrase pas.
  static double? _progress;

  /// Détail courant, mémorisé pour que [report] ne l'écrase pas.
  static String? _detail;

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
  static void set(String label, {double? progress, String? detail}) {
    final DateTime now = DateTime.now();
    if (_label != _initial.label) {
      history.value = <BootStepDone>[
        ...history.value,
        BootStepDone(_label, now.difference(_startedAt)),
      ];
    }
    _label = label;
    _startedAt = now;
    _progress = progress;
    // Le détail appartient à l'étape : changer d'étape le remet à zéro, sinon
    // « 34 279 films » resterait affiché sous « // prêt. ».
    _detail = detail;
    _lastBucket = progress == null ? -1 : _bucketOf(progress.clamp(0.0, 1.0));
    _pendingDetail = null;
    _lastDetailAt = DateTime.fromMillisecondsSinceEpoch(0);
    step.value = BootStep(label, progress: progress, detail: detail);
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
    _progress = v;
    // §bootDetailThrottle — un détail retenu part avec le palier suivant.
    if (_pendingDetail != null) {
      _detail = _pendingDetail;
      _pendingDetail = null;
      _lastDetailAt = DateTime.now();
    }
    step.value = BootStep(_label, progress: v, detail: _detail);
  }

  /// §bootPercent — Met à jour le **détail** de l'étape courante sans toucher à
  /// sa progression (« films · 24 100/53 781 »).
  ///
  /// ⚠️ Séparé de [report] plutôt que fusionné en un paramètre nommé : le
  /// rappel de progression des parsers est typé `void Function(double)` et
  /// circule à travers `ParsedPlaylistService`. Un second rappel indépendant
  /// n'oblige aucun appelant existant à changer de signature.
  ///
  /// Le débit est celui du parseur, qui n'émet qu'au changement de pourcentage
  /// entier — donc une centaine d'appels pour un catalogue entier, quel que
  /// soit son nombre d'entrées.
  /// §bootDetailThrottle (2026-09-06) — **Régulé à 4 publications par seconde.**
  ///
  /// Le parseur M3U publie son compteur d'entrées à CHAQUE tranche de 8 ms
  /// (~125 fois par seconde) : chaque publication reconstruisait tout le
  /// journal de boot (Column, polices, barre). Mesuré sur l'émulateur TV : la
  /// même analyse de 153 000 entrées prend **22 s** hors du boot et **73 s**
  /// pendant — l'écran mangeait deux tiers du thread principal. Un compteur
  /// lisible n'a pas besoin de plus de quelques rafraîchissements par seconde.
  static DateTime _lastDetailAt = DateTime.fromMillisecondsSinceEpoch(0);
  static String? _pendingDetail;
  static const Duration _detailEvery = Duration(milliseconds: 250);

  static void setDetail(String? detail) {
    if (detail == _detail) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastDetailAt) < _detailEvery) {
      // Trop tôt : on garde la valeur, elle partira avec la suivante ou au
      // changement d'étape (`set` republie l'état complet).
      _pendingDetail = detail;
      return;
    }
    _pendingDetail = null;
    _lastDetailAt = now;
    _detail = detail;
    step.value = BootStep(_label, progress: _progress, detail: detail);
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
    _progress = null;
    _detail = null;
    history.value = const <BootStepDone>[];
    step.value = _initial;
  }

  /// §bootLog — Recrache le journal chronométré vers `debugPrint`, donc vers le
  /// tampon de diagnostic (§tvLogs) et la console web.
  ///
  /// ⚠️ **C'est le seul instrument de mesure du démarrage sur un téléviseur** :
  /// il n'y a pas de logcat, et l'écran de boot disparaît au moment précis où
  /// l'on voudrait lire ses chiffres. Sans ce vidage, comparer un avant/après
  /// (§bootHydrate) supposerait de filmer l'écran.
  static void dumpToLog() {
    final List<BootStepDone> done = history.value;
    if (done.isEmpty) return;
    final Duration total = elapsedTotal;
    debugPrint('⏱️ §bootLog — démarrage en '
        '${(total.inMilliseconds / 1000).toStringAsFixed(1)} s :');
    for (final BootStepDone d in done) {
      debugPrint('   ${d.durationLabel.padLeft(8)}  ${d.label}');
    }
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
