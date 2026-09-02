import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'data/services/download_manager_service.dart';
import 'data/services/favorites_service.dart';
import 'data/services/stream_account_service.dart';
import 'data/services/storage_janitor.dart';
import 'data/services/playback_health_service.dart';
import 'data/models/stream_account.dart';
import 'data/services/parsed_playlist_service.dart';
import 'data/services/watch_progress_service.dart';
import 'data/services/search_history_service.dart';
import 'data/services/last_watched_channel_service.dart';
import 'data/services/hidden_regions_service.dart';
import 'data/services/track_preferences_service.dart';
import 'core/navigation/main_navigation.dart';
import 'core/navigation/focus_route_memory.dart';
import 'data/services/expiration_alert_service.dart';
import 'feature/accounts/accounts_page.dart';
import 'feature/accounts/expiration_alert_dialog.dart';
import 'feature/onboarding/onboarding_page.dart';
import 'feature/settings/backup_restore_flow.dart';
import 'feature/settings/perf_suggest_dialog.dart';
import 'core/boot/boot_status.dart';
import 'feature/boot/boot_screen.dart';
import 'core/diagnostics/log_buffer.dart';
import 'core/diagnostics/jank_meter.dart';
import 'feature/settings/web_console/web_console_page.dart';
import 'data/services/playlist_service.dart';
import 'data/services/remote_control_service.dart';
import 'core/themes/themes.dart';
import 'core/themes/colors.dart';
import 'core/themes/theme_service.dart';
import 'core/themes/app_theme_config.dart';
import 'core/settings/performance_settings_service.dart';
import 'data/services/update_service.dart';
import 'data/services/xmltv_service.dart';
import 'data/services/measured_quality_service.dart';
import 'data/services/inferred_category_service.dart';
import 'data/services/tmdb_poster_cache.dart';
import 'feature/update/update_dialog.dart';
import 'feature/player/video_fit.dart';
import 'feature/player/video_stats.dart';
import 'core/utils/platform_tv.dart';
import 'package:dpad/dpad.dart';

/// Clé globale pour le Navigator, permettant une navigation programmatique sans `BuildContext`.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// §perfBg — Observateur de routes global. Utilisé par les écrans qui doivent
/// **mettre en pause leur travail en arrière-plan** quand une route les couvre
/// (ex. lecture du player) : auto-rotation du hero, etc. Indispensable sur TV
/// (CPU/GPU limités → repaints invisibles = saccades).
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// §dpadRestore — Mémoire de focus par route : au retour d'une fiche ou du
/// player, le focus revient sur la carte d'où l'on est parti au lieu de retomber
/// sur la 1re carte de l'accueil (ce qui donnait l'impression d'un rechargement
/// de page). Détail du mécanisme dans `focus_route_memory.dart`.
final FocusRouteMemory focusRouteMemory = FocusRouteMemory();

/// Point d'entrée de l'application.
void main() async {
  // Séquence d'initialisation critique avant le lancement de l'UI.
  WidgetsFlutterBinding.ensureInitialized();
  // §tvLogs — Capture des logs AVANT tout le reste : sur TV il n'y a pas de
  // logcat accessible, ce tampon est le seul moyen de voir ce qui se passe
  // (consultable et exportable depuis la console web du téléphone).
  DiagnosticLog.install();
  // §jankMeter — Mesure de fluidité. Le rappel ne fait rien tant qu'aucune
  // fenêtre n'est ouverte ; ses relevés partent dans le tampon ci-dessus,
  // donc dans la console web — seul canal lisible depuis un téléviseur.
  //
  // ⚠️ En build DEBUG, les chiffres sont inexploitables (Dart non
  // optimisé) : chaque relevé le dit de lui-même plutôt que de laisser
  // citer une valeur fausse.
  JankMeter.install();

  // §bootFast — On n'attend AVANT `runApp` que ce qui est nécessaire pour
  // peindre juste : la plateforme (tailles TV) et le thème (couleurs). Tout le
  // reste passe après, observé par le journal de démarrage.
  //
  // Avant, `runApp` n'était appelé qu'une fois MediaKit, MediaStore, la
  // migration legacy et neuf services initialisés : pendant tout ce temps
  // l'utilisateur regardait la couleur du splash système, donc l'app paraissait
  // lente avant même d'avoir commencé.
  //
  // §3c-1 — la détection TV doit rester ici : les widgets lisent
  // `PlatformTv.isTv` de façon synchrone dès leur premier build.
  await PlatformTv.init();
  await ThemeService.load();

  // §3c-bis — Lock landscape global sur TV. La TV n'a pas de mode portrait
  // physique, mais Flutter peut quand même appliquer `setPreferredOrientations`
  // (utilisé par le PlayerPage à la sortie d'une lecture pour restaurer
  // portrait sur mobile). Sans ce verrou, l'app peut se retrouver en portrait
  // sur certains Fire Stick / Android TV émulateurs après une sortie player.
  if (PlatformTv.isTv) {
    unawaited(SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]));
  }

  runApp(const MyApp());

  // §updateDelay — La vérification de MAJ est déplacée vers
  // `_MainNavigationState.initState` (avec un délai plus long) : avant, lancée
  // à 3 s depuis `main()`, elle se superposait à l'apparition du menu → focus
  // TV se battait avec le dialog → impossible de sélectionner / fermer la MAJ.

  // §bootHydrate — Le préchargement du guide des chaînes (EPG XMLTV) a été
  // DÉPLACÉ en fin de `_initializeApp`.
  //
  // ⚠️ Ici, son `Future.delayed(4 s)` partait du lancement du PROCESSUS : sur un
  // démarrage qui dure plus de 4 s — c'est-à-dire tous ceux qui comptent — il
  // tombait au milieu du boot et disputait le réseau au téléchargement de la
  // playlist, puis le thread UI à son propre parsing (`readAsBytesSync` +
  // `utf8.decode` SYNCHRONES, cf. `XmltvService`). Le déclencher après le boot
  // le remet là où il ne gêne personne, sans rien changer à son TTL.
}

