/// §castLocal / §castRelay / §webConsole — revue 2026-09-11, D2A-12 —
/// L'adresse LAN du téléphone, choisie UNE fois pour les trois serveurs
/// locaux (fichier servi au Chromecast, relais converti, console web).
///
/// **Le défaut réparé.** Trois copies identiques de la même détection
/// acceptaient `ip.startsWith('172.')` — tout 172/8, alors que seul
/// 172.16/12 est privé — puis retombaient sur la PREMIÈRE adresse trouvée,
/// quelle qu'elle soit. Sur données mobiles (adresse d'opérateur, CGNAT
/// 100.64/10), une adresse publique passait donc pour une adresse LAN : le
/// motif « pas sur un réseau Wi-Fi » (`castNoWifi`) n'était jamais produit,
/// contrairement à ce que promettaient l'en-tête de `CastFileServer` et
/// §castLocal (« sans adresse LAN → refus AVANT d'envoyer »).
///
/// ⚠️ [allowNonPrivate] n'existe QUE pour la console web : elle garde son
/// comportement historique (afficher une adresse même sur un réseau exotique,
/// l'utilisateur la tape à la main). Les serveurs Cast, eux, refusent — un
/// film n'a rien à faire sur une adresse joignable depuis Internet.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Une interface réseau réduite à ce qu'on en lit : son nom et ses adresses
/// IPv4 textuelles. Type minimal exprès : [pickLanIpv4] se teste sans réseau.
typedef LanInterface = ({String name, List<String> addresses});

/// `true` si [ip] est une adresse IPv4 privée au sens de la RFC 1918 :
/// 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16. Rien d'autre — ni le CGNAT
/// (100.64/10), ni le lien local (169.254/16), ni le bouclage.
bool isRfc1918(String ip) {
  final List<String> parts = ip.split('.');
  if (parts.length != 4) return false;
  final List<int> o = <int>[];
  for (final String p in parts) {
    final int? v = int.tryParse(p);
    if (v == null || v < 0 || v > 255) return false;
    o.add(v);
  }
  if (o[0] == 10) return true;
  if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return true;
  if (o[0] == 192 && o[1] == 168) return true;
  return false;
}

/// Choisit l'adresse à publier parmi [interfaces] : Wi-Fi d'abord, puis
/// Ethernet, puis le reste — et, dans cet ordre, la première adresse PRIVÉE.
///
/// Sans adresse privée : `null`, sauf si [allowNonPrivate] (console web),
/// auquel cas la première adresse trouvée (comportement d'avant la revue).
String? pickLanIpv4(
  List<LanInterface> interfaces, {
  bool allowNonPrivate = false,
}) {
  int rank(String name) {
    final String n = name.toLowerCase();
    if (n.startsWith('wlan') || n.contains('wifi')) return 0;
    if (n.startsWith('eth')) return 1;
    return 2;
  }

  // Tri STABLE par rang (l'ordre du système départage), sans dépendre de la
  // stabilité de `List.sort`, que Dart ne garantit pas.
  final List<LanInterface> ordered = <LanInterface>[
    for (int r = 0; r <= 2; r++)
      ...interfaces.where((LanInterface i) => rank(i.name) == r),
  ];
  for (final LanInterface iface in ordered) {
    for (final String ip in iface.addresses) {
      if (isRfc1918(ip)) return ip;
    }
  }
  if (!allowNonPrivate) return null;
  for (final LanInterface iface in ordered) {
    if (iface.addresses.isNotEmpty) return iface.addresses.first;
  }
  return null;
}

/// Lit les interfaces du système et applique [pickLanIpv4]. `null` si aucune
/// adresse ne convient ou si la lecture échoue.
Future<String?> lanIpv4({bool allowNonPrivate = false}) async {
  try {
    final List<NetworkInterface> list = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    return pickLanIpv4(
      <LanInterface>[
        for (final NetworkInterface i in list)
          (
            name: i.name,
            addresses: <String>[
              for (final InternetAddress a in i.addresses) a.address,
            ],
          ),
      ],
      allowNonPrivate: allowNonPrivate,
    );
  } catch (e) {
    debugPrint('❌ lanIpv4 : $e');
    return null;
  }
}
