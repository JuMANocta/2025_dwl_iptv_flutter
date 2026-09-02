import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// §jankMeter — **Rendre la fluidité mesurable.**
///
/// ## Pourquoi ce fichier existe
///
/// La demande est « l'ergonomie doit être souple et pas saccader ». Sans
/// instrument, ça reste une opinion : on corrige au jugé, on croit avoir
/// amélioré, et personne ne peut le contredire. Or les outils habituels ne
/// répondent pas ici :
///
/// - `dumpsys gfxinfo` rend **0 frame** : l'app est rendue par Impeller, qui
///   n'alimente pas les compteurs HWUI d'Android ;
/// - les avertissements `Choreographer: Skipped frames` viennent du thread
///   principal **Android** et ne voient pas le travail Dart ;
/// - un téléviseur n'a pas de logcat accessible.
///
/// Ne restait que ce que Flutter sait de lui-même : `addTimingsCallback`, qui
/// rapporte pour chaque frame le temps de **construction** (Dart) et de
/// **rastérisation** (GPU). C'est la seule source qui voie réellement les
/// saccades de cette application.
///
/// ## ⚠️ Une mesure en debug ne vaut RIEN
///
/// En build debug, le Dart n'est pas optimisé (JIT, assertions, `debugPrint`
/// partout) : les temps de construction sont plusieurs fois supérieurs à la
/// réalité. Une saccade constatée en debug peut ne pas exister en release, et
/// une frame « bonne » en debug ne prouve rien non plus. **Toute conclusion
/// tirée d'ici doit venir d'un build profile ou release** — d'où le drapeau
/// [isTrustworthy], journalisé avec chaque relevé pour qu'on ne puisse pas
/// citer un chiffre sans savoir ce qu'il vaut.
///
/// ## ⚠️ Les timings arrivent EN RETARD
///
/// `addTimingsCallback` livre les mesures par lots, quelques frames après
/// coup. Fermer une fenêtre de mesure au moment exact où l'action se termine
/// laisserait donc dehors les frames les plus lourdes — précisément celles
/// qu'on cherche. [endSpan] attend [_drainDelay] avant de conclure.
abstract final class JankMeter {
  /// Fenêtre de purge après la fin d'une action, le temps que les dernières
  /// frames remontent (cf. l'avertissement ci-dessus).
  static const Duration _drainDelay = Duration(milliseconds: 400);

  /// Au-delà, on cesse d'attendre : une action qui n'a jamais été close
  /// (navigation interrompue, page démontée) ne doit pas retenir la mesure
  /// suivante.
  static const Duration _spanTimeout = Duration(seconds: 6);

  static bool _installed = false;

  /// Une mesure en cours, ou `null`. **Une seule à la fois** : deux fenêtres
  /// concurrentes se partageraient les mêmes frames et se compteraient
  /// mutuellement leurs saccades.
  static _Span? _span;

  static Timer? _timeout;

  /// Purge en cours après un [endSpan] — suivie, pour pouvoir l'annuler.
  ///
  /// ⚠️ Non suivie, elle produisait une perte SILENCIEUSE : deux défilements
  /// rapprochés (le cas normal quand on parcourt l'accueil) et la première
  /// mesure disparaissait sans un mot, parce que la purge ne retrouvait plus
  /// « sa » fenêtre. Un instrument qui jette ses relevés en silence ne vaut
  /// rien.
  static Timer? _drain;

  /// `false` en debug — voir l'avertissement de la classe.
  static bool get isTrustworthy => !kDebugMode;

  /// Budget d'une frame, déduit de la fréquence réelle de l'écran.
  ///
  /// ⚠️ Ne PAS coder 16,7 ms en dur : un téléviseur tourne souvent à 50 ou
  /// 60 Hz, un téléphone récent à 90 ou 120. Un budget faux transformerait des
  /// frames correctes en saccades imaginaires — ou l'inverse.
  static Duration get frameBudget {
    try {
      final double hz = SchedulerBinding
          .instance.platformDispatcher.views.first.display.refreshRate;
      if (hz > 1) {
        return Duration(microseconds: (1000000 / hz).round());
      }
    } catch (_) {
      // Pas de vue attachée (tests, démarrage très précoce) → repli 60 Hz.
    }
    return const Duration(microseconds: 16667);
  }

