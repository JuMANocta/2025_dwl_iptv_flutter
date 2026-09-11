import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Revue 2026-09-11, lot 8a (D1B-14, D1A-17) — **Sondes des préférences.**
///
/// ## Pourquoi
///
/// Deux tables vivent dans `SharedPreferences` et y sont réécrites EN ENTIER :
/// le cache d'affiches TMDB (jusqu'à 20 000 entrées, toutes les 5 s de
/// résolution) et les reprises de lecture (toutes les 10 s de lecture). Sur
/// Android, les préférences sont UN seul fichier XML : chaque écriture le
/// réécrit tout entier. La revue propose un fichier dédié « si le fichier
/// dépasse ~500 Ko » — encore faut-il le savoir.
///
/// ⚠️ Sur le téléviseur en release, ni logcat ni `adb shell run-as` (l'APK
/// n'est pas débogable) : la seule façon de connaître la taille réelle est que
/// l'app la dise dans son journal (§tvLogs, lisible par la console web).
///
/// ⚠️ Relecture lot 8a — **Le nombre de caractères n'est PAS la taille du
/// fichier.** Les valeurs sont du JSON écrit dans du XML : chaque guillemet y
/// devient `&quot;` (6 octets), un accent en fait 2. Le cache d'affiches, qui
/// aligne clés et URL entre guillemets, pèse sur le disque nettement plus que
/// sa longueur en caractères. Le seuil de la revue porte sur le FICHIER : la
/// sonde lit donc sa taille réelle (`shared_prefs/FlutterSharedPreferences.xml`,
/// le nom que `shared_preferences_android` donne au stockage de
/// `SharedPreferences.getInstance()`), et garde le décompte par clé pour dire
/// QUI pèse.
///
/// ## Coût
///
/// [logFootprint] : une ligne AU DÉMARRAGE — des longueurs de valeurs déjà en
/// mémoire (`SharedPreferences` les charge toutes) et UN `stat` de fichier.
/// [setStringTimed] : un chronomètre autour d'une écriture qui avait déjà
/// lieu ; rien n'est journalisé tant que l'écriture reste sous [slowWriteMs].
abstract final class PrefsProbe {
  /// Au-delà, la partie synchrone d'une écriture est journalisée : la moitié
  /// d'une frame à 60 Hz, le seuil où elle devient visible au défilement.
  static const int slowWriteMs = 8;

  /// Empreinte en caractères de chaque clé (chaîne : sa longueur ; liste :
  /// la somme ; autre valeur : 8, l'ordre de grandeur d'un nombre).
  ///
  /// Fonction pure : c'est elle qu'on teste.
  @visibleForTesting
  static ({int total, List<(String, int)> biggest}) footprintOf(
      Map<String, Object?> values,
      {int top = 3}) {
    int total = 0;
    final List<(String, int)> sizes = <(String, int)>[];
    values.forEach((String key, Object? value) {
      final int size = switch (value) {
        final String s => s.length,
        final List<Object?> l =>
          l.fold<int>(0, (int acc, Object? e) => acc + e.toString().length),
        _ => 8,
      };
      total += size;
      sizes.add((key, size));
    });
    sizes.sort(((String, int) a, (String, int) b) => b.$2.compareTo(a.$2));
    return (total: total, biggest: sizes.take(top).toList());
  }

  /// Une ligne de journal : taille du fichier des préférences sur le disque,
  /// taille des valeurs, et les plus grosses clés. À appeler UNE fois, au
  /// démarrage, sans l'attendre (`unawaited`) : rien n'en dépend.
  static Future<void> logFootprint(SharedPreferences prefs) async {
    try {
      // Instantané SYNCHRONE des valeurs, avant toute attente.
      final Map<String, Object?> values = <String, Object?>{
        for (final String k in prefs.getKeys()) k: prefs.get(k),
      };
      final r = footprintOf(values);
      final String detail = r.biggest
          .map(((String, int) e) => '${e.$1} ${_kc(e.$2)}')
          .join(', ');
      final int? fileBytes = await _prefsFileBytes();
      final String disk = fileBytes == null
          ? 'fichier : taille inconnue'
          : 'fichier ${_kb(fileBytes)} sur le disque';
      // Une seule ligne : le cliquet l10n ne reconnaît un diagnostic qu'à la
      // ligne qui porte `debugPrint(`.
      debugPrint('📦 PrefsProbe — préférences : $disk, valeurs ${_kc(r.total)} sur ${values.length} clés (les plus grosses : $detail)');
    } catch (e) {
      debugPrint('⚠️ PrefsProbe — empreinte impossible : $e');
    }
  }

  /// Taille réelle du fichier XML des préférences, ou `null` hors Android ou
  /// si on ne sait pas le trouver. `getApplicationSupportDirectory()` rend
  /// `<données de l'app>/files` sur Android ; `shared_prefs/` en est le voisin.
  static Future<int?> _prefsFileBytes() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final Directory files = await getApplicationSupportDirectory();
      final File xml = File(
          '${files.parent.path}/shared_prefs/FlutterSharedPreferences.xml');
      return await xml.exists() ? await xml.length() : null;
    } catch (_) {
      return null;
    }
  }

  /// Écrit [key] = `encode()` exactement comme `prefs.setString`, en mesurant
  /// la partie SYNCHRONE (encodage + remise au canal natif), celle qui prend le
  /// thread UI. Journalisée seulement au-delà de [slowWriteMs].
  static Future<bool> setStringTimed(
    SharedPreferences prefs,
    String key,
    String Function() encode, {
    required String tag,
  }) async {
    final Stopwatch sw = Stopwatch()..start();
    final String value = encode();
    final int encodeMs = sw.elapsedMilliseconds;
    final Future<bool> write = prefs.setString(key, value);
    final int syncMs = sw.elapsedMilliseconds;
    final bool ok = await write;
    if (syncMs >= slowWriteMs) {
      debugPrint('⏱️ PrefsProbe — $tag : ${_kc(value.length)} écrits, '
          '$syncMs ms sur le thread UI (dont encodage $encodeMs ms)');
    }
    return ok;
  }

  /// Octets → « X Ko ».
  static String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} Ko';

  /// Caractères → « X k car. » (ce n'est PAS une taille de fichier, cf. plus
  /// haut).
  static String _kc(int chars) =>
      '${(chars / 1024).toStringAsFixed(1)} k car.';
}
