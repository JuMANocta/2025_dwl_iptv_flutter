import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// §posterLang (2026-09-05) — **Dans quelle langue on veut les visuels et les
/// textes venus de TMDB.**
///
/// **Le constat qui a motivé ce service.** L'affiche d'un film vient d'abord du
/// FOURNISSEUR (politique « plus grosse liste », §23) : sa langue est celle du
/// catalogue, incontrôlable. Quand TMDB prend le relais — affiche manquante ou
/// morte, backdrop de fiche, casting, synopsis — la langue était **`fr-FR`
/// écrite en dur à douze endroits** de `TmdbService`. Et la locale de
/// l'appareil n'était lue **nulle part** dans l'app.
///
/// ⚠️ **À ne pas confondre avec §frOnly.** `main.dart` impose
/// `Locale('fr')` à l'INTERFACE, et ça ne change pas ici : tant que la
/// traduction n'est pas complète (§l10nAll), suivre l'appareil ne donnerait
/// qu'une app à moitié traduite. Ce réglage-ci ne concerne QUE le contenu
/// distant : affiches, synopsis, noms de genres TMDB.
enum VisualLanguage {
  /// Suit la langue de l'appareil (défaut).
  auto,

  /// Français, quelle que soit la langue du téléphone.
  fr,

  /// Anglais.
  en,

  /// Version originale : on préfère un visuel SANS texte, et à défaut celui de
  /// la langue d'origine du film.
  original,
}

abstract final class VisualLanguageService {
  static const String _prefsKey = 'visual_lang_v1';

  /// Change à chaque modification — les caches qui dépendent de la langue
  /// (affiches résolues, genres inférés) l'écoutent.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static VisualLanguage _value = VisualLanguage.auto;
  static VisualLanguage get value => _value;

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      _value = fromCode(raw) ?? VisualLanguage.auto;
      debugPrint('🎨 §posterLang — langue des visuels : ${_value.name} '
          '(résolue : $resolvedTag)');
    } catch (e) {
      debugPrint('⚠️ VisualLanguageService.init : $e');
    }
  }

  static Future<void> set(VisualLanguage v) async {
    if (v == _value) return;
    _value = v;
    version.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, v.name);
    } catch (e) {
      debugPrint('⚠️ VisualLanguageService.set : $e');
    }
  }

  /// Code stocké → valeur. `null` si inconnu (fichier d'une version future,
  /// valeur corrompue) : l'appelant retombe sur le défaut.
  static VisualLanguage? fromCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final v in VisualLanguage.values) {
      if (v.name == code) return v;
    }
    return null;
  }

  /// **La seule chose que `TmdbService` a besoin de savoir** : le tag de langue
  /// à envoyer à l'API (`fr-FR`, `en-US`…).
  ///
  /// ⚠️ `original` rend `en-US` : TMDB exige un tag valide, et l'anglais est sa
  /// langue de repli naturelle. Le « sans texte » ne se demande pas ici mais à
  /// l'endpoint `/images` (`include_image_language=<lang>,null`).
  static String get resolvedTag => switch (_value) {
        VisualLanguage.fr => 'fr-FR',
        VisualLanguage.en => 'en-US',
        VisualLanguage.original => 'en-US',
        VisualLanguage.auto => tagForLocale(_deviceLanguageCode()),
      };

  /// Code ISO 639-1 de la langue voulue pour `include_image_language`.
  /// `null` en mode [VisualLanguage.original] : on ne veut alors AUCUN texte
  /// sur l'affiche.
  static String? get imageLanguageCode => switch (_value) {
        VisualLanguage.fr => 'fr',
        VisualLanguage.en => 'en',
        VisualLanguage.original => null,
        VisualLanguage.auto => _deviceLanguageCode(),
      };

  /// Langue de l'appareil → tag TMDB. Tout ce qui n'est pas explicitement
  /// connu retombe sur l'anglais, la langue la mieux fournie de TMDB.
  @visibleForTesting
  static String tagForLocale(String languageCode) => switch (languageCode) {
        'fr' => 'fr-FR',
        'es' => 'es-ES',
        'de' => 'de-DE',
        'it' => 'it-IT',
        'pt' => 'pt-PT',
        'nl' => 'nl-NL',
        'ar' => 'ar-SA',
        'tr' => 'tr-TR',
        'ru' => 'ru-RU',
        'pl' => 'pl-PL',
        _ => 'en-US',
      };

  static String _deviceLanguageCode() {
    try {
      // ⚠️ `PlatformDispatcher.instance`, PAS `Localizations.localeOf` : ce
      // service est appelé depuis des couches SANS `BuildContext` (TmdbService,
      // caches) — et surtout, l'app force `Locale('fr')` à l'interface
      // (§frOnly), donc `Localizations` rendrait toujours « fr » et le mode
      // « auto » ne suivrait jamais l'appareil.
      return PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    } catch (e) {
      return 'fr';
    }
  }

  /// Libellé pour l'écran de réglages.
  static String labelOf(VisualLanguage v) => switch (v) {
        VisualLanguage.auto => 'Comme le téléphone',
        VisualLanguage.fr => 'Français',
        VisualLanguage.en => 'Anglais',
        VisualLanguage.original => 'Version originale (sans texte)',
      };

  /// Tests uniquement.
  @visibleForTesting
  static void resetForTest([VisualLanguage v = VisualLanguage.auto]) {
    _value = v;
    version.value = 0;
  }
}