/// §bootFast — Initialisations déplacées APRÈS `runApp`.
///
/// Mémorisées : le démarrage peut être rejoué (« Réessayer », fin d'onboarding,
/// changement de compte) sans réinitialiser les plugins natifs.
Future<void>? _servicesReady;

Future<void> ensureServicesReady() => _servicesReady ??= _initServices();

Future<void> _initServices() async {
  // L'ordre compte : `MediaStore.appFolder` doit être posé avant
  // `DownloadManagerService.init()`, qui réconcilie les tâches sur disque.
  await MediaStore.ensureInitialized();
  MediaStore.appFolder = 'AetherStream';
  // Migration legacy d'abord (touche le secure storage des comptes).
  await StreamAccountService.migrateFromLegacyIfNeeded();
  // §startupParallel — Ces init() sont des lectures de cache INDÉPENDANTES
  // (SharedPreferences / secure storage propres à chaque service). En parallèle,
  // le démarrage attend juste la plus lente au lieu d'additionner les temps.
  // `ThemeService.load()` n'est plus ici : il est attendu avant `runApp`, car
  // sans lui l'écran de démarrage se peindrait avec les mauvaises couleurs.
  await Future.wait([
    DownloadManagerService().init(),
    FavoritesService.init(),
    WatchProgressService.init(),
    SearchHistoryService.init(),
    LastWatchedChannelService.init(),
    // §stallCount — Historique de blocages par compte (quel abonnement rame).
    PlaybackHealthService.init(),
    HiddenRegionsService.init(),
    TrackPreferencesService.init(),
    PerformanceSettingsService.load(), // §perfSettings
    VideoFitPreference.load(), // §videoFit
    VideoStatsPreference.load(), // §videoStats
    MeasuredQualityService.init(), // §qualityTruth
    InferredCategoryService.init(), // §inferredCat
    TmdbPosterCache.init(), // §tmdbUrlPersist
  ]);
}

/// Vérifie silencieusement si une mise à jour est disponible.
/// Affiche le dialogue uniquement si une nouvelle version existe.
/// Public car appelé depuis `MainNavigation.initState` après que la home est
/// stable (cf. §updateDelay).
Future<void> checkForUpdate() async {
  final info = await UpdateService.checkForUpdate();
  if (info == null) return;
  final context = navigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  await UpdateDialog.show(context, info);
}

