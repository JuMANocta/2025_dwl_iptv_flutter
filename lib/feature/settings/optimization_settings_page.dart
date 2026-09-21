import 'package:flutter/material.dart';
import 'package:aetherStream/core/navigation/playlist_visibility.dart';
import 'package:aetherStream/core/settings/perf_config.dart';
import 'package:aetherStream/core/settings/performance_settings_service.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/themes/light_palette.dart';
import 'package:aetherStream/core/themes/themes.dart';
import 'package:aetherStream/core/utils/image_cache_config.dart';
import 'package:aetherStream/core/utils/user_error.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/download_manager_service.dart';
import 'package:aetherStream/data/services/storage_janitor.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:aetherStream/feature/downloads/logic/download_scheduler.dart';
import 'package:aetherStream/widgets/confirm_or_undo.dart';
import 'package:aetherStream/widgets/memory_stats_card.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';
import 'package:aetherStream/widgets/tv/focusable_chip.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_ext.dart';
import 'package:aetherStream/widgets/tv/section_beacon.dart';
import 'package:aetherStream/feature/settings/device_caps_page.dart';

/// §perfSettings — Page « Optimisation » (Fire Stick / terminaux faibles).
///
/// Profils prédéfinis (Confort/Équilibré/Performance) + réglages individuels
/// (hero banner, rotation, cartes hero, vignettes par rangée) + diagnostic
/// mémoire avec action de libération immédiate. Structure et helpers UI
/// calqués sur `ThemeSettingsPage` (presets row, stepper TV −/+).
class OptimizationSettingsPage extends StatefulWidget {
  const OptimizationSettingsPage({super.key});

  @override
  State<OptimizationSettingsPage> createState() =>
      _OptimizationSettingsPageState();
}

class _OptimizationSettingsPageState extends State<OptimizationSettingsPage> with TvInitialFocus {
  late PerfConfig _config;

  /// Change de valeur après « Libérer la mémoire » → recrée la MemoryStatsCard
  /// (initState → refresh) pour refléter immédiatement les comptes déchargés.
  int _memCardEpoch = 0;

  /// §acctPurge — Ce qu'un balayage libérerait, mesuré à l'ouverture de la page.
  /// `null` tant que le comptage n'a pas abouti.
  StorageSweepResult? _reclaimable;
  bool _purging = false;

  /// §dlQueueFix — Combien d'abonnements existent. `null` tant qu'on ne sait
  /// pas : on ne montre rien plutôt qu'un réglage qui pourrait être un
  /// mensonge.
  int? _accountCount;

  @override
  void initState() {
    super.initState();
    // §unloadGuard — Cette page affiche les COMPTEURS par compte
    // (`MemoryStatsCard`) : un déchargement automatique pendant qu'on la
    // regarde ferait tomber les chiffres à zéro sous les yeux de
    // l'utilisateur, en plein diagnostic mémoire. Le bouton « Libérer la
    // mémoire », lui, reste actif — c'est une action demandée, pas subie.
    PlaylistVisibility.hold();
    _config = PerformanceSettingsService.config.value;
    _scanStorage();
    StreamAccountService.listAccounts().then((a) {
      if (mounted) setState(() => _accountCount = a.length);
    });
  }

  @override
  void dispose() {
    PlaylistVisibility.release();
    super.dispose();
  }

  /// §acctPurge — Compte les fichiers sans propriétaire, sans rien supprimer.
  Future<void> _scanStorage() async {
    final res = await _measure(dryRun: true);
    if (mounted) setState(() => _reclaimable = res);
  }

