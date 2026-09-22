import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// §5 / R43 — Ce que l'app RETIENT d'un titre à l'autre pour les pistes.
///
/// Deux valeurs, et seulement deux formes chacune :
///   - [audio]    : un code de langue (« en », « fr », « pt-br »), ou `null` =
///                  automatique, le flux choisit. ⛔ JAMAIS un numéro de piste
///                  ni « unknown » : un numéro ne veut rien dire d'un fichier à
///                  l'autre, et « unknown » est ce que le natif renvoie quand
///                  la piste n'a pas de langue — les deux écrasaient une vraie
///                  préférence et se ré-appliquaient à chaque ouverture.
///   - [subtitle] : `null` = automatique, ou [kSubtitlesOff] = coupés. ⛔ Pas
///                  de langue ici : l'appliquer aux titres suivants allumerait
///                  les sous-titres français de tous les films français (R43).
///
/// Ce que ça change pour la personne : choisir une piste AUDIO vaut pour les
/// prochains titres ; choisir une piste de SOUS-TITRES ne vaut que pour
/// celui-ci ; couper les sous-titres vaut pour les suivants — et les deux
/// mémoires se VOIENT et se DÉFONT (feuille de pistes, Réglages → « Langues
/// des pistes »). Avant R43, la coupure était mémorisée sans le dire, sans
/// réglage pour l'annuler, et le seul retour épinglait une langue.
///
/// Statique + chargé une fois au boot (cf. `main()`), cohérent avec les autres
/// services (FavoritesService, WatchProgressService…).
class TrackPreferencesService {
  static const String _kAudio = 'track_pref_audio_v1';
  static const String _kSub = 'track_pref_sub_v1';

  /// La seule valeur mémorisable pour les sous-titres, hors `null`.
  static const String kSubtitlesOff = 'no';

  static String? audio;
  static String? subtitle;
  static bool _loaded = false;

  /// R43 — Une mémoire qui change se voit : la tuile des Réglages s'y abonne
  /// au lieu de relire au hasard d'un rebuild.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  /// Tests uniquement : rejoue [init] sur des préférences fictives pour
  /// vérifier la migration à la lecture (le vrai boot n'appelle `init` qu'une
  /// fois).
  @visibleForTesting
  static Future<void> reloadForTest() async {
    _loaded = false;
    await init();
  }

  static Future<void> init() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      // R43 — Migration à la lecture : les versions précédentes écrivaient un
      // numéro de piste (« 1 ») ou « unknown » côté audio, et une LANGUE côté
      // sous-titres. Ces valeurs n'ont plus de sens : on les laisse tomber ET on
      // efface la clé, pour ne pas les rejouer au démarrage suivant.
      final rawAudio = p.getString(_kAudio);
      audio = languageKeyFor(rawAudio);
      if (audio == null && rawAudio != null) await p.remove(_kAudio);
      final rawSub = p.getString(_kSub);
      subtitle = rawSub == kSubtitlesOff ? kSubtitlesOff : null;
      if (subtitle == null && rawSub != null) await p.remove(_kSub);
    } catch (e) {
      debugPrint('❌ TrackPreferencesService: chargement — $e');
    }
    _loaded = true;
  }

  static Future<void> setAudio(String? value) async {
    audio = value;
    await _save(_kAudio, value);
  }

  static Future<void> setSubtitle(String? value) async {
    subtitle = value;
    await _save(_kSub, value);
  }

  /// R43 — « Revenir à l'automatique » : les deux mémoires d'un coup.
  static Future<void> resetToAuto() async {
    await setAudio(null);
    await setSubtitle(null);
  }

  /// `true` quand quelque chose est mémorisé — donc quand il y a de quoi
  /// revenir à l'automatique.
  static bool get hasMemory => audio != null || subtitle != null;

  /// R43 — La règle « jamais un numéro » en UN seul endroit.
  ///
  /// Rend la clé à mémoriser pour une piste dont la langue est [language], ou
  /// `null` quand cette piste ne DOIT rien mémoriser : pas de langue,
  /// « unknown » du natif, « und » ISO, vestiges mpv (`auto`/`no`), numéro.
  /// ⚠️ `null` signifie « ne touche pas à la mémoire », pas « efface-la » :
  /// c'est à l'appelant de ne pas écrire.
  static String? languageKeyFor(String? language) {
    final v = language?.trim().toLowerCase();
    if (v == null || v.isEmpty) return null;
    if (!RegExp(r'^[a-z]').hasMatch(v)) return null;
    if (const {'unknown', 'und', 'off', 'auto', 'no', 'none'}.contains(v)) {
      return null;
    }
    return v;
  }

  /// §playerPanel backup — La règle « pas de langue ici » pour [subtitle], en
  /// UN seul endroit : une valeur restaurée depuis `.aether` ne doit jamais
  /// écraser cette mémoire par une langue (R43). `null` (automatique) et
  /// [kSubtitlesOff] sont les deux SEULES formes valides ; tout le reste est
  /// ignoré (sauvegarde bricolée, ou future version qui ajouterait une forme
  /// que celle-ci ne connaît pas).
  static bool isValidSubtitleMemory(String? value) =>
      value == null || value == kSubtitlesOff;

  static Future<void> _save(String key, String? value) async {
    // Les champs statiques sont déjà à jour : on prévient AVANT l'attente,
    // pour que l'écran suive le geste et non l'écriture disque.
    version.value++;
    try {
      final p = await SharedPreferences.getInstance();
      if (value == null) {
        await p.remove(key);
      } else {
        await p.setString(key, value);
      }
    } catch (e) {
      debugPrint('❌ TrackPreferencesService: persistence — $e');
    }
  }
}
