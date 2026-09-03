import 'package:flutter/material.dart';
import '../../core/themes/app_theme_config.dart';
import '../../core/themes/theme_service.dart';
import '../../core/utils/platform_tv.dart';
import '../../widgets/confirm_or_undo.dart';
import '../../widgets/tv/focusable_chip.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';
import '../../l10n/app_localizations.dart';

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> with TvInitialFocus {
  late AppThemeConfig _config;

  // Palette de couleurs disponibles pour la personnalisation
  static const _kPalette = [
    Color(0xFF00FF41), // Matrix green
    Color(0xFF00CED1), // Cyan
    Color(0xFF6A0DAD), // Violet
    Color(0xFFFF6B35), // Orange
    Color(0xFFFFD700), // Jaune
    Color(0xFF00C8FF), // Bleu Tron
    Color(0xFFC71585), // Magenta
    Color(0xFFE53935), // Rouge
    Color(0xFFFFFFFF), // Blanc
    Color(0xFF9E9E9E), // Gris
    Color(0xFFFF1493), // Rose
    Color(0xFF00BFA5), // Teal
    Color(0xFFFF9800), // Ambre
    Color(0xFF3F51B5), // Indigo
  ];

  @override
  void initState() {
    super.initState();
    _config = ThemeService.config.value;
  }

  /// Applique la config en live (ValueNotifier → rebuild MyApp) et la sauvegarde.
  void _apply(AppThemeConfig config) {
    setState(() => _config = config);
    ThemeService.save(config);
  }

  /// §undoReset + §undoTv — « Réinitialiser » reste réversible : un thème réglé
  /// couleur par couleur ne doit pas disparaître sur un tap malheureux.
  ///
  /// Au doigt : on applique, puis snackbar « Annuler » 5 s. À la télécommande :
  /// on DEMANDE avant, car l'action d'une snackbar n'est pas atteignable au
  /// D-pad (l'annulation y était décorative).
  ///
  /// ⚠️ Le snackbar survit à la page (il vit sur le `ScaffoldMessenger` racine) :
  /// si l'utilisateur a quitté avant d'annuler, on persiste sans `setState`.
  Future<void> _resetWithUndo() async {
    final AppThemeConfig old = _config;
    await confirmOrUndo(
      context,
      title: 'Réinitialiser le thème ?',
      question:
          'Toutes les couleurs et tous les effets reviennent aux valeurs par défaut.',
      confirmLabel: 'Réinitialiser',
      doneMessage: 'Réglages réinitialisés',
      action: () async => _apply(AppThemeConfig.defaults),
      onUndo: () {
        if (mounted) {
          _apply(old);
        } else {
          ThemeService.save(old);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.themeSettingsTitle),
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
          // Gradient piloté par la couleur principale courante → feedback live
          // quand l'utilisateur change la teinte via les color rows.
          gradient: isDark
              ? RadialGradient(
                  center: const Alignment(0, -1.5),
                  radius: 1.4,
                  colors: [
                    _config.primaryColor.withAlpha(20),
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
              _sectionLabel('Presets', cs),
              _buildPresetsRow(cs),
              _sectionLabel('Couleurs', cs),
              _buildColorRow('Principale',  _config.primaryColor,
                  (c) => _apply(_config.copyWith(primaryColor: c))),
              _buildColorRow('Accent',      _config.accentColor,
                  (c) => _apply(_config.copyWith(accentColor: c))),
              _buildColorRow('Tertiaire',   _config.tertiaryColor,
                  (c) => _apply(_config.copyWith(tertiaryColor: c))),
              // §themePlus — couleurs d'état (favori / reprise / erreur / succès)
              _sectionLabel('Couleurs d\'état', cs),
              _buildColorRow('Favori ❤',     _config.favoriteColor,
                  (c) => _apply(_config.copyWith(favoriteColor: c))),
              _buildColorRow('Reprise / Alerte', _config.warningColor,
                  (c) => _apply(_config.copyWith(warningColor: c))),
              _buildColorRow('Erreur',       _config.errorColor,
                  (c) => _apply(_config.copyWith(errorColor: c))),
              _buildColorRow('Succès',       _config.successColor,
                  (c) => _apply(_config.copyWith(successColor: c))),
              _sectionLabel('Effets', cs),
              _buildSlider(
                label:     'Glow',
                value:     _config.glowIntensity,
                min:       0.0,
                max:       1.0,
                step:      0.1,
                display:   _config.glowIntensity.toStringAsFixed(2),
                onChanged: (v) => _apply(_config.copyWith(glowIntensity: v)),
              ),
              _buildSlider(
                label:     'Arrondis',
                value:     _config.borderRadius,
                min:       0.0,
                max:       16.0,
                step:      1.0,
                display:   '${_config.borderRadius.toStringAsFixed(0)}px',
                onChanged: (v) => _apply(_config.copyWith(borderRadius: v)),
              ),
              _sectionLabel('Mode', cs),
              _buildThemeModeRow(cs),
              _sectionLabel('Aperçu', cs),
              _buildPreviewCard(),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers UI ──────────────────────────────────────────────────────────────

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

  // ── Presets ─────────────────────────────────────────────────────────────────

  Widget _buildPresetsRow(ColorScheme cs) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: AppThemeConfig.presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final preset = AppThemeConfig.presets[i];
          final active = _isPresetActive(preset.config);
          // §3c Phase 1 — FocusableChip : preset sélectionnable au D-pad.
          return FocusableChip(
            onTap: () => _apply(preset.config),
            borderRadius: BorderRadius.circular(10),
            child: GestureDetector(
            onTap: () => _apply(preset.config),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: preset.config.primaryColor.withAlpha(active ? 40 : 16),
                border: Border.all(
                  color: active
                      ? preset.config.primaryColor
                      : preset.config.primaryColor.withAlpha(60),
                  width: active ? 2.0 : 1.0,
                ),
                boxShadow: active
                    ? [BoxShadow(color: preset.config.primaryColor.withAlpha(80), blurRadius: 8)]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _dot(preset.config.primaryColor),
                      const SizedBox(width: 3),
                      _dot(preset.config.accentColor),
                      const SizedBox(width: 3),
                      _dot(preset.config.tertiaryColor),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    preset.name,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      color: active ? preset.config.primaryColor : cs.onSurface,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (active)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 16,
                      height: 2,
                      decoration: BoxDecoration(
                        color: preset.config.primaryColor,
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

  bool _isPresetActive(AppThemeConfig p) =>
      _config.primaryColor  == p.primaryColor  &&
      _config.accentColor   == p.accentColor   &&
      _config.tertiaryColor == p.tertiaryColor &&
      // §themePlus — les couleurs d'état font partie de l'identité du preset.
      _config.favoriteColor == p.favoriteColor &&
      _config.warningColor  == p.warningColor  &&
      _config.errorColor    == p.errorColor    &&
      _config.successColor  == p.successColor;

  Widget _dot(Color c) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: c,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white30, width: 0.5),
    ),
  );

  // ── Sélecteur de couleur ─────────────────────────────────────────────────────

  Widget _buildColorRow(String label, Color current, ValueChanged<Color> onSelect) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          // Couleur courante (peut ne pas être dans la palette)
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: current,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [BoxShadow(color: current.withAlpha(120), blurRadius: 6)],
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _kPalette.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final c = _kPalette[i];
                  final selected = current == c;
                  // §3c Phase 1 — FocusableChip : couleur sélectionnable au D-pad.
                  return FocusableChip(
                    onTap: () => onSelect(c),
                    borderRadius: BorderRadius.circular(13),
                    child: GestureDetector(
                    onTap: () => onSelect(c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? Colors.white : Colors.white24,
                          width: selected ? 2.5 : 1.0,
                        ),
                        boxShadow: selected
                            ? [BoxShadow(color: c.withAlpha(130), blurRadius: 6)]
                            : null,
                      ),
                      child: selected
                          ? Icon(Icons.check, size: 13,
                              color: _contrastColor(c))
                          : null,
                    ),
                  ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Renvoie noir ou blanc selon la luminosité de la couleur (lisibilité du check).
  Color _contrastColor(Color c) {
    final luminance = c.computeLuminance();
    return luminance > 0.4 ? Colors.black : Colors.white;
  }

  // ── Sliders ──────────────────────────────────────────────────────────────────

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    // §3c-bis #5 — Sur TV, le `Slider` est inutilisable au D-pad : les flèches
    // ← → bouffées par le thumb et la valeur saute par grands intervalles. On
    // remplace par 2 IconButton focusables (− / +) avec un step fixe.
    final isTv = PlatformTv.isTv;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          if (isTv)
            Expanded(
              child: _TvStepperRow(
                value: value,
                min: min,
                max: max,
                step: step,
                color: _config.primaryColor,
                onChanged: onChanged,
              ),
            )
          else
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor:   _config.primaryColor,
                  thumbColor:         _config.primaryColor,
                  inactiveTrackColor: _config.primaryColor.withAlpha(40),
                  overlayColor:       _config.primaryColor.withAlpha(30),
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(value: value, min: min, max: max, onChanged: onChanged),
              ),
            ),
          SizedBox(
            width: 38,
            child: Text(
              display,
              style: TextStyle(fontSize: 12, color: _config.primaryColor, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // ── Mode sombre/clair/système ────────────────────────────────────────────────

  Widget _buildThemeModeRow(ColorScheme cs) {
    const modes = [
      (ThemeMode.dark,   'Sombre',  Icons.dark_mode_outlined),
      (ThemeMode.light,  'Clair',   Icons.light_mode_outlined),
      (ThemeMode.system, 'Système', Icons.brightness_auto),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: modes.map((m) {
          final active = _config.themeMode == m.$1;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              // §3c Phase 1 — FocusableChip : mode clair/sombre/système au D-pad.
              child: FocusableChip(
                onTap: () => _apply(_config.copyWith(themeMode: m.$1)),
                borderRadius: BorderRadius.circular(8),
                child: GestureDetector(
                onTap: () => _apply(_config.copyWith(themeMode: m.$1)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: active
                        ? _config.primaryColor.withAlpha(30)
                        : cs.surfaceContainerHighest,
                    border: Border.all(
                      color: active ? _config.primaryColor : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(m.$3, size: 20,
                          color: active ? _config.primaryColor : cs.onSurfaceVariant),
                      const SizedBox(height: 4),
                      Text(
                        m.$2,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: active ? FontWeight.bold : FontWeight.normal,
                          color: active ? _config.primaryColor : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Aperçu live ──────────────────────────────────────────────────────────────

  Widget _buildPreviewCard() {
    final p  = _config.primaryColor;
    final a  = _config.accentColor;
    final t  = _config.tertiaryColor;
    final r  = _config.borderRadius;
    final gl = _config.glowIntensity;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          color: const Color(0xFF0D0D0D),
          border: Border.all(color: a.withAlpha((255 * 0.5).round()), width: 1),
          boxShadow: gl > 0
              ? [BoxShadow(color: p.withAlpha((255 * 0.25 * gl).round()), blurRadius: 18)]
              : null,
        ),
        child: Column(
          children: [
            // Poster + titre
            Container(
              height: 90,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(r)),
                gradient: LinearGradient(
                  colors: [p.withAlpha(70), Colors.transparent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Poster placeholder
                    Container(
                      width: 52,
                      height: 66,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(r * 0.5),
                        color: p.withAlpha(35),
                        border: Border.all(color: p.withAlpha(80), width: 1),
                      ),
                      child: Icon(Icons.movie_outlined, color: p, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Titre du Film',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              shadows: gl > 0
                                  ? [Shadow(color: p.withAlpha((255 * 0.5 * gl).round()), blurRadius: 8)]
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _chip('4K',    p),
                              const SizedBox(width: 4),
                              _chip('MULTI', a),
                              const SizedBox(width: 4),
                              _chip('Action', t),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Boutons d'action
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 34,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(r * 0.6),
                        gradient: LinearGradient(colors: [p, a]),
                        boxShadow: gl > 0
                            ? [BoxShadow(color: p.withAlpha((255 * 0.4 * gl).round()), blurRadius: 6)]
                            : null,
                      ),
                      child: const Center(
                        child: Text('▶  Lire',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _actionBtn(Icons.download_outlined, a, r, gl),
                  const SizedBox(width: 8),
                  _actionBtn(Icons.favorite_border,   t, r, gl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      color: color.withAlpha(30),
      border: Border.all(color: color.withAlpha(100), width: 0.5),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
    ),
  );

  Widget _actionBtn(IconData icon, Color color, double r, double gl) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color.withAlpha(150), width: 1),
      boxShadow: gl > 0
          ? [BoxShadow(color: color.withAlpha((255 * 0.2 * gl).round()), blurRadius: 4)]
          : null,
    ),
    child: Icon(icon, color: color, size: 17),
  );
}

/// §3c-bis #5 — Stepper TV-friendly (focusable au D-pad) qui remplace le
/// `Slider` quand `PlatformTv.isTv`. 2 IconButton − / + (focusables nativement)
/// + barre de progression visuelle au milieu.
class _TvStepperRow extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final double step;
  final Color color;
  final ValueChanged<double> onChanged;

  const _TvStepperRow({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.color,
    required this.onChanged,
  });

  void _decrement() {
    final next = (value - step).clamp(min, max);
    if (next != value) onChanged(next);
  }

  void _increment() {
    final next = (value + step).clamp(min, max);
    if (next != value) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final ratio = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? _decrement : null,
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
          onPressed: value < max ? _increment : null,
          color: color,
          tooltip: 'Augmenter',
        ),
      ],
    );
  }
}
