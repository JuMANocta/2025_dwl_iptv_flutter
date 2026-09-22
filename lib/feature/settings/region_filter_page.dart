import 'package:flutter/material.dart';

import '../../core/themes/colors.dart';
import '../../core/themes/light_palette.dart';
import '../../core/utils/user_error.dart';
import '../../data/models/m3u_entry.dart';
import '../../data/services/hidden_regions_service.dart';
import '../../data/services/parsed_playlist_service.dart';
import '../../data/services/playlist_service.dart';
import '../../data/services/stream_account_service.dart';
import '../../data/services/track_preferences_service.dart';
import '../../widgets/confirm_or_undo.dart';
import 'track_memory_summary.dart';
import '../search/m3u_filter.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_ext.dart';
import '../search/category_labels.dart';

/// §langFilter — Réglage des langues/régions à MASQUER du catalogue.
///
/// §settingsTidy (2026-09-21) — La page porte aussi, EN TÊTE, la mémoire des
/// pistes (R43) : l'ancienne tuile « Langues des pistes » des Paramètres vit
/// ici, à côté des autres réglages de langue (demande de l'utilisateur).
///
/// Les entrées dont le préfixe `|XX|` correspond à une région cochée sont
/// **filtrées au parsing** (jamais stockées) → RAM + cache réduits. À
/// l'application, le compte actif est re-parsé immédiatement (catalogue brut
/// conservé → pas de re-téléchargement) et les comptes secondaires invalidés.
class RegionFilterPage extends StatefulWidget {
  const RegionFilterPage({super.key});

  @override
  State<RegionFilterPage> createState() => _RegionFilterPageState();
}