  /// Branche l'écoute des frames. Idempotent.
  static void install() {
    if (_installed) return;
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// Ouvre une fenêtre de mesure nommée.
  ///
  /// Si une fenêtre est déjà ouverte, elle est **abandonnée** plutôt que
  /// fusionnée : mélanger deux actions donnerait un chiffre qui ne décrit
  /// aucune des deux.
  static void beginSpan(String label) {
    if (!_installed) return;
    // Une mesure encore en purge est publiée MAINTENANT plutôt que perdue.
    _flushPending();
    _timeout?.cancel();
    _span = _Span(label);
    _timeout = Timer(_spanTimeout, () {
      _span = null;
      _timeout = null;
    });
  }

  /// Conclut immédiatement une fenêtre qui attendait ses dernières frames.
  static void _flushPending() {
    final Timer? drain = _drain;
    if (drain == null) return;
    drain.cancel();
    _drain = null;
    final _Span? span = _span;
    _span = null;
    if (span != null) _report(span);
  }

  /// Ferme la fenêtre courante et journalise son verdict.
  ///
  /// Le relevé part dans `debugPrint`, donc dans le tampon §tvLogs et la
  /// console web : c'est le seul canal lisible depuis un téléviseur.
  static void endSpan() {
    final _Span? span = _span;
    if (span == null || _drain != null) return;
    _timeout?.cancel();
    _timeout = null;
    // La fenêtre reste OUVERTE pendant la purge : c'est tout l'intérêt, les
    // dernières frames — les plus lourdes — arrivent après coup.
    _drain = Timer(_drainDelay, () {
      _drain = null;
      if (!identical(_span, span)) return;
      _span = null;
      _report(span);
    });
  }

  static void _onTimings(List<FrameTiming> timings) {
    final _Span? span = _span;
    if (span == null) return;
    final int budgetUs = frameBudget.inMicroseconds;
    for (final FrameTiming t in timings) {
      final int buildUs = t.buildDuration.inMicroseconds;
      final int rasterUs = t.rasterDuration.inMicroseconds;
      // `totalSpan` couvre de la vsync à la fin du raster : c'est ce que
      // l'œil subit, et non la simple somme build+raster.
      final int totalUs = t.totalSpan.inMicroseconds;
      span.frames++;
      if (totalUs > budgetUs) span.janky++;
      // Une frame qui dépasse 3 budgets est un à-coup VISIBLE, pas un
      // dépassement marginal : on la compte à part.
      if (totalUs > budgetUs * 3) span.severe++;
      if (buildUs > span.worstBuildUs) span.worstBuildUs = buildUs;
      if (rasterUs > span.worstRasterUs) span.worstRasterUs = rasterUs;
      if (totalUs > span.worstTotalUs) span.worstTotalUs = totalUs;
    }
  }

  static void _report(_Span span) {
    if (span.frames == 0) {
      debugPrint('📉 §jankMeter « ${span.label} » : aucune frame observée.');
      return;
    }
    final String trust = isTrustworthy
        ? ''
        : '  ⚠️ BUILD DEBUG — chiffres non exploitables';
    debugPrint(
      '📉 §jankMeter « ${span.label} » : ${span.frames} frames, '
      '${span.janky} au-delà du budget (${span.severe} franches), '
      'pire build ${_ms(span.worstBuildUs)}, '
      'raster ${_ms(span.worstRasterUs)}, '
      'total ${_ms(span.worstTotalUs)} '
      '(budget ${_ms(frameBudget.inMicroseconds)})$trust',
    );
  }

  static String _ms(int microseconds) =>
      '${(microseconds / 1000).toStringAsFixed(1)} ms';

  /// Réservé aux tests : remet le compteur à zéro sans toucher au callback.
  @visibleForTesting
  static void resetForTest() {
    _timeout?.cancel();
    _timeout = null;
    _drain?.cancel();
    _drain = null;
    _span = null;
  }

  /// Réservé aux tests : injecte des frames comme le ferait le moteur.
  @visibleForTesting
  static void feedForTest(List<FrameTiming> timings) => _onTimings(timings);

  /// Réservé aux tests : la fenêtre en cours, pour vérifier ses compteurs sans
  /// attendre la purge.
  @visibleForTesting
  static ({int frames, int janky, int severe})? get currentForTest {
    final _Span? s = _span;
    return s == null
        ? null
        : (frames: s.frames, janky: s.janky, severe: s.severe);
  }

  @visibleForTesting
  static void installForTest() {
    _installed = true;
  }
}

class _Span {
  final String label;
  int frames = 0;
  int janky = 0;
  int severe = 0;
  int worstBuildUs = 0;
  int worstRasterUs = 0;
  int worstTotalUs = 0;

  _Span(this.label);
}

/// §jankMeter — Mesure la fluidité d'UN défilement, vertical **ou horizontal**.
///
/// Le défilement est l'endroit où une saccade se voit le plus : l'œil suit un
/// mouvement continu, donc une seule frame en retard se remarque, là où elle
/// passerait inaperçue sur une transition. Les carrousels horizontaux de
/// l'accueil comptent autant que le défilement vertical — ils affichent des
/// affiches qui se décodent en cours de route.
///
/// ⚠️ **Le filtre `depth == 0` n'est pas optionnel.** Les notifications de
/// défilement **remontent** l'arbre : sans lui, la sonde posée sur la liste
/// verticale se déclencherait aussi à chaque mouvement d'un carrousel
/// horizontal imbriqué. Comme une seule fenêtre de mesure peut être ouverte à
/// la fois, les deux se voleraient leurs frames et aucun des deux chiffres ne
/// décrirait quoi que ce soit.
class JankScrollProbe extends StatelessWidget {
  /// Nom lisible dans le journal — il doit dire QUOI défilait, sinon un relevé
  /// isolé ne se rattache à rien (« défilement » ne veut rien dire, « rangée
  /// Films » oui).
  final String label;
  final Widget child;

  const JankScrollProbe({
    super.key,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification n) {
        if (n.depth != 0) return false;
        if (n is ScrollStartNotification) {
          JankMeter.beginSpan(label);
        } else if (n is ScrollEndNotification) {
          JankMeter.endSpan();
        }
        // Toujours `false` : la sonde OBSERVE, elle ne consomme rien. Renvoyer
        // `true` couperait la remontée et casserait tout ce qui écoute plus
        // haut (barres qui se masquent, chargement paresseux…).
        return false;
      },
      child: child,
    );
  }
}
