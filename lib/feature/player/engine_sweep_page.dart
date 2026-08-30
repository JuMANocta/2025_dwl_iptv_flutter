import 'dart:async';
import 'dart:math';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/material.dart';

import '../../core/themes/colors.dart';
import '../../data/models/m3u_entry.dart';
import '../../data/services/parsed_playlist_service.dart';

/// §engineSweep — **Le balayage qui doit trancher : garde-t-on libmpv ?**
///
/// ## La question, et pourquoi elle vaut un écran dédié
///
/// L'argument « libmpv est plus tolérant aux formats » a servi à justifier une
/// architecture à **deux moteurs**. Or il n'a jamais été mesuré, et les deux
/// chiffres qu'on a désormais le fragilisent :
///
/// - sur **92 670 films**, les conteneurs sont **99,1 % mkv+mp4** (85,3 % mkv,
///   13,9 % mp4), que Media3 lit nativement. Il ne reste que **790 `.avi`**
///   (0,85 %) et 6 divers ;
/// - garder libmpv coûte **39,9 Mo de natif sur un APK de 107,4 Mo**, soit
///   37 % du poids, pour un cas de repli qu'on n'a jamais chiffré.
///
/// ⚠️ **Ce qui reste VRAIMENT inconnu, et que ce balayage doit révéler** : les
/// **codecs audio à l'intérieur des MKV**. Les dumps ne portent aucune
/// information de codec, et chercher « DTS » dans les titres ne prouve rien —
/// le parsing les normalise. Or ExoPlayer **n'a pas de décodeur DTS logiciel**,
/// seulement du passthrough vers un appareil capable : un fichier peut donc
/// très bien se charger, afficher l'image… et n'avoir aucun son. D'où la
/// colonne **pistes audio**, qui compte autant que le succès du chargement.
///
/// ## Comment il conclut
///
/// - zéro échec, ou quelques dizaines → **on jette libmpv**, moteur unique ;
/// - échecs concentrés sur l'AVI → on le jette quand même, en assumant 0,85 % ;
/// - échecs diffus sur du MKV, surtout **sans audio** → le repli se justifie,
///   mais en **secours automatique sur erreur**, jamais en sélecteur exposé.
///
/// ⚠️ **Code JETABLE**, comme `EngineProbePage`. À supprimer avec la décision.
class EngineSweepPage extends StatefulWidget {
  const EngineSweepPage({super.key});

  @override
  State<EngineSweepPage> createState() => _EngineSweepPageState();
}

/// Le résultat d'un flux, tel qu'il partira dans le journal §tvLogs.
class _SweepResult {
  final String container;
  final String title;
  bool loaded = false;
  int? width;
  int? height;
  int audioTracks = 0;
  String? error;

  _SweepResult(this.container, this.title);

  /// ⚠️ « Chargé » ne suffit pas : un flux qui affiche l'image sans piste audio
  /// est un ÉCHEC pour l'utilisateur, et c'est précisément le symptôme attendu
  /// d'un DTS non décodable. Les deux conditions comptent.
  bool get ok => loaded && audioTracks > 0;

  String get line {
    if (error != null) return '❌ $container · ${_short(title)} · $error';
    if (!loaded) return '⏱️ $container · ${_short(title)} · timeout';
    final res = (width != null) ? '${width}x$height' : '?';
    final flag = audioTracks > 0 ? '✅' : '🔇';
    return '$flag $container · ${_short(title)} · $res · ${audioTracks}a';
  }

  static String _short(String s) => s.length <= 38 ? s : '${s.substring(0, 38)}…';
}

class _EngineSweepPageState extends State<EngineSweepPage> {
  /// Temps laissé à chaque flux pour démarrer. Assez pour un panel lent, assez
  /// court pour que le balayage complet reste tenable en une session.
  static const _perItem = Duration(seconds: 9);

  /// Échantillon par conteneur. L'AVI est SUR-représenté à dessein : c'est la
  /// population suspecte (0,85 % du catalogue mais le seul conteneur qu'ExoPlayer
  /// ne garantit pas), donc 60 sur ~790 — assez pour que le taux d'échec soit
  /// significatif, sans les 2 h que coûterait la population entière.
  static const _sampleMkv = 40;
  static const _sampleMp4 = 25;
  static const _maxAvi = 60;

