import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cast_service.dart';
import 'fmp4_index.dart';

/// §castRelay — Le téléphone au milieu : il convertit le son du film en AAC
/// (côté natif, `AetherCastRelay.kt`) et **sert le résultat au téléviseur**
/// par un petit serveur HTTP local, pendant que la conversion continue.
///
/// **Pourquoi un serveur** : le récepteur Chromecast va chercher l'adresse
/// lui-même. Il lui faut donc une URL joignable sur le réseau local — d'où le
/// même patron que la Console web (`HttpServer` sur `anyIPv4`, adresse LAN
/// détectée sur l'interface WiFi).
///
/// **Pourquoi progressif et non HLS** (mesuré le 2026-09-04) : le récepteur
/// Philips rejette le HEVC servi en HLS (il télécharge init + 2 segments
/// puis part en IDLE — son moteur HLS/MSE ne décode pas le HEVC), alors que
/// son lecteur vidéo DIRECT le décode. On sert donc le fMP4 en flux
/// progressif continu. L'index `Fmp4Index` reste utile : il dit quand un
/// matelas suffisant est prêt avant de lancer la diffusion. Note d'origine :
/// servi d'un seul
/// tenant, le fichier qui grossit n'a ni taille ni durée connues. Le récepteur
/// a affiché « 00:02 » — le premier fragment — et n'a jamais avancé. Une liste
/// HLS de type EVENT dit exactement ce qui se passe : « voici ce qui existe, il
/// y en aura d'autres, et voici la fin quand elle arrive ». Chaque segment est
/// un fragment **complet** du MP4, servi par ses octets exacts (`Fmp4Index`).
///
/// ⚠️ **Rien ne démarre sans accord explicite de l'utilisateur** : la
/// conversion fait passer le film deux fois par son WiFi et occupe plusieurs
/// gigaoctets. La décision et le texte vivent dans `cast_relay_policy.dart`.
class CastRelayState {
  const CastRelayState({
    required this.url,
    required this.percent,
    required this.done,
    this.ready = Duration.zero,
    this.offset = Duration.zero,
    this.error,
  });

  /// Adresse à donner au récepteur (`http://192.168.x.y:port/relay.mp4`).
  final String url;

  /// Progression de la conversion, 0..100.
  final int percent;

  /// Conversion terminée (le fichier ne grossira plus).
  final bool done;

  /// Durée déjà servable au téléviseur.
  final Duration ready;

  /// §castResume — Où la conversion a COMMENCÉ dans le film. Le flux servi
  /// repart à zéro : toute position rapportée par le téléviseur doit se lire
  /// `offset + position` pour redevenir une position de film.
  final Duration offset;

  /// Message en clair si la conversion a échoué.
  final String? error;

  CastRelayState copyWith({
    int? percent,
    bool? done,
    Duration? ready,
    String? error,
  }) =>
      CastRelayState(
        url: url,
        percent: percent ?? this.percent,
        done: done ?? this.done,
        ready: ready ?? this.ready,
        offset: offset,
        error: error ?? this.error,
      );
}

abstract final class CastRelayService {
  static const MethodChannel _channel =
      MethodChannel('aetherstream/cast_relay');

  /// État de la conversion en cours, `null` si aucune.
  static final ValueNotifier<CastRelayState?> state =
      ValueNotifier<CastRelayState?>(null);

  /// Sans premier segment dans ce délai, on abandonne en le disant : un panel
  /// muet ne doit pas laisser l'utilisateur devant « Chargement » à vie.
  static const Duration firstSegmentTimeout = Duration(seconds: 60);

  /// Nombre de segments à avoir converti avant de donner l'adresse au
  /// téléviseur. ⚠️ Un seul segment (2 s) fait une liste famélique : le
  /// lecteur atteint la fin avant son premier rechargement. Trois segments
  /// donnent un vrai matelas sans faire attendre.
  static const int startupSegments = 3;

  static HttpServer? _server;
  static String? _filePath;
  static RandomAccessFile? _raf;
  static Fmp4Index? _index;
  static Future<void>? _refreshing;
  static bool _wired = false;

  /// Vrai tant que la conversion écrit encore dans le fichier.
  static bool _converting = false;