/// Widget racine de l'application.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeConfig>(
      valueListenable: ThemeService.config,
      builder: (context, config, _) => _buildApp(config),
    );
  }

  /// §dpadNav — Thème de focus global (reproduit §focusVisibility avec la couleur
  /// du thème actif) : effet par défaut des `DpadFocusable` sans `effects` propres.
  ///
  /// ⚠️ §touchNoFocus — Ces effets-là ne sont PAS filtrés par le mode d'entrée.
  /// Aucun `DpadFocusable` de l'app ne les utilise aujourd'hui (tous passent par
  /// `FocusableCard`/`FocusableChip`, ou fournissent `effects: const []`) ; un
  /// nouveau widget qui s'en contenterait ferait revenir le faux focus tactile.
  /// Dans ce cas, passer par `FocusEffectVisibility` (`focus_visibility.dart`).
  DpadThemeData _dpadTheme(AppThemeConfig config) {
    final r = BorderRadius.circular(config.borderRadius);
    return DpadThemeData(
      scrollPadding: 56,
      effects: [
        const DpadScaleEffect(scale: 1.05),
        DpadBorderEffect(color: config.primaryColor, width: 2.6, borderRadius: r),
        DpadGlowEffect(color: config.primaryColor, opacity: 0.5, borderRadius: r),
      ],
    );
  }

  Widget _buildApp(AppThemeConfig config) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [appRouteObserver, focusRouteMemory],
      title: 'AetherStream',
      themeMode: config.themeMode,
      theme: lightTheme(config),
      darkTheme: darkTheme(config),
      debugShowCheckedModeBanner: false,

      localizationsDelegates: const [
        AppLocalizations.delegate, // Notre delegate généré
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // §frOnly — La langue est IMPOSÉE, elle ne suit pas l'appareil.
      //
      // ⚠️ Ne pas « nettoyer » cette ligne. Sans elle, l'app suivait la langue
      // du téléphone : sur un appareil en anglais, les rares écrans câblés sur
      // l10n (Téléchargements, Comptes) passaient en anglais pendant que tout
      // le reste de l'interface — écrit en français directement dans le code —
      // restait en français. Résultat : une app à moitié traduite, jamais une
      // app anglaise.
      //
      // La base bilingue est conservée telle quelle (`app_en.arb` reste le
      // template et reste complet) : le jour où l'interface entière passera par
      // l10n, il suffira de retirer cette ligne.
      locale: const Locale('fr'),
      supportedLocales: const [
        Locale('fr'), // Français — en PREMIER : c'est aussi le repli
        Locale('en'), // Anglais
      ],

      // Le `builder` est utilisé ici pour superposer un bandeau "BETA"
      // uniquement en mode debug, sans interférer avec le widget `home`.
      // §3c-7 — Sur TV : texte en taille native (×1.0). Les itérations
      // précédentes (×1.3 puis ×1.15) donnaient une sensation "ultra-zoomée"
      // car la TV applique déjà sa propre densité physique généreuse
      // (1080p à 3m = équivalent retina mobile). Si jamais le texte devenait
      // trop petit sur certains modèles, ajuster ici (0.95 / 1.05).
      builder: (context, child) {
        bool isDebug = false;
        assert(isDebug = true); // Astuce pour n'être `true` qu'en mode debug.

        Widget wrapped = child ?? const SizedBox.shrink();

        if (PlatformTv.isTv) {
          final mq = MediaQuery.of(context);
          final scaled = mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.0);
          wrapped = MediaQuery(
            data: mq.copyWith(textScaler: scaled),
            child: wrapped,
          );
        }

        // §dpadNav — Racine de la navigation D-pad (package `dpad`). Installée
        // sur TOUTES les plateformes (requise par FocusableCard/FocusableChip et
        // bénéfique au clavier desktop). Remplace l'ancien TvBackHandler : la
        // touche Retour est gérée par `onBack`.
        wrapped = Dpad(
          // §touchNoFocus — ⚠️ Elle n'était PAS « inerte au tactile mobile »,
          // comme l'affirmait le commentaire d'origine. `restoreFocus` est un
          // filet de sécurité : dès que plus rien de réel n'a le focus (route
          // dépilée, dialogue fermé), dpad en DONNE un — au nœud marqué `entry`
          // ou au plus proche géométriquement. Sur TV c'est vital ; sur
          // téléphone ça allumait un élément au hasard (mesuré : le bouton de
          // rechargement de l'AppBar, en navigation 100 % tactile), et Material
          // dessinait sa surbrillance de focus par-dessus.
          //
          // Le filet ne sert qu'à une navigation directionnelle : au doigt, rien
          // ne doit JAMAIS avoir le focus.
          restoreFocus: PlatformTv.isTv,
          theme: _dpadTheme(config),
          keySet: const DpadKeySet().copyWith(
            back: const [
              LogicalKeyboardKey.escape,
              LogicalKeyboardKey.goBack,
              LogicalKeyboardKey.gameButtonB,
              LogicalKeyboardKey.browserBack,
            ],
            menu: const [
              LogicalKeyboardKey.contextMenu,
              LogicalKeyboardKey.info,
              LogicalKeyboardKey.gameButtonY,
            ],
          ),
          // §mediaKeys — Touches média de la télécommande (PLAY, PAUSE, STOP,
          // avance/recul rapide, piste suivante). Elles n'étaient captées nulle
          // part : ni ici, ni côté Android, ni par le moteur vidéo. Routées vers le
          // même dispatch que la télécommande web → un seul chemin d'actions.
          // Hors lecture, ces actions sont ignorées (pas de faux positif sur
          // l'accueil).
          shortcuts: {
            for (final e in kMediaKeyActions.entries)
              e.key: () => RemoteControlService.instance.dispatch(e.value),
          },
          onBack: AppBack.pop,
          onMenu: () => RemoteControlService.instance.invokeMenu(),
          // §focusTrace — Journalise ce qui prend le focus quand le traceur est
          // actif : « la télécommande ne fait plus rien » est presque toujours
          // un problème de focus, pas de touche.
          onFocusChange: DiagnosticLog.traceFocus,
          child: wrapped,
        );

        if (isDebug) {
          wrapped = Banner(
            message: "BETA",
            location: BannerLocation.topEnd,
            color: kAccentPrimary,
            child: wrapped,
          );
        }
        return wrapped;
      },
      home: const _LaunchDecider(),
    );
  }
}

