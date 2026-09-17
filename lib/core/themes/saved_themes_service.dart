import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme_config.dart';

/// §themeStudio — « Mes thèmes » : les thèmes composés à la main, gardés.
///
/// **Le défaut corrigé (signalé le 2026-09-16)** : régler les dix champs d'un
/// thème prend plusieurs minutes, et RIEN ne les gardait. « Réinitialiser »
/// remettait Matrix, un tap sur un préréglage écrasait tout, et les cinq
/// secondes d'« Annuler » passées, le travail était perdu sans recours — un
/// thème personnel n'était récupérable que par une sauvegarde `.aether`
/// restaurée en entier.
///
/// ⚠️ Les préréglages ne sont PAS ici : ils sont en dur dans
/// [AppThemeConfig.presets] et ne se renomment ni ne se suppriment. Cette
/// liste ne contient que ce que la personne a enregistré.
@immutable
class SavedTheme {
  /// Le nom donné par la personne. Jamais vide (cf. [SavedThemesService.sanitizeName]).
  final String name;
  final AppThemeConfig config;

  const SavedTheme({required this.name, required this.config});

  SavedTheme rename(String newName) =>
      SavedTheme(name: newName, config: config);

  /// Même convention compacte que [AppThemeConfig.toJson] : ces objets vivent
  /// dans les préférences ET dans le `.aether`, qu'on ne veut pas gonfler.
  Map<String, dynamic> toJson() => {'n': name, 'c': config.toJson()};

  /// Lecture TOLÉRANTE : rend `null` plutôt que de lever.
  ///
  /// ⚠️ Une entrée illisible ne doit jamais faire perdre les autres — ni,
  /// pire, empêcher une restauration `.aether` d'aboutir pour un accessoire.
  static SavedTheme? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? name = raw['n'];
    final Object? cfg = raw['c'];
    if (name is! String || cfg is! Map) return null;
    final String clean = SavedThemesService.sanitizeName(name);
    if (clean.isEmpty) return null;
    try {
      return SavedTheme(
        name: clean,
        config: AppThemeConfig.fromJson(cfg.cast<String, dynamic>()),
      );
    } catch (_) {
      // Champ manquant ou d'un autre type : on saute cette entrée.
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SavedTheme && other.name == name && other.config.sameLook(config);

  @override
  int get hashCode => Object.hash(name, config.primaryColor);
}

/// Les thèmes enregistrés, persistés dans les préférences et exportés dans le
/// `.aether`.
class SavedThemesService {
  static const String _kKey = 'aether_saved_themes_v1';

  /// Plafond volontaire. ⚠️ D1B-14 a mesuré le poids des préférences : elles
  /// sont relues à chaque démarrage, et une liste sans borne y grossirait
  /// jusqu'à peser sur le boot pour un usage qui en demande trois ou quatre.
  static const int kMaxThemes = 20;

  /// Longueur maximale d'un nom — au-delà, la liste devient illisible et le
  /// nom est tronqué à l'affichage de toute façon.
  static const int kMaxNameLength = 40;

  /// La liste, dans l'ordre d'enregistrement. Un notifieur : la page des
  /// thèmes s'y abonne au lieu de relire au hasard d'un rebuild.
  static final ValueNotifier<List<SavedTheme>> themes =
      ValueNotifier<List<SavedTheme>>(const []);

  static bool _loaded = false;

