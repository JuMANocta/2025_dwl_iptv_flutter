// §dlWifi (2026-09-06, lot 6) — Le réseau se lit sur les interfaces, sans
// plugin. Ce qui se vérifie : la classification des noms d'interfaces Android
// et la règle « Wi-Fi seulement ».

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/core/utils/network_kind.dart';

void main() {
  group('classifyInterfaces — noms Android réels', () {
    test('téléphone en Wi-Fi : wlan0 gagne même si rmnet garde une adresse', () {
      expect(classifyInterfaces(['rmnet_data0', 'wlan0']), NetKind.wifi);
    });

    test('données mobiles seules', () {
      expect(classifyInterfaces(['rmnet_data0']), NetKind.cellular);
      expect(classifyInterfaces(['ccmni0']), NetKind.cellular);
      expect(classifyInterfaces(['radio0']), NetKind.cellular);
      expect(classifyInterfaces(['clat4']), NetKind.cellular);
    });

    test('box / téléviseur en filaire', () {
      expect(classifyInterfaces(['eth0']), NetKind.ethernet);
      expect(classifyInterfaces(['eth0', 'rmnet0']), NetKind.ethernet);
    });

    test('aucune interface avec adresse → hors ligne', () {
      expect(classifyInterfaces(const []), NetKind.none);
    });

    test('interface inconnue → inconnu, jamais « hors ligne »', () {
      expect(classifyInterfaces(['tun0']), NetKind.unknown);
    });

    test('la casse ne compte pas', () {
      expect(classifyInterfaces(['WLAN0']), NetKind.wifi);
    });
  });

  group('downloadHoldFor — la règle « Wi-Fi seulement » = pas de réseau facturé', () {
    test('réglage OFF : rien ne retient, sauf l absence de réseau', () {
      expect(downloadHoldFor(wifiOnly: false, kind: NetKind.cellular, metered: true), isNull);
      expect(downloadHoldFor(wifiOnly: false, kind: NetKind.wifi, metered: true), isNull);
      expect(downloadHoldFor(wifiOnly: false, kind: NetKind.none, metered: false), DownloadHold.offline);
    });

    test('réglage ON : un réseau FACTURÉ attend, quel que soit son transport', () {
      expect(downloadHoldFor(wifiOnly: true, kind: NetKind.cellular, metered: true), DownloadHold.wifi);
      expect(downloadHoldFor(wifiOnly: true, kind: NetKind.wifi, metered: true), DownloadHold.wifi,
          reason: 'un partage de connexion facturé est un Wi-Fi facturé');
      expect(downloadHoldFor(wifiOnly: true, kind: NetKind.wifi, metered: false), isNull);
      expect(downloadHoldFor(wifiOnly: true, kind: NetKind.ethernet, metered: false), isNull,
          reason: 'le filaire d une box n est pas facturé au Go');
    });

    test('⚠️ inconnu et non facturé ne bloque jamais : on ne punit pas une ignorance', () {
      expect(downloadHoldFor(wifiOnly: true, kind: NetKind.unknown, metered: false), isNull);
    });
  });
}
