import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// §hostGate — **Une requête à la fois par serveur.**
///
/// **Le défaut corrigé** : les abonnements IPTV de l'utilisateur sont limités à
/// UNE connexion simultanée (« Connexions 1 / 1 » dans la page Comptes). Or le
/// téléchargement d'un catalogue lançait les 6 actions `player_api.php` en
/// `Future.wait`, chacune sur un `Dio`/`HttpClient` neuf — jusqu'à 6 sockets
/// ouverts en même temps vers le même panel. Le panel répondait alors
/// `403 Too many connections` sur les requêtes en trop, et comme l'échec
/// était avalé silencieusement (§catalogTruth), un catalogue **amputé**
/// écrasait le catalogue complet précédent.
///
/// Ce portillon est une **file d'attente FIFO par hôte**, posée *autour* de
/// l'appel réseau : elle ne touche ni aux en-têtes, ni à l'User-Agent, ni au
/// `HttpClient` → le profil §iptvUaCompat reste intact.
///
/// ⚠️ **Le lecteur vidéo ne passe JAMAIS par ici.** Quand le panel annonce
/// `max_connections`, on règle la limite à `max_connections - 1` : la
/// connexion restante est réservée à la lecture. Sinon, ouvrir la fiche d'un
/// film pendant un rafraîchissement de liste couperait la vidéo.
///
/// ⚠️ **Le jeton est rendu dans un `finally`.** Une exception dans le corps
/// gardé qui ne rendrait pas son jeton bloquerait l'hôte **à vie** : plus
/// aucune requête vers ce serveur jusqu'au redémarrage de l'app.
///
/// ⚠️ **Pas de réentrance.** Un corps gardé qui appelle lui-même [run] sur le
/// même hôte s'attend lui-même : à profondeur 1, il ne se débloquera qu'au
/// dépassement du délai de file. Garder les appels réseau à plat.
abstract final class HostGate {
  /// Limite par défaut : **1 requête à la fois**. C'est la valeur sûre —
  /// tant qu'on n'a pas lu `max_connections` du panel, on suppose le pire.
  ///
  /// §hostGate — Réglable par `PerfConfig.hostMaxConcurrent` (appliqué au
  /// démarrage) : `0` signifie « déduire du panel », toute autre valeur force.
  /// ⚠️ Ne sert que de valeur de repli : un `setLimit` explicite, posé quand
  /// on connaît `max_connections`, gagne toujours.
  static int defaultLimit = 1;

  /// Délai maximal d'attente dans la file, quand l'appelant n'en impose pas.
  ///
  /// Généreux à dessein : sur un gros panel, une seule action peut prendre
  /// deux minutes et six actions s'enchaînent. Trop court = on transformerait
  /// une lenteur normale en échec de chargement.
  static Duration defaultQueueTimeout = const Duration(minutes: 5);

  static final Map<String, _HostState> _states = {};

  /// « serveur.tv » ou « serveur.tv:8080 » — un hôte nu, rien d'autre.
  static final RegExp _bareHost = RegExp(r'^[A-Za-z0-9._\-]+(:\d{1,5})?$');

  /// Exécute [body] en garantissant qu'au plus `limitFor(url)` corps tournent
  /// simultanément pour l'hôte de [url].
  ///
  /// [timeout] borne **l'attente dans la file**, pas la durée de [body] : une
  /// fois le jeton obtenu, le corps a tout son temps (c'est `Dio` qui borne le
  /// réseau). Dépassement → [HostGateTimeoutException].
  ///
  /// Une URL non analysable est exécutée **sans garde** : on ne bloque jamais
  /// sur un cas qu'on ne sait pas nommer.
  static Future<T> run<T>(
    String url,
    Future<T> Function() body, {
    Duration? timeout,
  }) async {
    final key = hostKeyOf(url);
    if (key == null) return body();

    final st = _stateFor(key);
    await _acquire(st, key, timeout ?? defaultQueueTimeout);
    try {
      return await body();
    } finally {
      // ⚠️ Le `finally` est le cœur du portillon : sans lui, une exception
      // (403, timeout Dio, JSON invalide…) laisserait l'hôte verrouillé.
      _release(st);
    }
  }

  /// Fixe le nombre de requêtes simultanées tolérées pour [urlOrHost].
  ///
  /// Appelé quand `AccountInfo.maxConnections` est connu, avec
  /// `max(1, maxConnections - 1)`.
  static void setLimit(String urlOrHost, int limit) {
    final key = hostKeyOf(urlOrHost);
    if (key == null) return;
    final next = limit < 1 ? 1 : limit;
    final st = _stateFor(key);
    if (st.limit == next) return;
    st.limit = next;
    debugPrint('🚦 §hostGate $key : limite → $next requête(s) simultanée(s)');
    // Une limite relevée doit libérer immédiatement les appels en attente.
    _drain(st);
  }

