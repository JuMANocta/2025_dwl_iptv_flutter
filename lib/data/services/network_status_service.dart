import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/network_kind.dart';

/// §offlineBoot (2026-09-06, lot 6) — « Suis-je hors ligne ? », pour toute
/// l'app, sans plugin : le canal natif dit s'il y a un réseau actif
/// (`network_kind.dart`).
///
/// Tant qu'on est hors ligne, on re-regarde toutes les 15 s ; dès que le
/// réseau revient, [offline] repasse à `false` et chacun (bandeau, écran de
/// démarrage) réagit. Aucun sondage quand tout va bien.
abstract final class NetworkStatusService {
  /// `true` = aucun réseau actif. Défaut `false` : on ne suppose jamais une
  /// panne avant d'avoir regardé.
  static final ValueNotifier<bool> offline = ValueNotifier<bool>(false);

  static Timer? _poll;
  static const Duration _pollEvery = Duration(seconds: 15);

  /// Relit l'état du réseau et met [offline] à jour. Rend `true` si hors ligne.
  static Future<bool> refresh() async {
    final NetState s = await currentNetState();
    final bool off = s.kind == NetKind.none;
    if (offline.value != off) {
      offline.value = off;
      // (le cliquet l10n ne reconnaît un journal que sur la ligne du debugPrint)
      if (off) debugPrint('🔌 §offlineBoot — hors ligne (aucun réseau actif)');
      if (!off) debugPrint('🔌 §offlineBoot — connexion rétablie (${s.kind.name})');
    }
    if (off) {
      _poll ??= Timer.periodic(_pollEvery, (_) => refresh());
    } else {
      _poll?.cancel();
      _poll = null;
    }
    return off;
  }

  @visibleForTesting
  static void resetForTest() {
    _poll?.cancel();
    _poll = null;
    offline.value = false;
  }
}
