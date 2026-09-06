/// §dlWifi (2026-09-06, lot 6) — Quel réseau porte l'appareil, SANS plugin.
///
/// Le roadmap prévoyait de re-déclarer `connectivity_plus` (retiré par
/// §apkDiet : plugin natif, dex + manifeste, jamais appelé). La réponse vit
/// déjà dans notre canal natif (`aetherstream/device`, méthode `network`) :
/// le transport ACTIF selon Android, et surtout **facturé ou non**
/// (`NET_CAPABILITY_NOT_METERED`) — c'est cela que « Wi-Fi seulement » veut
/// dire, et un partage de connexion Wi-Fi facturé compte bien comme facturé.
///
/// ⚠️ Le nom d'interface n'est PAS une vérité : l'émulateur appelle son
/// réseau mobile `eth0`. Les interfaces (`dart:io`) ne servent qu'en repli,
/// quand le canal ne répond pas (tests, autre plateforme).
///
/// Ce que ça ne dit pas — et `connectivity_plus` non plus : si le réseau va
/// jusqu'à Internet. Un transfert qui échoue reste l'affaire du gardien.
library;

import 'dart:io';

import 'package:flutter/services.dart';

enum NetKind { wifi, ethernet, cellular, none, unknown }

/// Classe une liste de NOMS d'interfaces qui portent une adresse. Priorité :
/// Wi-Fi > filaire > données mobiles > inconnu — sur un téléphone en Wi-Fi,
/// l'interface mobile garde souvent une adresse, et c'est le Wi-Fi qui compte.
NetKind classifyInterfaces(Iterable<String> namesWithAddress) {
  var sawEthernet = false;
  var sawCellular = false;
  var sawAny = false;
  for (final String raw in namesWithAddress) {
    final String n = raw.toLowerCase();
    sawAny = true;
    if (n.startsWith('wlan') || n.contains('wifi') || n.startsWith('ap')) {
      return NetKind.wifi;
    }
    if (n.startsWith('eth') || n.startsWith('en')) {
      sawEthernet = true;
    } else if (n.startsWith('rmnet') ||
        n.startsWith('ccmni') ||
        n.startsWith('radio') ||
        n.startsWith('pdp') ||
        n.startsWith('wwan') ||
        n.startsWith('clat')) {
      sawCellular = true;
    }
  }
  if (sawEthernet) return NetKind.ethernet;
  if (sawCellular) return NetKind.cellular;
  return sawAny ? NetKind.unknown : NetKind.none;
}

/// Ce que le réseau actif est, et s'il est facturé.
typedef NetState = ({NetKind kind, bool metered});

const MethodChannel _deviceChannel = MethodChannel('aetherstream/device');

/// Le réseau ACTIF selon Android (canal natif) ; repli sur les interfaces si
/// le canal ne répond pas. `unknown` + non facturé si tout échoue : on ne
/// bloque jamais sur une ignorance.
Future<NetState> currentNetState() async {
  try {
    final dynamic r = await _deviceChannel.invokeMethod<dynamic>('network');
    if (r is Map) {
      final String t = (r['transport'] as String?) ?? 'unknown';
      final bool metered = (r['metered'] as bool?) ?? false;
      final NetKind kind = switch (t) {
        'wifi' => NetKind.wifi,
        'ethernet' => NetKind.ethernet,
        'cellular' => NetKind.cellular,
        'none' => NetKind.none,
        _ => NetKind.unknown,
      };
      return (kind: kind, metered: metered);
    }
  } catch (_) {
    // Canal absent (tests, autre plateforme) : les interfaces.
  }
  final NetKind k = await currentNetKind();
  // Sans Android pour le dire, seules les données mobiles sont supposées
  // facturées.
  return (kind: k, metered: k == NetKind.cellular);
}

/// Le réseau courant, lu sur les interfaces (IPv4, hors boucle locale et
/// hors adresses de lien). `unknown` si la lecture échoue.
Future<NetKind> currentNetKind() async {
  try {
    final List<NetworkInterface> ifaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    return classifyInterfaces(
      ifaces.where((i) => i.addresses.isNotEmpty).map((i) => i.name),
    );
  } catch (_) {
    return NetKind.unknown;
  }
}

/// Pourquoi la file des téléchargements est RETENUE, ou `null` si elle peut
/// faire partir des transferts.
enum DownloadHold {
  /// Réglage « Wi-Fi seulement » et l'appareil est sur les données mobiles.
  wifi,

  /// Aucun réseau : partir maintenant échouerait à la première requête.
  offline,
}

/// La règle, PURE : que retient-on, et pourquoi. « Wi-Fi seulement » retient
/// tout réseau FACTURÉ (données mobiles, partage de connexion facturé) — pas
/// le filaire d'une box, pas un Wi-Fi domestique.
DownloadHold? downloadHoldFor({
  required bool wifiOnly,
  required NetKind kind,
  required bool metered,
}) {
  if (kind == NetKind.none) return DownloadHold.offline;
  if (wifiOnly && metered) return DownloadHold.wifi;
  return null;
}
