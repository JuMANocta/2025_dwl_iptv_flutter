import 'package:aetherStream/feature/player/player_progress_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Revue 2026-09-11, D2A-01 — la position écrite par le lecteur ne lit la
/// diffusion QUE si elle existe.
///
/// Le défaut : pendant l'écran « Préparation » d'un relais (§castRelay), le
/// relais existe mais la diffusion pas encore ; l'ancien calcul faisait
/// `_relay!.offset + _cast!.position` et levait « Null check » — y compris
/// dans `dispose()`, qui s'interrompait (moteur non libéré, paysage figé).
void main() {
  const local = Duration(minutes: 20);
  const localDur = Duration(minutes: 100);

  test('pas de diffusion : position et durée locales', () {
    final r = resumeProgressFor(
      castsThisMedia: false,
      castPosition: null,
      castDuration: null,
      relayOffset: null,
      localPosition: local,
      localDuration: localDur,
    );
    expect(r.position, local);
    expect(r.duration, localDur);
  });

  test('diffusion de CE média : position et durée du téléviseur', () {
    final r = resumeProgressFor(
      castsThisMedia: true,
      castPosition: const Duration(minutes: 42),
      castDuration: const Duration(minutes: 101),
      relayOffset: null,
      localPosition: local,
      localDuration: localDur,
    );
    expect(r.position, const Duration(minutes: 42));
    expect(r.duration, const Duration(minutes: 101));
  });

  test('diffusion sans durée annoncée : durée locale en repli', () {
    final r = resumeProgressFor(
      castsThisMedia: true,
      castPosition: const Duration(minutes: 42),
      castDuration: null,
      relayOffset: null,
      localPosition: local,
      localDuration: localDur,
    );
    expect(r.position, const Duration(minutes: 42));
    expect(r.duration, localDur);
  });

  test('diffusion avec relais : décalage ajouté, durée LOCALE (§castResume)',
      () {
    final r = resumeProgressFor(
      castsThisMedia: true,
      castPosition: const Duration(minutes: 5),
      // Durée d'un flux converti qui grandit : jamais celle du film.
      castDuration: const Duration(minutes: 6),
      relayOffset: const Duration(minutes: 45),
      localPosition: local,
      localDuration: localDur,
    );
    expect(r.position, const Duration(minutes: 50));
    expect(r.duration, localDur);
  });

  test('D2A-01 — relais en préparation SANS diffusion : position locale, '
      'aucune lecture du récepteur', () {
    // `castsThisMedia` est faux (pas de diffusion), `castPosition` nul :
    // c'est la fenêtre qui levait « Null check » dans `dispose()`.
    final r = resumeProgressFor(
      castsThisMedia: false,
      castPosition: null,
      castDuration: null,
      relayOffset: const Duration(minutes: 45),
      localPosition: local,
      localDuration: localDur,
    );
    expect(r.position, local);
    expect(r.duration, localDur);
  });

  test('défense : « ce média » annoncé mais position absente → locale', () {
    final r = resumeProgressFor(
      castsThisMedia: true,
      castPosition: null,
      castDuration: const Duration(minutes: 101),
      relayOffset: const Duration(minutes: 45),
      localPosition: local,
      localDuration: localDur,
    );
    expect(r.position, local);
    expect(r.duration, localDur);
  });

  test('diffusion d’un AUTRE contenu : le lecteur garde sa position', () {
    final r = resumeProgressFor(
      castsThisMedia: false,
      castPosition: const Duration(minutes: 70),
      castDuration: const Duration(minutes: 90),
      relayOffset: null,
      localPosition: local,
      localDuration: localDur,
    );
    expect(r.position, local);
    expect(r.duration, localDur);
  });
}
