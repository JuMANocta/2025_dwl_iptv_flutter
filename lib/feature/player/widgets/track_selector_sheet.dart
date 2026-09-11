import 'package:flutter/material.dart';
import '../playback_engine.dart';

import '../../../core/themes/colors.dart';
import '../../../data/services/track_preferences_service.dart';
import '../../../widgets/tv/focusable_card.dart';
import '../../../widgets/tv/tv_adaptive_modal.dart';
import '../../../l10n/l10n_ext.dart';
import 'player_options_sheet.dart' show BackToVideoRow;

/// §5 — Sélecteur de pistes **audio** et **sous-titres** (libmpv expose tout
/// via `player.state.tracks` / `setAudioTrack` / `setSubtitleTrack`). Ouvert
/// depuis le bouton CC de `PlayerControls`. Sheet adaptatif (bottom sheet mobile,
/// Dialog + D-pad sur TV via [showAdaptiveActionSheet]).
///
/// §trackSheetUI — Style aligné sur l'app : en-tête, sections colorées (audio
/// vert / sous-titres cyan) avec barre d'accent, badges de langue, et état
/// sélectionné en contour néon + glow. Le choix est mémorisé globalement
/// ([TrackPreferencesService]) et ré-appliqué aux médias suivants.
Future<void> showTrackSelector(
    BuildContext context, AetherPlaybackEngine player) {
  return showAdaptiveActionSheet<void>(
    context: context,
    // §5 — Le sélecteur fournit son PROPRE scroll borné (cf. _TrackSelector) :
    // sans ça, beaucoup de pistes faisaient déborder la Column (RenderFlex
    // overflow sur mobile, où showAdaptiveActionSheet n'ajoute pas de scroll).
    scrollable: false,
    builder: (sheetCtx) => _TrackSelector(
      player: player,
      onClose: () => Navigator.of(sheetCtx).pop(),
    ),
  );
}

class _TrackSelector extends StatelessWidget {
  final AetherPlaybackEngine player;

  /// §tvOptionsBack — Ferme la feuille. Sans elle, la seule sortie à la
  /// télécommande était la touche Retour.
  final VoidCallback onClose;

  const _TrackSelector({required this.player, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // §engineVendor étape 3 — listes et sélection viennent du moteur, plus
    // d'un objet d'état propre au moteur.
    final audio = player.audioTracks;
    final subs = player.subtitleTracks;
    final curAudio = player.currentAudioTrack;
    final curSub = player.currentSubtitleTrack;
    final maxH = MediaQuery.of(context).size.height * 0.72;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En-tête.
                Row(
                  children: [
                    Icon(Icons.subtitles_rounded,
                        color: kAccentSecondary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      context.l10n.tracksTitle,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      context.l10n.tracksSubtitle,
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // ── AUDIO (accent vert) ────────────────────────────────────
                _SectionBar(
                    label: context.l10n.tracksAudio,
                    icon: Icons.graphic_eq_rounded,
                    accent: kAccentPrimary),
                const SizedBox(height: 8),
                if (audio.isEmpty)
                  _emptyHint(context.l10n.tracksNoAudio, cs)
                else
                  ...audio.map((t) => _audioRow(context, t, curAudio)),

                const SizedBox(height: 20),

                // ── SOUS-TITRES (accent cyan) ──────────────────────────────
                _SectionBar(
                    label: context.l10n.tracksSubtitles,
                    icon: Icons.closed_caption_rounded,
                    accent: kAccentSecondary),
                const SizedBox(height: 8),
                if (subs.isEmpty)
                  _emptyHint(context.l10n.tracksNoSubtitles, cs)
                else
                  ...subs.map((t) => _subtitleRow(context, t, curSub)),

                // §tvOptionsBack — Même manque que le panneau d'options : à la
                // télécommande, rien ne permettait de refermer cette feuille.
                // ⚠️ En DERNIER (`TvAutofocusFirst` focalise le premier
                // élément : « fermer » ne doit pas être l'action par défaut).
                const SizedBox(height: 18),
                BackToVideoRow(onTap: onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _audioRow(
      BuildContext context, AetherTrack t, AetherTrack? cur) {
    final isAuto = t.id == 'auto';
    final isNo = t.id == 'no';
    final title = isAuto
        ? 'Auto'
        : isNo
            ? L10n.current.tracksNone
            : (_langName(t.language) ?? t.title?.trim() ?? L10n.current.tracksTrackN(t.id));
    final sub = (!isAuto &&
            !isNo &&
            t.title != null &&
            t.title!.trim().isNotEmpty &&
            t.title!.trim() != title)
        ? t.title!.trim()
        : null;
    return _TrackRow(
      accent: kAccentPrimary,
      leading: isAuto
          ? _IconBadge(Icons.auto_awesome_rounded, kAccentPrimary)
          : isNo
              ? _IconBadge(Icons.volume_off_rounded, kAccentPrimary)
              : _LangBadge(_langShort(t.language), kAccentPrimary),
      title: title,
      subtitle: sub,
      selected: t.id == cur?.id,
      onTap: () {
        player.setAudioTrack(t);
        TrackPreferencesService.setAudio(_trackKey(t.language, t.id));
        Navigator.of(context).pop();
      },
    );
  }

  Widget _subtitleRow(
      BuildContext context, AetherTrack t, AetherTrack? cur) {
    final isNo = t.id == 'no';
    final isAuto = t.id == 'auto';
    final title = isNo
        ? L10n.current.tracksDisabled
        : isAuto
            ? 'Auto'
            : (_langName(t.language) ?? t.title?.trim() ?? L10n.current.tracksTrackN(t.id));
    final sub = (!isNo &&
            !isAuto &&
            t.title != null &&
            t.title!.trim().isNotEmpty &&
            t.title!.trim() != title)
        ? t.title!.trim()
        : null;
    return _TrackRow(
      accent: kAccentSecondary,
      leading: isNo
          ? _IconBadge(Icons.subtitles_off_rounded, kAccentSecondary)
          : isAuto
              ? _IconBadge(Icons.auto_awesome_rounded, kAccentSecondary)
              : _LangBadge(_langShort(t.language), kAccentSecondary),
      title: title,
      subtitle: sub,
      selected: t.id == cur?.id,
      onTap: () {
        player.setSubtitleTrack(t);
        TrackPreferencesService.setSubtitle(
            isNo ? 'no' : _trackKey(t.language, t.id));
        Navigator.of(context).pop();
      },
    );
  }

  Widget _emptyHint(String text, ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        child: Text(text,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
      );
}

/// En-tête de section : barre d'accent verticale + icône + label (style fiche).
class _SectionBar extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  const _SectionBar(
      {required this.label, required this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 17, color: accent),
        const SizedBox(width: 7),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: accent,
          ),
        ),
      ],
    );
  }
}

/// Badge de langue (ex. « FR ») coloré à l'accent de la section.
class _LangBadge extends StatelessWidget {
  final String code;
  final Color accent;
  const _LangBadge(this.code, this.accent);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(110)),
      ),
      child: Text(
        code,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Badge à icône (Auto / Aucune / Désactivés).
class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color accent;
  const _IconBadge(this.icon, this.accent);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withAlpha(22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(90)),
      ),
      child: Icon(icon, size: 18, color: accent),
    );
  }
}

