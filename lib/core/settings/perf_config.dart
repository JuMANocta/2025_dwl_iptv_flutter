import 'package:flutter/material.dart';

/// §perfSettings — Configuration des optimisations de rendu, sérialisable pour
/// SharedPreferences (même pattern que `AppThemeConfig`).
///
/// Cible : Fire Stick et box faibles. L'utilisateur choisit lui-même ce qu'il
/// coupe au lieu qu'on devine une config unique — le hero fan (empilement de
/// cartes + ombres = le plus gros poste de coût au 1er paint) et le nombre de
/// vignettes par rangée sont les leviers principaux.
@immutable
class PerfConfig {
  /// Affiche le hero fan en tête de la home.
  final bool heroEnabled;

  /// Auto-rotation 6 s du hero (repaints périodiques). Sans effet si
  /// [heroEnabled] est false. Le swipe/tap manuel reste toujours actif.
  final bool heroAutoRotate;

  /// Nombre de cartes empilées dans le hero (bornes [minHeroCards]-[maxHeroCards]).
  final int heroCardCount;

  /// Vignettes affichées par rangée de catégorie avant la tuile « Voir tout »
  /// (bornes [minItemsPerRow]-[maxItemsPerRowLimit]). Favoris exemptés (jamais
  /// tronqués).
  final int maxItemsPerRow;

  /// Plafond du cache image **en mémoire** (Mo), appliqué à
  /// `PaintingBinding.instance.imageCache` (défaut Flutter : 100 Mo).
  ///
  /// ⚠️ **§imgThrash — corrigé le 2026-08-05.** La version précédente
  /// descendait SOUS le défaut Flutter (80 / 60 / **40** Mo) en présentant la
  /// baisse comme un gain : le cache disque absorbant les évictions, on croyait
  /// pouvoir réduire sans dommage. C'était faux. Réduire ce cache ne réduit pas
  /// la mémoire nécessaire pour AFFICHER un écran : ça force seulement à
  /// re-décoder en boucle, ce qui a rendu la TV saccadée et fait clignoter les
  /// vignettes (elles disparaissaient puis revenaient).
  ///
  /// Le vrai levier était ailleurs : décoder les images à leur taille
  /// d'affichage (cf. `decodeWidthFor`), ce qui divise leur coût par ~3. À
  /// mémoire égale, le cache contient donc désormais 3× plus de vignettes.
  final int imageCacheMb;

  /// §autoNextEp — Enchaîne automatiquement l'épisode suivant à la fin d'un
  /// épisode, après un court décompte annulable.
  ///
  /// Volontairement **hors des profils** de performance : c'est un choix de
  /// confort, pas un levier de fluidité — les 3 presets le laissent donc
  /// intact. `true` par défaut, comme sur les plateformes de streaming.
  ///
  /// Ne s'applique jamais aux chaînes live ni au replay, et jamais au
  /// franchissement de saison (qui demande toujours une confirmation).
  final bool autoNextEpisode;

  /// §posterLang — Préférer l'affiche TMDB à celle de la liste IPTV.
  ///
  /// Par défaut **`false`**, et ce n'est pas de la prudence de principe : la
  /// règle actuelle (l'image vient du fournisseur le plus riche, TMDB seulement
  /// si toutes ont échoué) ne coûte **aucun** appel réseau suppplémentaire.
  /// Activer ce drapeau demande une résolution TMDB par titre concerné au
  /// premier passage — absorbée ensuite par `TmdbPosterCache` (persisté) et le
  /// cache disque des images, mais bien réelle la première fois.
  ///
  /// §posterScope (2026-09-05) — **Portée : le carrousel et la rangée Favoris,
  /// rien d'autre.** Appliquée à toutes les vignettes, l'option lançait ~450
  /// recherches TMDB à l'ouverture de l'accueil (limite TMDB ≈ 40/s) et les
  /// affiches arrivaient au compte-gouttes pendant 15 s, chacune avec son
  /// `setState` : l'accueil saccadait. Les deux endroits retenus sont ceux que
  /// l'utilisateur regarde vraiment, et ils tiennent en quelques dizaines de
  /// titres. Lue par `_TypePage` (rangée Favoris) et `_HeroFanBannerState`,
  /// JAMAIS par `_HomeCard` directement.
  ///
  /// ⚠️ **Exclu de l'égalité**, comme [autoNextEpisode] : c'est un choix de
  /// goût (« je veux des affiches homogènes »), pas un levier de fluidité — le
  /// basculer ne doit pas faire passer la page en « Personnalisé ».
  final bool tmdbPostersFirst;

