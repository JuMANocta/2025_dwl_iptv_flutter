import 'dart:async';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/material.dart';

import '../../core/themes/colors.dart';

/// §playerEngine — **Étape 1 : l'essai de vérité. Code JETABLE.**
///
/// ## Ce que cette page cherche, et pourquoi elle existe seule
///
/// La campagne du 2026-08-30 a montré que le téléviseur **ne bascule jamais en
/// HDR**, alors qu'il en est capable (il affiche l'Xbox Series X en HDR). La
/// cause est architecturale, pas un réglage : media_kit compose dans une
/// **texture Flutter**, or la documentation Android est explicite — « pour du
/// HDR 10 bits, il faut une SurfaceView », dont la Surface reçoit un **overlay
/// matériel** et part au contrôleur d'affichage **sans copie dans l'UI**.
///
/// `better_native_video_player` rend par défaut dans une `SurfaceView`
/// (`VideoPlayerView.kt`) et son contrôleur expose `enableHDR` (`true` par
/// défaut), qui ouvre la lecture HDR native dans ExoPlayer au lieu du
/// tone-mapping automatique. Cette page vérifie **une seule chose** :
///
/// > **le témoin HDR du téléviseur s'allume-t-il ?**
///
/// ⚠️ **Le juge est l'écran, pas le journal.** Si le témoin ne s'allume pas, il
/// n'y a aucun bénéfice à attendre d'un changement de moteur — on garde
/// `HDR = Allégé` sur media_kit, qui supprime déjà 100 % des pertes d'images,
/// et on supprime cette page. C'est précisément pour ne PAS construire
/// l'abstraction `AetherPlaybackEngine` avant d'avoir la réponse que l'essai
/// est isolé ici.
///
/// ## Ce qu'elle vérifie aussi, tant qu'on y est
///
/// Les inconnues bloquantes relevées au plan, dont deux sont déjà tranchées sur
/// signature (`startAt` couvre §resumeStart, `headers` couvre §iptvUaCompat) :
/// il reste à voir qu'elles **fonctionnent** contre un vrai panel.
///
/// ⚠️ **Manque identifié, sans contournement dans le paquet** : `setVolume` est
/// plafonné à `1.0`. Le boost 0→200 % (mpv `volume-max`, §audio) n'a **aucun**
/// équivalent — il demanderait un `LoudnessEnhancer` natif. À trancher avant
/// toute généralisation, pas ici.
///
/// ⚠️ **Aucun bypass SSL** n'est exposé par le paquet (le seul
/// `onBadCertificate` du code sert au Cast). Sans objet si la source est en
/// clair, rédhibitoire pour un panel en HTTPS à certificat invalide.
class EngineProbePage extends StatefulWidget {
  /// URL réseau réelle, prise dans le catalogue déjà chargé — on ne manipule
  /// jamais les identifiants du compte pour cet essai.
  final String url;

  /// Position de reprise (§resumeStart), pour vérifier `startAt` au passage.
  final Duration? startAt;

  final String title;

  const EngineProbePage({
    super.key,
    required this.url,
    required this.title,
    this.startAt,
  });

  @override
  State<EngineProbePage> createState() => _EngineProbePageState();
}

class _EngineProbePageState extends State<EngineProbePage> {
  late final NativeVideoPlayerController _controller;

  final List<StreamSubscription<dynamic>> _subs = [];

  String _status = 'initialisation…';
  String? _error;
  NativeVideoPlayerVideoSize? _size;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller = NativeVideoPlayerController(
      id: 4001,
      autoPlay: true,
      // Les contrôles natifs d'ExoPlayer captureraient le D-pad et masqueraient
      // ce qu'on veut observer. On ne garde que notre encart.
      showNativeControls: false,
      // Le cœur de l'essai : laisser passer le HDR natif au lieu du
      // tone-mapping automatique vers du SDR.
      enableHDR: true,
      allowsPictureInPicture: false,
      lockToLandscape: false,
    );
    _start();
  }

  Future<void> _start() async {
    // ⚠️ Les abonnements se posent AVANT `initialize()` : le paquet le demande
    // explicitement, sinon les premiers événements (dont l'erreur de
    // chargement, celle qui nous intéresse le plus) sont perdus.
    _subs.add(_controller.playerStateStream.listen((s) {
      _log('état=$s');
      if (mounted) setState(() => _status = s.toString());
    }));
    _subs.add(_controller.videoSizeStream.listen((s) {
      _log('taille=${s.width}×${s.height}');
      if (mounted) setState(() => _size = s);
    }));
    _subs.add(_controller.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    }));
    _subs.add(_controller.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d);
    }));

    try {
      await _controller.initialize();
      _log('contrôleur initialisé');
      await _controller.loadUrl(
        url: widget.url,
        // §iptvUaCompat — Les panels Xtream rejettent les UA navigateur par un
        // 500 muet. Le profil de requête doit être identique à celui de Dio.
        headers: const {'User-Agent': 'IPTVSmartersPro'},
        startAt: widget.startAt,
      );
      _log('chargement demandé · reprise=${widget.startAt ?? Duration.zero}');
    } catch (e) {
      _log('ÉCHEC : $e');
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Passe par `debugPrint` : le journal §tvLogs capture la sortie, donc le
  /// relevé se lit depuis la console web — seul canal sur ce téléviseur.
  void _log(String msg) => debugPrint('🧪 §playerEngine — $msg');

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: NativeVideoPlayer(
        controller: _controller,
        overlayBuilder: (context, _) => _hud(),
      ),
    );
  }

  /// Encart minimal. Il ne remplace pas §videoStats — les propriétés mpv
  /// n'existent pas ici — il donne juste de quoi savoir que la lecture est
  /// vivante pendant qu'on regarde le **téléviseur**.
  Widget _hud() {
    final size = _size;
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(170),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kAccentSecondary.withAlpha(120)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ESSAI MOTEUR MEDIA3',
                  style: TextStyle(
                    color: kAccentSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.4,
                  )),
              const SizedBox(height: 6),
              _line('Titre', widget.title),
              _line('État', _status),
              if (size != null) _line('Taille', '${size.width}×${size.height}'),
              _line('Position', '${_fmt(_position)} / ${_fmt(_duration)}'),
              if (_error != null)
                _line('ERREUR', _error!, color: kError),
              const SizedBox(height: 8),
              const SizedBox(
                width: 260,
                child: Text(
                  'Regarde le TÉLÉVISEUR, pas cet encart : le témoin HDR '
                  's\'allume-t-il ? C\'est la seule question de cet essai. '
                  'Retour pour quitter.',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: SizedBox(
          width: 260,
          child: Text(
            '$k : $v',
            style: TextStyle(color: color ?? Colors.white, fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}