class _RegionFilterPageState extends State<RegionFilterPage>
    with TvInitialFocus {
  late Set<String> _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selected = {...HiddenRegionsService.hidden};
  }

  bool get _dirty =>
      _selected.length != HiddenRegionsService.hidden.length ||
      !_selected.containsAll(HiddenRegionsService.hidden);

  /// R43 — « Revenir à l'automatique » pour les pistes (venu des Paramètres).
  ///
  /// Au doigt : on agit, puis « Annuler » 5 s ; à la télécommande : on demande
  /// avant (§undoTv). L'instantané est pris AVANT l'appel, jamais dedans. Le
  /// bouton n'existe que s'il y a une mémoire : pas de cas « rien à oublier ».
  Future<void> _resetTrackMemory() async {
    final String? oldAudio = TrackPreferencesService.audio;
    final String? oldSub = TrackPreferencesService.subtitle;
    await confirmOrUndo(
      context,
      title: context.l10n.settingsTracksResetTitle,
      question: context.l10n.settingsTracksResetQuestion,
      confirmLabel: context.l10n.settingsTracksResetConfirm,
      doneMessage: context.l10n.settingsTracksResetDone,
      // Rien n'est perdu qu'on ne puisse rechoisir au prochain titre : pas la
      // couleur du danger.
      destructive: false,
      action: TrackPreferencesService.resetToAuto,
      onUndo: () async {
        await TrackPreferencesService.setAudio(oldAudio);
        await TrackPreferencesService.setSubtitle(oldSub);
      },
    );
  }

  /// Titre de section de la page (pistes, puis contenu à masquer).
  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: kAccentPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      );

  /// R43 — Ce que l'app retient pour le PROCHAIN titre, et le geste pour
  /// l'oublier. Suit le service par son notifieur (`version`).
  Widget _buildTracksCard(ColorScheme cs) {
    return ValueListenableBuilder<int>(
      valueListenable: TrackPreferencesService.version,
      builder: (ctx, _, _) {
        final bool memory = TrackPreferencesService.hasMemory;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.subtitles_outlined,
                      color: memory ? kAccentSecondary : cs.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      trackMemorySummary(ctx.l10n),
                      style: TextStyle(
                          color: cs.onSurface, fontSize: 14, height: 1.35),
                    ),
                  ),
                ],
              ),
              if (memory) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _resetTrackMemory,
                    icon: const Icon(Icons.restart_alt),
                    label: Text(ctx.l10n.settingsTracksResetConfirm),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _apply() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final changed = await HiddenRegionsService.setHidden(_selected);
      if (changed) {
        // Re-parse du compte actif (filtre appliqué) + invalidation des autres.
        final accounts = await StreamAccountService.listAccounts();
        final active = await StreamAccountService.getCurrentAccount();
        if (active != null) {
          final path = await PlaylistService.pathForAccountId(active.id);
          await ParsedPlaylistService.reloadFromDisk(
              active.id, active.label, path);
        }
        for (final a in accounts) {
          if (a.id != active?.id) ParsedPlaylistService.invalidate(a.id);
        }
      }
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          // Revue 2026-09-11, D4B-08 — le thème impose un texte BLANC aux
          // snackbars : sur un fond d'état, le texte suit ce fond.
          content: Text(
              changed
                  ? context.l10n.regionApplied
                  : context.l10n.regionNoChange,
              style: TextStyle(color: onColorFor(kSuccess))),
          backgroundColor: kSuccess,
        ));
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(context.l10n.commonFailedWith(describeError(e)),
                style: TextStyle(color: onColorFor(kError))), // D4B-08
            backgroundColor: kError));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // ⚠️ Quitter pendant la ré-analyse laisserait un catalogue à moitié
    // rechargé : on retient la page le temps de l'opération.
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.regionFilterTitle),
          elevation: 0,
          scrolledUnderElevation: 0,
          // Barre de progression sous le titre : visible même quand le
          // bouton flottant, lui, n'est plus là.
          bottom: _busy
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(3),
                  child: LinearProgressIndicator(minHeight: 3),
                )
              : null,
          actions: [
            // §langFilter — Tout masquer / tout afficher d'un coup.
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        if (_selected.length == kHideableRegionLabels.length) {
                          _selected.clear();
                        } else {
                          _selected = {...kHideableRegionLabels};
                        }
                      }),
              child: Text(
                _selected.length == kHideableRegionLabels.length
                    ? context.l10n.regionShowAll
                    : context.l10n.regionHideAll,
                style: TextStyle(
                    color: kAccentPrimary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        // ⚠️ **`_dirty` retombe à faux dès la PREMIÈRE ligne du travail** :
        // `setHidden` écrit la sélection, donc elle devient égale à l'état
        // enregistré. Le bouton — et son indicateur — disparaissaient donc
        // pile au moment où l'attente commençait, laissant l'utilisateur
        // devant un écran muet pendant la ré-analyse (constaté 2026-09-05).
        // D'où `|| _busy` : l'indicateur survit à sa propre condition.
        floatingActionButton: (_dirty || _busy)
            ? FloatingActionButton.extended(
                backgroundColor: kAccentPrimary,
                foregroundColor: onColorFor(kAccentPrimary), // D4B-08
                onPressed: _busy ? null : _apply,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.check),
                label: Text(_busy
                    ? context.l10n.commonApplying
                    : context.l10n.commonApply),
              )
            : null,
        body: Stack(
          children: [
            // ⚠️ Le voile arrête le doigt, pas la télécommande : sans
            // `ExcludeFocus`, les cases restaient cochables au D-pad pendant
            // la ré-analyse.
            ExcludeFocus(
              excluding: _busy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  _sectionTitle(context.l10n.settingsTracks),
                  _buildTracksCard(cs),
                  _sectionTitle(context.l10n.regionHideSection),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      context.l10n.regionHelp,
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // §regionMerge — Une case par LIGNE : une clé seule ou un groupe
                  // de doublons. Cochée si une de ses clés est masquée ; la
                  // (dé)cocher masque ou affiche toutes ses clés d'un coup.
                  ...sortedRegionRows(context.l10n).map((row) {
                    final hidden = row.any(_selected.contains);
                    return CheckboxThemeListTile(
                      label: regionRowLabel(row, context.l10n),
                      hidden: hidden,
                      onChanged: (v) => setState(() {
                        if (v) {
                          _selected.addAll(row);
                        } else {
                          _selected.removeAll(row);
                        }
                      }),
                    );
                  }),
                ],
              ),
            ),
            // Ce que l'attente signifie, et pourquoi elle dure : le catalogue
            // entier est ré-analysé. Le voile empêche de re-cocher pendant.
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withAlpha(160),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 18),
                          Text(
                            context.l10n.regionApplying,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.l10n.regionApplyingSub,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withAlpha(200),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// §regionMerge — Les lignes triées sur leur libellé AFFICHÉ (dans la langue de
/// l'appareil, accents repliés), la VO toujours en dernier : un groupe
/// (« Anglais… ») se range à son nom, pas à celui de sa première clé (`UK`).
List<List<String>> sortedRegionRows(AppLocalizations l10n) {
  // Le repli des accents de la recherche (§searchAccents) : « Écosse » se
  // range avec les E, pas après le Z.
  String fold(String s) => TitleMetadata.foldAccents(s.toLowerCase());
  final rows = hideableRegionRows();
  final vo = rows.where((r) => r.contains(kVoRegionLabel)).toList();
  final rest = rows.where((r) => !r.contains(kVoRegionLabel)).toList()
    ..sort((a, b) =>
        fold(regionRowLabel(a, l10n)).compareTo(fold(regionRowLabel(b, l10n))));
  return [...rest, ...vo];
}

class CheckboxThemeListTile extends StatelessWidget {
  final String label;
  final bool hidden;
  final ValueChanged<bool> onChanged;
  const CheckboxThemeListTile({
    super.key,
    required this.label,
    required this.hidden,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: hidden,
      onChanged: (v) => onChanged(v ?? false),
      activeColor: kAccentPrimary,
      title: Text(label),
      secondary: Icon(
        hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color:
            hidden ? kWarning : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      subtitle: Text(hidden ? context.l10n.regionHidden : context.l10n.regionVisible,
          style: TextStyle(
              fontSize: 11,
              color: hidden
                  ? kWarning
                  : Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}
