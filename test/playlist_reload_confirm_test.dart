import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/services/playlist_reload_service.dart';

/// §reloadKeep — Le ↻ de l'accueil et « Recharger » d'une carte posent la même
/// question au même moment : la décision et le libellé d'âge sont des
/// fonctions PURES de `PlaylistReloadService`, testables sans disque.
void main() {
  group('shouldConfirm — seuil de 24 h', () {
    test('pas de cache → pas de question', () {
      expect(PlaylistReloadService.shouldConfirm(null), isFalse);
    });

    test('liste fraîche (2 h) → confirmation', () {
      expect(
        PlaylistReloadService.shouldConfirm(const Duration(hours: 2)),
        isTrue,
      );
    });

    test('à la limite (24 h pile) → plus de question', () {
      expect(
        PlaylistReloadService.shouldConfirm(
            PlaylistReloadService.confirmBelow),
        isFalse,
      );
    });

    test('vieille liste (3 jours) → rechargement direct', () {
      expect(
        PlaylistReloadService.shouldConfirm(const Duration(days: 3)),
        isFalse,
      );
    });
  });

  group('formatAge — libellé humain, jamais de secondes', () {
    test('heures + minutes', () {
      expect(
        PlaylistReloadService.formatAge(
            const Duration(hours: 3, minutes: 12, seconds: 40)),
        '3h 12min',
      );
    });

    test('heures rondes', () {
      expect(
        PlaylistReloadService.formatAge(const Duration(hours: 5)),
        '5h',
      );
    });

    test('minutes seules', () {
      expect(
        PlaylistReloadService.formatAge(const Duration(minutes: 45)),
        '45min',
      );
    });

    test('sous la minute', () {
      expect(
        PlaylistReloadService.formatAge(const Duration(seconds: 20)),
        'moins d\'une minute',
      );
    });
  });
}
