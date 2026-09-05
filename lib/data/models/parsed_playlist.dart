import 'package:flutter/foundation.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';

/// Résultat complet du parsing d'une playlist M3U pour un compte donné.
/// Sert de container sérialisable pour le cache disque (JSON.gz) et de source
/// de vérité en mémoire pour toute l'application.
class ParsedPlaylist {
  /// Version du schéma de sérialisation.
  /// Incrémenter quand la structure de [M3uEntry] ou [TitleMetadata] change
  /// → invalide automatiquement tous les caches disque existants.
  static const int schemaVersion = 19; // v19 : §catWords — les MOTS DE TYPE (FILMS/FILMES/MOVIES/SERIES/VOD) ne sont plus jamais un libellé. Relevé sur le téléviseur avec un vrai catalogue : **onze rangées commençaient par « films »** (FILMES 3 299, FILMS ANCIENS 2 023, FILMS DE NOËL 472…) soit ~6 900 films hors de leur genre, et des DOUBLONS de rangée pour un même genre (Arts martiaux 99 + FILMS ART-MARTIAUX 103, Fêtes 15 + FILMS DE NOËL 472, Sci-Fi 164 + SCIENCE-FICTION 368). Cause prouvée par sonde : `FILMS` passait le repli littéral comme un libellé valable, et sur `FILMS | ART-MARTIAUX` le segment principal « classait » avant qu'on lise le genre. Désormais : mots de type retirés de chaque segment, segment vide sauté, repli littéral vide → null (« Autres »). Vocabulaire ajouté : portugais/espagnol/italien (AÇÃO, COMÉDIA, TERROR, AVENTURA, SUSPENSE, FAROESTE, POLICIAL, ANIMAÇÃO, GUERRA), ART-MARTIAUX, NOËL/CHRISTMAS → Fêtes, ANCIEN → Cultes, FAMILY → Jeunesse, SCIENCE-FICTION → Sci-Fi, COMICS/MARVEL/DC → Super-Héros, THÉÂTRE → Spectacle, KARAOKÉ, TOP N → Sélection, V.O SOUS TITRÉS → VOSTFR ; DOLBY VISION → 4K HDR (une seule rangée HDR), 4K/UHD nus → « 4K » ; plateformes Netflix/Prime Video/HBO/Apple TV+ ; région « Asie » (reléguée ET masquable). ⚠️ LEGENDAD remonté EN TÊTE de la cascade : sinon « ANIMACAO LEGENDADA » partirait dans Animation et échapperait à la case Legendado. ⚠️ Bump OBLIGATOIRE : `M3uEntry.category` est écrit dans le cache. | v18 : §catFix — le RANGEMENT des catégories, corrigé sur la mesure. Les plateformes (PARAMOUNT/DISNEY/BRUTX/RAKUTEN) et les formats (3D/IMAX/4K HDR) étaient testés AVANT les genres, et ce fournisseur suffixe TOUS ses group-titles séries par `( NETFLIX| … | PARAMOUNT+ )` : **52 991 séries sur 104 257 (51 %) tombaient dans la seule rangée « Paramount+ »**. Le genre se lit désormais sur le SEGMENT PRINCIPAL (parenthèses et préfixe `|XX|` retirés, premier segment avant `|`), les plateformes ne classent que si elles y sont seules. Aussi : apostrophe typographique U+2019 (« FIN D’ANNÉE » ne matchait pas), POLICIER avant ACTION, « COMEDIE MUSICAL » était du code MORT (fusionné dans « Musical »), Cultes+Classiques fusionnés, vocabulaire multilingue (KINDER/NIÑOS/BAMBINI/CRIANÇAS, NEWS/NACHRICHTEN → « Actualités », MUSIC/MUSIK), ENGLISH → UK et FRANÇAIS → « Français » (696 films en repli littéral), sport nommé par sa compétition (DAZN/LIGUE 1/UEFA). ⚠️ Vocabulaire aligné avec `tmdb_genres.dart` ('Enfants'→'Jeunesse', 'Musique'→'Musical') ET clé `inferred_category_v2` : sans ce second bump, les libellés déjà persistés survivraient et l'accueil montrerait les deux vocabulaires. ⚠️ Bump OBLIGATOIRE : `M3uEntry.category` est écrit dans le cache. | v17 : §tmdbMerge + §tmdbField — deux copies d'un même film écrites dans deux langues (`100 METERS` / `100 mètres`, id TMDB 1295026) se réunissent enfin sous une seule vignette : 9 511 clés fusionnées sur les listes réelles. ⚠️ Le parseur ne lisait que `tmdb_id` alors que PREMIUM envoie `tmdb` — 16 650 identifiants étaient jetés. ⚠️ **Bump OBLIGATOIRE et distinct du v16** : le drapeau one-shot de §favReconcile est indexé sur le schéma. Changer les clés de groupe sans bumper laisse le drapeau du schéma précédent en place, la réconciliation ne tourne pas, et l'utilisateur PERD des favoris (constaté : 2 → 1 sur l'émulateur). | v16 : §tagResidue — un groupe de délimiteurs se traite EN BLOC (retiré entièrement ou laissé intact, jamais à moitié) et AVANT le strip global : `[MULTi VO/VQF]` ne laisse plus `[ /VQF]` dans le titre NI dans la clé de regroupement. 1 266 titres sur 353 475 étaient abîmés, il n'en reste 0. ⚠️ `_reLangParens` s'écrivait `[A-Z]{2,6}` en insensible à la casse — donc « n'importe quel mot de 2 à 6 lettres » : elle détruisait `[REC]`, un vrai titre. Liste désormais FERMÉE. Vocabulaire complété sur les jetons mesurés (SUBAR 705, LIGHT 270, SUB-AR 144, VQF 8, LEG/LEGENDADO, AUDIO, SUBS, et la coquille MUTLI). ⚠️ Les clés changent → réconciliation §favReconcile automatique et catégories §inferredCat ré-apprises. | v15 : §searchAccents — `computeGroupKey` replie les accents (é→e) : taper « piece montee » trouve enfin « Pièce Montée », et 18 % des titres portent un accent. Effet de bord modeste et voulu : deux listes qui écrivent le même titre avec et sans accents fusionnent (+91 titres au mieux). ⚠️ Les clés de groupe changent → réconciliation §favReconcile automatique, et les catégories déduites §inferredCat sont ré-apprises. | v14 : §providerTag + §camQuality + §orphanBracket + §labelLeak + §midYear + §keep3d — le marqueur de tete du fournisseur (FR, US, IT, RU...) a son propre champ au lieu de squatter versionLabel, que l'UI affichait comme une QUALITE ; les rips de salle (HDTS/HDCAM/CAMRIP) sont enfin detectes comme qualite (`hd` ne matche pas HDTS) ; delimiteur ferme sans ouvrant retire du titre affiche | v13 : §xenoFormat + §yearTitle — préfixe à pipe fermant seul (`FR| Titre`), tag composite `[MULTI-SUB]`, et une année en tête de titre n'est plus prise pour une date de sortie (le film « 2067 » s'affichait « (FR HD) ») | v12 : §parseAudit2026-06-30 — TitleMetadata.parse corrigé (préfixe casse mixte, pipes résiduels, exposants H265/H264, tag FPS) | v11 : §filterCats2 — filtres Algérie / Turkish / Novidades / Maghrébin (détection group-title) | v10 : §langFilterCat — filtre langues/régions aussi par CATÉGORIE (group-title), pas seulement le préfixe titre | v9 : §newCatMerge — Nouveauté/NEW/Derniers ajouts → label « New » | v8 : §newByAdded — M3uEntry.addedAt | v7 : §23 — champs riches JSON API

