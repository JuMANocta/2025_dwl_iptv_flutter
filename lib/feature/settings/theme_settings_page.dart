import 'package:flutter/material.dart';
import '../../core/themes/aether_theme_extension.dart';
import '../../core/themes/app_theme_config.dart';
import '../../core/themes/light_palette.dart';
import '../../core/themes/saved_themes_service.dart';
import '../../core/themes/theme_service.dart';
import '../../core/themes/themes.dart';
import '../../core/utils/app_snackbar.dart';
import '../../core/utils/platform_tv.dart';
import '../../widgets/color_wheel.dart';
import '../../widgets/confirm_or_undo.dart';
import '../../widgets/tv/focusable_chip.dart';
import '../../widgets/tv/tv_adaptive_modal.dart';
import '../../widgets/tv/tv_stepper_row.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_ext.dart';

/// §themeStudio — Les sept couleurs personnalisables, nommées UNE fois.
///
/// Elles étaient écrites trois fois dans cette page (une ligne d'édition, un
/// bout d'aperçu, rien du tout pour quatre d'entre elles) : la liste est
/// désormais la source, et l'écran s'en déduit.
enum ThemeColorSlot {
  primary,
  accent,
  tertiary,
  favorite,
  warning,
  error,
  success,
}

extension ThemeColorSlotX on ThemeColorSlot {
  /// La couleur que ce rôle porte dans [c].
  Color read(AppThemeConfig c) => switch (this) {
        ThemeColorSlot.primary => c.primaryColor,
        ThemeColorSlot.accent => c.accentColor,
        ThemeColorSlot.tertiary => c.tertiaryColor,
        ThemeColorSlot.favorite => c.favoriteColor,
        ThemeColorSlot.warning => c.warningColor,
        ThemeColorSlot.error => c.errorColor,
        ThemeColorSlot.success => c.successColor,
      };

  /// [c] avec ce rôle repeint en [v].
  AppThemeConfig write(AppThemeConfig c, Color v) => switch (this) {
        ThemeColorSlot.primary => c.copyWith(primaryColor: v),
        ThemeColorSlot.accent => c.copyWith(accentColor: v),
        ThemeColorSlot.tertiary => c.copyWith(tertiaryColor: v),
        ThemeColorSlot.favorite => c.copyWith(favoriteColor: v),
        ThemeColorSlot.warning => c.copyWith(warningColor: v),
        ThemeColorSlot.error => c.copyWith(errorColor: v),
        ThemeColorSlot.success => c.copyWith(successColor: v),
      };