  /// §tmdbRows (2026-09-05) — Rangée « Parce que tu as regardé X » sur
  /// l'accueil : les recommandations TMDB du dernier titre lu (ou du premier
  /// favori), croisées avec les listes. Un appel `/recommendations` par type
  /// et par jour, plus une recherche si le titre n'a pas d'identifiant TMDB.
  /// ⚠️ Exclu de l'égalité, comme [tmdbPostersFirst].
  final bool tmdbRowBecause;

  /// §tmdbRows — Rangée « Les mieux notés » (`/top_rated` croisé avec les
  /// listes). Un appel par type et par jour. ⚠️ Exclu de l'égalité.
  final bool tmdbRowTopRated;

  /// §tmdbProviders (2026-09-06) — Rangées « Tendances Netflix / Disney+ /
  /// Prime Video » en France (`/discover` par `with_watch_providers`,
  /// `watch_region=FR`, croisé avec les listes). Deux appels par plateforme
  /// et par jour (films + séries). Choix utilisateur du 2026-09-06 : la seule
  /// des sept rangées candidates retenue. ⚠️ Exclu de l'égalité.
  final bool tmdbRowProviders;

  /// §rowFold (2026-09-05) — En dessous de ce nombre de titres, une rangée
  /// de genre est REPLIÉE dans « Autres » au lieu d'occuper une rangée à elle
  /// seule. Mesuré sur le téléviseur avec un vrai catalogue : après §catWords,
  /// onze rangées Films avaient encore 9 titres ou moins (Oscar 1, 3D 2,
  /// Juridique 2, Survie 3…) — et sur TV, une rangée coûte un écran entier de
  /// télécommande, quel que soit son contenu.
  ///
  /// `1` = jamais replier. Exemptées quoi qu'il arrive : Favoris, New (elle
  /// annonce ce qui vient d'arriver, consigne utilisateur), France (TV) et
  /// les rangées TMDB (qui ont leur propre seuil).
  /// ⚠️ Exclu de l'égalité : un choix de lecture, pas un levier de fluidité.
  final int rowFoldMin;

  /// §playerBuffer — Secondes de vidéo que le lecteur cherche à garder d'avance.
  ///
  /// Media3 n'a **aucun** équivalent des réglages mpv perdus avec libmpv
  /// (`cache-pause`, `demuxer-readahead-secs`, le tampon de 64 Mo de
  /// §replayBuffer) : sa manette à lui est le `LoadControl`, que le paquet
  /// vendoré expose et que personne ne posait — on tournait donc sur SES
  /// defaults (50 s), jamais choisis.
  ///
  /// Le compromis est **mémoire contre résistance** : plus de tampon absorbe un
  /// panel qui bride, mais tient d'autant plus de flux en RAM. D'où le lien avec
  /// les profils — le profil Fire Stick en prend le moins.
  ///
  /// ⚠️ C'est un PLAFOND en temps, pas une réservation : ExoPlayer s'arrête
  /// aussi sur son propre budget en octets. 30 s d'un flux à 3 Mbit/s ne pèsent
  /// pas comme 30 s de 4K.
  final int bufferSeconds;

  /// §unloadGuard — Interdit tout déchargement paresseux des listes
  /// secondaires : elles restent en mémoire tant que l'application vit.
  ///
  /// C'est la réponse directe à « chaque liste doit être chargée » : le
  /// déchargement au bout de N minutes est invisible tant qu'on ne s'en sert
  /// pas, mais il transforme une recherche cross-comptes en attente de
  /// rechargement, et il faisait passer les chips de la page Comptes à
  /// « NON CHARGÉ » sans qu'aucun échec n'ait eu lieu.
  ///
  /// Le prix est de la mémoire : une liste réelle pèse ~50 à 150 Mo une fois
  /// analysée. D'où le `false` du profil Fire Stick.
  ///
  /// ⚠️ Quand ce drapeau est `true`, [idleUnloadMinutes] est **conservé mais
  /// inerte** : la valeur reste sous la main pour le jour où l'utilisateur
  /// éteint l'interrupteur, sans qu'il ait à la re-régler.
  final bool keepAllListsInMemory;

  /// §lazyUnload — Minutes d'inactivité avant qu'une liste secondaire soit
  /// déchargée de la mémoire (le cache disque reste, rechargement ~50 ms).
  ///
  /// `0` = **jamais** décharger. Sans effet si [keepAllListsInMemory] est vrai.
  /// Était codé en dur à 5 minutes dans `MainNavigation`.
  final int idleUnloadMinutes;