  NativeVideoPlayerController? _controller;
  final List<_SweepResult> _results = [];
  List<M3uEntry> _queue = [];
  int _index = 0;
  bool _running = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _buildQueue();
  }

  /// Constitue l'échantillon depuis le catalogue déjà en mémoire.
  ///
  /// ⚠️ Le conteneur se lit dans l'**URL** (les panels Xtream servent
  /// `…/12345.mkv`), pas dans le modèle : `M3uEntry` ne porte pas cette
  /// information, elle ne sert à rien au reste de l'app.
  void _buildQueue() {
    final all = ParsedPlaylistService.entries;
    final byExt = <String, List<M3uEntry>>{'avi': [], 'mkv': [], 'mp4': []};
    for (final e in all) {
      final u = e.url.toLowerCase();
      final dot = u.lastIndexOf('.');
      if (dot < 0 || u.length - dot > 5) continue;
      final ext = u.substring(dot + 1);
      byExt[ext]?.add(e);
    }
    final rnd = Random(42); // graine fixe → balayage reproductible
    List<M3uEntry> pick(String ext, int n) {
      final list = List<M3uEntry>.from(byExt[ext] ?? const []);
      list.shuffle(rnd);
      return list.take(n).toList();
    }

    _queue = [
      ...pick('avi', _maxAvi),
      ...pick('mkv', _sampleMkv),
      ...pick('mp4', _sampleMp4),
    ];
    debugPrint('🧪 §engineSweep — file : ${_queue.length} flux '
        '(avi=${byExt['avi']?.length ?? 0} dispo, '
        'mkv=${byExt['mkv']?.length ?? 0}, mp4=${byExt['mp4']?.length ?? 0})');
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    for (_index = 0; _index < _queue.length; _index++) {
      if (!mounted) return;
      await _test(_queue[_index]);
      setState(() {});
    }
    _summarise();
    if (mounted) setState(() => _done = true);
  }

  Future<void> _test(M3uEntry entry) async {
    final ext = entry.url.substring(entry.url.lastIndexOf('.') + 1).toLowerCase();
    final res = _SweepResult(ext, entry.title.baseTitle);
    _results.add(res);

    // ⚠️ Un contrôleur NEUF par flux, avec un id distinct. Réutiliser le même a
    // donné `PlatformException(NO_VIEW)` lors du premier essai : la vue native
    // ne suit pas un rechargement enchaîné.
    final c = NativeVideoPlayerController(
      id: 5000 + _index,
      autoPlay: true,
      showNativeControls: false,
      enableHDR: true,
      allowsPictureInPicture: false,
    );
    setState(() => _controller = c);

    final playing = Completer<void>();
    final subs = <StreamSubscription<dynamic>>[
      c.playerStateStream.listen((s) {
        if (s == PlayerActivityState.playing && !playing.isCompleted) {
          playing.complete();
        }
      }),
      c.videoSizeStream.listen((s) {
        res.width = s.width.round();
        res.height = s.height.round();
      }),
    ];

    try {
      await c.initialize();
      await c.loadUrl(
        url: entry.url,
        headers: const {'User-Agent': 'IPTVSmartersPro'}, // §iptvUaCompat
      );
      await playing.future.timeout(_perItem);
      res.loaded = true;
      // La liste des pistes n'est fiable qu'une fois la lecture engagée.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      res.audioTracks = (await c.getAvailableAudioTracks()).length;
    } on TimeoutException {
      // Laissé tel quel : `loaded` reste false → ligne « timeout ».
    } catch (e) {
      res.error = e.toString().replaceAll('\n', ' ');
      if (res.error!.length > 90) res.error = '${res.error!.substring(0, 90)}…';
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
      try {
        await c.pause();
      } catch (_) {}
      c.dispose();
    }
    debugPrint('🧪 §engineSweep — ${res.line}');
  }

  /// Le verdict, en trois lignes, dans le journal — c'est ce qui se lit depuis
  /// la console web, l'écran du téléviseur n'étant pas fait pour un tableau.
  void _summarise() {
    final byExt = <String, List<_SweepResult>>{};
    for (final r in _results) {
      byExt.putIfAbsent(r.container, () => []).add(r);
    }
    debugPrint('🧪 §engineSweep — ═══ VERDICT ═══');
    byExt.forEach((ext, list) {
      final ok = list.where((r) => r.ok).length;
      final mute = list.where((r) => r.loaded && r.audioTracks == 0).length;
      final ko = list.where((r) => !r.loaded).length;
      debugPrint('🧪 §engineSweep — $ext : ${list.length} testés · '
          '$ok OK · $mute SANS AUDIO · $ko en échec');
    });
    final total = _results.length;
    final ok = _results.where((r) => r.ok).length;
    debugPrint('🧪 §engineSweep — TOTAL : $ok/$total exploitables '
        '(${total == 0 ? 0 : (100 * ok / total).round()} %)');
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // La vidéo tourne en fond, minuscule : on ne la regarde pas, mais le
          // lecteur a besoin d'une vue native vivante pour se charger.
          if (c != null)
            Positioned(
              right: 8,
              bottom: 8,
              width: 160,
              height: 90,
              child: NativeVideoPlayer(controller: c),
            ),
          SafeArea(child: _panel()),
        ],
      ),
    );
  }

  Widget _panel() {
    final ok = _results.where((r) => r.ok).length;
    final mute = _results.where((r) => r.loaded && r.audioTracks == 0).length;
    final ko = _results.where((r) => !r.loaded).length;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BALAYAGE MOTEUR MEDIA3',
              style: TextStyle(
                color: kAccentSecondary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.6,
              )),
          const SizedBox(height: 4),
          Text(
            _done
                ? 'Terminé — le verdict est dans le journal.'
                : (_running
                    ? '${_index + 1} / ${_queue.length}'
                    : '${_queue.length} flux à tester · ~'
                        '${(_queue.length * 10 / 60).ceil()} min'),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _chip('$ok OK', kSuccess),
            const SizedBox(width: 6),
            _chip('$mute sans audio', kWarning),
            const SizedBox(width: 6),
            _chip('$ko échec', kError),
          ]),
          const SizedBox(height: 10),
          if (!_running)
            FilledButton.tonalIcon(
              onPressed: _run,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Lancer le balayage'),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _results.length,
              itemBuilder: (_, i) => Text(
                _results[_results.length - 1 - i].line,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontFamily: 'monospace'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withAlpha(120)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 11)),
      );
}
