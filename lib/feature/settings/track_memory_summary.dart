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