  final String accountId;
  /// Version du schéma au moment de la sauvegarde — comparé à [schemaVersion] à la relecture.
  final int schema;
  /// Date de dernière modification du fichier .m3u source — invalidation si changée.
  final DateTime m3uModifiedAt;
  /// Toutes les entrées brutes (films + séries + TV confondus).
  final List<M3uEntry> entries;

  ParsedPlaylist({
    required this.accountId,
    required this.schema,
    required this.m3uModifiedAt,
    required this.entries,
  });

  // ── Getters calculés en mémoire (non stockés dans le JSON) ────────────────

  late final List<M3uEntry> films  = entries.where((e) => e.type == M3uContentType.movie).toList();
  late final List<M3uEntry> series = entries.where((e) => e.type == M3uContentType.series).toList();
  late final List<M3uEntry> tv     = entries.where((e) => e.type == M3uContentType.tv).toList();

  // ── Sérialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'schema':       schema,
    'accountId':    accountId,
    'm3uModAt':     m3uModifiedAt.toIso8601String(),
    'entries':      entries.map((e) => e.toJson()).toList(),
  };

  factory ParsedPlaylist.fromJson(Map<String, dynamic> j) => ParsedPlaylist(
    schema:       j['schema']    as int,
    accountId:    j['accountId'] as String,
    m3uModifiedAt: DateTime.parse(j['m3uModAt'] as String),
    entries:      (j['entries'] as List)
        .map((e) => M3uEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// §secondaryCounts — Totaux par type d'une playlist.
///
/// Existe pour que les compteurs d'`AccountsPage` ne dépendent plus de la
/// présence du compte EN MÉMOIRE : ils sont écrits dans l'en-tête du cache et
/// restent donc exacts même après un déchargement.
@immutable
class PlaylistCounts {
  final int films;
  final int series;
  final int tv;

  const PlaylistCounts({
    required this.films,
    required this.series,
    required this.tv,
  });

  int get total => films + series + tv;
}
