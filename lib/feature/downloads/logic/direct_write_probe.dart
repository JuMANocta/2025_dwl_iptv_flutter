import 'dart:io';

import 'package:flutter/foundation.dart';

import 'partial_sweep.dart' show kPartialMarker;

/// §dlDirectWrite — « Ce dossier accepte-t-il **ce fichier-là** ? »
///
/// ## Pourquoi ce fichier existe (2026-09-10)
///
/// Le téléchargement vise à écrire son fichier partiel **directement à côté du
/// fichier final** : la finalisation devient alors un `rename()` instantané au
/// lieu d'une copie qui exige un pic d'espace disque de **2× la taille du
/// film** (deux transferts de 567 Mo ont échoué là-dessus le 2026-09-08).
///
/// Or, sur le Galaxy S25 comme sur l'émulateur, ce chemin nominal **retombe
/// toujours sur son repli** : les partiels finissent dans `cache/dl_tmp/`.
///
/// ⚠️ **La sonde d'origine ne ressemblait pas à ce qu'elle testait.** Elle
/// écrivait `.aether_write_probe` — un nom **sans extension** — pour décider si
/// l'on pouvait écrire `.Mon film.mkv.part`. Sous le stockage cloisonné
/// d'Android, un dossier média n'est pas un dossier ordinaire : le démon FUSE
/// décide fichier par fichier, **d'après l'extension**, et refuse ce qui n'a
/// rien à faire dans une collection vidéo. Une sonde qui ne porte pas la même
/// extension que le fichier réel peut donc se tromper **dans les deux sens** :
/// échouer alors que le vrai fichier passerait, ou passer alors qu'il échouera.
///
/// D'où [canWriteLike] : on sonde avec un nom **construit comme le vrai**,
/// même dossier, même chaîne d'extensions, seul le radical change.
///
/// ## Et [diagnose], pour trancher la cause
///
/// Savoir que ça échoue ne dit pas POURQUOI. [diagnose] n'est appelée que
/// lorsque la sonde nominale a échoué — elle essaie une batterie de formes de
/// noms et journalise laquelle passe. C'est cette table qui dira si le refus
/// vient de l'extension, du point de tête, ou du dossier lui-même (auquel cas
/// aucune forme ne passera et le repli est le bon comportement).
///
/// ## ✅ Ce que la table a dit (Android 16, 2026-09-10)
///
/// ```
/// ❌ .aether_probe.mkv.part  : Operation not permitted (errno 1)
/// ❌ aether_probe.mkv.part   : Operation not permitted
/// ✅ .aether_probe.mkv       : écrit
/// ✅ aether_probe.mkv        : écrit
/// ❌ aether_probe.part       : Operation not permitted
/// ❌ .aether_probe           : Operation not permitted
/// ```
///
/// **Le dossier est parfaitement inscriptible.** C'est l'**extension finale**
/// qui décide, et le point de tête n'y change rien. ⚠️ La sonde d'origine,
/// `.aether_probe` **sans extension**, tombait donc dans la seule catégorie
/// refusée : elle ne pouvait passer sur AUCUN appareil, et §dlDirectWrite n'a
/// jamais eu la moindre chance de s'engager. Le partiel porte désormais son
/// marqueur AVANT l'extension réelle (`.Heat.aetherpart.mkv`).
///
/// ⛔ Ne pas remettre `.part` en dernière position « pour la clarté » : c'est
/// exactement ce qui condamnait le chemin rapide.
class DirectWriteProbe {
  DirectWriteProbe._();

  /// Radical des fichiers de sonde. Assez identifiable pour qu'un résidu se
  /// reconnaisse au premier coup d'œil dans le dossier public.
  static const String stem = '.aether_probe';

  /// Les formes de noms essayées par [diagnose], pour une cible d'extension
  /// [extension] (sans point, ex. `mkv`). **Pure** — testée.
  ///
  /// L'ordre va du plus proche du fichier réel au plus éloigné : la première
  /// forme est exactement celle qu'un téléchargement écrirait.
  @visibleForTesting
  static List<String> probeNames(String extension) {
    final String ext = extension.replaceAll('.', '').toLowerCase();
    final String dotExt = ext.isEmpty ? '' : '.$ext';
    return <String>[
      '$stem.$kPartialMarker$dotExt', // la forme RÉELLE du partiel (cachée)
      '$stem$dotExt', // cachée, extension média seule
      'aether_probe$dotExt', // visible, extension média seule
      '$stem$dotExt.part', // ⛔ forme HISTORIQUE : refusée, mesuré
      'aether_probe.part', // `.part` sans extension média
      stem, // ⛔ la sonde HISTORIQUE : aucune extension — refusée elle aussi
    ];
  }