  /// §acctPurge + §dlPartSweep — Les DEUX ménages, en un seul chiffre.
  ///
  /// L'utilisateur n'a pas à savoir qu'il y a deux mécanismes : il voit une
  /// place récupérable et un bouton. Les deux balayages passent
  /// `allowEmpty…: true` — il a la page sous les yeux, donc une liste vide est
  /// un fait qu'il constate, pas un stockage qui a hoqueté au démarrage.
  Future<StorageSweepResult> _measure({required bool dryRun}) async {
    final accounts = await StreamAccountService.listAccounts();
    final accountFiles = await StorageJanitor.sweepOrphans(
      knownAccountIds: accounts.map((a) => a.id).toSet(),
      allowEmptyAccountList: true,
      dryRun: dryRun,
    );
    final partials = await StorageJanitor.sweepDownloadPartials(
      // ⚠️ TOUS les statuts : `failed` et `canceled` désignent des transferts
      // que « Relancer » reprend à l'octet près par un en-tête `Range`.
      liveTempPaths: DownloadManagerService()
          .tasksNotifier
          .value
          .map((t) => t.tempPath)
          .where((p) => p.isNotEmpty)
          .toSet(),
      allowEmptyTaskList: true,
      dryRun: dryRun,
    );
    return StorageSweepResult(
      fileCount: accountFiles.fileCount + partials.fileCount,
      bytes: accountFiles.bytes + partials.bytes,
    );
  }

