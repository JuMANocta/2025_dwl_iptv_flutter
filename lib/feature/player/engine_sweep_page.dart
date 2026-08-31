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

  /// §sweepAccount — De QUELLE liste vient le flux.
  ///
  /// ⚠️ Absent de la première version, et c'était un vrai manque : 29 des
  /// 37 échecs du balayage du 2026-08-30 étaient des liens morts, sans qu'on
  /// puisse dire s'ils venaient d'un seul fournisseur négligent ou des trois.
  /// Ce n'est pas le même diagnostic — et ça n'accuse pas le moteur.
  final String account;
  bool loaded = false;
  int? width;
  int? height;
  int audioTracks = 0;
  String? error;

  /// §sweepRetry — Vrai si le flux n'a réussi qu'à la SECONDE tentative.
  ///
  /// ⚠️ C'est l'arbitre entre deux explications d'un échec, et il fallait le
  /// rendre mesurable plutôt que d'en débattre : un flux qui échoue **deux
  /// fois de suite** accuse le format ; un flux qui passe au rattrapage accuse
  /// le harnais (enchaînement trop rapide, vue native pas encore prête).
  bool recovered = false;

  /// Échec CONFIRMÉ : les deux tentatives ont échoué.
  bool confirmedFailure = false;

  _SweepResult(this.container, this.title, this.account);

  /// ⚠️ « Chargé » ne suffit pas : un flux qui affiche l'image sans piste audio
  /// est un ÉCHEC pour l'utilisateur, et c'est précisément le symptôme attendu
  /// d'un DTS non décodable. Les deux conditions comptent.
  bool get ok => loaded && audioTracks > 0;

  String get line {
    final tag = recovered ? ' ⚠️RATTRAPÉ' : '';
    if (error != null) {
      return '❌ $container/$account · ${_short(title)} · ${confirmedFailure ? "x2 " : ""}$error';
    }
    if (!loaded) {
      return '⏱️ $container/$account · ${_short(title)} · '
          '${confirmedFailure ? "timeout x2" : "timeout"}';
    }
    final res = (width != null) ? '${width}x$height' : '?';
    final flag = audioTracks > 0 ? '✅' : '🔇';
    return '$flag $container/$account · ${_short(title)} · $res · ${audioTracks}a$tag';
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

  /// Abonnements posés UNE fois sur le contrôleur unique, et le résultat en
  /// cours qu'ils alimentent.
  final List<StreamSubscription<dynamic>> _subs = [];
  Completer<void>? _playing;
  _SweepResult? _current;

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
      // Démontage entre CHAQUE flux : un seul flux ouvert à la fois.
      if (_index < _queue.length - 1) await _teardown();
    }
    _summarise();
    if (mounted) setState(() => _done = true);
  }

  /// Prépare l'unique contrôleur, une fois pour toutes.
  ///
  /// ⚠️ **La version précédente créait un contrôleur NEUF par flux, et elle se
  /// bloquait au premier.** Diagnostic de l'utilisateur, vérifié au journal :
  /// un seul résultat produit puis plus rien. Chaque contrôleur ouvre une vue
  /// native **et une instance MediaCodec**, or un SoC n'en autorise qu'une
  /// poignée simultanément — et les précédentes n'étaient jamais vraiment
  /// démontées, puisqu'on appelait `dispose()` alors que l'arbre de widgets
  /// référençait encore la vue. Au deuxième flux, plus rien ne pouvait s'ouvrir.
  ///
  /// Réutiliser **un seul** contrôleur et enchaîner les `loadUrl` est de toute
  /// façon ce que le moteur définitif devra faire pour passer d'un épisode au
  /// suivant sans reconstruire la vue (l'équivalent de §episodeMeta).
  Future<NativeVideoPlayerController> _ensureController() async {
    final existing = _controller;
    if (existing != null) return existing;
    final c = NativeVideoPlayerController(
      id: 5000,
      autoPlay: true,
      showNativeControls: false,
      enableHDR: true,
      allowsPictureInPicture: false,
    );
    setState(() => _controller = c);
    // Laisse un frame à la vue native pour exister avant `initialize()`.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await c.initialize();
    _subs.add(c.playerStateStream.listen((st) {
      if (st == PlayerActivityState.playing && !(_playing?.isCompleted ?? true)) {
        _playing!.complete();
      }
    }));
    _subs.add(c.videoSizeStream.listen((sz) {
      _current?.width = sz.width.round();
      _current?.height = sz.height.round();
    }));
    return c;
  }

  Future<void> _test(M3uEntry entry) async {
    final ext = entry.url.substring(entry.url.lastIndexOf('.') + 1).toLowerCase();
    final res = _SweepResult(
      ext,
      entry.title.baseTitle,
      ParsedPlaylistService.accountName(entry.accountId) ?? entry.accountId,
    );
    _results.add(res);
    _current = res;

    await _attempt(entry, res);

    // §sweepRetry — Seconde chance, après une vraie remise à zéro et une pause.
    // ⚠️ Ne pas la supprimer « parce que ça double la durée » : sans elle, on
    // ne peut pas distinguer un format non supporté d'un artefact du harnais,
    // et tout le balayage perd sa valeur de preuve.
    if (!res.loaded) {
      res.error = null;
      await _teardown();
      await _attempt(entry, res);
      if (res.loaded) {
        res.recovered = true;
      } else {
        res.confirmedFailure = true;
      }
    }
    debugPrint('🧪 §engineSweep — ${res.line}');
  }

  /// Remise à zéro entre deux flux — **démontage COMPLET, pas une pause**.
  ///
  /// ⚠️ **La contrainte est le FOURNISSEUR, pas le décodeur.** L'abonnement de
  /// l'utilisateur n'autorise **qu'un flux à la fois** : tant que la connexion
  /// du flux précédent reste ouverte, le panel refuse la suivante et renvoie
  /// une réponse d'erreur — que le décodeur reçoit comme un format bidon, d'où
  /// le trompeur `MediaCodecVideoRenderer error, format=Format(0, nul…`. Les
  /// « échecs » observés au premier balayage étaient donc en bonne partie des
  /// FAUX POSITIFS, comme l'utilisateur le pressentait.
  ///
  /// ⚠️ Et `pause()` **ne ferme rien** : dans le paquet publié, `player.stop()`
  /// n'est appelé que par `handleDispose` — aucun arrêt n'est exposé. Le seul
  /// moyen de relâcher réellement la connexion est donc de **détruire le
  /// contrôleur**.
  ///
  /// ⚠️ **L'ORDRE est ce qui avait manqué la première fois** : détruire le
  /// contrôleur alors que l'arbre de widgets référence encore sa vue native ne
  /// libère ni la vue ni l'instance MediaCodec (d'où l'épuisement au 1er flux
  /// et le `NO_VIEW`). Il faut d'abord **démonter le widget** (`_controller =
  /// null` + `setState`), laisser passer une frame, PUIS disposer.
  ///
  /// C'est plus lent, et c'est voulu : un balayage qui produit de faux échecs
  /// ne mesure rien.
  Future<void> _teardown() async {
    final old = _controller;
    if (old == null) return;
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    // 1. Démonter la vue AVANT de disposer.
    if (mounted) setState(() => _controller = null);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // 2. Maintenant seulement, détruire — c'est ce qui appelle `player.stop()`
    //    côté natif et ferme la connexion au panel.
    try {
      old.dispose();
    } catch (_) {}
    // 3. Laisser le fournisseur libérer le créneau.
    await Future<void>.delayed(_settleDelay);
  }

  /// Temps laissé au FOURNISSEUR pour libérer le créneau de connexion après la
  /// fermeture du flux précédent.
  ///
  /// ⚠️ **Ne pas raccourcir pour gagner du temps.** Signalé deux fois par
  /// l'utilisateur (« tu vas trop vite pour passer de l'un à l'autre »), et la
  /// cause s'est révélée être la limite de flux simultanés de son abonnement.
  /// Mieux vaut dix minutes de plus qu'un verdict invalide.
  static const _settleDelay = Duration(seconds: 2);

  Future<void> _attempt(M3uEntry entry, _SweepResult res) async {
    _playing = Completer<void>();
    try {
      final c = await _ensureController();
      await c.loadUrl(
        url: entry.url,
        headers: const {'User-Agent': 'IPTVSmartersPro'}, // §iptvUaCompat
      );
      await _playing!.future.timeout(_perItem);
      res.loaded = true;
      // La liste des pistes n'est fiable qu'une fois la lecture engagée.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      res.audioTracks = (await c.getAvailableAudioTracks()).length;
    } on TimeoutException {
      // `loaded` reste false → ligne « timeout ».
    } catch (e) {
      res.error = e.toString().replaceAll('\n', ' ');
      if (res.error!.length > 90) res.error = '${res.error!.substring(0, 90)}…';
    } finally {
      // On met en pause entre deux flux sans détruire la vue : c'est
      // précisément ce qui saturait le décodeur.
      try {
        await _controller?.pause();
      } catch (_) {}
    }
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
      final rec = list.where((r) => r.recovered).length;
      debugPrint('🧪 §engineSweep — $ext : ${list.length} testés · '
          '$ok OK · $mute SANS AUDIO · $ko en échec CONFIRMÉ (x2)'
          '${rec > 0 ? " · $rec rattrapés au 2e essai" : ""}');
    });
    final total = _results.length;
    final ok = _results.where((r) => r.ok).length;
    // §sweepAccount — Le même décompte par LISTE : un taux d'échec concentré
    // sur un seul fournisseur ne dit pas la même chose qu'un taux diffus.
    final byAcc = <String, List<_SweepResult>>{};
    for (final r in _results) {
      byAcc.putIfAbsent(r.account, () => []).add(r);
    }
    byAcc.forEach((acc, list) {
      final dead = list.where((r) => (r.error ?? '').contains('Source')).length;
      final dec = list.where((r) =>
          (r.error ?? '').contains('MediaCodec')).length;
      debugPrint('🧪 §engineSweep — liste $acc : ${list.length} testés · '
          '${list.where((r) => r.ok).length} OK · $dead liens morts · '
          '$dec refus de décodeur');
    });

    final rec = _results.where((r) => r.recovered).length;
    debugPrint('🧪 §engineSweep — TOTAL : $ok/$total exploitables '
        '(${total == 0 ? 0 : (100 * ok / total).round()} %)');
    // ⚠️ Le chiffre qui juge le HARNAIS, pas les formats : s'il est élevé,
    // les échecs « confirmés » deviennent eux-mêmes suspects.
    debugPrint('🧪 §engineSweep — rattrapés au 2e essai : $rec '
        '(si > 0, le harnais est en cause autant que les formats)');
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
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