  /// ⚠️ **Le démarrage n'est pas instantané et l'utilisateur peut annuler
  /// pendant.** `start()` enchaîne plusieurs attentes (adresse réseau,
  /// lancement natif, ouverture du serveur) AVANT de publier son état : un
  /// `stop()` tombant dans cette fenêtre ne trouvait rien à arrêter, puis
  /// `start()` reprenait tranquillement son cours et envoyait quand même le
  /// flux au téléviseur. Ce compteur permet à chaque étape de vérifier
  /// qu'elle appartient toujours à la session en cours.
  static int _generation = 0;

  /// §castRelay — Position la plus avancée que le téléviseur a rapportée.
  /// Sert la REPRISE : si le récepteur relance le flux (l'utilisateur a
  /// touché la télécommande — constaté le 2026-09-04, ça repartait de
  /// zéro), on ne resert PAS depuis le début mais depuis le fragment de
  /// cette position. Monotone : un rembobinage n'efface pas la place.
  static Duration _maxPosition = Duration.zero;

  /// §castResume — Décalage de la conversion en cours (0 = depuis le début).
  static Duration _offset = Duration.zero;

  /// Position de film correspondant à une position rapportée par le
  /// téléviseur. Sans ce décalage, un film repris à 45 min s'enregistrerait
  /// comme vu depuis le début.
  static Duration filmPosition(Duration reported) => _offset + reported;

  static bool get isActive => state.value != null;

  /// Démarre la conversion et le serveur, attend le premier segment servable,
  /// puis rend l'adresse de la liste HLS à donner au récepteur. Lève une
  /// [CastRelayException] en clair sinon.
  ///
  /// [audioIndex] — rang, dans l'ordre du fichier, de la piste audio à
  /// convertir (`-1` : laisser Media3 choisir).
  ///
  /// [startAt] — §castResume : où commencer la conversion dans le film.
  static Future<String> start(
    String sourceUrl, {
    int audioIndex = -1,
    Duration startAt = Duration.zero,
  }) async {
    await stop();
    _ensureWired();
    final int gen = _generation;

    final String? ip = await _detectLocalIp();
    if (gen != _generation) throw const CastRelayCancelled();
    if (ip == null) {
      throw const CastRelayException(
        'Aucune adresse réseau : le téléviseur ne pourrait pas joindre le '
        'téléphone.',
      );
    }

    final Duration begin = startAt > Duration.zero ? startAt : Duration.zero;
    final String? path = await _channel.invokeMethod<String>(
      'start',
      {
        'url': sourceUrl,
        'audioIndex': audioIndex,
        'startMs': begin.inMilliseconds,
      },
    );
    if (gen != _generation) {
      // Annulé pendant le lancement natif : il tourne peut-être déjà.
      try {
        await _channel.invokeMethod('stop');
      } catch (_) {}
      throw const CastRelayCancelled();
    }
    if (path == null || path.isEmpty) {
      throw const CastRelayException("La conversion n'a pas pu démarrer.");
    }
    _filePath = path;
    _converting = true;
    _maxPosition = Duration.zero;
    _offset = begin;
    _index = Fmp4Index();

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    } catch (e) {
      debugPrint('❌ CastRelayService: bind impossible — $e');
      // `stop()` plutôt qu'un appel natif isolé : sinon `_filePath` et
      // `_converting` restaient posés et un `onRelayProgress` tardif
      // travaillait sur un fichier fantôme.
      await stop();
      throw const CastRelayException(
        'Impossible d\'ouvrir le relais sur le réseau local.',
      );
    }
    if (gen != _generation) {
      await stop();
      throw const CastRelayCancelled();
    }
    _server!.listen(_handle, onError: (Object e) {
      debugPrint('⚠️ CastRelayService: $e');
    });

    // ⚠️ **Progressif, PAS HLS.** Mesuré le 2026-09-04 : le récepteur
    // Philips télécharge la liste HLS + l'init + 2 segments HEVC, puis part
    // en IDLE — son moteur HLS/MSE ne décode pas le HEVC. Son lecteur
    // vidéo DIRECT, lui, le décode (le même film 4K envoyé en fichier
    // complet affichait l'image). On lui sert donc un flux progressif
    // continu (`/relay.mp4`), pas une liste de segments. Les endpoints HLS
    // restent servis, en repli/diagnostic.
    final String url = 'http://$ip:${_server!.port}/relay.mp4';
    debugPrint(
        '🎞️ §castRelay — conversion démarrée, relais progressif sur $url');
    state.value =
        CastRelayState(url: url, percent: 0, done: false, offset: begin);