class _TrackRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;
  const _TrackRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: FocusableCard(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? accent.withAlpha(26) : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : cs.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withAlpha(70),
                      blurRadius: 14,
                      spreadRadius: -3,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? accent : cs.onSurfaceVariant.withAlpha(120),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Clé de mémorisation/match d'une piste : langue si dispo, sinon id.
String _trackKey(String? language, String id) =>
    (language != null && language.isNotEmpty) ? language : id;

/// Code court 2 lettres pour le badge (ex. « FR »). Fallback : 2 premières
/// lettres du code en majuscules, ou « ? ».
String _langShort(String? code) {
  if (code == null || code.trim().isEmpty) return '?';
  final c = code.toLowerCase().trim();
  const map = {
    'fr': 'FR',
    'fre': 'FR',
    'fra': 'FR',
    'en': 'EN',
    'eng': 'EN',
    'es': 'ES',
    'spa': 'ES',
    'de': 'DE',
    'ger': 'DE',
    'deu': 'DE',
    'it': 'IT',
    'ita': 'IT',
    'pt': 'PT',
    'por': 'PT',
    'ar': 'AR',
    'ara': 'AR',
    'ru': 'RU',
    'rus': 'RU',
    'nl': 'NL',
    'dut': 'NL',
    'nld': 'NL',
    'ja': 'JA',
    'jpn': 'JA',
    'zh': 'ZH',
    'chi': 'ZH',
    'zho': 'ZH',
    'ko': 'KO',
    'kor': 'KO',
    'tr': 'TR',
    'tur': 'TR',
    'pl': 'PL',
    'pol': 'PL',
  };
  return map[c] ?? c.substring(0, c.length >= 2 ? 2 : 1).toUpperCase();
}

/// Mappe les codes ISO 639 (libmpv renvoie souvent du 639-2/B : fre, ger…) vers
/// un libellé FR lisible. Fallback : code en majuscules.
String? _langName(String? code) {
  if (code == null || code.trim().isEmpty) return null;
  final c = code.toLowerCase().trim();
  // §l10nAll — Le CODE reste la clé (stable) ; le nom vient de la l10n.
  final l10n = L10n.current;
  return switch (c) {
    'fr' || 'fre' || 'fra' => l10n.langFrench,
    'en' || 'eng' => l10n.langEnglish,
    'es' || 'spa' => l10n.langSpanish,
    'de' || 'ger' || 'deu' => l10n.langGerman,
    'it' || 'ita' => l10n.langItalian,
    'pt' || 'por' => l10n.langPortuguese,
    'ar' || 'ara' => l10n.langArabic,
    'ru' || 'rus' => l10n.langRussian,
    'nl' || 'dut' || 'nld' => l10n.langDutch,
    'ja' || 'jpn' => l10n.langJapanese,
    'zh' || 'chi' || 'zho' => l10n.langChinese,
    'ko' || 'kor' => l10n.langKorean,
    'tr' || 'tur' => l10n.langTurkish,
    'pl' || 'pol' => l10n.langPolish,
    'vostfr' => 'VOSTFR',
    _ => code.toUpperCase(),
  };
}