  /// §acctPurge + §dlPartSweep — Supprime les fichiers des comptes qui
  /// n'existent plus, ET les partiels de téléchargement abandonnés.
  Future<void> _purgeOrphans() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _purging = true);
    // Revue 2026-09-11, D4B-11 — `_measure` lit le stockage et la liste des
    // comptes : s'il lève, le bouton restait en « Suppression… » jusqu'à la
    // sortie de la page. Le drapeau est désormais toujours relâché.
    try {
      final res = await _measure(dryRun: false);
      if (!mounted) return;
      setState(() {
        _reclaimable = const StorageSweepResult(fileCount: 0, bytes: 0);
        _memCardEpoch++;
      });
      messenger.showSnackBar(SnackBar(
        content: Text(res.isEmpty
            ? l10n.perfPurgeNothing
            : l10n.perfPurgeDone(res.label, res.fileCount)),
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.commonFailedWith(describeError(e)))));
    } finally {
      if (mounted) setState(() => _purging = false);
    }
  }

  /// Applique la config en live (ValueNotifier → rebuild home) et la persiste.
  void _apply(PerfConfig config) {
    setState(() => _config = config);
    PerformanceSettingsService.save(config);
  }

  /// §undoReset + §undoTv — « Réinitialiser » reste réversible : un tap sur
  /// l'icône de l'AppBar effaçait sans retour des réglages ajustés un par un.
  ///
  /// Au doigt : on applique, puis snackbar « Annuler » 5 s. À la télécommande :
  /// on DEMANDE avant, car l'action d'une snackbar n'est pas atteignable au
  /// D-pad (l'annulation y était décorative).
  ///
  /// ⚠️ Le snackbar survit à la page (il vit sur le `ScaffoldMessenger` racine) :
  /// si l'utilisateur a quitté avant d'annuler, on persiste sans `setState`.
  ///
  /// Revue 2026-09-11, D4B-01 : la cible épargne les options de la page TMDB
  /// et « Wi-Fi seulement » (`withOptimizationDefaults`), et le test « rien à
  /// faire » compare TOUS les champs — `==` ignore le confort, donc
  /// « Réinitialiser » ne faisait rien quand seul le confort avait changé.
  Future<void> _resetWithUndo() async {
    final PerfConfig old = _config;
    final PerfConfig target = old.withOptimizationDefaults();
    if (old.sameSettingsAs(target)) return; // rien à réinitialiser
    await confirmOrUndo(
      context,
      title: context.l10n.perfResetTitle,
      question: context.l10n.perfResetQuestion,
      confirmLabel: context.l10n.perfResetConfirm,
      doneMessage: context.l10n.perfResetDone,
      action: () async => _apply(target),
      onUndo: () {
        if (mounted) {
          _apply(old);
        } else {
          PerformanceSettingsService.save(old);
        }
      },
    );
  }

  /// §lazyUnload — Décharge immédiatement les comptes secondaires de la
  /// mémoire (caches disque conservés → rechargement ~50 ms au prochain accès).
  Future<void> _freeMemory() async {
    final messenger = ScaffoldMessenger.of(context);
    final acc = await StreamAccountService.getCurrentAccount();
    final n = ParsedPlaylistService.unloadIdleSecondaries(
      activeAccountId: acc?.id ?? '',
      idle: Duration.zero,
    );
    if (!mounted) return;
    setState(() => _memCardEpoch++);
    messenger.showSnackBar(SnackBar(
      content: Text(n > 0
          ? context.l10n.perfFreeMemoryDone(n)
          : context.l10n.perfFreeMemoryNothing),
    ));
  }

  /// §imgDiskCache — Vide le cache disque des vignettes. Utile si une image a
  /// changé côté provider ou si le stockage sature ; elles se re-téléchargeront
  /// à la demande.
  Future<void> _clearImageCache() async {
    final messenger = ScaffoldMessenger.of(context);
    await AetherImageCache.emptyAll();
    if (!mounted) return;
    setState(() => _memCardEpoch++);
    messenger.showSnackBar(SnackBar(
      content: Text(context.l10n.perfImageCacheCleared),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.optimizationTitle),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: context.l10n.perfResetConfirm,
            onPressed: _resetWithUndo,
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? null : cs.surface,
          gradient: isDark
              ? RadialGradient(
                  center: const Alignment(0, -1.5),
                  radius: 1.4,
                  colors: [
                    kAccentSecondary.withAlpha(20),
                    cs.surface,
                  ],
                )
              : null,
        ),
        // §navBlind — La page la plus longue de l'app : sept sections, aucun
        // repere. Le bandeau nomme celle qu'on regarde (TV uniquement).
        child: SectionBeacon(
          pageTitle: context.l10n.optimizationTitle,
          // Repli tactile : au doigt rien n'a le focus, on lit au tiers haut.
          thresholdFraction: 0.3,
          child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // §deviceCaps — La sonde d'abord : c'est elle qui explique le
              // profil choisi, et ce que l'appareil peut lire.
              _capsTile(cs),
              SectionMark(context.l10n.perfSectionProfiles),
              _buildProfilesRow(cs),
              SectionMark(context.l10n.perfSectionHero),
              _switchTile(
                icon: Icons.style_outlined,
                title: context.l10n.perfSectionHero,
                subtitle: context.l10n.perfHeroSub,
                value: _config.heroEnabled,
                onChanged: (v) => _apply(_config.copyWith(heroEnabled: v)),
              ),
              _switchTile(
                icon: Icons.autorenew,
                title: context.l10n.perfAutoRotateTitle,
                subtitle: context.l10n.perfAutoRotateSub,
                value: _config.heroAutoRotate,
                enabled: _config.heroEnabled,
                onChanged: (v) => _apply(_config.copyWith(heroAutoRotate: v)),
              ),
              _buildStepper(
                label: context.l10n.perfHeroCardsLabel,
                value: _config.heroCardCount,
                min: PerfConfig.minHeroCards,
                max: PerfConfig.maxHeroCards,
                step: 1,
                enabled: _config.heroEnabled,
                onChanged: (v) => _apply(_config.copyWith(heroCardCount: v)),
              ),
              SectionMark(context.l10n.perfSectionRows),
              _buildStepper(
                label: context.l10n.perfItemsLabel,
                value: _config.maxItemsPerRow,
                min: PerfConfig.minItemsPerRow,
                max: PerfConfig.maxItemsPerRowLimit,
                step: 5,
                onChanged: (v) => _apply(_config.copyWith(maxItemsPerRow: v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  context.l10n.perfItemsSub,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
              // §rowFold — Seuil de repli des micro-rangées. Réglage de
              // confort (exclu de l'égalité des profils), mesuré sur TV : une
              // rangée d'une carte coûte un écran entier de télécommande.
              _buildStepper(
                label: context.l10n.perfMinItemsTitle,
                value: _config.rowFoldMin,
                min: PerfConfig.minRowFoldMin,
                max: PerfConfig.maxRowFoldMin,
                step: 1,
                onChanged: (v) => _apply(_config.copyWith(rowFoldMin: v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  context.l10n.perfMinItemsSub,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
              // §autoNextEp — Réglage de CONFORT, volontairement hors des
              // profils de performance (les 3 presets le laissent intact).
              // §dlQueue (2026-09-06, lot 6) — Plafond global des transferts ;
              // la limite par abonnement (un seul) n'est pas réglable, elle
              // vient des panels eux-mêmes (§hostGate).
              SectionMark(context.l10n.perfDownloadsSection),
              // §dlQueueFix — Avec un seul abonnement, la file n'autorise
              // qu'UN transfert (§dlQueue / §hostGate) : le curseur ne
              // changerait rien, et un réglage qui ne fait rien ment à qui le
              // tourne. Il n'apparaît donc qu'à partir de deux abonnements, et
              // son sous-titre dit alors ce que le nombre veut dire.
              if (showParallelDownloadsSetting(_accountCount ?? 0)) ...[
                _buildStepper(
                  label: context.l10n.perfParallelDownloadsTitle,
                  value: _config.maxParallelDownloads,
                  min: PerfConfig.minParallelDownloads,
                  max: PerfConfig.maxParallelDownloadsLimit,
                  step: 1,
                  onChanged: (v) =>
                      _apply(_config.copyWith(maxParallelDownloads: v)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    context.l10n.perfParallelDownloadsPerHostSub(
                        _config.maxParallelDownloads),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
              // §dlWifi — « Wi-Fi seulement » = pas sur un réseau facturé.
              _switchTile(
                icon: Icons.wifi_rounded,
                title: context.l10n.perfWifiOnlyTitle,
                subtitle: context.l10n.perfWifiOnlySub,
                value: _config.downloadsWifiOnly,
                onChanged: (v) =>
                    _apply(_config.copyWith(downloadsWifiOnly: v)),
              ),
              SectionMark(context.l10n.perfSectionPlayback),
              _switchTile(
                icon: Icons.skip_next_rounded,
                title: context.l10n.perfAutoNextTitle,
                subtitle: context.l10n.perfAutoNextSub,
                value: _config.autoNextEpisode,
                onChanged: (v) => _apply(_config.copyWith(autoNextEpisode: v)),
              ),
              // §playerBuffer — Le `LoadControl` d'ExoPlayer, enfin réglé.
              _buildStepper(
                label: context.l10n.perfBufferLabel,
                value: _config.bufferSeconds,
                min: PerfConfig.minBufferSeconds,
                max: PerfConfig.maxBufferSeconds,
                step: 10,
                suffix: context.l10n.perfUnitSeconds,
                onChanged: (v) => _apply(_config.copyWith(bufferSeconds: v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  context.l10n.perfBufferSub,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
              // §unloadGuard — Les listes en mémoire, enfin réglables.
              //
              // Le déchargement paresseux existait depuis §lazyUnload mais
              // était codé en dur (5 min) et invisible : l'utilisateur voyait
              // ses listes passer à « NON CHARGÉ » sans rien avoir demandé, et
              // n'avait aucun moyen de l'éteindre.
              SectionMark(context.l10n.perfSectionLists),
              _switchTile(
                icon: Icons.playlist_add_check_circle_outlined,
                title: context.l10n.perfKeepListsTitle,
                subtitle: context.l10n.perfKeepListsSub,
                value: _config.keepAllListsInMemory,
                onChanged: (v) =>
                    _apply(_config.copyWith(keepAllListsInMemory: v)),
              ),
              _buildStepper(
                label: context.l10n.perfUnloadAfterLabel,
                value: _config.idleUnloadMinutes,
                min: PerfConfig.minIdleUnloadMinutes,
                max: PerfConfig.maxIdleUnloadMinutes,
                step: 5,
                // Le délai ne sert que si on accepte de décharger : grisé tant
                // que l'interrupteur ci-dessus est allumé, mais la valeur est
                // conservée pour le jour où on l'éteint.
                enabled: !_config.keepAllListsInMemory,
                valueLabel: (v) => v <= 0
                    ? context.l10n.perfUnloadNever
                    : context.l10n.perfMinutesShort(v),
                onChanged: (v) =>
                    _apply(_config.copyWith(idleUnloadMinutes: v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  context.l10n.perfUnloadSub,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
              SectionMark(context.l10n.perfSectionMemory),
              // §imgMemCache — plafond du cache image EN RAM.
              _buildStepper(
                label: context.l10n.perfImageRamLabel,
                value: _config.imageCacheMb,
                min: PerfConfig.minImageCacheMb,
                max: PerfConfig.maxImageCacheMb,
                step: 10,
                suffix: context.l10n.perfUnitMegabytes,
                onChanged: (v) => _apply(_config.copyWith(imageCacheMb: v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  context.l10n.perfImageRamSub,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: MemoryStatsCard(key: ValueKey(_memCardEpoch)),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FocusableCard(
                  scaleOnFocus: false,
                  onTap: _freeMemory,
                  decorateOnly: true,
                  // §tourFix — Même défaut que les tuiles à interrupteur : un
                  // `FilledButton` porte SON propre nœud de focus, ce qui
                  // créait un 2e arrêt D-pad sans halo sur la même commande.
                  // ExcludeFocus le retire de la traversée ; le tap tactile
                  // n'est pas touché (ExcludeFocus n'agit que sur le focus).
                  child: ExcludeFocus(
                    // Style commun des boutons pleins (`aetherFilledStyle`) :
                    // ces trois-là étaient les seuls `tonalIcon` de l'app.
                    child: FilledButton.icon(
                      onPressed: _freeMemory,
                      icon:
                          const Icon(Icons.cleaning_services_outlined, size: 18),
                      label: Text(context.l10n.perfFreeMemoryButton),
                      style: aetherFilledStyle(kAccentPrimary,
                          minimumSize: const Size.fromHeight(44)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // §imgDiskCache — purge manuelle du cache des vignettes.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FocusableCard(
                  scaleOnFocus: false,
                  onTap: _clearImageCache,
                  decorateOnly: true,
                  // §tourFix — cf. le bouton ci-dessus : ExcludeFocus supprime
                  // le second arrêt D-pad apporté par le FilledButton.
                  child: ExcludeFocus(
                    child: FilledButton.icon(
                      onPressed: _clearImageCache,
                      icon: const Icon(Icons.image_not_supported_outlined,
                          size: 18),
                      label: Text(context.l10n.perfClearImageCacheButton),
                      style: aetherFilledStyle(kAccentSecondary,
                          minimumSize: const Size.fromHeight(44)),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  context.l10n.perfClearImageCacheNote,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),

              // §acctPurge — Fichiers sans propriétaire.
              SectionMark(context.l10n.perfSectionStorage),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _reclaimable == null
                      ? context.l10n.perfStorageScanning
                      : _reclaimable!.isEmpty
                          ? context.l10n.perfStorageNothing
                          : context.l10n.perfStorageReclaimable(
                              _reclaimable!.label, _reclaimable!.fileCount),
                  style: TextStyle(
                    fontSize: 11,
                    color: (_reclaimable?.isEmpty ?? true)
                        ? cs.onSurfaceVariant
                        : kWarning,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FocusableCard(
                  scaleOnFocus: false,
                  onTap: _purging ? null : _purgeOrphans,
                  decorateOnly: true,
                  // §tourFix — cf. les deux boutons ci-dessus : ExcludeFocus
                  // supprime le second arrêt D-pad apporté par le FilledButton.
                  child: ExcludeFocus(
                    // Ce bouton EFFACE des fichiers : il porte la couleur
                    // d'alerte, comme la ligne « récupérable » juste au-dessus.
                    child: FilledButton.icon(
                      onPressed: _purging ? null : _purgeOrphans,
                      icon: const Icon(Icons.folder_delete_outlined, size: 18),
                      label: Text(_purging
                          ? context.l10n.perfPurging
                          : context.l10n.perfPurgeButton),
                      style: aetherFilledStyle(kWarning,
                          minimumSize: const Size.fromHeight(44)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
          ),
        ),
      ),
    );
  }

  // ── Helpers UI (mêmes patterns que ThemeSettingsPage) ────────────────────

  /// §deviceCaps — Libellés des profils : par identifiant, dans la l10n.
  String _presetLabel(String id) => switch (id) {
        'confort' => context.l10n.perfProfileConfort,
        'equilibre' => context.l10n.perfProfileEquilibre,
        'performance' => context.l10n.perfProfilePerformance,
        _ => id,
      };

  String _presetSubtitle(String id) => switch (id) {
        'confort' => context.l10n.perfProfileConfortSub,
        'equilibre' => context.l10n.perfProfileEquilibreSub,
        'performance' => context.l10n.perfProfilePerformanceSub,
        _ => '',
      };

  Widget _capsTile(ColorScheme cs) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: FocusableCard(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DeviceCapsPage()),
        ),
        child: ListTile(
          leading: Icon(Icons.memory, color: kAccentSecondary),
          title: Text(l10n.capsTitle),
          subtitle: Text(l10n.capsSub, style: const TextStyle(fontSize: 11)),
          trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildProfilesRow(ColorScheme cs) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: PerfConfig.presets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final preset = PerfConfig.presets[i];
          final active = _config == preset.config;
          // §tourFix — les réglages de CONFORT sont hors des profils de
          // performance (cf. §autoNextEp dans perf_config.dart) ; appliquer
          // preset.config tel quel les écrasait silencieusement.
          // Revue 2026-09-11, D4B-01 : le report champ par champ n'en gardait
          // que deux sur huit (« Wi-Fi seulement » repassait à faux) →
          // `withProfileOf` garde tout ce qui n'est pas un levier de profil.
          void applyPreset() => _apply(_config.withProfileOf(preset.config));
          return FocusableChip(
            onTap: applyPreset,
            borderRadius: BorderRadius.circular(10),
            child: GestureDetector(
              onTap: applyPreset,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                // 2026-09-21 — Largeur MINIMALE, plus fixe : sur TV, le
                // plancher de texte (§tvSmallText) agrandit le sous-titre et
                // la tuile de 104 le coupait (« Static hero, short… »). La
                // rangée défile déjà : la tuile s'élargit à son texte.
                constraints: const BoxConstraints(minWidth: 104),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: kAccentSecondary.withAlpha(active ? 40 : 16),
                  border: Border.all(
                    color: active
                        ? kAccentSecondary
                        : kAccentSecondary.withAlpha(60),
                    width: active ? 2.0 : 1.0,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                              color: kAccentSecondary.withAlpha(80),
                              blurRadius: 8),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(preset.icon,
                        size: 20,
                        color: active ? kAccentSecondary : cs.onSurfaceVariant),
                    const SizedBox(height: 4),
                    Text(
                      _presetLabel(preset.name),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            active ? FontWeight.bold : FontWeight.normal,
                        color: active ? kAccentSecondary : cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _presetSubtitle(preset.name),
                      style: TextStyle(
                        fontSize: 9,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (active)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        width: 16,
                        height: 2,
                        decoration: BoxDecoration(
                          color: kAccentSecondary,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Tuile toggle pleine largeur — `FocusableCard(decorateOnly)` : OK
  /// télécommande → toggle, tap tactile géré par le SwitchListTile lui-même.
  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: FocusableCard(
        scaleOnFocus: false,
        decorateOnly: true,
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? () => onChanged(!value) : null,
        // §lightTheme — ⚠️ Ce n'était PAS une opacité, c'en était deux :
        // `Opacity(0.45)` par-dessus les 38 % que Material applique déjà à une
        // tuile désactivée. Sur le fond blanc du thème clair, le titre, le
        // sous-titre et l'icône d'un réglage grisé disparaissaient (mesuré sur
        // la planche, réglage « Rotation automatique »). L'atténuation est
        // désormais DÉRIVÉE, avec un plancher de contraste (`mutedOn`).
        child: Builder(builder: (context) {
          final ColorScheme cs = Theme.of(context).colorScheme;
          final Color fg =
              enabled ? cs.onSurface : mutedOn(cs.onSurface, cs.surface);
          final Color sub = enabled
              ? cs.onSurfaceVariant
              : mutedOn(cs.onSurfaceVariant, cs.surface);
          final Color ic = enabled
              ? kAccentSecondary
              : mutedOn(kAccentSecondary, cs.surface);
          // §tourFix — même patron que SettingsPage : l'InkWell interne du
          // SwitchListTile est focusable par défaut → 2e arrêt D-pad par tuile,
          // sans halo. ExcludeFocus le retire de la traversée ; seul le Focus
          // du FocusableCard reste (le tap tactile, lui, n'est pas affecté).
          return ExcludeFocus(
            child: SwitchListTile(
              secondary: Icon(icon, color: ic),
              title: Text(title,
                  style: TextStyle(fontSize: 14, color: fg)),
              subtitle: Text(subtitle,
                  style: TextStyle(fontSize: 11, color: sub)),
              value: value,
              activeTrackColor: kAccentSecondary,
              onChanged: enabled ? onChanged : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Stepper −/+ int (focusable D-pad, utilisé aussi hors TV : valeurs
  /// discrètes à petit pas → plus précis qu'un Slider au doigt).
  Widget _buildStepper({
    required String label,
    required int value,
    required int min,
    required int max,
    required int step,
    required ValueChanged<int> onChanged,
    bool enabled = true,
    String suffix = '',
    /// §unloadGuard — Certaines valeurs ne se lisent pas comme un nombre :
    /// « 0 min » veut dire « jamais ». Quand ce formateur est fourni, il
    /// remplace `valeur + suffixe`.
    String Function(int value)? valueLabel,
  }) {
    final ratio = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final ColorScheme cs = Theme.of(context).colorScheme;
    // §lightTheme — Même défaut que les tuiles à interrupteur : une opacité de
    // 45 % posée sur une couleur déjà atténuée de 65 % ne laissait rien à
    // l'écran en thème clair (les − / + du réglage « Cartes »). Deux niveaux
    // seulement, tous deux dérivés avec un plancher de contraste : PLEIN pour
    // ce qui répond, ATTÉNUÉ pour ce qui ne répond pas (désactivé, ou borne
    // atteinte).
    final Color color =
        enabled ? kAccentSecondary : mutedOn(kAccentSecondary, cs.surface);
    final Color spent = mutedOn(color, cs.surface);
    final Color label0 =
        enabled ? cs.onSurface : mutedOn(cs.onSurface, cs.surface);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: label0)),
            ),
            // §boundFocus — `onPressed: null` retire le bouton de la
            // traversee ALORS QU'IL A LE FOCUS : arrive a la borne, le bouton
            // focuse disparait et la telecommande se retrouve nulle part.
            // Il reste donc actif — le `clamp` en fait deja un geste sans
            // effet — et c'est la COULEUR qui dit qu'on est au bout.
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: enabled
                  ? () => onChanged((value - step).clamp(min, max))
                  : null,
              color: value > min ? color : spent,
              tooltip: context.l10n.commonDecrease,
            ),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: spent.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: enabled
                  ? () => onChanged((value + step).clamp(min, max))
                  : null,
              color: value < max ? color : spent,
              tooltip: context.l10n.commonIncrease,
            ),
            SizedBox(
              width: (suffix.isEmpty && valueLabel == null) ? 26 : 52,
              child: Text(
                valueLabel != null ? valueLabel(value) : '$value$suffix',
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
      ),
    );
  }
}
