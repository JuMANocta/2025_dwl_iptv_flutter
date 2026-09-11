// §castLocal / §castRelay / §webConsole — revue 2026-09-11, D2A-12 — Le choix
// de l'adresse LAN, UNE fonction pour les trois serveurs locaux. Trois copies
// acceptaient tout 172/8 et retombaient sur la première adresse venue : une
// adresse d'opérateur passait pour une adresse LAN, et « pas sur un réseau
// Wi-Fi » n'était jamais dit.

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/core/utils/lan_address.dart';

void main() {
  group('isRfc1918 — 10/8, 172.16/12, 192.168/16, rien d autre', () {
    test('privées', () {
      for (final String ip in <String>[
        '10.0.0.1',
        '10.0.2.15', // émulateur Android
        '172.16.0.1',
        '172.20.5.4',
        '172.31.255.255',
        '192.168.1.42',
      ]) {
        expect(isRfc1918(ip), isTrue, reason: ip);
      }
    });

    test('⚠️ refusées : 172 hors /12, CGNAT, lien local, publiques, bouclage', () {
      for (final String ip in <String>[
        '172.15.0.1',
        '172.32.0.1',
        '100.64.0.1', // CGNAT — données mobiles
        '169.254.10.1',
        '8.8.8.8',
        '127.0.0.1',
        '192.169.0.1',
        'pas.une.ip',
        '10.0.0',
        '10.0.0.256',
      ]) {
        expect(isRfc1918(ip), isFalse, reason: ip);
      }
    });
  });

  group('pickLanIpv4 — Wi-Fi, puis Ethernet, puis le reste', () {
    test('Wi-Fi privé préféré à l Ethernet privé, même listé après', () {
      expect(
        pickLanIpv4(<LanInterface>[
          (name: 'eth0', addresses: <String>['10.0.0.5']),
          (name: 'wlan0', addresses: <String>['192.168.1.20']),
        ]),
        '192.168.1.20',
      );
    });

    test('⚠️ données mobiles seules (CGNAT) : null — refus AVANT d envoyer', () {
      expect(
        pickLanIpv4(<LanInterface>[
          (name: 'rmnet_data0', addresses: <String>['100.64.12.7']),
        ]),
        isNull,
      );
    });

    test('Wi-Fi + données : l adresse Wi-Fi, jamais celle de l opérateur', () {
      expect(
        pickLanIpv4(<LanInterface>[
          (name: 'rmnet_data0', addresses: <String>['100.64.12.7']),
          (name: 'wlan0', addresses: <String>['192.168.0.12']),
        ]),
        '192.168.0.12',
      );
    });

    test('console web (allowNonPrivate) : repli sur la première adresse', () {
      expect(
        pickLanIpv4(
          <LanInterface>[
            (name: 'eth0', addresses: <String>['172.32.0.9']),
          ],
          allowNonPrivate: true,
        ),
        '172.32.0.9',
      );
    });

    test('aucune interface : null, même en repli', () {
      expect(pickLanIpv4(const <LanInterface>[]), isNull);
      expect(pickLanIpv4(const <LanInterface>[], allowNonPrivate: true), isNull);
    });
  });
}
