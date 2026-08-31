import 'dart:async';
import 'dart:math';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter/material.dart';

import '../../core/themes/colors.dart';
import '../../data/models/m3u_entry.dart';
import '../../data/services/parsed_playlist_service.dart';
import 'player_controller.dart';

/// §engineDuel — **Le témoin qui manquait : les DEUX moteurs, mêmes fichiers.**
///
/// ## Pourquoi cette page existe
///
/// Le balayage §engineSweep a mesuré ce que **Media3** sait faire : 7 refus de
/// décodage sur 125 flux (5,6 %), plus un fichier muet. Mais il n'a **pas**
/// mesuré l'écart entre les moteurs, et c'est pourtant la seule question qui
/// décide : **libmpv sauve-t-il ces fichiers, oui ou non ?**
///
/// - S'il les sauve → le repli automatique se justifie, on garde les 39,9 Mo.
/// - S'il échoue aussi → ces échecs n'accusent plus le choix de moteur, ils
///   accusent les fichiers. Et **libmpv part**, avec 37 % de l'APK.
///
/// ⚠️ Sans ce témoin, tout chiffre de §engineSweep reste ininterprétable : on
/// ne sait pas si 5,6 % est bon ou mauvais **par rapport à quoi**.
///
/// ## L'échantillon
///
/// Les **8 cas problématiques identifiés** (recherchés par titre), plus un
/// tirage aléatoire à graine fixe pour donner une ligne de base. Chaque fichier
/// passe dans Media3 **puis** dans media_kit, avec démontage complet entre les
/// deux — l'abonnement de l'utilisateur n'autorise **qu'un flux à la fois**.
///
/// ⚠️ **Code JETABLE**, comme les deux autres pages d'essai.
class EngineDuelPage extends StatefulWidget {
  const EngineDuelPage({super.key});

  @override
  State<EngineDuelPage> createState() => _EngineDuelPageState();
}

/// Verdict d'un fichier, moteur par moteur.
class _Duel {
  final String title;
  final String container;
  final String account;
  final bool suspect;

  bool? media3Ok;
  int media3Audio = 0;
  String? media3Err;

  bool? mpvOk;
  int mpvAudio = 0;
  String? mpvErr;

  _Duel(this.title, this.container, this.account, this.suspect);

  /// LE cas qui justifierait de garder libmpv : Media3 perd, mpv rattrape.
  bool get mpvSaves => media3Ok == false && mpvOk == true;

  /// Les deux échouent : le fichier est en cause, pas le moteur.
  bool get bothFail => media3Ok == false && mpvOk == false;

  String get line {
    String fmt(bool? ok, int audio, String? err) {
      if (ok == null) return '—';
      if (!ok) {
        if (err == 'figé') return '❌figé';
        return '❌${err != null && err.contains("Source") ? "lien" : "dec"}';
      }
      return audio > 0 ? '✅${audio}a' : '🔇';
    }

    final flag = mpvSaves ? '  ⭐MPV SAUVE' : (bothFail ? '  (les 2 échouent)' : '');
    return '${suspect ? "🎯" : "· "} $container/$account · '
        '${title.length > 30 ? "${title.substring(0, 30)}…" : title} · '
        'media3=${fmt(media3Ok, media3Audio, media3Err)} · '
        'mpv=${fmt(mpvOk, mpvAudio, mpvErr)}$flag';
  }
}

class _EngineDuelPageState extends State<EngineDuelPage> {
  /// Les cas que §engineSweep a vus échouer côté Media3, à retrouver par titre.
  static const _suspects = <String>[
    'Babylon 5',
    'Yu-Gi-Oh',
    'Le ciel est partout',
    'Kurtlar Vadisi',
    'Lethal Weapon',
    'Sakura',
    'Larguées',
    'Les Blagues de Toto',
  ];

  static const _baseline = 12;

  /// §duelLive — Chaînes TV incluses à la demande de l'utilisateur.
  ///
  /// ⚠️ Elles ne se repèrent PAS à l'extension : une chaîne Xtream sort en
  /// `.ts` ou en URL nue (format « Ultimate »). On les prend par leur TYPE.
  ///
  /// ⚠️ Et ce sont elles qui rendent l'arrêt franc indispensable : un flux live
  /// ne se termine jamais, sa connexion reste ouverte tant qu'on ne détruit pas
  /// le lecteur — or l'abonnement n'autorise qu'un flux à la fois.
  static const _liveSample = 8;
  static const _perItem = Duration(seconds: 10);

