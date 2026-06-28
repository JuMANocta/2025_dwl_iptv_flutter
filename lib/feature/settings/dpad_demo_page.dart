import 'package:flutter/material.dart';
import 'package:dpad/dpad.dart';

import '../../core/themes/colors.dart';

/// §dpadDemo — Banc d'essai de la navigation D-pad via le package `dpad`
/// (évaluation, option B). Isolé : `Dpad` n'enveloppe QUE cette page, le reste
/// de l'app garde son système de focus actuel.
///
/// **Pourquoi un panneau d'état à l'écran** : la TV ne donne pas de logcat à
/// l'utilisateur → chaque événement (focus, select, long-select, bord, back,
/// menu) est affiché EN DIRECT pour qu'on évalue le comportement réel depuis le
/// canapé. On couvre les patterns de l'app : rail latéral, carrousel horizontal
/// avec mémoire, grille (chaînes), région « stop » (bord qui bloque), et un
/// dialog pour vérifier la restauration de focus au retour.
class DpadDemoPage extends StatefulWidget {
  const DpadDemoPage({super.key});

  @override
  State<DpadDemoPage> createState() => _DpadDemoPageState();
}

class _DpadDemoPageState extends State<DpadDemoPage> {
  final List<String> _events = <String>[];
  bool _overlay = false;

  void _log(String msg) {
    setState(() {
      _events.insert(0, msg);
      if (_events.length > 7) _events.removeLast();
    });
  }

  List<DpadEffect> get _fx => [
        const DpadScaleEffect(scale: 1.06),
        DpadBorderEffect(
            color: kAccentPrimary,
            width: 2.6,
            borderRadius: BorderRadius.circular(12)),
        DpadGlowEffect(
            color: kAccentPrimary,
            opacity: 0.5,
            borderRadius: BorderRadius.circular(12)),
      ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Démo navigation D-pad'),
        actions: [
          // Toggle de l'inspecteur de focus intégré au package.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [
              const Text('Inspecteur', style: TextStyle(fontSize: 12)),
              Switch(
                value: _overlay,
                onChanged: (v) => setState(() => _overlay = v),
              ),
            ]),
          ),
        ],
      ),
      body: Dpad(
        debugOverlay: _overlay,
        theme: const DpadThemeData(scrollPadding: 48),
        // Back : on log puis on laisse la route se fermer (return false).
        onBack: () {
          _log('⬅️ BACK');
          return false;
        },
        onMenu: () => _log('☰ MENU (télécommande)'),
        onFocusChange: (node) => _log('focus → ${node?.debugLabel ?? '—'}'),
        child: Column(
          children: [
            _statusPanel(cs),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _rail(),
                  const VerticalDivider(width: 1),
                  Expanded(child: _content(cs)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Panneau d'état (diagnostic sans logcat) ───────────────────────────────
  Widget _statusPanel(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      color: cs.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(Icons.bug_report_outlined, size: 16, color: kAccentSecondary),
            const SizedBox(width: 6),
            Text('ÉVÉNEMENTS D-PAD (le plus récent en haut)',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: kAccentSecondary)),
          ]),
          const SizedBox(height: 4),
          SizedBox(
            height: 84,
            child: _events.isEmpty
                ? Text('Déplace-toi à la télécommande…',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))
                : ListView.builder(
                    itemCount: _events.length,
                    itemBuilder: (_, i) => Text(
                      _events[i],
                      style: TextStyle(
                        fontSize: 12,
                        color: i == 0 ? kAccentPrimary : cs.onSurfaceVariant,
                        fontWeight:
                            i == 0 ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Rail latéral (comme la NavigationRail TV) ─────────────────────────────
  Widget _rail() {
    const labels = ['Accueil', 'Recherche', 'Télécharg.', 'Réglages'];
    const icons = [
      Icons.home_rounded,
      Icons.search_rounded,
      Icons.download_rounded,
      Icons.settings_rounded,
    ];
    return SizedBox(
      width: 96,
      // verticalEdge: stop → le rail ne « fuit » pas en haut/bas (panneau nav).
      child: DpadRegion(
        debugLabel: 'rail',
        verticalEdge: DpadEdgeBehavior.stop,
        onEdge: (d) => _log('bord rail: $d'),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            for (int i = 0; i < labels.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: DpadFocusable(
                  debugLabel: 'rail/${labels[i]}',
                  autofocus: i == 0,
                  effects: _fx,
                  onSelect: () => _log('▶️ SELECT rail "${labels[i]}"'),
                  onLongSelect: () => _log('☰ LONG rail "${labels[i]}"'),
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icons[i], size: 22, color: kAccentPrimary),
                        const SizedBox(height: 4),
                        Text(labels[i], style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Contenu : carrousel mémoire + grille + région stop + dialog ───────────
  Widget _content(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section('Carrousel horizontal (mémoire de focus)'),
          SizedBox(
            height: 150,
            child: DpadRegion(
              debugLabel: 'carrousel',
              memoryKey: 'demo_carousel', // restaure la position au retour
              onEdge: (d) => _log('bord carrousel: $d'),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 14,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _card('Film ${i + 1}', 'carrousel'),
              ),
            ),
          ),
          const SizedBox(height: 22),

          _section('Grille (comme les chaînes)'),
          DpadRegion(
            debugLabel: 'grille',
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.1,
              ),
              itemCount: 15,
              itemBuilder: (_, i) => _card('Ch. ${i + 1}', 'grille',
                  square: true),
            ),
          ),
          const SizedBox(height: 22),

          _section('Région « STOP » (le bord bloque — bump)'),
          DpadRegion(
            debugLabel: 'stop',
            horizontalEdge: DpadEdgeBehavior.stop,
            onEdge: (d) => _log('🛑 bord STOP consommé: $d'),
            child: SizedBox(
              height: 90,
              child: Row(
                children: [
                  for (int i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _card('Stop ${i + 1}', 'stop'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),

          _section('Restauration de focus après un dialog'),
          DpadFocusable(
            debugLabel: 'btn/dialog',
            effects: _fx,
            onSelect: _openDialog,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: kAccentSecondary.withAlpha(28),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kAccentSecondary.withAlpha(110)),
              ),
              child: const Text('Ouvrir un dialog (OK pour fermer)'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
              width: 4,
              height: 15,
              decoration: BoxDecoration(
                  color: kAccentPrimary,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(title.toUpperCase(),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: kAccentPrimary)),
        ]),
      );

  Widget _card(String label, String region, {bool square = false}) {
    final cs = Theme.of(context).colorScheme;
    final w = square ? null : 108.0;
    return DpadFocusable(
      debugLabel: '$region/$label',
      effects: _fx,
      onSelect: () => _log('▶️ SELECT "$label"'),
      onLongSelect: () => _log('☰ LONG (menu) "$label"'),
      child: Container(
        width: w,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Text(label,
            style: TextStyle(color: cs.onSurface, fontSize: 13)),
      ),
    );
  }

  Future<void> _openDialog() async {
    _log('📄 dialog ouvert');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dialog de test'),
        content: const Text(
            'Ferme avec OK : au retour, le focus doit revenir sur le bouton '
            '(restoreFocus du package).'),
        actions: [
          DpadFocusable(
            debugLabel: 'dialog/ok',
            autofocus: true,
            effects: _fx,
            onSelect: () => Navigator.of(ctx).pop(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text('OK'),
            ),
          ),
        ],
      ),
    );
    _log('📄 dialog fermé → focus restauré ?');
  }
}
