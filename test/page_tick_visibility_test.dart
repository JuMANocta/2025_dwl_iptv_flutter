import 'package:aetherStream/feature/home/deferred_refresh.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// §pageTick — Le MÉCANISME de `_TypePageState`, reproduit à l'identique sur
/// un widget minimal : abonnement au signal de contenu, visibilité lue par
/// `TickerMode.getValuesNotifier` (sans dépendance), `setState` déclenché
/// depuis le rappel du notifieur — c'est-à-dire PENDANT le build du parent.
///
/// Ce qu'on fige :
///  - une bascule de visibilité seule ne reconstruit PAS la page (contrat de
///    §tabPageKeep : 0 page par changement d'onglet) ;
///  - un signal sur une page cachée est différé, puis appliqué dans la MÊME
///    frame où elle redevient visible, sans assertion Flutter
///    (« setState() called during build ») ;
///  - un signal sur une page visible la reconstruit.
class _Probe extends StatefulWidget {
  const _Probe({required this.tick});
  final ValueListenable<int> tick;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  static int builds = 0;
  late final DeferredRefresh _refresh = DeferredRefresh(apply: _rebuild);
  ValueListenable<TickerModeData>? _tickerMode;

  @override
  void initState() {
    super.initState();
    widget.tick.addListener(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final n = TickerMode.getValuesNotifier(context);
    if (!identical(n, _tickerMode)) {
      _tickerMode?.removeListener(_onVisibility);
      _tickerMode = n..addListener(_onVisibility);
      _refresh.visible = n.value.enabled;
    }
  }

  @override
  void dispose() {
    widget.tick.removeListener(_onTick);
    _tickerMode?.removeListener(_onVisibility);
    super.dispose();
  }

  void _onTick() => _refresh.signal();
  void _onVisibility() => _refresh.visible = _tickerMode!.value.enabled;
  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    builds++;
    return Text('build $builds', textDirection: TextDirection.ltr);
  }
}

class _Host extends StatefulWidget {
  const _Host({required this.tick});
  final ValueNotifier<int> tick;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool visible = true;

  /// Comme `_typePages` sur la HomePage : l'enfant est une instance STABLE,
  /// que Flutter saute (`identical`) quand seul le parent se reconstruit.
  late final Widget _probe = _Probe(tick: widget.tick);

  @override
  Widget build(BuildContext context) {
    return TickerMode(enabled: visible, child: _probe);
  }
}

void main() {
  testWidgets('§pageTick — différé quand caché, appliqué au retour, '
      'jamais de reconstruction sur une simple bascule', (tester) async {
    _ProbeState.builds = 0;
    final tick = ValueNotifier<int>(0);
    await tester.pumpWidget(_Host(tick: tick));
    expect(_ProbeState.builds, 1);
    final host = tester.state<_HostState>(find.byType(_Host));

    // Cacher la page : aucune reconstruction (pas de dépendance TickerMode).
    host.setState(() => host.visible = false);
    await tester.pump();
    expect(_ProbeState.builds, 1);

    // Un signal pendant qu'elle est cachée : différé.
    tick.value++;
    await tester.pump();
    expect(_ProbeState.builds, 1);

    // Elle redevient visible : rattrapage dans la même frame, sans exception.
    host.setState(() => host.visible = true);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(_ProbeState.builds, 2);
    expect(find.text('build 2'), findsOneWidget);

    // Revenir visible sans signal : rien.
    host.setState(() => host.visible = false);
    await tester.pump();
    host.setState(() => host.visible = true);
    await tester.pump();
    expect(_ProbeState.builds, 2);

    // Un signal sur une page visible : reconstruite.
    tick.value++;
    await tester.pump();
    expect(_ProbeState.builds, 3);

    tick.dispose();
  });
}