  /// §duelStrict — **La même preuve est exigée des DEUX moteurs.**
  ///
  /// ⚠️ La première version comparait deux choses différentes : Media3 devait
  /// vraiment lire, tandis que mpv était compté « OK » dès que
  /// `stream.playing` passait à vrai — un état qui peut être atteint alors que
  /// le flux ne délivre rien. Résultat, mpv affichait `🔇` sur les 8 chaînes
  /// que Media3 lisait avec audio, tout en étant crédité de 2 « sauvetages »
  /// sur des liens morts. **Le verdict penchait en sa faveur par construction**,
  /// et il aurait fait conclure de garder libmpv sur un artefact de mesure.
  ///
  /// Le critère commun, vérifiable de la même façon des deux côtés : après le
  /// premier signal de lecture, **la position doit avoir réellement avancé**
  /// sur une fenêtre de [_stableFor]. Une position figée = pas de lecture,
  /// quel que soit ce que le moteur prétend.
  static const _stableFor = Duration(seconds: 3);
  static const _minProgress = Duration(milliseconds: 500);
  static const _settle = Duration(seconds: 2);

  /// §duelFairness — Le contrôleur media_kit est MONTÉ pendant son essai.
  ///
  /// ⚠️ Sans surface de sortie, media_kit peut ne jamais rendre la main sur
  /// `open()` — observé sur émulateur, le duel s'est figé au 1er fichier. Le
  /// borner par un délai aurait été pire que le mal : Media3 reçoit une vraie
  /// vue native pendant son essai, alors mpv aurait accumulé des échecs dus à
  /// l'ABSENCE DE SORTIE et non à un défaut de décodage. Le verdict aurait
  /// penché contre lui pour une raison qui n'a rien à voir avec la question
  /// posée. Les deux moteurs doivent jouer à armes égales.
  AetherPlayerController? _mpv;

  NativeVideoPlayerController? _m3;
  final List<StreamSubscription<dynamic>> _m3subs = [];
  Completer<void>? _m3playing;

