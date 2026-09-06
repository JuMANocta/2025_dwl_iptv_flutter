/// §deviceCaps (2026-09-06) — Ce que l'appareil SAIT FAIRE, tel que mesuré par
/// le canal natif `aetherstream/device` (`AetherDeviceCaps.kt`), et les règles
/// PURES qui en tirent un verdict.
///
/// **Le constat de départ** : la seule vérification au démarrage était « suis-je
/// un téléviseur ? ». Aucune détection de mémoire, de décodeur ni de
/// définition d'écran — et les profils Confort / Équilibré / Performance
/// restaient un choix manuel, « Confort » par défaut quel que soit le matériel.
///
/// ⚠️ **Décoder n'est pas afficher.** §video4k a mesuré une image sur trois
/// perdue à la SORTIE vidéo, pas à la source : un appareil peut savoir décoder
/// de la 4K et ne pas savoir l'afficher. Les deux questions sont posées
/// séparément, et la 4K exige les deux réponses.
library;

/// Un décodeur vidéo, tel que `MediaCodecList` le décrit.
class DecoderCaps {
  final String name;
  final bool hardware;
  final int maxWidth;
  final int maxHeight;

  /// Cadence maximale supportée en 1920×1080 ; `0` = taille non supportée.
  final double fps1080;

  /// Cadence maximale supportée en 3840×2160 ; `0` = taille non supportée.
  final double fps2160;

  const DecoderCaps({
    required this.name,
    required this.hardware,
    required this.maxWidth,
    required this.maxHeight,
    required this.fps1080,
    required this.fps2160,
  });

  bool get supports2160 => fps2160 > 0;
  bool get supports1080 => fps1080 > 0;

