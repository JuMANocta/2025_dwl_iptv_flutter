import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/core/navigation/foreground_gate.dart';

/// Revue 2026-09-11, D3B-13 — La mise à jour, l'alerte d'expiration et
/// l'annonce du profil s'ouvraient sur minuterie par-dessus n'importe quel
/// écran, lecteur compris (sur TV, le dialogue de mise à jour volait le focus
/// d'un film lancé dans les dix premières secondes). La porte les retient
/// tant que l'accueil n'est pas à l'écran.
void main() {
  // Planification SYNCHRONE pour les tests (la vraie attend la frame
  // suivante), mais gardée de côté pour vérifier QU'elle a été demandée.
  late List<VoidCallback> scheduled;
  late ForegroundGate gate;

  setUp(() {
    scheduled = <VoidCallback>[];
    gate = ForegroundGate(schedule: scheduled.add);
  });

  test('accueil à l\'écran → l\'action part tout de suite', () {
    gate.foreground = true;
    var ran = 0;
    gate.runOrDefer(() => ran++);
    expect(ran, 1);
    expect(gate.pendingCount, 0);
  });

  test('lecteur par-dessus → l\'action ATTEND le retour sur l\'accueil', () {
    var ran = 0;
    gate.foreground = false;
    gate.runOrDefer(() => ran++);
    expect(ran, 0, reason: 'jamais par-dessus le lecteur');
    expect(gate.pendingCount, 1);

    gate.foreground = true; // didPopNext
    expect(ran, 0, reason: 'jamais PENDANT le build : après la frame');
    expect(scheduled, hasLength(1));
    scheduled.single();
    expect(ran, 1);
    expect(gate.pendingCount, 0);
  });

  test('une route re-poussée avant la frame → on attend encore', () {
    var ran = 0;
    gate.runOrDefer(() => ran++);
    gate.foreground = true;
    gate.foreground = false; // lecteur relancé aussitôt
    scheduled.single();
    expect(ran, 0);
    expect(gate.pendingCount, 1);
    gate.foreground = true;
    scheduled.last();
    expect(ran, 1);
  });

  test('les actions en attente partent dans l\'ordre, une seule fois', () {
    final order = <int>[];
    gate.runOrDefer(() => order.add(1));
    gate.runOrDefer(() => order.add(2));
    gate.foreground = true;
    scheduled.single();
    gate.foreground = false;
    gate.foreground = true; // aucun nouvel envoi : la file est vide
    expect(order, <int>[1, 2]);
    expect(scheduled, hasLength(1));
  });

  test('une action qui lève n\'empêche pas les suivantes', () {
    var ran = 0;
    gate.runOrDefer(() => throw StateError('dialogue impossible'));
    gate.runOrDefer(() => ran++);
    gate.foreground = true;
    scheduled.single();
    expect(ran, 1);
  });
}
