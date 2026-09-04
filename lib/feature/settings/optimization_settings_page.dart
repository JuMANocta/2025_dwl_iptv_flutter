import 'package:flutter/material.dart';
import 'package:aetherStream/core/navigation/playlist_visibility.dart';
import 'package:aetherStream/core/settings/perf_config.dart';
import 'package:aetherStream/core/settings/performance_settings_service.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/utils/image_cache_config.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/storage_janitor.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:aetherStream/widgets/confirm_or_undo.dart';
import 'package:aetherStream/widgets/memory_stats_card.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';
import 'package:aetherStream/widgets/tv/focusable_chip.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';
import '../../l10n/app_localizations.dart';
import 'package:aetherStream/widgets/tv/section_beacon.dart';

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
  }

  @override
  void dispose() {
    PlaylistVisibility.release();
    super.dispose();
  }

  /// §acctPurge — Compte les fichiers sans propriétaire, sans rien supprimer.
  Future<void> _scanStorage() async {
    final accounts = await StreamAccountService.listAccounts();
    final res = await StorageJanitor.preview(
      knownAccountIds: accounts.map((a) => a.id).toSet(),
      // L'utilisateur a la page sous les yeux : s'il n'a aucun compte, c'est un
      // fait qu'il voit, pas un stockage sécurisé qui a hoqueté au démarrage.
      allowEmptyAccountList: true,
    );
    if (mounted) setState(() => _reclaimable = res);
  }

  /// §acctPurge — Supprime les fichiers des comptes qui n'existent plus.
  Future<void> _purgeOrphans() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _purging = true);
    final accounts = await StreamAccountService.listAccounts();
    final res = await StorageJanitor.sweepOrphans(
      knownAccountIds: accounts.map((a) => a.id).toSet(),
      allowEmptyAccountList: true,
    );
    if (!mounted) return;
    setState(() {
      _purging = false;
      _reclaimable = const StorageSweepResult(fileCount: 0, bytes: 0);
      _memCardEpoch++;
    });
    messenger.showSnackBar(SnackBar(
      content: Text(res.isEmpty
          ? 'Rien à récupérer — aucun fichier orphelin'
          : '🧹 ${res.label} libérés (${res.fileCount} fichier(s))'),
    ));
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
  Future<void> _resetWithUndo() async {
    final PerfConfig old = _config;
    if (old == PerfConfig.defaults) return; // rien à réinitialiser
    await confirmOrUndo(
      context,
      title: 'Réinitialiser les réglages ?',
      question:
          'Tous les réglages d\'optimisation reviennent aux valeurs par défaut.',
      confirmLabel: 'Réinitialiser',
      doneMessage: 'Réglages réinitialisés',
      action: () async => _apply(PerfConfig.defaults),
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
          ? '💤 $n compte(s) secondaire(s) déchargé(s) de la mémoire'
          : 'Rien à libérer (un seul compte chargé)'),
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
    messenger.showSnackBar(const SnackBar(
      content: Text('🧹 Cache images vidé'),
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
            tooltip: 'Réinitialiser',
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
          pageTitle: 'Optimisation',
          // Repli tactile : au doigt rien n'a le focus, on lit au tiers haut.
          thresholdFraction: 0.3,
          child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionMark('Profils'),
              _buildProfilesRow(cs),
              const SectionMark('Hero banner'),
              _switchTile(
                icon: Icons.style_outlined,
                title: 'Hero banner',
                subtitle:
                    'Empilement de cartes en tête de la home (coûteux sur box faible)',
                value: _config.heroEnabled,
                onChanged: (v) => _apply(_config.copyWith(heroEnabled: v)),
              ),
              _switchTile(
                icon: Icons.autorenew,
                title: 'Rotation automatique',
                subtitle: 'Fait défiler le hero toutes les 6 s (swipe manuel toujours actif)',
                value: _config.heroAutoRotate,
                enabled: _config.heroEnabled,
                onChanged: (v) => _apply(_config.copyWith(heroAutoRotate: v)),
              ),
              _buildStepper(
                label: 'Cartes',
                value: _config.heroCardCount,
                min: PerfConfig.minHeroCards,
                max: PerfConfig.maxHeroCards,
                step: 1,
                enabled: _config.heroEnabled,
                onChanged: (v) => _apply(_config.copyWith(heroCardCount: v)),
              ),
              const SectionMark('Rangées de catégories'),
              _buildStepper(
                label: 'Vignettes',
                value: _config.maxItemsPerRow,
                min: PerfConfig.minItemsPerRow,
                max: PerfConfig.maxItemsPerRowLimit,
                step: 5,
                onChanged: (v) => _apply(_config.copyWith(maxItemsPerRow: v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  'Vignettes affichées par rangée avant la tuile « Voir tout » '
                  '(les Favoris ne sont jamais tronqués).',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
              // §autoNextEp — Réglage de CONFORT, volontairement hors des
              // profils de performance (les 3 presets le laissent intact).
              const SectionMark('Lecture'),
              _switchTile(
                icon: Icons.skip_next_rounded,
                title: 'Épisode suivant automatique',
                subtitle:
                    'Enchaîne l\'épisode suivant en fin de lecture, après un '
                    'décompte annulable. Un changement de saison demande '
                    'toujours confirmation.',
                value: _config.autoNextEpisode,
                onChanged: (v) => _apply(_config.copyWith(autoNextEpisode: v)),
              ),
              // §playerBuffer — Le `LoadControl` d'ExoPlayer, enfin réglé.
              _buildStepper(
                label: 'Tampon de lecture',
                value: _config.bufferSeconds,
                min: PerfConfig.minBufferSeconds,
                max: PerfConfig.maxBufferSeconds,
                step: 10,
                suffix: ' s',
                onChanged: (v) => _apply(_config.copyWith(bufferSeconds: v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Secondes de vidéo gardées d\'avance. Monter aide sur un '
                  'fournisseur qui bride — la lecture puise dans le tampon au '
                  'lieu de s\'arrêter — mais tient d\'autant plus de flux en '
                  'mémoire, ce qui compte sur une box. Le compteur '
                  '« Blocages » de l\'encart Infos vidéo dit si le réglage '
                  'sert à quelque chose. Prend effet à la lecture suivante.',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
              // §unloadGuard — Les listes en mémoire, enfin réglables.
              //
              // Le déchargement paresseux existait depuis §lazyUnload mais
              // était codé en dur (5 min) et invisible : l'utilisateur voyait
              // ses listes passer à « NON CHARGÉ » sans rien avoir demandé, et
              // n'avait aucun moyen de l'éteindre.
              const SectionMark('Listes'),
              _switchTile(
                icon: Icons.playlist_add_check_circle_outlined,
                title: 'Garder toutes les listes en mémoire',
                subtitle:
                    'Chaque compte reste chargé : recherche cross-comptes et '
                    'changement de liste instantanés. Coûte de la mémoire '
                    '(~50 à 150 Mo par liste) — à éteindre sur Fire Stick ou '
                    'box à faible RAM.',
                value: _config.keepAllListsInMemory,
                onChanged: (v) =>
                    _apply(_config.copyWith(keepAllListsInMemory: v)),
              ),
              _buildStepper(
                label: 'Décharger après',
                value: _config.idleUnloadMinutes,
                min: PerfConfig.minIdleUnloadMinutes,
                max: PerfConfig.maxIdleUnloadMinutes,
                step: 5,
                // Le délai ne sert que si on accepte de décharger : grisé tant
                // que l'interrupteur ci-dessus est allumé, mais la valeur est
                // conservée pour le jour où on l'éteint.
                enabled: !_config.keepAllListsInMemory,
                valueLabel: (v) => v <= 0 ? 'Jamais' : '$v min',
                onChanged: (v) =>
                    _apply(_config.copyWith(idleUnloadMinutes: v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Minutes sans consulter une liste secondaire avant de la '
                  'sortir de la mémoire. Le cache disque est conservé : elle '
                  'revient en ~50 ms au prochain accès. « Jamais » (0) équivaut '
                  'à garder toutes les listes. Les pages qui affichent les '
                  'listes ou leurs compteurs suspendent le déchargement tant '
                  'qu\'elles sont ouvertes.',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
              const SectionMark('Mémoire & usage'),
              // §imgMemCache — plafond du cache image EN RAM.
              _buildStepper(
                label: 'Images (RAM)',
                value: _config.imageCacheMb,
                min: PerfConfig.minImageCacheMb,
                max: PerfConfig.maxImageCacheMb,
                step: 10,
                suffix: ' Mo',
                onChanged: (v) => _apply(_config.copyWith(imageCacheMb: v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Mémoire vive réservée aux images déjà affichées (défaut '
                  'Flutter : 100 Mo). ⚠️ Baisser ne rend pas l\'app plus '
                  'fluide : trop bas, les vignettes sont re-décodées en '
                  'permanence et l\'affichage se met à saccader. À n\'ajuster '
                  'que si la mémoire manque vraiment.',
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
                    child: FilledButton.tonalIcon(
                      onPressed: _freeMemory,
                      icon:
                          const Icon(Icons.cleaning_services_outlined, size: 18),
                      label: const Text(
                          'Libérer la mémoire des comptes secondaires'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  'Les caches disque sont conservés : un compte déchargé se '
                  'recharge en ~50 ms au prochain accès.',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
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
                    child: FilledButton.tonalIcon(
                      onPressed: _clearImageCache,
                      icon: const Icon(Icons.image_not_supported_outlined,
                          size: 18),
                      label: const Text('Vider le cache images'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  'Les vignettes sont gardées sur le disque pour éviter de les '
                  're-télécharger. À vider si une affiche a changé côté '
                  'fournisseur ou si le stockage sature.',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),

              // §acctPurge — Fichiers sans propriétaire.
              const SectionMark('Stockage'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _reclaimable == null
                      ? 'Analyse du stockage…'
                      : _reclaimable!.isEmpty
                          ? 'Rien à récupérer : chaque fichier appartient à un '
                              'compte existant.'
                          : '${_reclaimable!.label} occupés par des fichiers '
                              'qui n\'appartiennent plus à aucun compte '
                              '(${_reclaimable!.fileCount} fichier(s)) — '
                              'playlists et caches laissés derrière eux par des '
                              'comptes supprimés.',
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
                    child: FilledButton.tonalIcon(
                      onPressed: _purging ? null : _purgeOrphans,
                      icon: const Icon(Icons.folder_delete_outlined, size: 18),
                      label: Text(_purging
                          ? 'Nettoyage…'
                          : 'Nettoyer les fichiers orphelins'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                child: Text(
                  'Supprimer un compte ne supprimait pas ses fichiers : ils '
                  'restaient sur l\'appareil, sans propriétaire et sans que '
                  'rien ne les compte. C\'est corrigé à la source, ce bouton '
                  'rattrape ce qui traîne déjà. Sans effet sur les comptes '
                  'actuels, leurs listes ni tes favoris.',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  // ── Helpers UI (mêmes patterns que ThemeSettingsPage) ────────────────────

  Widget _buildProfilesRow(ColorScheme cs) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: PerfConfig.presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final preset = PerfConfig.presets[i];
          final active = _config == preset.config;
          // §tourFix — reporter autoNextEpisode dans la config du preset :
          // c'est un réglage de CONFORT volontairement hors des profils de
          // performance (cf. §autoNextEp dans perf_config.dart) ; appliquer
          // preset.config tel quel l'écrasait silencieusement.
          void applyPreset() => _apply(
              preset.config.copyWith(autoNextEpisode: _config.autoNextEpisode));
          return FocusableChip(
            onTap: applyPreset,
            borderRadius: BorderRadius.circular(10),
            child: GestureDetector(
              onTap: applyPreset,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 104,
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
                      preset.name,
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
                      preset.subtitle,
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
        child: Opacity(
          opacity: enabled ? 1.0 : 0.45,
          // §tourFix — même patron que SettingsPage : l'InkWell interne du
          // SwitchListTile est focusable par défaut → 2e arrêt D-pad par tuile,
          // sans halo. ExcludeFocus le retire de la traversée ; seul le Focus
          // du FocusableCard reste (le tap tactile, lui, n'est pas affecté).
          child: ExcludeFocus(
            child: SwitchListTile(
              secondary: Icon(icon, color: kAccentSecondary),
              title: Text(title, style: const TextStyle(fontSize: 14)),
              subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
              value: value,
              activeTrackColor: kAccentSecondary,
              onChanged: enabled ? onChanged : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
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
    final color = enabled ? kAccentSecondary : kAccentSecondary.withAlpha(90);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(label, style: const TextStyle(fontSize: 13)),
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
              color: value > min ? color : color.withAlpha(70),
              tooltip: 'Diminuer',
            ),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: color.withAlpha(40),
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
              color: value < max ? color : color.withAlpha(70),
              tooltip: 'Augmenter',
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
      ),
    );
  }
}