  final List<_Duel> _results = [];
  final List<M3uEntry> _queue = [];
  final List<bool> _isSuspect = [];
  int _index = 0;
  bool _running = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _buildQueue();
  }

  void _buildQueue() {
    final all = ParsedPlaylistService.entries;
    final playable = all.where((e) {
      final u = e.url.toLowerCase();
      final dot = u.lastIndexOf('.');
      if (dot < 0 || u.length - dot > 5) return false;
      return const {'avi', 'mkv', 'mp4'}.contains(u.substring(dot + 1));
    }).toList();

    // 1. Les suspects, par correspondance de titre (le premier qui matche).
    for (final needle in _suspects) {
      final low = needle.toLowerCase();
      final hit = playable.where(
          (e) => e.title.baseTitle.toLowerCase().contains(low));
      if (hit.isNotEmpty) {
        _queue.add(hit.first);
        _isSuspect.add(true);
      }
    }
    // 2. Une ligne de base tirée au sort, graine fixe.
    final rest = List<M3uEntry>.from(playable)..shuffle(Random(7));
    for (final e in rest.take(_baseline)) {
      _queue.add(e);
      _isSuspect.add(false);
    }

    // 3. §duelLive — Des chaînes TV, prises par TYPE et non par extension.
    final live = all.where((e) => e.type == M3uContentType.tv).toList()
      ..shuffle(Random(11));
    for (final e in live.take(_liveSample)) {
      _queue.add(e);
      _isSuspect.add(false);
    }
    debugPrint('⚔️ §engineDuel — file : ${_queue.length} fichiers '
        '(${_isSuspect.where((s) => s).length} suspects retrouvés)');
  }

  /// Étiquette de format : le type pour une chaîne (pas d'extension fiable),
  /// l'extension pour un fichier.
  String _label(M3uEntry e) {
    if (e.type == M3uContentType.tv) return 'tv';
    final u = e.url.toLowerCase();
    final dot = u.lastIndexOf('.');
    if (dot < 0 || u.length - dot > 5) return '?';
    return u.substring(dot + 1);
  }

  Future<void> _run() async {
    setState(() => _running = true);
    for (_index = 0; _index < _queue.length; _index++) {
      if (!mounted) return;
      final entry = _queue[_index];
      final d = _Duel(
        entry.title.baseTitle,
        _label(entry),
        ParsedPlaylistService.accountName(entry.accountId) ?? '?',
        _isSuspect[_index],
      );
      _results.add(d);

      await _testMedia3(entry, d);
      await _teardownMedia3();
      await _testMpv(entry, d);
      await Future<void>.delayed(_settle);

      debugPrint('⚔️ §engineDuel — ${d.line}');
      if (mounted) setState(() {});
    }
    _summarise();
    if (mounted) setState(() => _done = true);
  }

  // ── Moteur A : Media3 ──────────────────────────────────────────────────────

  Future<void> _testMedia3(M3uEntry entry, _Duel d) async {
    _m3playing = Completer<void>();
    try {
      final c = NativeVideoPlayerController(
        id: 6000,
        autoPlay: true,
        showNativeControls: false,
        enableHDR: true,
        allowsPictureInPicture: false,
      );
      setState(() => _m3 = c);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await c.initialize();
      _m3subs.add(c.playerStateStream.listen((s) {
        if (s == PlayerActivityState.playing &&
            !(_m3playing?.isCompleted ?? true)) {
          _m3playing!.complete();
        }
      }));
      await c.loadUrl(
        url: entry.url,
        headers: const {'User-Agent': 'IPTVSmartersPro'},
      );
      await _m3playing!.future.timeout(_perItem);
      // §duelStrict — La position doit AVANCER, pas seulement l'état changer.
      final p0 = c.currentPosition;
      await Future<void>.delayed(_stableFor);
      final p1 = c.currentPosition;
      if (p1 - p0 < _minProgress) {
        d.media3Ok = false;
        d.media3Err = 'figé';
        return;
      }
      d.media3Audio = (await c.getAvailableAudioTracks()).length;
      d.media3Ok = true;
    } on TimeoutException {
      d.media3Ok = false;
      d.media3Err = 'timeout';
    } catch (e) {
      d.media3Ok = false;
      d.media3Err = e.toString();
    }
  }

  /// ⚠️ Démontage dans l'ORDRE : widget d'abord, contrôleur ensuite. C'est ce
  /// qui manquait au premier balayage et qui saturait MediaCodec.
  Future<void> _teardownMedia3() async {
    final old = _m3;
    for (final s in _m3subs) {
      await s.cancel();
    }
    _m3subs.clear();
    // §duelLive — Couper la lecture AVANT de démonter. Sur une chaîne live,
    // le flux ne s'arrête jamais tout seul : sans ça la connexion resterait
    // ouverte jusqu'au `dispose`, et le fournisseur refuserait la suivante.
    try {
      await old?.pause();
    } catch (_) {}
    if (mounted) setState(() => _m3 = null);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    try {
      old?.dispose();
    } catch (_) {}
    await Future<void>.delayed(_settle);
  }

  // ── Moteur B : media_kit / libmpv ─────────────────────────────────────────

  /// ⚠️ Pas de `VideoController` affiché : on teste la capacité à **ouvrir et
  /// décoder**, pas à afficher. `AetherPlayerController` en crée un de toute
  /// façon, ce qui suffit à exercer le vrai chemin.
  Future<void> _testMpv(M3uEntry entry, _Duel d) async {
    // ⚠️ Borne la séquence ENTIÈRE, pas seulement l'attente de lecture.
    // Observé sur émulateur : `open()` peut ne jamais rendre la main quand
    // aucun widget `Video()` n'est monté (media_kit attend une sortie vidéo qui
    // n'existe pas). Un `timeout` posé seulement sur `playing.future` ne protège
    // alors de rien, et le duel se fige au premier fichier.
    try {
      await _testMpvInner(entry, d).timeout(_perItem * 2);
    } on TimeoutException {
      d.mpvOk = false;
      d.mpvErr = 'timeout global';
    }
  }

  Future<void> _testMpvInner(M3uEntry entry, _Duel d) async {
    final ctrl = AetherPlayerController();
    // Monte la sortie vidéo AVANT d'ouvrir : c'est ce qui manquait.
    if (mounted) setState(() => _mpv = ctrl);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final playing = Completer<void>();
    final subs = <StreamSubscription<dynamic>>[
      ctrl.player.stream.playing.listen((p) {
        if (p && !playing.isCompleted) playing.complete();
      }),
      ctrl.player.stream.error.listen((e) {
        if (!playing.isCompleted) playing.completeError(e);
      }),
    ];
    try {
      await ctrl.open(entry.url);
      await playing.future.timeout(_perItem);
      // §duelStrict — Rigoureusement le même contrôle que pour Media3 : la
      // position doit avoir avancé sur la même fenêtre. C'est ce qui rend les
      // deux colonnes comparables.
      final p0 = ctrl.player.state.position;
      await Future<void>.delayed(_stableFor);
      final p1 = ctrl.player.state.position;
      if (p1 - p0 < _minProgress) {
        d.mpvOk = false;
        d.mpvErr = 'figé';
        return;
      }
      // ⚠️ Le relevé des pistes vient APRÈS la fenêtre de stabilité : sur du
      // live, la liste de media_kit n'est pas peuplée avant. Compter trop tôt
      // produisait des `🔇` qui n'existaient pas.
      d.mpvAudio = ctrl.player.state.tracks.audio
          .where((t) => t.id != 'no' && t.id != 'auto')
          .length;
      d.mpvOk = true;
    } on TimeoutException {
      d.mpvOk = false;
      d.mpvErr = 'timeout';
    } catch (e) {
      d.mpvOk = false;
      d.mpvErr = e.toString();
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
      // §duelLive — Même précaution côté mpv : couper, puis démonter, puis
      // détruire. Indispensable sur une chaîne, qui ne se termine jamais.
      try {
        await ctrl.player.pause();
      } catch (_) {}
      if (mounted) setState(() => _mpv = null);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      ctrl.dispose();
    }
  }

  void _summarise() {
    final saves = _results.where((r) => r.mpvSaves).length;
    final both = _results.where((r) => r.bothFail).length;
    final m3ko = _results.where((r) => r.media3Ok == false).length;
    final mpvko = _results.where((r) => r.mpvOk == false).length;
    debugPrint('⚔️ §engineDuel — ═══ VERDICT ═══');
    debugPrint('⚔️ §engineDuel — ${_results.length} fichiers · '
        'Media3 échoue $m3ko · mpv échoue $mpvko · les deux échouent $both');
    final m3mute = _results.where((r) => r.media3Ok == true && r.media3Audio == 0).length;
    final mpvmute = _results.where((r) => r.mpvOk == true && r.mpvAudio == 0).length;
    debugPrint('⚔️ §engineDuel — sans audio : media3 $m3mute · mpv $mpvmute');
    debugPrint('⚔️ §engineDuel — ⭐ mpv RATTRAPE $saves fichier(s) que Media3 '
        'perd — c\'est le SEUL chiffre qui justifierait de garder libmpv');
    debugPrint('⚔️ §engineDuel — (critère IDENTIQUE des 2 côtés : position '
        'avancée de ${_minProgress.inMilliseconds} ms sur '
        '${_stableFor.inSeconds} s)');
  }

  @override
  void dispose() {
    for (final s in _m3subs) {
      s.cancel();
    }
    _m3?.dispose();
    _mpv?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _m3;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (c != null)
            Positioned(
              right: 8,
              bottom: 8,
              width: 140,
              height: 80,
              child: NativeVideoPlayer(controller: c),
            ),
          if (_mpv != null)
            Positioned(
              right: 156,
              bottom: 8,
              width: 140,
              height: 80,
              child: Video(controller: _mpv!.videoController, controls: null),
            ),
          SafeArea(child: _panel()),
        ],
      ),
    );
  }

  Widget _panel() {
    final saves = _results.where((r) => r.mpvSaves).length;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DUEL MEDIA3 ⚔ MEDIA_KIT',
              style: TextStyle(
                  color: kAccentSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.6)),
          Text(
            _done
                ? 'Terminé — verdict dans le journal.'
                : (_running
                    ? '${_index + 1} / ${_queue.length}'
                    : '${_queue.length} fichiers × 2 moteurs · '
                        '~${(_queue.length * 30 / 60).ceil()} min'),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text('⭐ mpv rattrape : $saves',
              style: TextStyle(color: kWarning, fontSize: 13)),
          const SizedBox(height: 8),
          if (!_running)
            FilledButton.tonalIcon(
              onPressed: _run,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Lancer le duel'),
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
}