    // ⚠️ Le relais n'existe QUE pour servir une diffusion : dès qu'elle
    // s'arrête (bouton, fin, connexion perdue), la conversion s'arrête et le
    // fichier temporaire est supprimé. Sans ça, plusieurs gigaoctets
    // resteraient dans le cache et le transcodage continuerait dans le vide.
    CastService.state.addListener(_onCastStateChanged);

    // ⚠️ Une liste vide ferait échouer le premier chargement côté récepteur :
    // on ne donne l'adresse qu'avec au moins un segment publiable.
    await _waitForFirstSegment();
    return url;
  }

  static Future<void> _waitForFirstSegment() async {
    final DateTime deadline = DateTime.now().add(firstSegmentTimeout);
    DateTime lastLog = DateTime.fromMillisecondsSinceEpoch(0);
    while (true) {
      // ⚠️ `stop()` a pu passer PENDANT l'attente (bouton « Annuler la
      // conversion », fin de la diffusion) : il vide `_filePath`. Sans ce
      // test, la boucle tournait jusqu'à son délai puis accusait la
      // source d'être « trop lente » — faux, et après une annulation
      // volontaire. On sort sans un mot : l'appelant sait déjà.
      if (_filePath == null) throw const CastRelayCancelled();
      // ⚠️ **L'instrument qui coupe le problème en deux.** Le 2026-09-04, la
      // conversion s'est arrêtée à 3 fragments sans un mot. Rien ne permettait
      // de distinguer « Media3 ne produit plus » de « mon index n'avance
      // plus » — deux causes opposées, deux corrections opposées. La taille du
      // fichier tranche : elle vient du système de fichiers, pas de l'index.
      if (DateTime.now().difference(lastLog) >= const Duration(seconds: 2)) {
        lastLog = DateTime.now();
        final String? p = _filePath;
        int size = -1;
        if (p != null) {
          try {
            final f = File(p);
            if (await f.exists()) size = await f.length();
          } catch (_) {}
        }
        final Fmp4Index? i = _index;
        debugPrint('🎞️ §castRelay — attente : fichier ${size ~/ 1024} Ko · '
            '${i?.fragmentCount ?? 0} fragments · '
            '${i?.segments(done: false).length ?? 0} segments publiables');
      }
      final String? error = state.value?.error;
      if (error != null) {
        await stop();
        throw CastRelayException(error);
      }
      await _refreshIndex();
      final Fmp4Index? idx = _index;
      final int ready =
          idx == null ? 0 : idx.segments(done: !_converting).length;
      if (idx != null &&
          idx.hasInit &&
          (ready >= startupSegments || (!_converting && ready > 0))) {
        debugPrint('🎞️ §castRelay — $ready segments prêts '
            '(${idx.readyDuration(done: !_converting).inSeconds} s)');
        return;
      }
      if (!_converting && state.value != null) {
        // Conversion finie sans un seul segment : fichier vide ou illisible.
        await stop();
        throw const CastRelayException(
          "La conversion n'a rien produit de lisible.",
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        await stop();
        throw const CastRelayException(
          "Le début du film n'est pas arrivé à temps : la source est trop "
          'lente pour être convertie.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  static void _onCastStateChanged() {
    final CastState? s = CastService.state.value;
    if (s == null) {
      if (state.value != null) {
        debugPrint('🎞️ §castRelay — diffusion terminée : arrêt du relais');
        unawaited(stop());
      }
      return;
    }
    // ⚠️ **La position ne compte que si elle vient de NOTRE flux.** Sans ce
    // test, la diffusion PRÉCÉDENTE (encore vivante le temps que la nouvelle
    // conversion démarre) alimentait `_maxPosition` : le serveur reprenait
    // alors 108 s trop loin dans un fichier qui venait de naître, et le
    // téléviseur refusait le flux (`IDLE (ERROR)`, constaté le 2026-09-05).
    final CastRelayState? mine = state.value;
    if (mine == null || s.url != mine.url) return;
    if (!s.live && s.position > _maxPosition) _maxPosition = s.position;
  }

  /// Arrête tout et **supprime le fichier temporaire** (plusieurs Go).
  static Future<void> stop() async {
    // Toute étape de `start()` encore en vol se saura périmée.
    _generation++;
    CastService.state.removeListener(_onCastStateChanged);
    // ⚠️ Attendre l'indexation en cours : sinon elle reprend APRÈS la
    // fermeture, voit `_raf == null` et rouvre un descripteur que plus
    // personne ne referme.
    try {
      await _refreshing;
    } catch (_) {}
    if (_server != null) {
      try {
        await _server!.close(force: true);
      } catch (_) {}
      _server = null;
    }
    if (_raf != null) {
      try {
        await _raf!.close();
      } catch (_) {}
      _raf = null;
    }
    if (_filePath != null || _converting) {
      try {
        await _channel.invokeMethod('stop');
      } catch (e) {
        debugPrint('⚠️ CastRelayService.stop : $e');
      }
    }
    _filePath = null;
    _index = null;
    _converting = false;
    _maxPosition = Duration.zero;
    _offset = Duration.zero;
    state.value = null;
  }

  // ── Index ─────────────────────────────────────────────────────────────────

  /// Met l'index à jour sur ce qui est écrit. Une seule lecture à la fois :
  /// le `RandomAccessFile` a une position, deux lecteurs se marcheraient dessus.
  static Future<void> _refreshIndex() {
    final Future<void>? inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final Future<void> f = _doRefresh().whenComplete(() => _refreshing = null);
    _refreshing = f;
    return f;
  }

  static Future<void> _doRefresh() async {
    final Fmp4Index? idx = _index;
    final String? path = _filePath;
    if (idx == null || path == null) return;
    final file = File(path);
    if (!await file.exists()) return;
    final int length = await file.length();
    // La session a pu être arrêtée pendant ces attentes : ne PAS rouvrir un
    // descripteur qui n'aurait plus de propriétaire.
    if (!identical(_index, idx) || _filePath != path) return;
    _raf ??= await file.open();
    final RandomAccessFile raf = _raf!;
    try {
      await idx.update(length, (int offset, int n) async {
        await raf.setPosition(offset);
        return raf.read(n);
      });
    } catch (e) {
      debugPrint('⚠️ §castRelay — index : $e');
    }
  }

  // ── Serveur ───────────────────────────────────────────────────────────────

  /// ⚠️ **L'instrument qui manquait.** Le récepteur refusait la diffusion en
  /// 400 ms et rien ne disait s'il avait seulement DEMANDÉ la liste. Sans ce
  /// journal, impossible de distinguer un manifeste refusé d'un flux jamais
  /// téléchargé — deux causes opposées.
  static Future<void> _handle(HttpRequest req) async {
    final String path = req.uri.path;
    req.response.done.then((_) {
      debugPrint('🌐 §castRelay — ${req.method} $path '
          '→ ${req.response.statusCode}');
    }, onError: (Object e) {
      debugPrint('🌐 §castRelay — ${req.method} $path → coupé ($e)');
    });
    return _serve(req);
  }

  static Future<void> _serve(HttpRequest req) async {
    final HttpResponse res = req.response;
    // CORS : le lecteur HLS du récepteur est du JavaScript qui télécharge
    // liste et segments par `fetch` — sans ces en-têtes il ne lit rien.
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    res.headers.set('Access-Control-Allow-Headers', '*');
    res.headers
        .set('Access-Control-Expose-Headers', 'Content-Length, Content-Range');
    res.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    if (req.method == 'OPTIONS') {
      res.statusCode = HttpStatus.noContent;
      await res.close();
      return;
    }

    final Fmp4Index? idx = _index;
    final String? path = _filePath;
    if (idx == null || path == null) {
      await _notFound(res);
      return;
    }

    try {
      final String p = req.uri.path;
      if (p == '/relay.mp4') {
        await _serveProgressive(req, res, path);
        return;
      }
      if (p == '/relay.m3u8') {
        await _refreshIndex();
        final String body = idx.hlsEventPlaylist(done: !_converting);
        final Uint8List bytes = Uint8List.fromList(body.codeUnits);
        res.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl');
        res.contentLength = bytes.length;
        if (req.method != 'HEAD') res.add(bytes);
        await res.close();
        return;
      }
      if (p == '/init.mp4') {
        await _refreshIndex();
        final int? end = idx.initEnd;
        if (end == null) {
          await _notFound(res);
          return;
        }
        await _serveBytes(req, res, path, 0, end);
        return;
      }
      if (p.startsWith('/seg/') && p.endsWith('.m4s')) {
        final int? i = int.tryParse(p.substring(5, p.length - 4));
        List<Fmp4Segment> segs = idx.segments(done: !_converting);
        if (i != null && i >= segs.length) {
          // Le récepteur est en avance sur notre dernier rafraîchissement.
          await _refreshIndex();
          segs = idx.segments(done: !_converting);
        }
        if (i == null || i < 0 || i >= segs.length) {
          await _notFound(res);
          return;
        }
        await _serveBytes(req, res, path, segs[i].start, segs[i].end);
        return;
      }
      await _notFound(res);
    } catch (e) {
      // Le récepteur a coupé (changement de contenu, arrêt) : normal.
      debugPrint('ℹ️ §castRelay — requête interrompue ($e)');
      try {
        await res.close();
      } catch (_) {}
    }
  }

  /// §castRelay — **Le flux progressif continu**, la seule voie que le
  /// récepteur sait décoder pour du HEVC. Un fMP4 se lit aussi bien en
  /// progressif qu'en segments : on envoie ftyp+moov puis les fragments au
  /// fur et à mesure qu'ils s'écrivent, dans UNE réponse qui ne se ferme
  /// qu'à la fin de la conversion.
  ///
  /// ⚠️ **Aucun `Content-Length`, aucun `Range`.** La taille finale est
  /// inconnue (le fichier grandit) ; annoncer une taille ou accepter un saut
  /// ferait croire au récepteur à une durée fixe — c'est ce qui donnait
  /// « 00:02 » figé. Réponse `200` en transfert chunké (Dart le fait dès
  /// qu'on ne fixe pas `contentLength`), `streamType: LIVE` côté Cast.
  static Future<void> _serveProgressive(
    HttpRequest req,
    HttpResponse res,
    String path,
  ) async {
    res.headers.contentType = ContentType('video', 'mp4');
    // On NE propose PAS le saut : un flux qui grandit n'a pas de fin connue.
    res.headers.set(HttpHeaders.acceptRangesHeader, 'none');
    res.statusCode = HttpStatus.ok;
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }
    final int gen = _generation;
    final file = File(path);
    await _refreshIndex();
    final Fmp4Index? idx = _index;
    final int initEnd = idx?.initEnd ?? 0;

    // ⚠️ **Reprise.** Chaque requête (re)commence par l'init (moov), PUIS
    // les fragments à partir de la dernière position connue — pas du
    // début. Quand le récepteur relance (télécommande), il reprend là où
    // il en était au lieu de repartir de zéro. `- 3 s` : petit
    // recouvrement pour ne pas sauter un bout.
    if (initEnd > 0) {
      await res.addStream(file.openRead(0, initEnd));
    }
    final Duration resumeAt = _maxPosition - const Duration(seconds: 3);
    int sent = idx?.byteOffsetForPosition(
          resumeAt > Duration.zero ? resumeAt : Duration.zero,
        ) ??
        initEnd;
    if (sent < initEnd) sent = initEnd;
    if (sent > initEnd) {
      debugPrint('🎞️ §castRelay — reprise à ${resumeAt.inSeconds}s '
          '(octet $sent)');
    }

    while (true) {
      // ⚠️ Sans ce test, une connexion abandonnée SANS nouvel octet à écrire
      // ne déclenchait aucune erreur : la boucle tournait toutes les 300 ms
      // jusqu'à la fin de la conversion, une fois par client parti.
      if (gen != _generation) break;
      final int size = await file.exists() ? await file.length() : 0;
      if (sent < size) {
        await res.addStream(file.openRead(sent, size));
        sent = size;
        continue;
      }
      if (!_converting) break; // conversion finie et tout est parti
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    await res.close();
  }

  static Future<void> _notFound(HttpResponse res) async {
    res.statusCode = HttpStatus.notFound;
    await res.close();
  }

  /// Sert `[start, end)` du fichier, avec un `Range` optionnel **à l'intérieur**
  /// de cet intervalle. Ici la taille est connue exactement : le `206` est
  /// honnête, contrairement au fichier entier qui grossit encore.
  static Future<void> _serveBytes(
    HttpRequest req,
    HttpResponse res,
    String path,
    int start,
    int end,
  ) async {
    final int total = end - start;
    int from = 0;
    int to = total - 1;
    final String? range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null && range.startsWith('bytes=')) {
      final List<String> parts = range.substring(6).split('-');
      final int? a = int.tryParse(parts[0].trim());
      final int? b = parts.length > 1 ? int.tryParse(parts[1].trim()) : null;
      if (a != null && a >= 0 && a < total) {
        from = a;
        if (b != null && b >= a && b < total) to = b;
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $from-$to/$total',
        );
      }
    }
    res.headers.contentType = ContentType('video', 'mp4');
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    res.contentLength = to - from + 1;
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }
    await res.addStream(File(path).openRead(start + from, start + to + 1));
    await res.close();
  }

  // ── Pont natif ────────────────────────────────────────────────────────────

  static void _ensureWired() {
    if (_wired) return;
    _wired = true;
    _channel.setMethodCallHandler((call) async {
      final args = (call.arguments as Map?) ?? const {};
      final CastRelayState? current = state.value;
      switch (call.method) {
        case 'onRelayProgress':
          if (current == null) return;
          await _refreshIndex();
          state.value = current.copyWith(
            percent: (args['percent'] as int?) ?? current.percent,
            ready: _index?.readyDuration(done: false),
          );
        case 'onRelayDone':
          _converting = false;
          if (current == null) return;
          await _refreshIndex();
          debugPrint('🎞️ §castRelay — conversion terminée');
          state.value = current.copyWith(
            percent: 100,
            done: true,
            ready: _index?.readyDuration(done: true),
          );
        case 'onRelayFailed':
          _converting = false;
          final String msg =
              (args['message'] as String?) ?? 'conversion impossible';
          final bool userFacing = (args['userFacing'] as bool?) ?? false;
          debugPrint('❌ §castRelay — $msg');
          if (current == null) return;
          state.value = current.copyWith(
            error: userFacing
                ? msg
                : 'La conversion a échoué : le téléphone ne sait pas relire '
                    'ce format.',
          );
      }
    });
  }

  /// Même détection que la Console web : on privilégie le WiFi.
  static Future<String?> _detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      if (interfaces.isEmpty) return null;
      String prioOf(String name) {
        final n = name.toLowerCase();
        if (n.startsWith('wlan') || n.contains('wifi')) return 'a';
        if (n.startsWith('eth')) return 'b';
        return 'c';
      }

      interfaces.sort((a, b) => prioOf(a.name).compareTo(prioOf(b.name)));
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.')) {
            return ip;
          }
        }
      }
      return interfaces.first.addresses.first.address;
    } catch (e) {
      debugPrint('❌ CastRelayService._detectLocalIp: $e');
      return null;
    }
  }

  /// Tests uniquement.
  @visibleForTesting
  static void resetForTest() {
    _generation++;
    unawaited(_server?.close(force: true));
    _server = null;
    unawaited(_raf?.close());
    _raf = null;
    _wired = false;
    _offset = Duration.zero;
    _filePath = null;
    _index = null;
    _converting = false;
    state.value = null;
  }
}

/// La conversion a été arrêtée pendant qu'on l'attendait (annulation
/// volontaire ou fin de diffusion) : rien à afficher, l'appelant le sait.
class CastRelayCancelled implements Exception {
  const CastRelayCancelled();
}

/// Erreur de relais, déjà écrite pour l'utilisateur.
class CastRelayException implements Exception {
  const CastRelayException(this.message);
  final String message;
  @override
  String toString() => message;
}
