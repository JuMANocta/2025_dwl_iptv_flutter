import 'package:flutter/foundation.dart';

import '../models/m3u_entry.dart';

/// §tmdbMerge — Réunit sous une seule vignette les copies d'un même film dont
/// les fournisseurs n'écrivent pas le titre dans la même langue.
///
/// **Le cas signalé.** Le corpus contient `100 Mètres` (VOD, PREMIUM, XENO) et
/// `100 METERS` (PLATINIUM, PREMIUM) : le **même film**, en français et en
/// anglais. Leurs clés de regroupement sont `100 metres` et `100 meters` —
/// aucune normalisation de chaîne ne peut ni ne doit les rapprocher (le repli
/// d'accents donne `metres` d'un côté, `meters` de l'autre). Seul l'identifiant
/// TMDB, que les panels fournissent, dit qu'il s'agit d'une seule œuvre.
///
/// **Ce que ça couvre — et ce que ça ne couvre pas.** Mesuré le 2026-08-30 :
/// PLATINIUM porte l'identifiant sur 93 % de ses films (champ `tmdb_id`),
/// PREMIUM sur 99 % (champ `tmdb`, cf. §tmdbField). VOD et XENO n'en ont
/// **aucun**. La fusion joue donc entre les deux premières listes, et les
/// copies des deux autres restent à part. C'est une amélioration partielle,
/// assumée : mieux vaut réunir ce qu'on peut prouver que deviner le reste.
///
/// ⚠️ **Garde-fou sur l'année.** Un identifiant fournisseur peut être faux —
/// c'est de la donnée saisie par un tiers. Deux titres ne sont fusionnés que
/// si leurs années sont compatibles (identiques, ou inconnues). Sans ce
/// contrôle, une seule coquille dans un catalogue fusionne deux films
/// différents, et l'utilisateur n'a AUCUN moyen de comprendre pourquoi.
abstract final class TmdbGroupAliasService {
  /// `clé variante` → `clé canonique`. Vide tant que rien n'est chargé.
  static Map<String, String> _alias = const <String, String>{};

  /// Bumpé à chaque reconstruction — les vues qui mémoïsent leur regroupement
  /// doivent l'inclure dans leur clé de cache, comme `ParsedPlaylistService`.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static int get aliasCount => _alias.length;

  /// Clé canonique d'un groupe. Retourne [key] tel quel si aucune fusion ne
  /// s'applique — c'est le cas de l'immense majorité des titres.
  static String canonical(String key) => _alias[key] ?? key;

  @visibleForTesting
  static void resetForTest() {
    _alias = const <String, String>{};
    version.value++;
  }

  /// Reconstruit la table depuis TOUTES les entrées chargées.
  ///
  /// ⚠️ Doit voir **tous les comptes à la fois** : une fusion cross-listes ne
  /// peut pas se déduire d'un catalogue isolé.
  static void rebuild(Iterable<M3uEntry> entries) {
    // (type, tmdbId) → clé de groupe → nombre d'entrées
    final byId = <String, Map<String, int>>{};
    // (type, tmdbId) → années rencontrées (hors null)
    final years = <String, Set<String>>{};

    for (final e in entries) {
      if (e.type == M3uContentType.tv) continue; // pas de TMDB pour les chaînes
      final id = e.tmdbId;
      if (id == null || id.isEmpty || id == '0') continue;
      final key = e.title.groupKey;
      if (key.isEmpty) continue;
      final bucket = '${e.type.name}|$id';
      (byId[bucket] ??= <String, int>{}).update(key, (n) => n + 1,
          ifAbsent: () => 1);
      final y = e.title.year;
      if (y != null) (years[bucket] ??= <String>{}).add(y);
    }

    final alias = <String, String>{};
    for (final entry in byId.entries) {
      final variants = entry.value;
      if (variants.length < 2) continue; // rien à réunir
      // ⚠️ Années divergentes → identifiant douteux, on s'abstient.
      if ((years[entry.key]?.length ?? 0) > 1) continue;
      // Canonique = la forme la plus répandue ; à égalité, la plus petite dans
      // l'ordre alphabétique — pour que la table soit STABLE d'un lancement à
      // l'autre (sinon les favoris dériveraient à chaque démarrage).
      final ordered = variants.keys.toList()
        ..sort((a, b) {
          final c = variants[b]!.compareTo(variants[a]!);
          return c != 0 ? c : a.compareTo(b);
        });
      final canonicalKey = ordered.first;
      for (final k in ordered.skip(1)) {
        alias[k] = canonicalKey;
      }
    }

    // ⚠️ Chaînage : si A→B et B→C existaient, une clé pourrait pointer sur une
    // variante au lieu de la canonique. On aplatit en une passe.
    final flat = <String, String>{};
    alias.forEach((k, v) {
      var target = v;
      var hops = 0;
      while (alias.containsKey(target) && hops++ < 8) {
        target = alias[target]!;
      }
      if (target != k) flat[k] = target;
    });

    _alias = flat;
    version.value++;
    debugPrint('🔗 §tmdbMerge — ${flat.length} clés fusionnées par identifiant '
        'TMDB (${byId.length} identifiants vus)');
  }
}
