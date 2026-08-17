import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'data/services/download_manager_service.dart';
import 'data/services/favorites_service.dart';
import 'data/services/stream_account_service.dart';
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
import 'core/diagnostics/log_buffer.dart';
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
import 'feature/update/update_dialog.dart';
import 'core/utils/platform_tv.dart';
import 'package:dpad/dpad.dart';
import 'package:google_fonts/google_fonts.dart';

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
  MediaKit.ensureInitialized();
  await MediaStore.ensureInitialized();
  MediaStore.appFolder = 'AetherStream';
  // §3c-1 — détection plateforme TV (Android TV / Fire TV) avant tout build UI
  // → permet aux widgets d'adapter focus/tailles synchrone via PlatformTv.isTv.
  await PlatformTv.init();
  // §3c-bis — Lock landscape global sur TV. La TV n'a pas de mode portrait
  // physique, mais Flutter peut quand même appliquer `setPreferredOrientations`
  // (utilisé par le PlayerPage à la sortie d'une lecture pour restaurer
  // portrait sur mobile). Sans ce verrou, l'app peut se retrouver en portrait
  // sur certains Fire Stick / Android TV émulateurs après une sortie player.
  if (PlatformTv.isTv) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
  // Migration legacy d'abord (touche le secure storage des comptes).
  await StreamAccountService.migrateFromLegacyIfNeeded();
  // §startupParallel — Ces 6 init() sont des lectures de cache INDÉPENDANTES
  // (SharedPreferences / secure storage propres à chaque service). Avant elles
  // s'enchaînaient en série (temps additif au cold start) ; en parallèle, le
  // démarrage attend juste la plus lente. Toutes terminées avant runApp (MyApp
  // lit ThemeService.config).
  await Future.wait([
    DownloadManagerService().init(),
    FavoritesService.init(),
    WatchProgressService.init(),
    SearchHistoryService.init(),
    LastWatchedChannelService.init(),
    HiddenRegionsService.init(),
    TrackPreferencesService.init(),
    ThemeService.load(),
    PerformanceSettingsService.load(), // §perfSettings
  ]);

  runApp(const MyApp());

  // §updateDelay — La vérification de MAJ est déplacée vers
  // `_MainNavigationState.initState` (avec un délai plus long) : avant, lancée
  // à 3 s depuis `main()`, elle se superposait à l'apparition du menu → focus
  // TV se battait avec le dialog → impossible de sélectionner / fermer la MAJ.

  // Préchargement du guide des chaînes (EPG XMLTV) en arrière-plan, non-bloquant.
  // Sans ça, le guide était vide au 1er lancement tant qu'on n'ouvrait pas une
  // fiche chaîne. `ensureLoaded()` est gardé par le TTL 12h + cache fichier
  // persistant → coût quasi nul aux lancements suivants.
  Future.delayed(const Duration(seconds: 4), () => XmltvService.ensureLoaded());
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
      supportedLocales: const [
        Locale('en'), // Anglais
        Locale('fr'), // Français
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
        // bénéfique au clavier desktop ; inerte au tactile mobile). Remplace
        // l'ancien TvBackHandler : la touche Retour est gérée par `onBack`.
        wrapped = Dpad(
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
          // part : ni ici, ni côté Android, ni par media_kit. Routées vers le
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
    BootStatus.set('// vérification du compte…');
    final accounts = await StreamAccountService.listAccounts();
    if (accounts.isEmpty) return null;

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
      );
    }

    // Multi-comptes : charger les autres playlists pour que la recherche et la
    // home agrègent tous les contenus disponibles.
    //   1. Préchargement disque AWAITED (rapide, ~quelques ms par compte) →
    //      le menu n'apparait que quand tout est prêt à afficher (plus de
    //      "carrousels qui se remplissent en différé" derrière le menu).
    //   2. Téléchargement + parsing réseau des manquants RESTE en arrière-plan
    //      (peut prendre plusieurs secondes, on ne bloque pas le boot dessus).
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
      // §secondaryRefresh — Différé de quelques secondes : l'hydratation peut
      // désormais RETÉLÉCHARGER (contrôle de TTL, plus seulement peupler les
      // manquants). On laisse la home s'afficher et se stabiliser avant de
      // lancer du réseau + du parsing en isolate — sur box TV, les deux en même
      // temps se sentent. Même motif que le préchargement XMLTV.
      Future.delayed(
        const Duration(seconds: 5),
        () => _hydrateSecondaryAccounts(others),
      ); // fire & forget
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

    BootStatus.set('// prêt.', progress: 1);

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

  /// Télécharge le M3U manquant des comptes secondaires et les charge en
  /// mémoire (parsing). Asynchrone & silencieux — la home se met à jour via
  /// `ParsedPlaylistService.version` quand chaque compte termine. §16 : push
  /// les transitions d'état via `setLoadState` pour que `_AccountTile` affiche
  /// "EN COURS…" pendant download/parse puis "DISPONIBLE" à la fin.
  Future<void> _hydrateSecondaryAccounts(List<StreamAccount> others) async {
    for (final acc in others) {
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
          continue;
        }
        if (alreadyLoaded) {
          // Rien de neuf : la copie en mémoire est déjà la bonne.
          if (!res.downloaded) continue;
          // Fichier renouvelé → la mémoire est périmée, on la remplace
          // atomiquement (reloadFromDisk parse AVANT de permuter, donc pas
          // d'état vide intermédiaire visible sur la home).
          await ParsedPlaylistService.reloadFromDisk(acc.id, acc.label, res.path!);
          debugPrint('🔄 §secondaryRefresh : « ${acc.label} » rechargée en mémoire.');
          continue;
        }
        // loadSecondary gère lui-même les transitions parsing → loaded / error.
        await ParsedPlaylistService.loadSecondary(acc.id, acc.label, res.path!);
      } catch (_) {
        if (!alreadyLoaded) {
          ParsedPlaylistService.setLoadState(acc.id, AccountLoadState.error);
        }
        // Ne pas planter le démarrage à cause d'un compte cassé (network, IO…).
      }
    }
    // §favReconcile — Passe FINALE : tous les comptes secondaires ont été
    // tentés (chargés ou en erreur) → ré-appariement des favoris orphelins
    // avec la vue la plus complète possible, puis pose du flag one-shot.
    await FavoritesService.reconcileWithPlaylist(finalPass: true);
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24.0), child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            const Text('Erreur au Démarrage', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(snapshot.error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: _retryInitialization, icon: const Icon(Icons.refresh), label: const Text("Réessayer")),
            const SizedBox(height: 8),
            TextButton(onPressed: _recheckAfterSettings, child: const Text("Vérifier les comptes"))
          ]))));
        }
        final data = snapshot.data;
        if (data != null) {
          return MainNavigation(initialData: data);
        }
        // §webConsoleOnly — Sur TV, pas de compte = on propose direct la
        // Console web (la saisie au D-pad est inutilisable, et le panneau
        // complet couvre aussi bien l'ajout que la réparation d'une liste).
        // Sur mobile, on garde le raccourci historique "Configurer les comptes".
        final isTv = PlatformTv.isTv;
        return Scaffold(
          appBar: AppBar(title: const Text('AetherStream')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isTv ? Icons.qr_code_2 : Icons.settings, size: 64),
                  const SizedBox(height: 16),
                  const Text('Aucun compte configuré',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    isTv
                        ? 'Scanne un QR code avec ton téléphone pour gérer tes '
                            'playlists sans avoir à taper à la télécommande.'
                        : 'Ajoutez un compte via la roue crantée pour commencer.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  // §webConsoleOnly — Sur TV, la Console web devient le bouton
                  // PRINCIPAL (donc celui qui prend le focus D-pad). Avant, le
                  // focus allait au pairing mono-formulaire et la console était
                  // un lien discret en dessous : depuis une télécommande, on
                  // tombait mécaniquement sur la version étroite.
                  FilledButton.icon(
                    onPressed: isTv ? _openWebConsole : _recheckAfterSettings,
                    icon: Icon(isTv ? Icons.phone_iphone : Icons.settings),
                    label: Text(isTv
                        ? 'Configurer depuis mon téléphone'
                        : 'Configurer les comptes'),
                  ),
                  // Sur mobile, la Console web reste proposée en second : le
                  // clavier du PC est plus confortable pour une longue URL.
                  if (!isTv) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _openWebConsole,
                      icon: const Icon(Icons.language, size: 18),
                      label: const Text('Configurer via Console web'),
                    ),
                  ],
                  // §restore — Récupérer une sauvegarde .aether existante.
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _restoreFromBackup,
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('Restaurer une sauvegarde'),
                  ),
                  if (isTv) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _recheckAfterSettings,
                      child: const Text('Saisir manuellement'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// §loadingScreen — Écran d'accueil affiché pendant l'initialisation de l'app
/// (chargement playlist active, parsing, cache TMDB, etc.). Remplace un
/// `CircularProgressIndicator` mono-thread qui saccadait pendant le parsing M3U.
///
/// Design "terminal cyberpunk" cohérent avec l'identité de l'app :
///   - Fond sombre + radial gradient sur la couleur primaire (comme la home).
///   - Wordmark **AETHERSTREAM** en VT323 (police monospace pixel-art) avec glow.
///   - Sous-titre style terminal "// initialisation…".
///   - Barre de progression indéterminée linéaire (moins sensible aux jank du
///     thread UI qu'un spinner circulaire), thémée à la couleur primaire.
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: cs.surface,
          gradient: RadialGradient(
            center: const Alignment(0, -0.2),
            radius: 1.2,
            colors: [primary.withAlpha(32), cs.surface],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Wordmark glow VT323 (Matrix terminal).
                Text(
                  'AetherStream',
                  style: GoogleFonts.vt323(
                    color: primary,
                    fontSize: 56,
                    letterSpacing: 4,
                    shadows: [
                      Shadow(color: primary.withAlpha(180), blurRadius: 18),
                      Shadow(color: primary.withAlpha(120), blurRadius: 32),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // §bootStatus — Sous-titre terminal + barre pilotés par
                // l'étape réelle du boot (au lieu d'un texte figé).
                ValueListenableBuilder<BootStep>(
                  valueListenable: BootStatus.step,
                  builder: (_, step, __) {
                    final pct = step.progress == null
                        ? ''
                        : ' ${(step.progress! * 100).round()} %';
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${step.label}$pct',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.sourceCodePro(
                            color: cs.onSurfaceVariant.withAlpha(180),
                            fontSize: 13,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 40),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              minHeight: 5,
                              // `null` → animation indéterminée (étapes sans
                              // progression mesurable).
                              value: step.progress,
                              backgroundColor: cs.surfaceContainerHighest,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(primary),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}