  /// Tests uniquement : rejoue [load] sur des préférences fictives.
  @visibleForTesting
  static Future<void> reloadForTest() async {
    _loaded = false;
    themes.value = const [];
    await load();
  }

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      themes.value = decode(p.getString(_kKey));
    } catch (e) {
      debugPrint('❌ SavedThemesService: chargement — $e');
    }
    _loaded = true;
  }

  /// **Pure** — testée. Un JSON absent, tronqué ou d'un autre type rend une
  /// liste vide ; les entrées illisibles sont sautées une par une.
  static List<SavedTheme> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
    return fromList(parsed);
  }

  /// **Pure** — la même tolérance, à partir d'une valeur déjà décodée (c'est
  /// la forme qu'a la clé `savedThemes` d'un `.aether`).
  static List<SavedTheme> fromList(Object? raw) {
    if (raw is! List) return const [];
    final out = <SavedTheme>[];
    for (final Object? e in raw) {
      final SavedTheme? t = SavedTheme.tryFromJson(e);
      if (t != null) out.add(t);
      if (out.length >= kMaxThemes) break;
    }
    return List.unmodifiable(out);
  }

  /// **Pure** — testée.
  static String encode(List<SavedTheme> list) =>
      jsonEncode([for (final t in list) t.toJson()]);

  static List<Map<String, dynamic>> toJsonList(List<SavedTheme> list) =>
      [for (final t in list) t.toJson()];

  /// **Pure** — un nom utilisable : espaces rognés, longueur bornée, sauts de
  /// ligne écartés (un nom sur deux lignes casserait toutes les listes).
  static String sanitizeName(String raw) {
    final String flat = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= kMaxNameLength
        ? flat
        : flat.substring(0, kMaxNameLength).trim();
  }

  /// **Pure** — `true` quand [config] ne correspond à AUCUN préréglage ni
  /// thème enregistré : c'est exactement le cas où « Réinitialiser » ferait
  /// perdre un travail irrécupérable, et donc où il faut proposer de le garder.
  static bool isUnsaved(AppThemeConfig config, List<SavedTheme> saved) {
    for (final p in AppThemeConfig.presets) {
      if (config.sameLook(p.config)) return false;
    }
    for (final t in saved) {
      if (config.sameLook(t.config)) return false;
    }
    return true;
  }

  /// Enregistre [config] sous [name]. Un nom déjà pris est REMPLACÉ (on
  /// enregistre « par-dessus », comme un fichier) plutôt que dupliqué.
  ///
  /// Rend `false` si le nom est vide ou si le plafond est atteint — l'appelant
  /// le dit à l'écran, il ne disparaît pas en silence.
  static Future<bool> saveAs(String name, AppThemeConfig config) async {
    final String clean = sanitizeName(name);
    if (clean.isEmpty) return false;
    final list = [...themes.value];
    final int at = list.indexWhere((t) => t.name == clean);
    if (at >= 0) {
      list[at] = SavedTheme(name: clean, config: config);
    } else {
      if (list.length >= kMaxThemes) return false;
      list.add(SavedTheme(name: clean, config: config));
    }
    await _write(list);
    return true;
  }

  /// Renomme le thème [index]. Rend `false` sur un nom vide ou déjà pris.
  static Future<bool> rename(int index, String newName) async {
    final String clean = sanitizeName(newName);
    if (clean.isEmpty) return false;
    final list = [...themes.value];
    if (index < 0 || index >= list.length) return false;
    if (list[index].name == clean) return true;
    if (list.any((t) => t.name == clean)) return false;
    list[index] = list[index].rename(clean);
    await _write(list);
    return true;
  }

  static Future<void> remove(int index) async {
    final list = [...themes.value];
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await _write(list);
  }

  /// Réinsère [theme] à [index] — le pendant exact de [remove], pour qu'une
  /// suppression reste ANNULABLE (§undoTv).
  static Future<void> insert(int index, SavedTheme theme) async {
    final list = [...themes.value];
    final int at = index.clamp(0, list.length);
    list.insert(at, theme);
    await _write(list);
  }

  /// Remplace toute la liste — utilisé par la restauration d'un `.aether`.
  /// ⚠️ Une liste VIDE est un choix légitime (« je n'en ai aucun ») ; c'est à
  /// l'appelant de ne pas appeler quand la clé est ABSENTE (`null` ≠ vide).
  static Future<void> replaceAll(List<SavedTheme> list) =>
      _write(list.take(kMaxThemes).toList());

  static Future<void> _write(List<SavedTheme> list) async {
    // La liste est déjà à jour à l'écran avant l'écriture disque : le geste
    // suit le doigt, pas les préférences.
    themes.value = List.unmodifiable(list);
    try {
      final p = await SharedPreferences.getInstance();
      if (list.isEmpty) {
        await p.remove(_kKey);
      } else {
        await p.setString(_kKey, encode(list));
      }
    } catch (e) {
      debugPrint('❌ SavedThemesService: persistence — $e');
    }
  }
}