  /// §cookieScope — Requêtes simultanées autorisées vers un MÊME serveur IPTV.
  ///
  /// Les panels Xtream comptent les connexions par abonnement : deux appels en
  /// parallèle sur un compte à `max_connections: 1` se répondent par un refus
  /// (« PANEL SATURÉ ») qui ressemble à une panne réseau alors que c'est une
  /// limite de compte.
  ///
  /// `0` signifie « déduire de `max_connections` remonté par le panel » ; toute
  /// valeur ≥ 1 la force. Sert donc aussi d'interrupteur : à 1, un seul appel
  /// à la fois, quoi que raconte le panel.
  final int hostMaxConcurrent;

  static const int minHeroCards = 5;
  static const int maxHeroCards = 15;
  static const int minItemsPerRow = 5;
  static const int maxItemsPerRowLimit = 25;

  /// §imgThrash — Plancher relevé de 20 à 60 Mo : en dessous, le cache ne tient
  /// même plus un écran d'accueil et le thrash est garanti.
  static const int minImageCacheMb = 60;
  static const int maxImageCacheMb = 200;

  /// §playerBuffer — sous 10 s le moindre à-coup réseau coupe la lecture ;
  /// au-delà de 90 s on immobilise de la RAM sans gain observable.
  static const int minBufferSeconds = 10;
  static const int maxBufferSeconds = 90;

  /// §rowFold — Bornes du seuil de repli (1 = jamais replier).
  static const int minRowFoldMin = 1;
  static const int maxRowFoldMin = 10;

  /// §unloadGuard — `0` est une valeur SIGNIFIANTE (« jamais »), pas un
  /// plancher accidentel : le clamp part donc bien de zéro. Au-delà de 2 h, le
  /// réglage ne se distingue plus de « jamais ».
  static const int minIdleUnloadMinutes = 0;
  static const int maxIdleUnloadMinutes = 120;

  /// §cookieScope — `0` = « déduire du panel ». Au-delà de 8 requêtes
  /// simultanées vers un même hôte, on sature n'importe quel abonnement grand
  /// public avant de gagner quoi que ce soit.
  static const int minHostMaxConcurrent = 0;
  static const int maxHostMaxConcurrent = 8;

  const PerfConfig({
    required this.heroEnabled,
    required this.heroAutoRotate,
    required this.heroCardCount,
    required this.maxItemsPerRow,
    required this.imageCacheMb,
    this.bufferSeconds = 30,
    this.autoNextEpisode = true,
    this.tmdbPostersFirst = false,
    this.tmdbRowBecause = true,
    this.tmdbRowTopRated = true,
    this.tmdbRowProviders = true,
    this.rowFoldMin = 5,
    this.keepAllListsInMemory = true,
    this.idleUnloadMinutes = 0,
    this.hostMaxConcurrent = 1,
  });

  /// §unloadGuard — Délai réellement appliqué par `MainNavigation`, ou `null`
  /// si rien ne doit jamais être déchargé. Un seul endroit décide, pour que la
  /// page Optimisation et le timer ne puissent pas diverger.
  Duration? get idleUnloadDelay =>
      (keepAllListsInMemory || idleUnloadMinutes <= 0)
          ? null
          : Duration(minutes: idleUnloadMinutes);

  // ── Presets ───────────────────────────────────────────────────────────────

  /// Confort = comportement historique de l'app (défaut).
  static const PerfConfig defaults = PerfConfig(
    heroEnabled: true,
    heroAutoRotate: true,
    heroCardCount: 15,
    maxItemsPerRow: 15,
    imageCacheMb: 120,
    bufferSeconds: 30,
    // §unloadGuard — Rien ne sort de la mémoire : c'est le profil « j'ai de la
    // RAM et je veux que tout réponde tout de suite ».
    keepAllListsInMemory: true,
    idleUnloadMinutes: 0,
    hostMaxConcurrent: 1,
  );

  /// Hero conservé mais immobile, rangées allégées.
  static const PerfConfig equilibre = PerfConfig(
    heroEnabled: true,
    heroAutoRotate: false,
    heroCardCount: 10,
    maxItemsPerRow: 10,
    imageCacheMb: 100,
    bufferSeconds: 30,
    // §unloadGuard — L'interrupteur reste sur « garder », mais le délai est
    // déjà réglé : éteindre l'interrupteur suffit, sans re-régler quoi que ce
    // soit.
    keepAllListsInMemory: true,
    idleUnloadMinutes: 15,
    hostMaxConcurrent: 1,
  );