/// Ce widget agit comme un "aiguilleur" au démarrage.
/// Il affiche un écran de chargement, puis décide de la page à afficher
/// en fonction de l'état de l'initialisation (comptes, playlist).
class _LaunchDecider extends StatefulWidget {
  const _LaunchDecider();
  @override
  State<_LaunchDecider> createState() => _LaunchDeciderState();
}

class _LaunchDeciderState extends State<_LaunchDecider> {
  late Future<({String path, String accountId, String accountName})?> _initFuture;
  bool? _showOnboarding;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
    _initFuture = _initializeApp();
  }

  /// §1i — Vérifie si l'onboarding doit être affiché (1re ouverture seulement).
  Future<void> _checkOnboarding() async {
    final show = await OnboardingService.shouldShow();
    if (mounted) setState(() => _showOnboarding = show);
  }

  void _finishOnboarding() {
    setState(() {
      _showOnboarding = false;
      // §restore — Une restauration `.aether` a pu créer des comptes pendant
      // l'onboarding. On relance l'init pour les charger (sinon l'écran
      // "aucun compte configuré" s'afficherait malgré la restauration).
      _initFuture = _initializeApp();
    });
  }

  /// Valide la configuration initiale et retourne les données du compte actif (null = pas de compte).
  Future<({String path, String accountId, String accountName})?> _initializeApp() async {
    // §bootStatus — L'écran de lancement reflète l'étape réelle : sur une
    // grosse playlist le boot dure plusieurs secondes, et un texte figé ne
    // permettait pas de distinguer « ça travaille » de « c'est bloqué ».
    BootStatus.reset();
    // §bootFast — Les services lourds sont initialisés ICI plutôt qu'avant
    // `runApp` : l'écran de démarrage est donc déjà à l'écran pendant qu'ils se
    // préparent, et leur durée est visible dans le journal. On déplace le point
    // d'attente, on ne le supprime pas : rien ne touche aux comptes avant.
    BootStatus.set('// préparation des services…');
    await ensureServicesReady();

    BootStatus.set('// vérification du compte…');
    final accounts = await StreamAccountService.listAccounts();
    if (accounts.isEmpty) return null;

    // §acctPurge — Ménage des fichiers sans propriétaire, en tâche de fond.
    //
    // Le correctif de source (`deleteAccount` supprime désormais les fichiers)
    // ne nettoie que l'avenir : les installations existantes portent déjà leurs
    // orphelins — 290 Mo sur l'appareil de test, dont un `.m3u` de 217 Mo
    // rattaché à un compte effacé trois mois plus tôt.
    //
    // ⚠️ NON attendu (`unawaited`) : c'est du confort, jamais un préalable au
    // démarrage. Et il n'est lancé qu'APRÈS le test `accounts.isEmpty`
    // ci-dessus — une liste vide est précisément le cas où le balayage se
    // refuse à agir (cf. `StorageJanitor`), pour qu'un stockage sécurisé qui
    // hoquette n'efface jamais les playlists de l'utilisateur.
    unawaited(StorageJanitor.sweepOrphans(
      knownAccountIds: accounts.map((a) => a.id).toSet(),
    ));

    // Téléchargement / vérification cache M3U du compte actif.
    BootStatus.set('// lecture de la playlist…');
    final path = await PlaylistService.getOrDownloadPlaylist(
      // Appelé seulement si le cache est absent/périmé → on distingue une
      // lecture disque instantanée d'un vrai téléchargement réseau.
      onDownloadStart: () =>
          BootStatus.set('// téléchargement de la playlist…'),
    );
    final acc  = await StreamAccountService.getCurrentAccount();

    // §initBoot — Parsing du M3U actif AWAITED ici (au lieu de le faire dans
    // `HomePage._ensureLoaded` plus tard) : la home se montait avec
    // `_loading = true` → spinner hors-écran AetherStream visible une fraction
    // de seconde. Maintenant l'écran AetherStream tient jusqu'à ce que la
    // playlist active soit en mémoire → MainNavigation apparait directement.
    if (acc != null) {
      // §bootStatus — Seule étape à progression DÉTERMINÉE : `loadActive`
      // expose déjà `onProgress` (throttlé côté BootStatus au pourcentage
      // entier). C'est aussi la plus longue sur un gros catalogue.
      BootStatus.set('// analyse du catalogue…', progress: 0);
      await ParsedPlaylistService.loadActive(
        acc.id,
        acc.label,
        path,
        onProgress: BootStatus.report,
        // §bootPercent — Le compteur d'entrées PROUVE que ça travaille, là où
        // un pourcentage se contente de l'affirmer.
        onDetail: BootStatus.setDetail,
      );
    }

    // Multi-comptes : charger les autres playlists pour que la recherche et la
    // home agrègent tous les contenus disponibles.
    //   1. Préchargement disque AWAITED (rapide, ~quelques ms par compte) →
    //      le menu n'apparait que quand tout est prêt à afficher (plus de
    //      "carrousels qui se remplissent en différé" derrière le menu).
    //   2. §bootHydrate — Téléchargement + parsing des comptes PÉRIMÉS faits
    //      ici, dans le boot, annoncés compte par compte. Ceux qui n'ont rien à
    //      faire ne coûtent qu'un `stat`.
    if (accounts.length > 1) {
      final others = accounts.where((a) => a.id != acc?.id).toList();
      // §bootStatus — Retour à une barre indéterminée : ce préchargement disque
      // n'expose pas de progression (quelques ms par compte).
      BootStatus.set('// chargement des autres comptes…');
      await ParsedPlaylistService.preloadOthersFromDisk(others);
      // §favReconcile — 1re passe sur ce qui est déjà en mémoire (compte actif
      // + préchargés disque). La passe FINALE (qui pose le flag one-shot) est
      // déclenchée en fin d'hydratation, quand TOUS les comptes sont chargés.
      FavoritesService.reconcileWithPlaylist(); // fire & forget
      // §bootHydrate — L'hydratation se fait MAINTENANT, dans le boot.
      //
      // ⚠️ Ceci REVIENT sur §secondaryRefresh, qui différait volontairement ce
      // travail de 5 s « pour laisser la home se stabiliser avant de lancer du
      // réseau + du parsing ». Le raisonnement d'origine restait juste — les
      // deux en même temps se sentent sur box TV — mais il se trompait de
      // remède : différer ne supprime pas le parallélisme, il le déplace sous
      // les doigts de l'utilisateur. Mesuré sur le téléviseur le 2026-09-01 :
      // 46 s de téléchargement + parsing + écriture gzip APRÈS l'affichage de
      // l'accueil, pendant qu'on fait défiler des vignettes — et chaque compte
      // terminé y déclenche 3 regroupements complets + 3 recompositions de hero.
      //
      // Ce qui rend le déplacement acceptable, c'est qu'on ne bloque QUE sur les
      // comptes qui ont réellement du travail : un jour de caches valides, le
      // boot ne bouge pas d'une milliseconde (cf. `_hydrateInBoot`).
      await _hydrateInBoot(others);
    } else {
      // §favReconcile — Mono-compte : tout est en mémoire → passe unique qui
      // pose le flag directement.
      FavoritesService.reconcileWithPlaylist(finalPass: true); // fire & forget
    }

    // §17b — Fetch background des AccountInfo pour TOUS les comptes
    // (alimente le cache `ExpirationAlertService.infos`). On déclenche
    // la popup d'alerte si au moins un compte expire <30 jours.
    _checkExpirationAlerts(accounts);

    // §perfAutoSuggest — Sur box TV, propose une fois le profil Performance
    // (fire & forget, one-shot, seulement si la config perf est aux défauts).
    _suggestTvPerfProfile();

    _bootAnnouncing = false;
    BootStatus.set('// prêt.', progress: 1);
    // §bootLog — Le journal chronométré part dans le tampon de diagnostic : sur
    // un téléviseur il n'y a pas de logcat, et l'écran de boot disparaît au
    // moment précis où l'on voudrait lire ses chiffres.
    BootStatus.dumpToLog();
    // §bootHydrate — Le guide des chaînes, une fois le boot fini (cf. `main`).
    Future.delayed(
      const Duration(seconds: 3),
      () => XmltvService.ensureLoaded(),
    ); // fire & forget

    return (
      path:        path,
      accountId:   acc?.id   ?? '',
      accountName: acc?.label ?? '',
    );
  }

  /// §17b — Vérifie les expirations en background et affiche la popup
  /// `ExpirationAlertDialog` si au moins un compte expire <30 jours. Le
  /// dédoublonnage (SharedPreferences) est géré par
  /// `ExpirationAlertService.computeUnackedAlerts`. Délai de 4s pour laisser
  /// le splash + l'init terminer avant d'interrompre l'utilisateur.
  Future<void> _checkExpirationAlerts(List<StreamAccount> accounts) async {
    if (accounts.isEmpty) return;
    try {
      await ExpirationAlertService.fetchAll(accounts);
      if (!mounted) return;
      final alerts =
          await ExpirationAlertService.computeUnackedAlerts(accounts);
      if (alerts.isEmpty) return;
      // Délai pour laisser le UI démarrer proprement.
      await Future.delayed(const Duration(seconds: 4));
      final ctx = navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      await ExpirationAlertDialog.show(ctx, alerts);
    } catch (e) {
      // Échec silencieux — pas critique au boot.
    }
  }

  /// §perfAutoSuggest — Propose le profil Performance sur box TV (one-shot).
  /// Délai 2,5 s pour laisser la home se monter (le dialog d'expiration §17b,
  /// plus critique, arrive à 4 s et passerait par-dessus — cas rare accepté).
  Future<void> _suggestTvPerfProfile() async {
    try {
      await Future.delayed(const Duration(milliseconds: 2500));
      final ctx = navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      await PerfSuggestDialog.maybeShow(ctx);
    } catch (_) {
      // Échec silencieux — pas critique au boot.
    }
  }

  /// §bootHydrate — Budget TOTAL accordé à l'hydratation pendant le démarrage.
  ///
  /// ⚠️ **Cette borne n'est pas décorative.** Rien, dans la chaîne
  /// `ensureDownloadedForAccount`, n'a de délai global : la tentative catalogue
  /// JSON tolère 30 s de connexion + 2 min de réception, le repli `get.php`
  /// 30 s + 60 s, et la boucle est séquentielle. Un seul panel injoignable
  /// pouvait donc retenir un démarrage pendant plusieurs minutes — un défaut
  /// bien pire que celui qu'on corrige.
  ///
  /// Ce qui déborde n'est PAS annulé : le travail continue en arrière-plan
  /// exactement comme avant, on cesse simplement de l'attendre. L'annuler
  /// laisserait un `.part` orphelin ; le relancer téléchargerait deux fois le
  /// même fichier au même endroit.
  static const Duration _bootHydrateBudget = Duration(seconds: 60);

  /// §bootHydrate — Le journal de démarrage accepte-t-il encore des étapes ?
  ///
  /// ⚠️ Un compte qui a débordé du budget **continue de travailler** en
  /// arrière-plan (on cesse de l'attendre, on ne l'annule pas). Sans ce
  /// drapeau, il publierait ses étapes et sa progression APRÈS la fin du
  /// démarrage : le journal chronométré s'allongerait après avoir été relevé,
  /// et l'étape courante changerait alors que l'écran de boot n'existe plus.
  bool _bootAnnouncing = true;

  /// §bootHydrate — Met à jour les comptes secondaires **pendant le boot**,
  /// mais uniquement ceux qui ont du travail.
  Future<void> _hydrateInBoot(List<StreamAccount> others) async {
    // ⚠️ Le croisement des DEUX conditions est obligatoire. « Cache frais » ne
    // veut pas dire « prêt » : un compte dont le préchargement disque a échoué
    // a un fichier valide et rien en mémoire. Ne regarder que le TTL le
    // sauterait pour toujours.
    final List<StreamAccount> pending = <StreamAccount>[];
    for (final acc in others) {
      final bool loaded =
          ParsedPlaylistService.stateOf(acc.id) == AccountLoadState.loaded;
      if (!loaded || await PlaylistService.hasPendingWork(acc)) {
        pending.add(acc);
      }
    }

    if (pending.isEmpty) {
      debugPrint('✅ §bootHydrate : rien à mettre à jour, le boot ne bouge pas.');
      // §favReconcile — Tout est en mémoire : la passe finale peut être posée.
      unawaited(FavoritesService.reconcileWithPlaylist(finalPass: true));
      return;
    }

    debugPrint('🚚 §bootHydrate : ${pending.length}/${others.length} compte(s) '
        'à mettre à jour dans le boot.');
    final DateTime deadline = DateTime.now().add(_bootHydrateBudget);
    final List<Future<void>> started = <Future<void>>[];

    for (int i = 0; i < pending.length; i++) {
      final StreamAccount acc = pending[i];
      final Duration left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        // Budget épuisé : le reste reprend le comportement historique —
        // silencieux, en arrière-plan.
        debugPrint('⏳ §bootHydrate : budget épuisé, « ${acc.label} » passe en '
            'arrière-plan.');
        started.add(_hydrateOne(acc));
        continue;
      }
      BootStatus.set(
        '// mise à jour ${i + 1}/${pending.length} · ${acc.label}…',
      );
      final Future<void> f = _hydrateOne(acc, announce: true);
      started.add(f);
      // ⚠️ `catchError` en plus du try/catch interne de `_hydrateOne` : ce
      // `await` est sur le chemin du DÉMARRAGE. Une exception qui remonterait
      // ici ferait échouer `_initializeApp` en entier — un compte secondaire
      // cassé empêcherait d'ouvrir l'application.
      await f.timeout(left, onTimeout: () {
        debugPrint('⏳ §bootHydrate : « ${acc.label} » dépasse le budget ; on '
            'cesse de l\'attendre, le travail continue.');
      }).catchError((Object e) {
        debugPrint('⚠️ §bootHydrate : « ${acc.label} » a échoué ($e) — on passe '
            'au suivant.');
      });
    }

    // §favReconcile — La passe FINALE pose un drapeau one-shot : elle ne doit
    // tomber qu'une fois TOUT retombé, y compris ce qui a débordé du budget.
    // Sans le `catchError`, un compte cassé ferait échouer le `Future.wait` et
    // le drapeau ne serait jamais posé.
    unawaited(
      Future.wait(started.map((f) => f.catchError((_) {})))
          .then((_) => FavoritesService.reconcileWithPlaylist(finalPass: true)),
    );
  }

  /// Télécharge le M3U manquant d'UN compte secondaire et le charge en mémoire.
  /// Ne lève jamais. §16 : pousse les transitions d'état via `setLoadState`
  /// pour que `_AccountTile` affiche "EN COURS…" pendant download/parse.
  ///
  /// [announce] câble la progression sur `BootStatus` : réservé à l'hydratation
  /// faite DANS le boot, où l'étape est visible et où une barre figée pendant
  /// 14 s serait exactement le défaut que §bootPercent corrige. En arrière-plan,
  /// la méthode reste silencieuse comme avant.
  Future<void> _hydrateOne(StreamAccount acc, {bool announce = false}) async {
    // Fermetures plutôt que tear-offs : le droit de parler est réévalué à
    // CHAQUE publication, pas figé au lancement de l'hydratation.
    void report(double v) {
      if (_bootAnnouncing) BootStatus.report(v);
    }

    void detail(String d) {
      if (_bootAnnouncing) BootStatus.setDetail(d);
    }

    final void Function(double)? onProgress = announce ? report : null;
    final void Function(String)? onDetail = announce ? detail : null;
    // §secondaryRefresh — On ne saute PLUS les comptes déjà chargés depuis le
    // disque : ils passent quand même par le contrôle de TTL. Avant, un compte
    // secondaire dont le cache existait n'était jamais retéléchargé, quelle
    // que soit son ancienneté — sa liste restait figée à vie.
    final bool alreadyLoaded =
        ParsedPlaylistService.stateOf(acc.id) == AccountLoadState.loaded;
    if (!alreadyLoaded) {
      ParsedPlaylistService.setLoadState(acc.id, AccountLoadState.downloading);
    }
    try {
      final res = await PlaylistService.ensureDownloadedForAccount(acc);
      if (res.path == null) {
        if (!alreadyLoaded) {
          ParsedPlaylistService.setLoadState(acc.id, AccountLoadState.error);
        }
        return;
      }
      if (announce && _bootAnnouncing) {
        BootStatus.set('// analyse · ${acc.label}…', progress: 0);
      }
      if (alreadyLoaded) {
        // Rien de neuf : la copie en mémoire est déjà la bonne.
        if (!res.downloaded) return;
        // Fichier renouvelé → la mémoire est périmée, on la remplace
        // atomiquement (reloadFromDisk parse AVANT de permuter, donc pas
        // d'état vide intermédiaire visible sur la home).
        await ParsedPlaylistService.reloadFromDisk(
          acc.id,
          acc.label,
          res.path!,
          onProgress: onProgress,
          onDetail: onDetail,
        );
        debugPrint('🔄 §secondaryRefresh : « ${acc.label} » rechargée en mémoire.');
        return;
      }
      // loadSecondary gère lui-même les transitions parsing → loaded / error.
      await ParsedPlaylistService.loadSecondary(
        acc.id,
        acc.label,
        res.path!,
        onProgress: onProgress,
        onDetail: onDetail,
      );
    } catch (_) {
      if (!alreadyLoaded) {
        ParsedPlaylistService.setLoadState(acc.id, AccountLoadState.error);
      }
      // Ne pas planter le démarrage à cause d'un compte cassé (network, IO…).
    }
  }

  /// Permet de relancer la validation, typiquement après une action de l'utilisateur.
  void _retryInitialization() {
    setState(() {
      _initFuture = _initializeApp();
    });
  }

  /// §restore — Restaure une sauvegarde `.aether` depuis l'écran "aucun compte"
  /// (cas : onboarding passé sans config). Recharge l'app au succès.
  Future<void> _restoreFromBackup() async {
    final restored = await runBackupImportFlow(context);
    if (restored && mounted) _retryInitialization();
  }

  /// Navigue vers les paramètres et force une réinitialisation au retour.
  Future<void> _recheckAfterSettings() async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AccountsPage()));
    _retryInitialization();
  }

  /// §webConsoleFirstLaunch — Ouvre la Console web (même flux que
  /// Settings → Console web) depuis l'écran "aucun compte". Au retour, on
  /// relance l'init : si l'utilisateur a créé un compte côté navigateur,
  /// l'app bascule directement sur la home.
  ///
  /// §webConsoleOnly — C'est désormais **le** chemin QR de cet écran, y compris
  /// sur TV où il remplace l'ancien pairing mono-formulaire : quand la playlist
  /// est en cause, on veut pouvoir la recharger, la corriger ou restaurer une
  /// sauvegarde, pas seulement en ressaisir l'URL. Le QR ouvre directement la
  /// page « Comptes » du panneau, le reste restant à un clic.
  Future<void> _openWebConsole() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const WebConsolePage(initialView: 'accounts'),
      ),
    );
    if (mounted) _retryInitialization();
  }

  @override
  Widget build(BuildContext context) {
    // §1i — Onboarding affiché en priorité au tout premier lancement.
    if (_showOnboarding == true) {
      return OnboardingPage(onFinish: _finishOnboarding);
    }

    // Le FutureBuilder gère nativement les différents états (chargement, erreur, succès)
    // de notre logique d'initialisation asynchrone.
    return FutureBuilder<({String path, String accountId, String accountName})?>(
      future: _initFuture,
      builder: (context, snapshot) {
        // §bootShell — Les 4 états partagent le même décor (`BootShell`) : le
        // cadre ne bouge pas, seul le contenu change. Le rendu vit dans
        // `lib/feature/boot/`, ce widget ne fait plus que l'aiguillage.
        // §bootExit — fondu court vers l'accueil, au lieu du remplacement sec.
        final Widget screen;
        if (snapshot.connectionState == ConnectionState.waiting) {
          screen = const BootLoadingScreen();
        } else if (snapshot.hasError) {
          screen = BootErrorScreen(
            error: snapshot.error!,
            onRetry: _retryInitialization,
            onOpenAccounts: _recheckAfterSettings,
          );
        } else if (snapshot.data != null) {
          screen = MainNavigation(initialData: snapshot.data!);
        } else {
          screen = BootNoAccountScreen(
            onOpenWebConsole: _openWebConsole,
            onOpenAccounts: _recheckAfterSettings,
            onRestoreBackup: _restoreFromBackup,
          );
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOut,
          child: KeyedSubtree(
            key: ValueKey<String>(screen.runtimeType.toString()),
            child: screen,
          ),
        );
      },
    );
  }
}