  /// Le dossier de [path] accepte-t-il un fichier nommé **comme** [path] ?
  ///
  /// On écrit un octet sous un nom jumeau (même dossier, même chaîne
  /// d'extensions) puis on l'efface. `Directory.exists()` ne suffirait pas :
  /// sous stockage cloisonné un dossier peut être listable sans être
  /// inscriptible, et inscriptible pour un nom mais pas pour un autre.
  static Future<bool> canWriteLike(String path) async {
    final int slash = path.lastIndexOf('/');
    final String dir = slash >= 0 ? path.substring(0, slash) : '.';
    final String name = slash >= 0 ? path.substring(slash + 1) : path;
    final String twin = '$dir/$stem${_extensionChainOf(name)}';

    final String? error = await _tryWrite(twin);
    if (error == null) return true;

    debugPrint('⚠️ §dlDirectWrite: « $twin » refusé — $error');
    await _logDiagnosis(dir, _extensionChainOf(name));
    return false;
  }

  /// Les **deux dernières** extensions de [fileName], point de tête ignoré.
  ///
  /// `.Mon film.mkv.part` → `.mkv.part` · `Le.film.2024.mkv.part` →
  /// `.mkv.part` · `Film.mp4` → `.mp4` · `truc` → `''`.
  ///
  /// ⚠️ Deux au maximum, jamais tout ce qui suit le premier point : un titre
  /// comme « Le.film.2024.mkv.part » ferait sonder
  /// `.aether_probe.film.2024.mkv.part`, un nom que rien ne produit jamais.
  /// ⚠️ Le point de TÊTE d'un fichier caché n'est pas une extension.
  /// **Pure** — testée.
  @visibleForTesting
  static String extensionChainOf(String fileName) =>
      _extensionChainOf(fileName);

  static String _extensionChainOf(String fileName) {
    final String body =
        fileName.startsWith('.') ? fileName.substring(1) : fileName;
    final List<String> parts = body.split('.');
    // `parts.first` est le radical : il reste au moins un segment devant.
    final int available = parts.length - 1;
    if (available <= 0) return '';
    final List<String> kept = parts.sublist(parts.length - (available >= 2 ? 2 : 1));
    if (kept.any((String s) => s.isEmpty)) return '';
    return '.${kept.join('.')}';
  }

  /// Essaie chaque forme de [probeNames] dans [directory] et journalise le
  /// résultat. N'est appelée que sur le chemin d'ÉCHEC : elle ne coûte rien au
  /// cas nominal.
  static Future<Map<String, String?>> diagnose(
      String directory, String extension) async {
    final Map<String, String?> results = <String, String?>{};
    for (final String name in probeNames(extension)) {
      results[name] = await _tryWrite('$directory/$name');
    }
    return results;
  }

  static Future<void> _logDiagnosis(String dir, String extChain) async {
    // `.mkv.part` → on redonne `mkv` à `probeNames`, qui reconstruit la chaîne.
    final String ext = extChain.startsWith('.')
        ? extChain.substring(1).split('.').first
        : extChain.split('.').first;
    final Map<String, String?> table = await diagnose(dir, ext);
    debugPrint('🔬 §dlDirectWrite — diagnostic du dossier $dir :');
    for (final MapEntry<String, String?> e in table.entries) {
      debugPrint(e.value == null ? '   ✅ « ${e.key} » : écrit' : '   ❌ « ${e.key} » : ${e.value}');
    }
    debugPrint('🔬 §dlDirectWrite — verdict : ${verdict(table)}');
  }

  /// Ce que la table de [diagnose] permet de conclure, en une phrase.
  /// **Pure** — testée. Destinée au journal, jamais à l'écran (§clientText).
  @visibleForTesting
  static String verdict(Map<String, String?> results) {
    final List<String> ok = <String>[
      for (final MapEntry<String, String?> e in results.entries)
        if (e.value == null) e.key
    ];
    if (ok.isEmpty) {
      return 'aucune forme acceptee — le dossier lui-meme est ferme, '
          'le repli est le bon comportement';
    }
    if (ok.length == results.length) {
      return 'toutes les formes acceptees — le refus ne vient pas du nom';
    }
    return 'accepte seulement : ${ok.join(', ')}';
  }

  /// Écrit un octet puis efface. Rend `null` si ça a marché, sinon le message
  /// d'erreur. **N'échoue jamais** : c'est un diagnostic.
  static Future<String?> _tryWrite(String path) async {
    final File probe = File(path);
    try {
      await probe.writeAsString('x', flush: true);
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      try {
        if (await probe.exists()) await probe.delete();
      } catch (_) {
        // Un résidu d'un octet est inoffensif — et il porte un nom reconnaissable.
      }
    }
  }
}