  /// Fire Stick / box faible : hero coupé (les valeurs hero restent cohérentes
  /// si l'utilisateur le réactive ensuite à la main).
  ///
  /// ⚠️ §imgThrash — Le cache image N'EST PLUS le levier d'allègement de ce
  /// profil : c'est lui qui provoquait les saccades TV, or ce profil est celui
  /// que §perfAutoSuggest propose justement sur box TV. On allège désormais par
  /// le hero et le nombre de vignettes ; le cache reste au niveau du défaut
  /// Flutter.
  static const PerfConfig performance = PerfConfig(
    heroEnabled: false,
    heroAutoRotate: false,
    heroCardCount: 8,
    maxItemsPerRow: 10,
    // ⚠️ §imgThrash — Était à **80 Mo**, en contradiction directe avec le
    // commentaire ci-dessus qui promet « le cache reste au niveau du défaut
    // Flutter ». Or le défaut Flutter est de **100 Mo** : ce profil descendait
    // donc encore sous lui — exactement l'erreur que §imgThrash avait
    // diagnostiquée puis annoncée comme corrigée, et sur le profil que
    // §perfAutoSuggest propose justement sur box TV.
    //
    // Corrigé le 2026-09-02 (audit mémoire). L'allègement de ce profil passe
    // par le hero coupé et les rangées courtes, pas par le cache image.
    imageCacheMb: 100,
    // Le profil Fire Stick : moins de flux tenu en RAM.
    bufferSeconds: 15,
    // §unloadGuard — Le SEUL profil qui décharge : sur une box à 1 Go, garder
    // quatre listes analysées en mémoire est ce qui finit par tuer le process.
    keepAllListsInMemory: false,
    idleUnloadMinutes: 5,
    hostMaxConcurrent: 1,
  );

  /// Profils affichés dans OptimizationSettingsPage. Un état ne correspondant
  /// à aucun preset = « Personnalisé » (implicite, rien n'est stocké pour ça).
  ///
  /// §deviceCaps (2026-09-06) — `name` est un IDENTIFIANT, plus un libellé :
  /// les libellés vivent dans la l10n (« Complet / Équilibré / Léger »). Les
  /// anciens sous-titres nommaient des appareils (« Fire Stick ») ; depuis que
  /// la sonde choisit le profil d'après la MESURE, un nom d'appareil ne veut
  /// plus rien dire — un profil décrit ce qu'il allège, pas pour qui.
  /// ⚠️ Rien n'est persisté par nom (seule la config l'est) : renommer est sûr.
  static const presets = [
    (
      name: 'confort',
      icon: Icons.weekend_outlined,
      config: defaults,
    ),
    (
      name: 'equilibre',
      icon: Icons.balance,
      config: equilibre,
    ),
    (
      name: 'performance',
      icon: Icons.speed,
      config: performance,
    ),
  ];

  // ── Sérialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'he': heroEnabled,
        'har': heroAutoRotate,
        'hcc': heroCardCount,
        'mir': maxItemsPerRow,
        'icm': imageCacheMb,
        'bfs': bufferSeconds,
        'ane': autoNextEpisode,
        'tpf': tmdbPostersFirst,
        'trb': tmdbRowBecause,
        'trt': tmdbRowTopRated,
        'trp': tmdbRowProviders,
        'mnr': rowFoldMin,
        'kal': keepAllListsInMemory,
        'ium': idleUnloadMinutes,
        'hmc': hostMaxConcurrent,
      };

  /// Clés optionnelles + valeurs clampées à la lecture → rétro-compat des
  /// backups `.aether` et des futures évolutions du modèle.
  factory PerfConfig.fromJson(Map<String, dynamic> j) => PerfConfig(
        heroEnabled: j['he'] as bool? ?? defaults.heroEnabled,
        heroAutoRotate: j['har'] as bool? ?? defaults.heroAutoRotate,
        heroCardCount: (j['hcc'] as int? ?? defaults.heroCardCount)
            .clamp(minHeroCards, maxHeroCards),
        maxItemsPerRow: (j['mir'] as int? ?? defaults.maxItemsPerRow)
            .clamp(minItemsPerRow, maxItemsPerRowLimit),
        imageCacheMb: (j['icm'] as int? ?? defaults.imageCacheMb)
            .clamp(minImageCacheMb, maxImageCacheMb),
        bufferSeconds: (j['bfs'] as int? ?? defaults.bufferSeconds)
            .clamp(minBufferSeconds, maxBufferSeconds),
        autoNextEpisode: j['ane'] as bool? ?? defaults.autoNextEpisode,
        tmdbPostersFirst: j['tpf'] as bool? ?? defaults.tmdbPostersFirst,
        tmdbRowBecause: j['trb'] as bool? ?? defaults.tmdbRowBecause,
        tmdbRowTopRated: j['trt'] as bool? ?? defaults.tmdbRowTopRated,
        tmdbRowProviders: j['trp'] as bool? ?? defaults.tmdbRowProviders,
        rowFoldMin: (j['mnr'] as int? ?? defaults.rowFoldMin)
            .clamp(minRowFoldMin, maxRowFoldMin),
        // §unloadGuard — Absentes des backups `.aether` antérieurs : elles
        // retombent sur le défaut « on garde tout », qui est le comportement
        // le moins surprenant pour quelqu'un qui restaure une sauvegarde.
        keepAllListsInMemory:
            j['kal'] as bool? ?? defaults.keepAllListsInMemory,
        idleUnloadMinutes: (j['ium'] as int? ?? defaults.idleUnloadMinutes)
            .clamp(minIdleUnloadMinutes, maxIdleUnloadMinutes),
        hostMaxConcurrent: (j['hmc'] as int? ?? defaults.hostMaxConcurrent)
            .clamp(minHostMaxConcurrent, maxHostMaxConcurrent),
      );

  PerfConfig copyWith({
    bool? heroEnabled,
    bool? heroAutoRotate,
    int? heroCardCount,
    int? maxItemsPerRow,
    int? imageCacheMb,
    int? bufferSeconds,
    bool? autoNextEpisode,
    bool? tmdbPostersFirst,
    bool? tmdbRowBecause,
    bool? tmdbRowTopRated,
    bool? tmdbRowProviders,
    int? rowFoldMin,
    bool? keepAllListsInMemory,
    int? idleUnloadMinutes,
    int? hostMaxConcurrent,
  }) =>
      PerfConfig(
        heroEnabled: heroEnabled ?? this.heroEnabled,
        heroAutoRotate: heroAutoRotate ?? this.heroAutoRotate,
        heroCardCount: heroCardCount ?? this.heroCardCount,
        maxItemsPerRow: maxItemsPerRow ?? this.maxItemsPerRow,
        imageCacheMb: imageCacheMb ?? this.imageCacheMb,
        bufferSeconds: bufferSeconds ?? this.bufferSeconds,
        autoNextEpisode: autoNextEpisode ?? this.autoNextEpisode,
        tmdbPostersFirst: tmdbPostersFirst ?? this.tmdbPostersFirst,
        tmdbRowBecause: tmdbRowBecause ?? this.tmdbRowBecause,
        tmdbRowTopRated: tmdbRowTopRated ?? this.tmdbRowTopRated,
        tmdbRowProviders: tmdbRowProviders ?? this.tmdbRowProviders,
        rowFoldMin: rowFoldMin ?? this.rowFoldMin,
        keepAllListsInMemory:
            keepAllListsInMemory ?? this.keepAllListsInMemory,
        idleUnloadMinutes: idleUnloadMinutes ?? this.idleUnloadMinutes,
        hostMaxConcurrent: hostMaxConcurrent ?? this.hostMaxConcurrent,
      );

  // Égalité champ-à-champ → détection du preset actif dans la page.
  @override
  bool operator ==(Object other) =>
      other is PerfConfig &&
      other.heroEnabled == heroEnabled &&
      other.heroAutoRotate == heroAutoRotate &&
      other.heroCardCount == heroCardCount &&
      other.maxItemsPerRow == maxItemsPerRow &&
      other.imageCacheMb == imageCacheMb &&
      other.bufferSeconds == bufferSeconds &&
      // §unloadGuard — Ces trois-là SONT des leviers de profil (mémoire contre
      // réactivité, connexions contre refus du panel) : les inclure est ce qui
      // fait basculer la page en « Personnalisé » quand on les ajuste à la
      // main, exactement comme le tampon ou le nombre de vignettes.
      other.keepAllListsInMemory == keepAllListsInMemory &&
      other.idleUnloadMinutes == idleUnloadMinutes &&
      other.hostMaxConcurrent == hostMaxConcurrent;
  // NB : `autoNextEpisode`, `tmdbPostersFirst`, `tmdbRowBecause`,
  // `tmdbRowTopRated` et `tmdbRowProviders` sont volontairement EXCLUS de l'égalité — c'est un
  // réglage de confort, pas un paramètre de profil. L'inclure ferait basculer
  // la page en « Personnalisé » dès qu'on touche l'interrupteur.

  @override
  int get hashCode => Object.hash(
      heroEnabled,
      heroAutoRotate,
      heroCardCount,
      maxItemsPerRow,
      imageCacheMb,
      bufferSeconds,
      keepAllListsInMemory,
      idleUnloadMinutes,
      hostMaxConcurrent);
}
