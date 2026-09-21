import 'package:aetherStream/feature/player/buffer_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// §bufferBudget (2026-09-21) — Le tampon ne prend jamais plus que la mémoire
/// Java de l'appareil ne peut donner : sur une box à 128 Mo, le défaut de
/// Media3 (~125 Mo de vidéo) suffisait à provoquer un OutOfMemoryError.
void main() {
  const int mib = 1024 * 1024;

  test('box à 128 Mo de tas : ~51 Mo, loin des 125 Mo du défaut', () {
    final int b = bufferBudgetBytes(memoryClassMb: 128);
    expect(b, closeTo(51.2 * mib, mib));
    expect(b, lessThan(128 * mib ~/ 2));
  });

  test('AVD TV (192 Mo) : ~77 Mo', () {
    expect(bufferBudgetBytes(memoryClassMb: 192), closeTo(76.8 * mib, mib));
  });

  test('appareil confortable : jamais plus que le défaut de Media3', () {
    expect(bufferBudgetBytes(memoryClassMb: 512), kMedia3VideoBufferBytes);
    expect(bufferBudgetBytes(memoryClassMb: 1024), kMedia3VideoBufferBytes);
  });

  test('tout petit tas : le plancher tient (un flux FHD reste lisible)', () {
    expect(bufferBudgetBytes(memoryClassMb: 48), kMinBufferBudgetBytes);
  });

  test('pas encore mesuré : un budget sûr, pas le défaut de Media3', () {
    expect(bufferBudgetBytes(), kUnknownDeviceBufferBytes);
    expect(bufferBudgetBytes(memoryClassMb: 0), kUnknownDeviceBufferBytes);
    expect(kUnknownDeviceBufferBytes, lessThan(kMedia3VideoBufferBytes));
  });

  test('tampon arrière : 10 s en Complet / Équilibré, rien en Léger', () {
    expect(backBufferMsFor(30), 10000);
    expect(backBufferMsFor(90), 10000);
    expect(backBufferMsFor(15), 0);
    expect(backBufferMsFor(10), 0);
  });
}
