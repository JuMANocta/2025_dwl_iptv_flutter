import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/core/boot/boot_status.dart';

/// §bootStatus — Verrouille le **throttle** de l'écran de démarrage.
///
/// Le `onProgress` des parsers tombe par lot d'entrées : sans throttle, chaque
/// appel notifierait le `ValueNotifier` et rebuilderait l'écran de lancement
/// pendant tout le parsing d'un catalogue de centaines de milliers d'entrées —
/// exactement le « spam de setState » signalé en roadmap.
void main() {
  setUp(BootStatus.reset);

  test('report ne notifie que si le POURCENTAGE ENTIER change', () {
    BootStatus.set('// analyse…', progress: 0);
    var notifications = 0;
    void listener() => notifications++;
    BootStatus.step.addListener(listener);
    addTearDown(() => BootStatus.step.removeListener(listener));

    // 50 valeurs toutes comprises dans le même pourcentage entier (0,4 %).
    for (var i = 0; i < 50; i++) {
      BootStatus.report(0.004 + i * 0.000001);
    }
    expect(notifications, 0, reason: 'aucun changement de % entier');

    BootStatus.report(0.02); // 2 % → une seule notification
    expect(notifications, 1);
  });

  test('un parsing complet reste borné à ~100 notifications, et atteint 100 %',
      () {
    BootStatus.set('// analyse…', progress: 0);
    var notifications = 0;
    void listener() => notifications++;
    BootStatus.step.addListener(listener);
    addTearDown(() => BootStatus.step.removeListener(listener));

    // 100 000 appels (ordre de grandeur d'un gros catalogue).
    for (var i = 0; i <= 100000; i++) {
      BootStatus.report(i / 100000);
    }
    // 101 paliers de pourcentage + 1 palier de complétion.
    expect(notifications, lessThanOrEqualTo(102));
    // La complétion DOIT être publiée : sans palier dédié, la barre restait
    // figée à 99,x % (le dernier lot partage le % entier du précédent).
    expect(BootStatus.step.value.progress, 1.0);
  });

  test('set change le libellé et réarme le throttle', () {
    BootStatus.set('// analyse…', progress: 0.5);
    expect(BootStatus.step.value.label, '// analyse…');
    expect(BootStatus.step.value.progress, 0.5);

    // Nouvelle étape SANS progression → barre indéterminée.
    BootStatus.set('// chargement des autres comptes…');
    expect(BootStatus.step.value.progress, isNull);

    // Le throttle est réarmé : 50 % redevient notifiable.
    var notified = false;
    void listener() => notified = true;
    BootStatus.step.addListener(listener);
    addTearDown(() => BootStatus.step.removeListener(listener));
    BootStatus.report(0.5);
    expect(notified, isTrue);
  });

  test('report borne les valeurs hors [0,1]', () {
    BootStatus.set('// analyse…', progress: 0);
    BootStatus.report(-3);
    expect(BootStatus.step.value.progress, 0.0);
    BootStatus.report(42);
    expect(BootStatus.step.value.progress, 1.0);
  });

  test('reset revient à l\'état initial (boot rejouable)', () {
    BootStatus.set('// prêt.', progress: 1);
    BootStatus.reset();
    expect(BootStatus.step.value.label, '// initialisation…');
    expect(BootStatus.step.value.progress, isNull);
  });
}