  /// Limite courante pour [urlOrHost] ([defaultLimit] si jamais réglée).
  static int limitFor(String urlOrHost) {
    final key = hostKeyOf(urlOrHost);
    if (key == null) return defaultLimit;
    return _states[key]?.limit ?? defaultLimit;
  }

  /// Nombre d'appels **en attente** d'un jeton pour [urlOrHost] (les appels en
  /// cours d'exécution ne comptent pas). Pour les tests et le journal.
  static int queueDepth(String urlOrHost) {
    final key = hostKeyOf(urlOrHost);
    if (key == null) return 0;
    return _states[key]?.waiting.length ?? 0;
  }

  /// Nombre d'appels **en cours** pour [urlOrHost]. Observabilité.
  static int activeCount(String urlOrHost) {
    final key = hostKeyOf(urlOrHost);
    if (key == null) return 0;
    return _states[key]?.active ?? 0;
  }

  /// Remet le portillon à zéro (tests uniquement).
  static void resetForTest() {
    _states.clear();
    defaultQueueTimeout = const Duration(minutes: 5);
  }

  /// Clé de file : `scheme://host:port`, en minuscules, port explicité.
  ///
  /// Accepte aussi bien une URL complète (`http://srv:8080/player_api.php?…`)
  /// qu'un hôte nu (`srv:8080`) — les deux formes doivent tomber sur la MÊME
  /// case, sinon `setLimit` réglerait une file que `run` n'utilise pas.
  /// Retourne `null` si rien d'exploitable.
  @visibleForTesting
  static String? hostKeyOf(String urlOrHost) {
    final s = urlOrHost.trim();
    if (s.isEmpty) return null;
    var uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) {
      // « srv:8080 » se parse en scheme=srv/path=8080 : on force un schéma.
      // ⚠️ Uniquement si la chaîne ressemble VRAIMENT à un hôte : `Uri.parse`
      // accepte « http://pas une url » en encodant les espaces dans le host,
      // et on inventerait une file pour une chaîne qui n'en est pas une.
      if (!_bareHost.hasMatch(s)) return null;
      uri = Uri.tryParse('http://$s');
    }
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.host.contains(' ') || uri.host.contains('%')) return null;
    final scheme = uri.scheme.isEmpty ? 'http' : uri.scheme.toLowerCase();
    final port = uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);
    return '$scheme://${uri.host.toLowerCase()}:$port';
  }

  // ── Implémentation ───────────────────────────────────────────────────────

  static _HostState _stateFor(String key) =>
      _states.putIfAbsent(key, () => _HostState());

  static Future<void> _acquire(
      _HostState st, String key, Duration timeout) async {
    if (st.active < st.limit) {
      st.active++;
      return;
    }
    final w = _Waiter();
    st.waiting.add(w);
    try {
      await w.granted.future.timeout(timeout);
    } on TimeoutException {
      if (w.granted.isCompleted) {
        // Course serrée : le jeton venait d'être transmis. On le rend, sinon
        // il serait perdu et l'hôte finirait bloqué.
        _release(st);
      } else {
        w.cancelled = true;
        st.waiting.remove(w);
      }
      throw HostGateTimeoutException(key, timeout);
    }
    // Jeton transmis par `_release` : `active` a déjà été maintenu.
  }

  static void _release(_HostState st) {
    // Transmission directe au premier de la file : `active` reste inchangé.
    while (st.waiting.isNotEmpty) {
      final w = st.waiting.removeFirst();
      if (w.cancelled) continue;
      w.granted.complete();
      return;
    }
    st.active--;
    if (st.active < 0) st.active = 0;
  }

  /// Libère autant d'attentes que la limite le permet (après un `setLimit`).
  static void _drain(_HostState st) {
    while (st.active < st.limit && st.waiting.isNotEmpty) {
      final w = st.waiting.removeFirst();
      if (w.cancelled) continue;
      st.active++;
      w.granted.complete();
    }
  }
}

/// L'attente dans la file a dépassé le délai autorisé.
class HostGateTimeoutException implements Exception {
  final String host;
  final Duration waited;

  const HostGateTimeoutException(this.host, this.waited);

  @override
  String toString() =>
      'HostGateTimeoutException($host — attente > ${waited.inSeconds} s)';
}

class _HostState {
  int limit = HostGate.defaultLimit;
  int active = 0;
  final Queue<_Waiter> waiting = Queue<_Waiter>();
}

class _Waiter {
  final Completer<void> granted = Completer<void>();
  bool cancelled = false;
}