  String label(AppLocalizations l) => switch (this) {
        ThemeColorSlot.primary => l.themeColorPrimary,
        ThemeColorSlot.accent => l.themeColorAccent,
        ThemeColorSlot.tertiary => l.themeColorTertiary,
        ThemeColorSlot.favorite => l.themeColorFavorite,
        ThemeColorSlot.warning => l.themeColorWarning,
        ThemeColorSlot.error => l.themeColorError,
        ThemeColorSlot.success => l.themeColorSuccess,
      };
}

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage>
    with TvInitialFocus {
  late AppThemeConfig _config;

  /// §themeStudio — La couleur en cours d'édition, ou `null` si la grille est
  /// fermée. UNE seule à la fois : sept grilles ouvertes feraient une page de
  /// pastilles où l'on ne trouve plus les réglages.
  ThemeColorSlot? _openSlot;

  /// Valeurs PROPOSÉES, pas des couleurs d'interface : cette liste reste donc
  /// une liste de littéraux, et c'est la seule de ce fichier (§lightTheme —
  /// zéro couleur en dur ailleurs).
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
    // Idempotent : le service ne relit les préférences qu'une fois.
    SavedThemesService.load();
  }

  /// Applique la config en live (ValueNotifier → rebuild MyApp) et la sauvegarde.
  void _apply(AppThemeConfig config) {
    setState(() => _config = config);
    ThemeService.save(config);
  }

  // ── Réinitialisation ───────────────────────────────────────────────────────

  /// §undoReset + §undoTv — « Réinitialiser » reste réversible : un thème réglé
  /// couleur par couleur ne doit pas disparaître sur un tap malheureux.
  ///
  /// Au doigt : on applique, puis snackbar « Annuler » 5 s. À la télécommande :
  /// on DEMANDE avant, car l'action d'une snackbar n'est pas atteignable au
  /// D-pad (l'annulation y était décorative).
  ///
  /// §themeStudio (2026-09-16) — ⚠️ Et AVANT tout ça, on propose de GARDER :
  /// les cinq secondes d'annulation passées, un thème composé à la main était
  /// perdu sans recours. On ne le propose que quand il y a vraiment quelque
  /// chose à perdre — ni un préréglage, ni un thème déjà enregistré.
  ///
  /// ⚠️ Le snackbar survit à la page (il vit sur le `ScaffoldMessenger` racine) :
  /// si l'utilisateur a quitté avant d'annuler, on persiste sans `setState`.
  Future<void> _resetWithUndo() async {
    if (SavedThemesService.isUnsaved(_config, SavedThemesService.themes.value)) {
      final bool? keep = await showAppDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.themeKeepBeforeResetTitle),
          content: Text(ctx.l10n.themeKeepBeforeResetBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(L10n.current.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.l10n.themeKeepBeforeResetSkip),
            ),
            TextButton(
              // §safeFocus — le focus s'ouvre sur ce qui ne perd rien.
              autofocus: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.l10n.themeKeepBeforeResetSave),
            ),
          ],
        ),
      );
      if (keep == null || !mounted) return; // annulé : on ne réinitialise pas
      if (keep) {
        final bool saved = await _promptSaveAs();
        // ⚠️ Un enregistrement raté (nom vide, liste pleine) ne doit PAS
        // enchaîner sur la réinitialisation : ce serait exactement la perte
        // que la question venait d'éviter.
        if (!saved || !mounted) return;
      }
    }
    final AppThemeConfig old = _config;
    await confirmOrUndo(
      context,
      title: context.l10n.themeResetTitle,
      question: context.l10n.themeResetQuestion,
      confirmLabel: context.l10n.perfResetConfirm,
      doneMessage: context.l10n.perfResetDone,
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

  // ── Mes thèmes ─────────────────────────────────────────────────────────────

  /// Demande un nom et enregistre le thème courant. Rend `true` si c'est fait.
  Future<bool> _promptSaveAs() async {
    final String? name = await _askName(
      title: context.l10n.themeSaveAsTitle,
      initial: _suggestedName(),
    );
    if (name == null || !mounted) return false;
    final int max = SavedThemesService.kMaxThemes;
    final bool ok = await SavedThemesService.saveAs(name, _config);
    if (!mounted) return ok;
    AppSnackBar.show(
      context,
      ok
          ? context.l10n.themeSavedDone(SavedThemesService.sanitizeName(name))
          : context.l10n.themeSaveFull(max),
    );
    return ok;
  }

  /// « Mon thème 2 » : le premier numéro libre. Un nom déjà pris remplacerait
  /// silencieusement l'enregistrement précédent.
  String _suggestedName() {
    final taken = SavedThemesService.themes.value.map((t) => t.name).toSet();
    for (int i = 1; i <= SavedThemesService.kMaxThemes + 1; i++) {
      final String n = L10n.current.themeDefaultName(i);
      if (!taken.contains(n)) return n;
    }
    return L10n.current.themeDefaultName(1);
  }

  /// ⚠️ Recette AVD du 2026-09-17 — écran ROUGE (`_dependents.isEmpty`) : le
  /// contrôleur était détruit dans un `finally`, donc dès le `pop`, alors que
  /// l'animation de sortie du dialogue dessine encore le champ — et la
  /// réinitialisation qui suit reconstruit tout le thème par-dessus. Le
  /// contrôleur appartient désormais au dialogue ([_ThemeNameDialog]), qui le
  /// libère quand IL disparaît.
  Future<String?> _askName(
          {required String title, required String initial}) =>
      showAppDialog<String>(
        context: context,
        builder: (_) => _ThemeNameDialog(title: title, initial: initial),
      );


  Future<void> _renameSaved(int index, SavedTheme theme) async {
    final String? name =
        await _askName(title: context.l10n.themeRenameTitle, initial: theme.name);
    if (name == null || !mounted) return;
    final bool ok = await SavedThemesService.rename(index, name);
    if (!mounted || ok) return;
    AppSnackBar.show(context, context.l10n.themeNameTaken);
  }

  /// ⚠️ L'instantané est pris AVANT l'appel, jamais dedans : c'est la
  /// condition pour que « Annuler » puisse vraiment remettre le thème à SA
  /// place dans la liste (§undoTv).
  Future<void> _deleteSaved(int index, SavedTheme theme) async {
    await confirmOrUndo(
      context,
      title: context.l10n.themeDeleteTitle(theme.name),
      question: context.l10n.themeDeleteQuestion,
      confirmLabel: context.l10n.commonDelete,
      doneMessage: context.l10n.themeDeleteDone,
      action: () => SavedThemesService.remove(index),
      onUndo: () => SavedThemesService.insert(index, theme),
    );
  }

  // ── Couleurs ───────────────────────────────────────────────────────────────

  void _toggleSlot(ThemeColorSlot slot) =>
      setState(() => _openSlot = _openSlot == slot ? null : slot);

  Future<void> _pickFreeColor(ThemeColorSlot slot) async {
    final Color? picked = await showColorWheelSheet(
      context,
      initial: slot.read(_config),
      title: context.l10n.themeColorFreeTitle,
    );
    if (picked == null || !mounted) return;
    _apply(slot.write(_config, picked));
  }

  // ── Écran ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      // ⚠️ Retour FERME la grille ouverte avant de quitter la page : sur
      // téléviseur, une grille sans sortie est un piège (§tvOptionsBack).
      canPop: _openSlot == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) setState(() => _openSlot = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.themeSettingsTitle),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // §themeStudio — L'aperçu est ÉPINGLÉ. Dernier enfant d'une page
              // défilante, il était hors écran dès qu'on touchait à la première
              // couleur : on réglait à l'aveugle ce qu'il était censé montrer.
              _buildPreviewCard(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel(context.l10n.themeSectionPresets, cs),
                      _buildPresetsRow(cs),
                      _sectionLabel(context.l10n.themeSectionMyThemes, cs),
                      _buildSavedThemes(cs),
                      _sectionLabel(context.l10n.themeSectionColors, cs),
                      for (final slot in const [
                        ThemeColorSlot.primary,
                        ThemeColorSlot.accent,
                        ThemeColorSlot.tertiary,
                      ])
                        ..._buildColorRow(slot, cs),
                      // §themePlus — couleurs d'état (favori/reprise/erreur/succès)
                      _sectionLabel(context.l10n.themeSectionStateColors, cs),
                      for (final slot in const [
                        ThemeColorSlot.favorite,
                        ThemeColorSlot.warning,
                        ThemeColorSlot.error,
                        ThemeColorSlot.success,
                      ])
                        ..._buildColorRow(slot, cs),
                      _sectionLabel(context.l10n.themeSectionEffects, cs),
                      _buildSlider(
                        label: context.l10n.themeGlow,
                        value: _config.glowIntensity,
                        min: 0.0,
                        max: 1.0,
                        step: 0.1,
                        display: _config.glowIntensity.toStringAsFixed(2),
                        onChanged: (v) =>
                            _apply(_config.copyWith(glowIntensity: v)),
                      ),
                      _buildSlider(
                        label: context.l10n.themeRadius,
                        value: _config.borderRadius,
                        min: 0.0,
                        max: 16.0,
                        step: 1.0,
                        display:
                            '${_config.borderRadius.toStringAsFixed(0)}px',
                        onChanged: (v) =>
                            _apply(_config.copyWith(borderRadius: v)),
                      ),
                      _sectionLabel(context.l10n.themeSectionMode, cs),
                      _buildThemeModeRow(cs),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
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

  /// Recette AVD TV du 2026-09-17 — la primaire BRUTE servait de TEXTE (valeurs
  /// des curseurs, libellé du mode choisi) : jaune vif sur blanc, illisible en
  /// thème clair. Même dérivation que le reste de l'app (§lightTheme).
  Color _primaryInk(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? readableOn(_config.primaryColor)
          : _config.primaryColor;

  Widget _buildPresetsRow(ColorScheme cs) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: AppThemeConfig.presets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final preset = AppThemeConfig.presets[i];
          final active = _config.sameLook(preset.config);
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
                      ? [
                          BoxShadow(
                              color:
                                  preset.config.primaryColor.withAlpha(80),
                              blurRadius: 8)
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _dot(preset.config.primaryColor, cs),
                        const SizedBox(width: 3),
                        _dot(preset.config.accentColor, cs),
                        const SizedBox(width: 3),
                        _dot(preset.config.tertiaryColor, cs),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      // Revue 2026-09-11, lot 7 (recette en anglais) — trois
                      // noms de préréglages sont des mots FRANÇAIS ; ils ne
                      // servent qu'à l'affichage (aucune persistance par nom).
                      switch (preset.name) {
                        'Phosphore' => context.l10n.themePresetPhosphore,
                        'Nordique' => context.l10n.themePresetNordique,
                        'Minimaliste' => context.l10n.themePresetMinimaliste,
                        _ => preset.name,
                      },
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            active ? FontWeight.bold : FontWeight.normal,
                        color:
                            active ? preset.config.primaryColor : cs.onSurface,
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

  Widget _dot(Color c, ColorScheme cs) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: cs.outlineVariant, width: 0.5),
        ),
      );

  // ── Mes thèmes ──────────────────────────────────────────────────────────────

  Widget _buildSavedThemes(ColorScheme cs) {
    return ValueListenableBuilder<List<SavedTheme>>(
      valueListenable: SavedThemesService.themes,
      builder: (context, list, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: FocusableChip(
              onTap: _promptSaveAs,
              borderRadius: BorderRadius.circular(10),
              // ⛔ §dpadChildFocus — `OutlinedButton` porte SON propre nœud de
              // focus : imbriqué, il créerait un second arrêt D-pad sans halo
              // (et le premier ne serait candidat nulle part). `ExcludeFocus`
              // le retire de la traversée ; le tap tactile n'est pas touché.
              child: ExcludeFocus(
                child: OutlinedButton.icon(
                  onPressed: _promptSaveAs,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: Text(context.l10n.themeSaveAs),
                ),
              ),
            ),
          ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                context.l10n.themeMyThemesEmpty,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            )
          else
            for (int i = 0; i < list.length; i++) _savedRow(i, list[i], cs),
        ],
      ),
    );
  }

  Widget _savedRow(int index, SavedTheme theme, ColorScheme cs) {
    final bool active = _config.sameLook(theme.config);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Row(
        children: [
          // ⛔ §dpadChildFocus — Renommer et Supprimer sont des FRÈRES de la
          // carte, jamais ses enfants : un focusable DANS un focusable n'est
          // candidat nulle part à la traversée.
          Expanded(
            child: FocusableChip(
              onTap: () {
                _apply(theme.config);
                AppSnackBar.show(
                    context, context.l10n.themeAppliedDone(theme.name));
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: cs.surfaceContainerHighest,
                  border: Border.all(
                    color: active
                        ? theme.config.primaryColor
                        : cs.outlineVariant,
                    width: active ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    _dot(theme.config.primaryColor, cs),
                    const SizedBox(width: 4),
                    _dot(theme.config.accentColor, cs),
                    const SizedBox(width: 4),
                    _dot(theme.config.tertiaryColor, cs),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        theme.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              active ? FontWeight.bold : FontWeight.normal,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      context.l10n.themeSavedApply,
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: context.l10n.themeRename,
            onPressed: () => _renameSaved(index, theme),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: context.l10n.commonDelete,
            onPressed: () => _deleteSaved(index, theme),
          ),
        ],
      ),
    );
  }

  // ── Sélecteur de couleur ─────────────────────────────────────────────────────

  /// §themeStudio — Une ligne par rôle, et SOUS elle, quand on l'ouvre, une
  /// grille de pastilles pleine largeur.
  ///
  /// **Le défaut corrigé** : les 14 pastilles vivaient dans une bande de 26 px
  /// coincée à droite du libellé — sur téléphone il en restait cinq visibles,
  /// et rien n'annonçait qu'on pouvait faire défiler. La couleur se choisissait
  /// donc dans un couloir.
  List<Widget> _buildColorRow(ThemeColorSlot slot, ColorScheme cs) {
    final bool open = _openSlot == slot;
    final Color current = slot.read(_config);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        child: FocusableChip(
          onTap: () => _toggleSlot(slot),
          borderRadius: BorderRadius.circular(10),
          // ⛔ §dpadChildFocus — un `GestureDetector`, pas un `InkWell` : ce
          // dernier est focusable, et doublerait le nœud du `FocusableChip`.
          child: GestureDetector(
            onTap: () => _toggleSlot(slot),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(slot.label(context.l10n),
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: current,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.outlineVariant, width: 2),
                      boxShadow: [
                        BoxShadow(color: current.withAlpha(120), blurRadius: 6)
                      ],
                    ),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more,
                      color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
      if (open)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in _kPalette) _swatch(slot, c, current == c, cs),
              // §themeStudio — La sortie vers une couleur QUELCONQUE, au même
              // endroit que les valeurs proposées : sans elle, une couleur hors
              // palette restait inatteignable.
              FocusableChip(
                onTap: () => _pickFreeColor(slot),
                borderRadius: BorderRadius.circular(_config.borderRadius),
                child: GestureDetector(
                  onTap: () => _pickFreeColor(slot),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_config.borderRadius),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.colorize, size: 16, color: cs.onSurface),
                        const SizedBox(width: 6),
                        Text(context.l10n.themeColorFree,
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _swatch(ThemeColorSlot slot, Color c, bool selected, ColorScheme cs) {
    return FocusableChip(
      onTap: () => _apply(slot.write(_config, c)),
      borderRadius: BorderRadius.circular(17),
      child: GestureDetector(
        onTap: () => _apply(slot.write(_config, c)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? cs.onSurface : cs.outlineVariant,
              width: selected ? 2.5 : 1.0,
            ),
            boxShadow: selected
                ? [BoxShadow(color: c.withAlpha(130), blurRadius: 6)]
                : null,
          ),
          child: selected
              ? Icon(Icons.check, size: 16, color: onColorFor(c))
              : null,
        ),
      ),
    );
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
              child: TvStepperRow(
                value: value,
                min: min,
                max: max,
                step: step,
                color: _primaryInk(context),
                onChanged: onChanged,
              ),
            )
          else
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _config.primaryColor,
                  thumbColor: _config.primaryColor,
                  inactiveTrackColor: _config.primaryColor.withAlpha(40),
                  overlayColor: _config.primaryColor.withAlpha(30),
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child:
                    Slider(value: value, min: min, max: max, onChanged: onChanged),
              ),
            ),
          SizedBox(
            width: 38,
            child: Text(
              display,
              style: TextStyle(
                  fontSize: 12,
                  color: _primaryInk(context),
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // ── Mode sombre/clair/système ────────────────────────────────────────────────

  Widget _buildThemeModeRow(ColorScheme cs) {
    final modes = [
      (ThemeMode.dark, context.l10n.themeModeDark, Icons.dark_mode_outlined),
      (ThemeMode.light, context.l10n.themeModeLight, Icons.light_mode_outlined),
      (ThemeMode.system, context.l10n.themeModeSystem, Icons.brightness_auto),
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
                        color:
                            active ? _config.primaryColor : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(m.$3,
                            size: 20,
                            color: active
                                ? _primaryInk(context)
                                : cs.onSurfaceVariant),
                        const SizedBox(height: 4),
                        Text(
                          m.$2,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                active ? FontWeight.bold : FontWeight.normal,
                            color: active
                                ? _primaryInk(context)
                                : cs.onSurfaceVariant,
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

  /// §themeStudio — L'aperçu peint ce que l'app peindra. **Rien d'autre.**
  ///
  /// **Les quatre mensonges corrigés (constatés le 2026-09-16)** :
  ///   1. la carte était NOIRE en dur (`Color(0xFF0D0D0D)`, titre blanc, bouton
  ///      au texte noir) — en mode clair, elle montrait un écran que l'app
  ///      n'affiche jamais ;
  ///   2. elle montrait les couleurs BRUTES, alors que le thème clair les
  ///      dérive par contraste (§lightTheme) : un vert Matrix éclatant ici, un
  ///      vert sombre à l'écran ;
  ///   3. quatre des sept couleurs (favori, alerte, erreur, succès) n'y avaient
  ///      AUCUN élément : les modifier « ne faisait rien » ;
  ///   4. il était le dernier enfant d'une page défilante (corrigé plus haut :
  ///      il est épinglé).
  ///
  /// ⛔ Ne pas recopier ici la dérivation de `themes.dart` : on construit le
  /// VRAI `ThemeData` du thème en cours d'édition et on lit ses couleurs. Une
  /// copie divergerait au premier changement, et c'est précisément le défaut
  /// qu'on vient de corriger.
  Widget _buildPreviewCard() {
    final Brightness b = ThemeService.brightnessFor(
        _config.themeMode, MediaQuery.platformBrightnessOf(context));
    final ThemeData data =
        b == Brightness.light ? lightTheme(_config) : darkTheme(_config);
    final AetherThemeExtension ext =
        data.extension<AetherThemeExtension>()!;
    final double r = _config.borderRadius;
    final double gl = _config.glowIntensity;
    final Color onCard = data.textTheme.bodyLarge?.color ??
        data.colorScheme.onSurface;

    return Theme(
      data: data,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
            // Le FOND de l'app dans le mode en cours, pas un noir décidé ici.
            color: data.scaffoldBackgroundColor,
            border: Border.all(color: ext.accentColor.withAlpha(128), width: 1),
            boxShadow: gl > 0
                ? [
                    BoxShadow(
                        color: ext.primaryColor
                            .withAlpha((255 * 0.25 * gl).round()),
                        blurRadius: 18)
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(r)),
                  gradient: LinearGradient(
                    colors: [
                      ext.primaryColor.withAlpha(70),
                      data.cardColor.withAlpha(0),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(r * 0.5),
                          color: ext.primaryColor.withAlpha(35),
                          border: Border.all(
                              color: ext.primaryColor.withAlpha(80), width: 1),
                        ),
                        child: Icon(Icons.movie_outlined,
                            color: ext.primaryColor, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              context.l10n.themePreviewTitle,
                              style: TextStyle(
                                color: onCard,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                shadows: gl > 0
                                    ? [
                                        Shadow(
                                            color: ext.primaryColor.withAlpha(
                                                (255 * 0.5 * gl).round()),
                                            blurRadius: 8)
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                _chip('4K', ext.primaryColor),
                                const SizedBox(width: 4),
                                _chip('MULTI', ext.accentColor),
                                const SizedBox(width: 4),
                                _chip('Action', ext.tertiaryColor),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Les QUATRE couleurs d'état, enfin visibles.
                            Wrap(
                              spacing: 10,
                              runSpacing: 4,
                              children: [
                                _stateBit(Icons.favorite, ext.favoriteColor,
                                    context.l10n.themePreviewFavorite),
                                _stateBit(Icons.play_circle_outline,
                                    ext.warningColor,
                                    context.l10n.themePreviewAlert),
                                _stateBit(Icons.error_outline, ext.errorColor,
                                    context.l10n.themePreviewError),
                                _stateBit(Icons.check_circle_outline,
                                    ext.successColor,
                                    context.l10n.themePreviewSuccess),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(r * 0.6),
                          gradient: LinearGradient(colors: [
                            ext.primaryColor,
                            ext.accentColor,
                          ]),
                          boxShadow: gl > 0
                              ? [
                                  BoxShadow(
                                      color: ext.primaryColor.withAlpha(
                                          (255 * 0.4 * gl).round()),
                                      blurRadius: 6)
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            context.l10n.themePreviewPlay,
                            // §lightTheme — le texte suit le fond du bouton, il
                            // n'est pas noir par principe.
                            style: TextStyle(
                                color: onColorFor(ext.primaryColor),
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _actionBtn(Icons.download_outlined, ext.accentColor, gl),
                    const SizedBox(width: 8),
                    _actionBtn(Icons.favorite_border, ext.tertiaryColor, gl),
                  ],
                ),
              ),
            ],
          ),
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
          style:
              TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
        ),
      );

  Widget _stateBit(IconData icon, Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 9, fontWeight: FontWeight.w600)),
        ],
      );

  Widget _actionBtn(IconData icon, Color color, double gl) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withAlpha(150), width: 1),
          boxShadow: gl > 0
              ? [
                  BoxShadow(
                      color: color.withAlpha((255 * 0.2 * gl).round()),
                      blurRadius: 4)
                ]
              : null,
        ),
        child: Icon(icon, color: color, size: 16),
      );
}

/// Dialogue « nom du thème » : possède son contrôleur (cf. `_askName`).
class _ThemeNameDialog extends StatefulWidget {
  final String title;
  final String initial;
  const _ThemeNameDialog({required this.title, required this.initial});

  @override
  State<_ThemeNameDialog> createState() => _ThemeNameDialogState();
}

class _ThemeNameDialogState extends State<_ThemeNameDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: !PlatformTv.isTv,
        maxLength: SavedThemesService.kMaxNameLength,
        decoration: InputDecoration(
          labelText: context.l10n.themeNameHint,
          counterText: '',
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(context.l10n.commonOk),
        ),
      ],
    );
  }
}
