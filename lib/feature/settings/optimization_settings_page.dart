import 'package:flutter/material.dart';
import 'package:aetherStream/core/settings/perf_config.dart';
import 'package:aetherStream/core/settings/performance_settings_service.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/utils/image_cache_config.dart';
import 'package:aetherStream/feature/player/video_render.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:aetherStream/widgets/memory_stats_card.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';
import 'package:aetherStream/widgets/tv/focusable_chip.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';
import '../../l10n/app_localizations.dart';

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

  @override
  void initState() {
    super.initState();
    _config = PerformanceSettingsService.config.value;
  }

  /// Applique la config en live (ValueNotifier → rebuild home) et la persiste.
  void _apply(PerfConfig config) {
    setState(() => _config = config);
    PerformanceSettingsService.save(config);
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
            onPressed: () => _apply(PerfConfig.defaults),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('Profils', cs),
              _buildProfilesRow(cs),
              _sectionLabel('Hero banner', cs),
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
              _sectionLabel('Rangées de catégories', cs),
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
              _sectionLabel('Lecture', cs),
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
              _sectionLabel('Mémoire & usage', cs),
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
                  child: FilledButton.tonalIcon(
                    onPressed: _freeMemory,
                    icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                    label: const Text('Libérer la mémoire des comptes secondaires'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  'Les vignettes sont gardées sur le disque pour éviter de les '
                  're-télécharger. À vider si une affiche a changé côté '
                  'fournisseur ou si le stockage sature.',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
              ..._buildVideoBench(cs),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers UI (mêmes patterns que ThemeSettingsPage) ────────────────────

  Widget _sectionLabel(String title, ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.8,
            color: cs.onSurfaceVariant,
          ),
        ),
      );

  /// §video4kBench — Section « Banc d'essai vidéo ».
  ///
  /// Elle vit ici et pas dans le panneau du lecteur pour une raison de méthode :
  /// changer `vo`/`hwdec` ne prend effet qu'à la lecture SUIVANTE (ils sont
  /// figés à la construction du `VideoController`). Un réglage posé au milieu
  /// d'un film donnerait l'illusion d'un essai qui n'a pas eu lieu.
  ///
  /// Le relevé qui la justifie (box réelle, 2026-08-30) : `mediacodec-copy`,
  /// 8,12 images perdues par seconde, **invariantes au débit** — donc la sortie
  /// vidéo, ni le réseau ni le décodeur. Cf. `video_render.dart`.
  List<Widget> _buildVideoBench(ColorScheme cs) {
    final overridden = VideoRenderPreference.isOverridden;
    return [
      _sectionLabel('Banc d\'essai vidéo', cs),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Text(
          'Pour diagnostiquer une lecture 4K qui saccade sur box TV. '
          'Les changements ne s\'appliquent qu\'à la PROCHAINE lecture. '
          'Vérifier le résultat avec « Infos vidéo » dans le lecteur '
          '(↑ → Options), qui affiche la sortie retenue et les images perdues.',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ),
      _benchRow<VideoRenderMode>(
        cs: cs,
        title: 'Rendu',
        values: VideoRenderMode.values,
        current: VideoRenderPreference.mode,
        labelOf: (v) => v.label,
        detailOf: (v) => v.detail,
        onPick: (v) => setState(() => VideoRenderPreference.setMode(v)),
      ),
      _benchRow<VideoSyncMode>(
        cs: cs,
        title: 'Synchro A/V',
        values: VideoSyncMode.values,
        current: VideoRenderPreference.sync,
        labelOf: (v) => v.label,
        detailOf: (v) => v.detail,
        onPick: (v) => setState(() => VideoRenderPreference.setSync(v)),
      ),
      // §video4kHdr — Le levier qui ne coûte aucun sous-titre, contrairement à
      // « Direct ». « Passthrough » se vérifie à l'œil : le témoin HDR du
      // téléviseur doit s'allumer.
      _benchRow<VideoHdrMode>(
        cs: cs,
        title: 'HDR',
        values: VideoHdrMode.values,
        current: VideoRenderPreference.hdr,
        labelOf: (v) => v.label,
        detailOf: (v) => v.detail,
        onPick: (v) => setState(() => VideoRenderPreference.setHdr(v)),
      ),
      // ⚠️ L'avertissement n'apparaît QUE hors configuration d'origine : un
      // relevé fait sur un banc oublié est un relevé faux, et c'est le genre
      // d'oubli qui coûte une session entière.
      if (overridden)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            '⚠️ Réglages de diagnostic actifs — la lecture ne se comporte plus '
            'comme par défaut. « Direct » supprime les sous-titres affichés par '
            'le lecteur.',
            style: TextStyle(fontSize: 11, color: kWarning),
          ),
        ),
      if (overridden)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: FocusableCard(
            scaleOnFocus: false,
            onTap: _resetBench,
            decorateOnly: true,
            child: FilledButton.tonalIcon(
              onPressed: _resetBench,
              icon: const Icon(Icons.settings_backup_restore, size: 18),
              label: const Text('Rétablir le rendu par défaut'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ),
        ),
    ];
  }

  void _resetBench() {
    setState(VideoRenderPreference.reset);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('🔬 Rendu vidéo rétabli — actif à la prochaine lecture'),
    ));
  }

  /// Rangée de choix exclusifs, calquée sur `_buildProfilesRow` (même grammaire
  /// visuelle et même focusabilité D-pad).
  Widget _benchRow<T extends Enum>({
    required ColorScheme cs,
    required String title,
    required List<T> values,
    required T current,
    required String Function(T) labelOf,
    required String Function(T) detailOf,
    required void Function(T) onPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Text(title,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
        SizedBox(
          height: 62,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final v = values[i];
              final active = v == current;
              return FocusableChip(
                onTap: () => onPick(v),
                borderRadius: BorderRadius.circular(10),
                child: GestureDetector(
                  onTap: () => onPick(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 132,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: kAccentSecondary.withAlpha(active ? 40 : 16),
                      border: Border.all(
                        color: active
                            ? kAccentSecondary
                            : kAccentSecondary.withAlpha(60),
                        width: active ? 2.0 : 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          labelOf(v),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                active ? FontWeight.bold : FontWeight.normal,
                            color: active ? kAccentSecondary : cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detailOf(v),
                          style:
                              TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

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
          return FocusableChip(
            onTap: () => _apply(preset.config),
            borderRadius: BorderRadius.circular(10),
            child: GestureDetector(
              onTap: () => _apply(preset.config),
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
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: enabled && value > min
                  ? () => onChanged((value - step).clamp(min, max))
                  : null,
              color: color,
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
              onPressed: enabled && value < max
                  ? () => onChanged((value + step).clamp(min, max))
                  : null,
              color: color,
              tooltip: 'Augmenter',
            ),
            SizedBox(
              width: suffix.isEmpty ? 26 : 52,
              child: Text(
                '$value$suffix',
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
