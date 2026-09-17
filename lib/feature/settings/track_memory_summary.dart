import '../../data/services/track_preferences_service.dart';
import '../../l10n/app_localizations.dart';
import '../player/track_language_names.dart';

/// R43 — Ce que la tuile « Langues des pistes » affiche : la mémoire telle
/// qu'elle s'appliquera au PROCHAIN titre, dite en résultat (§clientText).
///
/// Fonction pure (lit le service, rend un texte) pour être testée sans page :
/// c'est elle qui décide si la personne lit « Automatique » ou « Audio :
/// Anglais · Sous-titres : coupés ».
String trackMemorySummary(AppLocalizations l10n) {
  final parts = <String>[];
  final audio = TrackPreferencesService.audio;
  if (audio != null) {
    parts.add(l10n.settingsTracksAudioLang(
        trackLanguageName(audio) ?? audio.toUpperCase()));
  }
  if (TrackPreferencesService.subtitle == TrackPreferencesService.kSubtitlesOff) {
    parts.add(l10n.settingsTracksSubsOff);
  }
  return parts.isEmpty ? l10n.settingsTracksAuto : parts.join(' · ');
}

/// R43 (2026-09-16) — Ce que la tuile des Réglages affiche, ou `null` quand il
/// n'y a **rien à oublier** : la tuile est alors MASQUÉE.
///
/// ⚠️ Le défaut corrigé : la tuile portait un chevron `>` — la promesse d'une
/// sous-page — et, dans l'état par défaut (aucune mémoire), un tap n'ouvrait
/// rien et n'oubliait rien. Elle ne se montre donc plus que lorsqu'elle SERT,
/// et son sous-titre dit alors le geste, pas seulement l'état.
///
/// Rendre `null` plutôt que de laisser la page interroger le service met la
/// règle d'affichage dans une fonction pure, testable sans écran.
String? trackMemoryTileSubtitle(AppLocalizations l10n) =>
    TrackPreferencesService.hasMemory
        ? l10n.settingsTracksResetTile(trackMemorySummary(l10n))
        : null;