  static DecoderCaps? fromMap(Map<dynamic, dynamic>? m) {
    if (m == null) return null;
    return DecoderCaps(
      name: (m['name'] ?? '').toString(),
      hardware: m['hardware'] == true,
      maxWidth: (m['maxWidth'] as num?)?.toInt() ?? 0,
      maxHeight: (m['maxHeight'] as num?)?.toInt() ?? 0,
      fps1080: (m['fps1080'] as num?)?.toDouble() ?? 0,
      fps2160: (m['fps2160'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'hardware': hardware,
        'maxWidth': maxWidth,
        'maxHeight': maxHeight,
        'fps1080': fps1080,
        'fps2160': fps2160,
      };
}

/// L'écran : le mode COURANT (`width`/`height`) et le plus grand mode que
/// l'écran ANNONCE (`maxModeWidth`/`maxModeHeight`).
///
/// ⚠️ **§caps4kDisplay (2026-09-06) — l'écran n'est pas une vérité.** Sur le
/// téléviseur 4K de l'utilisateur, Android rendait 1920×1080 : la plupart des
/// téléviseurs Android font tourner l'INTERFACE en 1080p et sortent la vidéo
/// en 2160p natif par leur propre chemin. `Display.getMode()` décrit
/// l'interface, pas la dalle — et `getSupportedModes()` peut faire de même.
/// Conséquence : la 4K était refusée sur un écran 4K avec tous ses décodeurs.
/// Ce qui est lu ici est INFORMATIF ; seul le décodeur décide (cf.
/// `verdictFor`).
class DisplayCaps {
  final int width;
  final int height;
  final double refreshHz;
  final List<String> hdr;

  /// Le plus grand mode annoncé par l'écran (0 = inconnu).
  final int maxModeWidth;
  final int maxModeHeight;

  const DisplayCaps({
    required this.width,
    required this.height,
    required this.refreshHz,
    this.hdr = const [],
    this.maxModeWidth = 0,
    this.maxModeHeight = 0,
  });

  /// Le plus grand côté : un téléphone en portrait rend 1080×2340, un
  /// téléviseur 3840×2160 — dans les deux cas on compare au grand côté.
  int get longSide => width > height ? width : height;
  int get shortSide => width > height ? height : width;

  /// Le mode courant OU un mode annoncé atteint 2160p. `false` ne prouve
  /// RIEN (voir l'en-tête) : à n'utiliser que pour informer.
  bool get is2160 =>
      longSide >= 3840 ||
      shortSide >= 2160 ||
      maxModeWidth >= 3840 ||
      maxModeHeight >= 2160;

  /// L'écran annonce des modes plus grands que ce qu'il affiche pour
  /// l'interface : typique d'un téléviseur 4K.
  bool get announcesMoreThanShown =>
      maxModeWidth > width || maxModeHeight > height;

  static DisplayCaps? fromMap(Map<dynamic, dynamic>? m) {
    if (m == null || m['width'] == null) return null;
    int maxW = (m['maxModeWidth'] as num?)?.toInt() ?? 0;
    int maxH = (m['maxModeHeight'] as num?)?.toInt() ?? 0;
    // La sonde native envoie la liste des modes ; on n'en retient que le
    // plus grand (persisté ensuite sous `maxModeWidth`/`maxModeHeight`).
    final List? modes = m['modes'] as List?;
    if (modes != null) {
      for (final dynamic mode in modes) {
        if (mode is Map) {
          final int w = (mode['width'] as num?)?.toInt() ?? 0;
          final int h = (mode['height'] as num?)?.toInt() ?? 0;
          if (w * h > maxW * maxH) {
            maxW = w;
            maxH = h;
          }
        }
      }
    }
    return DisplayCaps(
      width: (m['width'] as num).toInt(),
      height: (m['height'] as num?)?.toInt() ?? 0,
      refreshHz: (m['refreshHz'] as num?)?.toDouble() ?? 0,
      hdr: ((m['hdr'] as List?) ?? const []).map((e) => e.toString()).toList(),
      maxModeWidth: maxW,
      maxModeHeight: maxH,
    );
  }

  Map<String, dynamic> toMap() => {
        'width': width,
        'height': height,
        'refreshHz': refreshHz,
        'hdr': hdr,
        'maxModeWidth': maxModeWidth,
        'maxModeHeight': maxModeHeight,
      };
}

class MemoryCaps {
  final int totalMb;
  final int availMb;
  final bool lowRamDevice;
  final int memoryClassMb;

  const MemoryCaps({
    required this.totalMb,
    required this.availMb,
    required this.lowRamDevice,
    required this.memoryClassMb,
  });

  static MemoryCaps? fromMap(Map<dynamic, dynamic>? m) {
    if (m == null || m['totalMb'] == null) return null;
    return MemoryCaps(
      totalMb: (m['totalMb'] as num).toInt(),
      availMb: (m['availMb'] as num?)?.toInt() ?? 0,
      lowRamDevice: m['lowRamDevice'] == true,
      memoryClassMb: (m['memoryClassMb'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'totalMb': totalMb,
        'availMb': availMb,
        'lowRamDevice': lowRamDevice,
        'memoryClassMb': memoryClassMb,
      };
}

/// Le verdict pour UNE définition demandée.
enum PlayVerdict {
  /// Rien ne s'y oppose.
  ok,

  /// Aucun décodeur n'accepte cette taille d'image.
  decoderTooSmall,

  /// Le décodeur suit, mais l'écran n'affiche pas cette définition.
  displayTooSmall,

  /// La sonde n'a pas de réponse (jamais mesurée, ou mesure incomplète) : on
  /// ne refuse RIEN sur une absence d'information.
  unknown,
}

/// Le profil de performance recommandé par la sonde.
enum SuggestedProfile { confort, equilibre, performance }

class DeviceCaps {
  final String model;
  final String manufacturer;
  final int sdk;
  final int cores;
  final MemoryCaps? memory;
  final DisplayCaps? display;

  /// Clés : `avc`, `hevc`, `av1`, `vp9`. Valeur nulle = aucun décodeur.
  final Map<String, DecoderCaps?> decoders;

  /// Quand la mesure a été faite (`null` = jamais).
  final DateTime? measuredAt;

  const DeviceCaps({
    required this.model,
    required this.manufacturer,
    required this.sdk,
    required this.cores,
    required this.memory,
    required this.display,
    required this.decoders,
    this.measuredAt,
  });

  static DeviceCaps fromMap(Map<dynamic, dynamic> m, {DateTime? measuredAt}) {
    final rawDec = (m['decoders'] as Map?) ?? const {};
    return DeviceCaps(
      model: (m['model'] ?? '').toString(),
      manufacturer: (m['manufacturer'] ?? '').toString(),
      sdk: (m['sdk'] as num?)?.toInt() ?? 0,
      cores: (m['cores'] as num?)?.toInt() ?? 0,
      memory: MemoryCaps.fromMap(m['memory'] as Map?),
      display: DisplayCaps.fromMap(m['display'] as Map?),
      decoders: {
        for (final k in const ['avc', 'hevc', 'av1', 'vp9'])
          k: DecoderCaps.fromMap(rawDec[k] as Map?),
      },
      measuredAt: measuredAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'model': model,
        'manufacturer': manufacturer,
        'sdk': sdk,
        'cores': cores,
        'memory': memory?.toMap(),
        'display': display?.toMap(),
        'decoders': {for (final e in decoders.entries) e.key: e.value?.toMap()},
      };

  /// La sonde a-t-elle mesuré ce qu'il faut pour rendre un verdict ?
  bool get isComplete =>
      display != null && decoders.values.any((d) => d != null);

  /// Le meilleur décodeur qui accepte du 2160p (matériel d'abord).
  DecoderCaps? get best2160 {
    DecoderCaps? best;
    for (final d in decoders.values) {
      if (d == null || !d.supports2160) continue;
      if (best == null || (d.hardware && !best.hardware)) best = d;
    }
    return best;
  }

  bool get canDecode2160 => best2160 != null;
  bool get canDisplay2160 => display?.is2160 ?? false;

  /// Verdict pour une définition annoncée par la liste (`4K`, `FHD`, `HD`,
  /// `SD`, ou `null` = inconnue).
  ///
  /// ⚠️ Seule la **4K** peut être refusée : c'est le seul cas où un appareil
  /// courant échoue vraiment. Une FHD s'affiche partout, quitte à être réduite.
  /// Et une définition inconnue ne se refuse jamais.
  ///
  /// ⚠️ **§caps4kDisplay (2026-09-06) — l'écran ne refuse plus rien.** La
  /// première version exigeait aussi un écran 2160p sur téléviseur : sur le
  /// téléviseur 4K de l'utilisateur, Android annonçait 1920×1080 (l'interface,
  /// pas la dalle) et la 4K était refusée avec tous ses décodeurs présents.
  /// Le décodeur, lui, est une mesure vraie : c'est lui seul qui tranche.
  /// `PlayVerdict.displayTooSmall` n'est plus jamais rendu (gardé pour les
  /// appelants qui l'énumèrent).
  PlayVerdict verdictFor(String? quality) {
    if (quality == null) return PlayVerdict.ok;
    final q = quality.toUpperCase();
    final bool wants2160 = q == '4K' || q == 'UHD' || q == '2160P';
    if (!wants2160) return PlayVerdict.ok;
    if (!isComplete) return PlayVerdict.unknown;
    if (!canDecode2160) return PlayVerdict.decoderTooSmall;
    return PlayVerdict.ok;
  }

  /// Le profil recommandé, à partir de la mémoire et des cœurs.
  ///
  /// Confort = le comportement historique (le plus riche visuellement) ;
  /// Performance = le plus léger. ⚠️ `lowRamDevice` est un drapeau posé par le
  /// constructeur, pas une mesure — on le croit, mais on regarde aussi la RAM.
  SuggestedProfile get suggestedProfile {
    final mem = memory;
    if (mem == null) return SuggestedProfile.confort;
    if (mem.lowRamDevice || mem.totalMb < 2048) return SuggestedProfile.performance;
    if (mem.totalMb < 3500 || (cores > 0 && cores <= 4)) {
      return SuggestedProfile.equilibre;
    }
    return SuggestedProfile.confort;
  }
}
