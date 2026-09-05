import 'package:dio/dio.dart';

import 'visual_language_service.dart';
import 'package:flutter/foundation.dart';
import '../models/tmdb_genres.dart';
import 'tmdb_api_service.dart';
import 'package:aetherStream/data/models/media_model.dart';
import 'package:aetherStream/data/models/person_model.dart';

/// Titre tendance TMDB (léger) — sert à croiser avec la playlist par titre.
/// On garde le titre localisé (fr-FR) ET le titre original (VO), car les
/// providers IPTV utilisent souvent l'un ou l'autre.
class TrendingTitle {
  final String title;
  final String? originalTitle;
  /// §trendingYear — Année de sortie TMDB (release_date / first_air_date),
  /// pour matcher la BONNE année quand la playlist a des homonymes/remakes.
  final String? year;
  const TrendingTitle({required this.title, this.originalTitle, this.year});
}

/// §personSearch — Résultat léger de `/search/person`, juste ce qu'il faut pour
/// la rangée « Personnes » (le détail complet vient ensuite de
/// `getPersonDetails` quand on ouvre la fiche).
/// §searchTmdb — Un titre trouvé sur TMDB, candidat à l'affichage dans la
/// recherche quand il est ABSENT des listes de l'utilisateur.
class TmdbTitleHit {
  final int id;
  final String title;

  /// Titre original — sert au rapprochement quand la liste d'un fournisseur
  /// utilise la VO là où TMDB rend le titre français (ou l'inverse).
  final String? originalTitle;
  final String? year;
  final String? posterPath;
  final bool isTv;
  final double popularity;

  const TmdbTitleHit({
    required this.id,
    required this.title,
    required this.isTv,
    this.originalTitle,
    this.year,
    this.posterPath,
    this.popularity = 0,
  });
}

class PersonHit {
  final int id;
  final String name;
  final String? profilePath;
  /// "Acting", "Directing", "Writing"… (`known_for_department`).
  final String? knownForDepartment;
  final double popularity;

  const PersonHit({
    required this.id,
    required this.name,
    this.profilePath,
    this.knownForDepartment,
    this.popularity = 0,
  });

  /// Métier affichable en français (null si TMDB ne le donne pas).
  String? get roleLabel => switch (knownForDepartment) {
        'Directing' => 'Réalisateur',
        'Acting' => 'Acteur',
        'Writing' => 'Scénariste',
        'Production' => 'Production',
        'Sound' => 'Musique',
        'Camera' => 'Image',
        _ => null,
      };
}

class TmdbService {
  Dio? _dio;
  String? _bearerToken;

  // §trending — Cache des tendances de la semaine (TTL 24h), keyé par isTv.
  // Vidé automatiquement au reset du singleton (changement de clé TMDB).
  final Map<bool, List<TrendingTitle>> _trendingCache = {};
  final Map<bool, DateTime> _trendingCacheAt = {};
  static const Duration _trendingTtl = Duration(hours: 24);

  /// §tmdbReco — Cache des films d'une saga (collection), keyé par collectionId.
  /// Les collections ne changent quasi jamais → cache pour la session.
  final Map<int, List<MediaRef>> _collectionCache = {};

  static TmdbService? _instance;

  /// §tmdbRows — Incrémenté à chaque `resetInstance()` (clé changée ou
  /// retirée). Les caches de cette classe meurent avec l'instance ; ce
  /// compteur permet aux mémos qui vivent AILLEURS (les rangées de l'accueil)
  /// de savoir qu'ils parlent d'une autre clé.
  static int generation = 0;
  static TmdbService get instance {
    _instance ??= TmdbService._internal();
    return _instance!;
  }

  /// §posterLang — La langue demandée à TMDB, lue À CHAQUE APPEL.
  ///
  /// ⚠️ Ne jamais la mémoriser dans un champ : le réglage change en cours de
  /// session (écran Paramètres) et ce singleton n'est pas recréé pour autant.
  /// C'est aussi pourquoi `language` a été retiré des `BaseOptions`, dont les
  /// `queryParameters` sont figés à la création du client.
  static String get _lang => VisualLanguageService.resolvedTag;

  TmdbService._internal();

  static void resetInstance() {
    generation++;
    debugPrint("💣 Forçage de la destruction du Singleton TmdbService.");
    _instance = null;
  }

  /// 📅 Extrait l'année (4 chiffres) d'une chaine brute
  String? _extractYear(String raw) {
    // Cherche 19xx ou 20xx (ex: 2024, (1999), [2005])
    final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(raw);
    return match?.group(0);
  }

  /// 🧹 Nettoyeur de nom de fichier
  String _cleanQuery(String rawName) {
    // 1. Mise en minuscule immédiate pour faciliter la comparaison
    String clean = rawName.toLowerCase();

    // --- ÉTAPE 1: Nettoyage des Préfixes IPTV & Caractères Non-Standard ---
    // Supprime un tag de pays/langue ENCADRÉ en tête (ex: |FR|, |FR-4K DV|).
    //
    // §cleanQuery — L'alternative `\w{2,}\s*[:-]` a été RETIRÉE. Elle visait
    // les préfixes non encadrés (`FR: `, `EN- `) mais matchait en réalité
    // **n'importe quel premier mot suivi de `:` ou `-`**, et décapitait donc le
    // titre juste avant de l'envoyer à TMDB :
    //   `Spider-Man : Brand New Day` → « man : brand new day »
    //   `Ong-Bak` → « bak »   ·   `Mission : Impossible 2` → « impossible 2 »
    //   `Hadestown: The Musical` → « the musical »
    //
    // Mesuré sur les 4 dumps réels (155 463 titres) : **8 259 titres amputés**,
    // dont 1 730 pour la seule liste XENO. Le retrait en récupère **8 241**.
    //
    // ⚠️ Le « coût » supposé est nul : les 276 titres que cette règle
    // nettoyait encore et que le retrait laisse passer **ne sont pas des
    // préfixes fournisseur** — ce sont de vrais titres (`ARK: The Animated
    // Series`, `BTS: Burn the Stage`, `BNA: Brand New Animal`,
    // `Arn: Tempelriddaren`). Sur 155 463 titres réels, pas UN seul préfixe
    // fournisseur de la forme `XX: ` / `XX- `. La règle ne protégeait de rien.
    //
    // ⚠️ Elle est de toute façon un vestige d'avant §providerTag : les marqueurs
    // de tête (`|FR|`, `FR| `) sont désormais extraits par `TitleMetadata.parse`
    // dans `providerTag`, donc le `displayName` qui arrive ici en est déjà purgé.
    //
    // Pourquoi ça se voyait surtout avec XENO : une entrée qui porte un
    // `tmdb_id` prend le chemin direct `getFullDetailsById` et ne passe JAMAIS
    // ici. PLATINIUM en fournit 93 % — XENO, PREMIUM et VOD **aucun** (0 %).
    // Ajouter XENO, c'est ajouter 36 000 titres qui dépendent tous de la
    // recherche par nom.
    clean = clean.replaceAll(RegExp(r'^\|.*?\|\s*', caseSensitive: false), ' ');

    // Ajout du pipe (|) aux séparateurs pour éviter qu'il ne reste seul
    clean = clean.replaceAll(RegExp(r'[|]'), ' ');

    // --- ÉTAPE 2: Supprimer les informations techniques et de langue ---
    final List<String> noiseWords = [
      // Saisons/Épisodes (Regex)
      r's\d{1,2}\s?e\d{1,2}|\d{1,2}x\d{1,2}|saison\s?\d{1,2}|episode\s?\d{1,2}', // Recherche et supprime SXXEXX, XXxXX, Saison XX, etc.

      // Qualité Vidéo & Résolutions
      '4k', 'uhd', '2160p', '1080p', '720p', '480p', 'fhd', 'hd', 'sd', 'bdrip', 'webrip',
      'hdr', 'dv', 'dvdscr', 'cam', 'ts', 'telecine', 'screener',

      // Codecs Vidéo
      'hevc', 'h.264', 'x264', 'h.265', 'x265', 'avc', 'vp9', 'divx', 'xvid', 'mpeg',

      // Codecs Audio & Formats
      'aac', 'dts', 'dtshd', 'dts-hd', 'atmos', 'truehd', 'dolby', 'ac3', 'dd5.1', 'mp3', 'flac',

      // Conteneurs
      'mkv', 'mp4', 'avi', 'ts', 'iso', 'img',

      // Langues & Groupes
      'vostfr', 'vost', 'vf', 'vo', 'vff', 'truefrench', 'multi', 'english', 'french', 'fr', 'en', 'sub',

      // Mentions Diverses (Groupes de release, versions)
      'extended', 'uncut', 'final cut', 'version longue', 'vostf', 'raw', 'repack', 'proper', 'retail', 'remux',
      'imax', 'imax enhanced', '4d', '3d', '2d'
    ];

    // Construit la Regex avec frontière de mot (\b)
    final noiseRegex = RegExp(r'\b(' + noiseWords.join('|') + r')\b', caseSensitive: true);
    clean = clean.replaceAll(noiseRegex, ' ');

    // --- ÉTAPE 3: Supprimer les séparateurs restants et l'année ---
    // Remplace les points, crochets, parenthèses, underscores, tirets par des espaces
    clean = clean.replaceAll(RegExp(r'[\.\[\]\(\)_\-]+'), ' ');

    // Supprime l'année (ex: 2024, 1999)
    clean = clean.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');

    // --- ÉTAPE 4: Nettoyage final ---
    // Supprime les espaces multiples et les espaces au début/fin
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();

    return clean;
  }

  Future<void> reinitialize() async => await _init();

  /// §tmdbKeyCheck (2026-09-05) — Demande à TMDB si une clé est acceptée,
  /// AVANT de l'enregistrer.
  ///
  /// Jusqu'ici, n'importe quelle chaîne collée donnait « TMDB connecté » : une
  /// clé mal copiée laissait une app sans affiche ni résumé, sans le moindre
  /// message. `/configuration` est l'appel le plus léger qui exige le jeton.
  ///
  /// Rend `true` (acceptée), `false` (refusée : 401), `null` (impossible de
  /// savoir : pas de réseau, délai dépassé, erreur serveur). Sur `null` on
  /// enregistre quand même — l'utilisateur est peut-être hors ligne, et la
  /// clé se vérifiera au premier usage.
  static Future<bool?> probeKey(String token) async {
    try {
      final r = await Dio(
        BaseOptions(
          baseUrl: 'https://api.themoviedb.org/3',
          headers: {
            'Authorization': 'Bearer $token',
            'accept': 'application/json',
          },
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (_) => true,
        ),
      ).get<dynamic>('/configuration');
      if (r.statusCode == 200) return true;
      if (r.statusCode == 401) return false;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _init() async {
    final String? storedToken = await TmdbApiService.getApiKey();
    if (storedToken == null || storedToken.isEmpty) {
      if (_dio != null) { _dio = null; _bearerToken = null; }
      return false;
    }
    if (_bearerToken == storedToken && _dio != null) return true;

    _bearerToken = storedToken;
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.themoviedb.org/3',
        // §posterLang — ⚠️ **`language` a été RETIRÉ d'ici.** Les
        // `queryParameters` d'un `BaseOptions` sont figés à la création du
        // client : la langue y serait restée celle du démarrage, et changer
        // le réglage n'aurait rien fait tant que le jeton TMDB ne bougeait
        // pas. Chaque appel passe désormais `_lang` explicitement.
        queryParameters: {'include_adult': 'false'},
        headers: {'Authorization': 'Bearer $_bearerToken', 'accept': 'application/json'},
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    return true;
  }

  /// 🎭 Mappe les mots-clés du group-title M3U vers des genre_ids TMDB.
  /// Utilisé pour désambiguïser les homonymes sans année (ex: anime vs live-action).
  static List<int> _groupTitleToGenreHints(String groupTitle) {
    final g = groupTitle.toUpperCase();
    final hints = <int>[];
    // Animation / Manga — id 16 (commun films ET séries TMDB)
    if (g.contains('MANGA') || g.contains('ANIME') || g.contains('ANIMÉ') ||
        g.contains('ANIMAT') || g.contains('CARTOON')) {
      hints.add(16);
    }
    // Documentaire
    if (g.contains('DOCU')) hints.add(99);
    // Comédie
    if (g.contains('COMÉD') || g.contains('COMED') || g.contains('HUMOUR')) hints.add(35);
    // Horreur
    if (g.contains('HORREUR') || g.contains('HORROR') || g.contains('ÉPOUVANTE')) hints.add(27);
    // Action (28 = film, 10759 = TV)
    if (g.contains('ACTION')) hints.addAll([28, 10759]);
    // Science-fiction (878 = film, 10765 = TV)
    if (g.contains('SCI-FI') || g.contains('SCIENCE-FI') || g.contains('SF ') ||
        g.contains(' SF') || g.contains('SCIFI')) {
      hints.addAll([878, 10765]);
    }
    // Fantastique (14 = film, 10765 = TV)
    if (g.contains('FANTAST') || g.contains('FANTASY')) hints.addAll([14, 10765]);
    // Famille / Enfants
    if (g.contains('FAMIL') || g.contains('ENFANT') || g.contains('KIDS')) {
      hints.addAll([10751, 10762]);
    }
    // Romance
    if (g.contains('ROMAN') || g.contains('ROMANCE')) hints.add(10749);
    // Thriller
    if (g.contains('THRILLER')) hints.add(53);
    // Drame
    if (g.contains('DRAME') || g.contains('DRAMA')) hints.add(18);
    // Western
    if (g.contains('WESTERN')) hints.add(37);
    // Crime
    if (g.contains('CRIME') || g.contains('POLICIER') || g.contains('POLAR')) hints.add(80);
    return hints;
  }

  /// 🧠 SMART SEARCH V3 : Langue + Type + ANNÉE + GENRE
  /// [explicitYear] : année déjà extraite par TitleMetadata (prioritaire sur l'extraction depuis rawQuery).
  /// [groupTitle]   : group-title M3U → converti en hints de genre pour désambiguïser les homonymes.
  /// Permet de désambiguïser les homonymes (ex: One Piece anime 1999 vs live-action 2023).
  /// §23c — Détails EXACTS par ID TMDB fourni par le provider (`tmdb_id` des
  /// catalogues JSON player_api). Court-circuite la recherche floue par titre,
  /// qui pouvait verrouiller un homonyme ("Michael" → "Michael Collins",
  /// série "H" → "M.A.S.H"). Retourne `null` si l'ID est invalide côté TMDB
  /// (l'appelant retombe alors sur [getFullDetails]).
  Future<Media?> getFullDetailsById(int id, {required bool isTv}) async {
    if (!await _init()) return null;
    try {
      debugPrint('🎯 TMDB byId: $id (${isTv ? 'TV' : 'Film'}) — ID provider, zéro ambiguïté');
      final detailResponse = await _dio!.get(
        isTv ? '/tv/$id' : '/movie/$id',
        queryParameters: {
          'language': _lang,
          // §tmdbReco — recommandations + (films) belongs_to_collection dans la
          // MÊME réponse (zéro appel réseau en plus pour les « similaires »).
          // §tmdbBadges — release_dates (films) / content_ratings (séries) pour
          // la certification d'âge (badge « 12 », « 16 », « TP »…).
          'append_to_response':
              'credits,videos,recommendations,release_dates,content_ratings',
        },
      );
      return Media.fromJson(detailResponse.data);
    } catch (e) {
      debugPrint('⚠️ TMDB byId($id, isTv=$isTv) échec : $e — fallback recherche titre');
      return null;
    }
  }

  /// §tmdbReco — Films d'une saga/collection TMDB (`/collection/{id}` → `parts`),
  /// triés par date de sortie. Cachés pour la session. Liste vide si pas de clé
  /// ou échec.
  Future<List<MediaRef>> getCollectionTitles(int collectionId) async {
    final cached = _collectionCache[collectionId];
    if (cached != null) return cached;
    if (!await _init()) return const [];
    try {
      final resp = await _dio!.get('/collection/$collectionId',
          queryParameters: {'language': _lang});
      final parts = (resp.data['parts'] as List<dynamic>?) ?? const [];
      final list = <MediaRef>[];
      for (final p in parts) {
        if (p is! Map<String, dynamic>) continue;
        final pid = p['id'] as int?;
        final ptitle = (p['title'] ?? p['name']) as String?;
        if (pid == null || ptitle == null || ptitle.isEmpty) continue;
        final pdate = (p['release_date'] ?? p['first_air_date']) as String?;
        list.add(MediaRef(
          id: pid,
          title: ptitle,
          year:
              (pdate != null && pdate.length >= 4) ? pdate.substring(0, 4) : null,
        ));
      }
      // Tri par année croissante (ordre chronologique de la saga).
      list.sort((a, b) => (a.year ?? '9999').compareTo(b.year ?? '9999'));
      _collectionCache[collectionId] = list;
      return list;
    } catch (e) {
      debugPrint('⚠️ TMDB collection($collectionId) échec : $e');
      return const [];
    }
  }

  Future<Media?> getFullDetails(String rawQuery, {required bool isTv, String? explicitYear, String? groupTitle}) async {
    if (!await _init()) return null;

    // 1. Détections Préalables
    final bool appearsEnglish = RegExp(r'\b(VO|VOST|VOSTFR|ENGLISH)\b', caseSensitive: false).hasMatch(rawQuery);
    final String searchLanguage = appearsEnglish ? 'en-US' : _lang;

    // 📅 Extraction de l'année (Crucial pour les homonymes)
    // L'année explicite (issue de TitleMetadata) est prioritaire — elle est déjà proprement parsée.
    // Fallback : extraction depuis rawQuery (cas où getFullDetails est appelé sans contexte).
    final String? year = explicitYear ?? _extractYear(rawQuery);

    // 2. Nettoyage
    final cleanQuery = _cleanQuery(rawQuery);

    // 🎭 Hints de genre issus du group-title (pour désambiguïser sans année)
    final List<int> genreHints = groupTitle != null ? _groupTitleToGenreHints(groupTitle) : [];
    debugPrint("🔍 Scan TMDB | Titre: '$cleanQuery' | Année: ${year ?? 'N/A'} | Lang: $searchLanguage | Genre hints: $genreHints");

    try {
      Map<String, dynamic>? result;

      // --- PHASES 1 à 4 (Recherche avec/sans année, inversion type, fallback langue) ---

      // Tente 1: Strict (Année + Type)
      if (year != null) {
        result = await _performSearch(cleanQuery, isTv: isTv, language: searchLanguage, year: year, genreHints: genreHints);
      }

      // Tente 2: Souple (Type seul, genre hints actifs)
      if (result == null) {
        if (year != null) debugPrint("⚠️ Pas de match avec l'année $year. Tentative sans année...");
        result = await _performSearch(cleanQuery, isTv: isTv, language: searchLanguage, genreHints: genreHints);
      }

      // Tente 3: Fallback Type
      if (result == null) {
        debugPrint("! Bascule de type (TV <-> Film)...");
        if (year != null) {
          result = await _performSearch(cleanQuery, isTv: !isTv, language: searchLanguage, year: year, genreHints: genreHints);
        }
        result ??= await _performSearch(cleanQuery, isTv: !isTv, language: searchLanguage, genreHints: genreHints);
      }

      // Tente 4: Fallback Langue Ultime (sans genre hints — dernier recours)
      if (result == null && appearsEnglish) {
        debugPrint("⚠️ Échec VO. Tentative repli FR...");
        result = await _performSearch(cleanQuery, isTv: isTv, language: _lang);
      }

      if (result == null) {
        debugPrint("❌ ECHEC TOTAL : '$cleanQuery' introuvable.");
        return null;
      }

      // --- SUCCÈS : Téléchargement Détails + Extras (credits, videos) ---
      final int id = result['id'];
      final bool foundAsTv = result['media_type'] == 'tv';

      debugPrint("🎯 Cible verrouillée : ID $id (${foundAsTv ? 'TV' : 'Film'}). Demande d'extras (Cast, Trailer)...");

      final detailEndpoint = foundAsTv ? '/tv/$id' : '/movie/$id';

      // 🎯 NOUVEAU : AJOUT DE APPEND_TO_RESPONSE
      final detailResponse = await _dio!.get(
          detailEndpoint,
          queryParameters: {
            'language': _lang,
            // §tmdbMore — aligné sur getFullDetailsById : ce chemin fallback
            // (recherche par titre, sans tmdb_id provider) perdait sinon les
            // recommandations ET la certification d'âge. `credits` porte
            // aussi `crew` → réalisateur (§directorView).
            'append_to_response':
                'credits,videos,recommendations,release_dates,content_ratings',
          }
      );

      // Le parsing de ces nouveaux champs (cast, trailerKey) doit être fait dans Media.fromJson
      return Media.fromJson(detailResponse.data);

    } catch (e) {
      debugPrint("❌ Glitch TMDB : $e");
      return null;
    }
  }

  Future<int?> getPersonId(String query) async {
    if (!await _init()) return null;

    try {
      debugPrint("🔎 Recherche ID personne pour : '$query'");
      final response = await _dio!.get('/search/person', queryParameters: {
        'query': query,
        'language': _lang, // Recherche de nom dans le langage ciblé
      });

      if (response.data['results'].isNotEmpty) {
        return response.data['results'][0]['id'] as int;
      }
    } catch (e) {
      debugPrint("❌ Erreur recherche personne : $e");
    }
    return null;
  }

  /// §personSearch — Recherche de PERSONNES (acteurs, réalisateurs…) pour la
  /// rangée « Personnes » des résultats de recherche.
  ///
  /// Différence avec [getPersonId] (qui ne rend que le 1er id) : on expose la
  /// LISTE avec ce qu'il faut pour l'afficher (nom, photo, métier). Trié par
  /// popularité décroissante, plafonné à [limit].
  /// Contrat maison : jamais d'exception, `const []` sans clé TMDB.
  /// §searchByPerson — Mémo d'UNE entrée : la rangée « Personnes » et la
  /// rangée « … dans tes listes » interrogent la même requête à la même
  /// frappe. Sans ça, chaque caractère tapé partait en double sur le réseau.
  String? _lastPersonQuery;
  List<PersonHit> _lastPersonHits = const [];

  Future<List<PersonHit>> searchPersons(String query, {int limit = 10}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    if (q == _lastPersonQuery) return _lastPersonHits;
    if (!await _init()) return const [];

    try {
      final response = await _dio!.get('/search/person', queryParameters: {
        'query': q,
        'language': _lang,
      });
      final results = (response.data?['results'] as List<dynamic>?) ?? const [];
      final hits = <PersonHit>[];
      for (final r in results) {
        if (r is! Map) continue;
        final id = r['id'];
        final name = r['name'];
        if (id is! int || name is! String || name.isEmpty) continue;
        hits.add(PersonHit(
          id: id,
          name: name,
          profilePath: r['profile_path'] as String?,
          knownForDepartment: r['known_for_department'] as String?,
          popularity: (r['popularity'] as num?)?.toDouble() ?? 0,
        ));
      }
      hits.sort((a, b) => b.popularity.compareTo(a.popularity));
      if (hits.length > limit) hits.length = limit;
      _lastPersonQuery = q;
      _lastPersonHits = hits;
      return hits;
    } catch (e) {
      debugPrint('❌ §personSearch — recherche personne échouée : $e');
      return const [];
    }
  }

  /// §searchTmdb — Recherche de TITRES (films et séries en un seul appel).
  ///
  /// Sert à montrer ce qui existe **mais n'est dans aucune liste** : sans ça,
  /// rien ne distingue « ça n'existe pas » de « tu ne l'as pas ».
  ///
  /// ⚠️ `/search/multi` retourne aussi des PERSONNES : elles sont écartées
  /// ici, la rangée « Personnes » (§personSearch) les traite déjà et les
  /// afficher deux fois n'apprendrait rien.
  ///
  /// ⚠️ Tri par popularité : TMDB rend volontiers des obscurités homonymes en
  /// tête. Sur une rangée de quelques vignettes, montrer d'abord ce que
  /// l'utilisateur avait probablement en tête est ce qui compte.
  Future<List<TmdbTitleHit>> searchTitles(String query, {int limit = 12}) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    if (!await _init()) return const [];

    try {
      final response = await _dio!.get('/search/multi', queryParameters: {
        'query': q,
        'language': _lang,
        'include_adult': 'false',
      });
      final results = (response.data?['results'] as List<dynamic>?) ?? const [];
      final hits = <TmdbTitleHit>[];
      for (final r in results) {
        if (r is! Map) continue;
        final mediaType = r['media_type'];
        final isTv = mediaType == 'tv';
        if (!isTv && mediaType != 'movie') continue; // personnes écartées
        final id = r['id'];
        final title = (isTv ? r['name'] : r['title']) as String?;
        if (id is! int || title == null || title.isEmpty) continue;
        final rawDate = (isTv ? r['first_air_date'] : r['release_date']) as String?;
        hits.add(TmdbTitleHit(
          id: id,
          title: title,
          originalTitle:
              (isTv ? r['original_name'] : r['original_title']) as String?,
          year: (rawDate != null && rawDate.length >= 4)
              ? rawDate.substring(0, 4)
              : null,
          posterPath: r['poster_path'] as String?,
          isTv: isTv,
          popularity: (r['popularity'] as num?)?.toDouble() ?? 0,
        ));
      }
      hits.sort((a, b) => b.popularity.compareTo(a.popularity));
      if (hits.length > limit) hits.length = limit;
      return hits;
    } catch (e) {
      debugPrint('❌ §searchTmdb — recherche de titres échouée : $e');
      return const [];
    }
  }

  Future<Person?> getPersonDetails(int personId) async {
    if (!await _init()) return null;

    final endpoint = '/person/$personId';

    try {
      debugPrint("🎬 Demande détails acteur ID: $personId + filmographie.");
      final response = await _dio!.get(
          endpoint,
          queryParameters: {
            'language': _lang,
            'append_to_response': 'combined_credits' // Filmographie (films et séries)
          }
      );

      return Person.fromJson(response.data);

    } catch (e) {
      debugPrint("❌ Erreur récupération détails acteur : $e");
      return null;
    }
  }

  /// Détails d'un épisode précis : identifie la série, puis récupère l'épisode.
  /// [tmdbId] : ID TMDB exact fourni par le provider (§23c) — PRIORITAIRE, la
  /// recherche floue par nom ne sert plus que de fallback (elle verrouillait
  /// des homonymes / renvoyait null sur année fausse → synopsis d'épisode vide
  /// alors que film/série utilisaient déjà l'id exact via getFullDetailsById).
  /// [groupTitle] : group-title M3U transmis pour désambiguïser la série (ex: "MANGAS" → genre Animation).
  Future<Map<String, dynamic>?> getEpisodeDetails(
    String showQuery,
    int seasonNumber,
    int episodeNumber, {
    int? tmdbId,
    String? yearFilter,
    String? groupTitle,
  }) async {
    if (!await _init()) return null;

    Future<Map<String, dynamic>?> fetchEpisode(int id) async {
      final resp = await _dio!.get(
        '/tv/$id/season/$seasonNumber/episode/$episodeNumber',
        queryParameters: {
          'language': _lang,
          'append_to_response': 'credits,images,videos',
        },
      );
      if (resp.statusCode == 200) {
        return resp.data as Map<String, dynamic>?;
      }
      return null;
    }

    // 1. ID provider exact — zéro recherche floue.
    if (tmdbId != null && tmdbId > 0) {
      try {
        final data = await fetchEpisode(tmdbId);
        if (data != null) return data;
        // ID invalide côté TMDB (404…) → on retombe sur la recherche par nom.
      } catch (e) {
        debugPrint('⚠️ Épisode TMDB par id $tmdbId KO — fallback recherche : $e');
      }
    }

    // 2. Fallback : recherche floue par nom (comportement historique).
    final List<int> genreHints = groupTitle != null ? _groupTitleToGenreHints(groupTitle) : [];
    try {
      final searchResult = await _performSearch(
        showQuery,
        isTv: true,
        language: _lang,
        year: yearFilter,
        genreHints: genreHints,
      );
      if (searchResult == null) return null;
      final id = searchResult['id'] as int;
      return await fetchEpisode(id);
    } catch (e) {
      debugPrint("❌ Erreur récupération épisode TMDB : $e");
    }
    return null;
  }

  /// Recherche atomique avec paramètres optionnels.
  /// [genreHints] : liste de genre_ids TMDB préférés — si non vide, on regarde jusqu'à 5 résultats
  ///               et on préfère le premier dont les genres matchent. Fallback sur results[0].
  Future<Map<String, dynamic>?> _performSearch(String query, {
    required bool isTv,
    required String language,
    String? year,
    List<int> genreHints = const [],
  }) async {
    try {
      final endpoint = isTv ? '/search/tv' : '/search/movie';

      final params = <String, dynamic>{
        'query': query,
        'language': language,
      };

      if (year != null) {
        if (isTv) {
          params['first_air_date_year'] = year;
        } else {
          params['year'] = year;
        }
      }

      final response = await _dio!.get(endpoint, queryParameters: params);

      if (response.statusCode == 200) {
        final results = response.data['results'] as List?;
        if (results == null || results.isEmpty) return null;

        Map<String, dynamic>? best;

        // Désambiguïsation par genre : on parcourt jusqu'à 5 résultats
        if (genreHints.isNotEmpty) {
          for (final r in results.take(5)) {
            final genres = ((r as Map)['genre_ids'] as List?)?.cast<int>() ?? [];
            if (genres.any(genreHints.contains)) {
              best = r.cast<String, dynamic>();
              debugPrint("🎭 Genre match: '${r['name'] ?? r['title']}' genres=$genres hints=$genreHints");
              break;
            }
          }
        }

        final item = (best ?? results[0]) as Map<String, dynamic>;
        item['media_type'] = isTv ? 'tv' : 'movie';
        return item;
      }
    } catch (_) {}
    return null;
  }

  static String? getPosterUrl(String? path, {String size = 'w500'}) {
    if (path == null || path.isEmpty) return null;
    return 'https://image.tmdb.org/t/p/$size$path';
  }

  /// 🖼️ Recherche LÉGÈRE : ne renvoie que l'URL de l'affiche (aucun appel
  /// `append_to_response` credits/videos). Utilisée comme fallback pour les
  /// entrées dont le M3U ne fournit pas de `tvg-logo` (cas liste Ultimate :
  /// VOD sans poster). Réutilise la smart search (année → souple → bascule type)
  /// mais s'arrête au premier résultat et n'en extrait que `poster_path`.
  /// §inferredCat — Renvoie l'affiche **et** la catégorie déduite des
  /// `genre_ids` du résultat.
  ///
  /// Le genre était déjà dans la réponse et partait à la poubelle. Le récupérer
  /// ne coûte aucune requête supplémentaire, et c'est la seule source de
  /// rangement disponible pour les listes qui n'en fournissent aucune (format
  /// « Ultimate » : ni `group-title`, ni catalogue JSON).
  Future<({String? posterUrl, String? category})> fetchPosterAndGenre({
    required String query,
    required bool isTv,
    String? year,
    String? groupTitle,
    String size = 'w342',
  }) async {
    const empty = (posterUrl: null, category: null);
    if (!await _init()) return empty;
    final clean = _cleanQuery(query);
    if (clean.isEmpty) return empty;

    final bool appearsEnglish =
        RegExp(r'\b(VO|VOST|VOSTFR|ENGLISH)\b', caseSensitive: false).hasMatch(query);
    final String lang = appearsEnglish ? 'en-US' : _lang;
    final List<int> hints = groupTitle != null ? _groupTitleToGenreHints(groupTitle) : const [];

    try {
      Map<String, dynamic>? r;
      if (year != null) {
        r = await _performSearch(clean, isTv: isTv, language: lang, year: year, genreHints: hints);
      }
      r ??= await _performSearch(clean, isTv: isTv, language: lang, genreHints: hints);
      r ??= await _performSearch(clean, isTv: !isTv, language: lang, genreHints: hints);
      if (r == null) return empty;
      final ids = (r['genre_ids'] as List?)?.whereType<int>().toList() ?? const <int>[];
      return (
        posterUrl: getPosterUrl(r['poster_path'] as String?, size: size),
        category: tmdbGenreLabel(ids),
      );
    } catch (e) {
      debugPrint("❌ Glitch TMDB (poster fallback) : $e");
      return empty;
    }
  }

  /// 🔥 §trending — Tendances de la semaine TMDB (`/trending/{movie|tv}/week`).
  /// Retourne la liste des titres classés par popularité (ordre conservé pour
  /// le carrousel). Cache mémoire 24h par type. Retourne `[]` si pas de clé
  /// TMDB ou en cas d'erreur réseau (dégradation silencieuse).
  Future<List<TrendingTitle>> getTrending({required bool isTv}) async {
    if (!await _init()) return const [];

    final cached = _trendingCache[isTv];
    final at = _trendingCacheAt[isTv];
    if (cached != null && at != null &&
        DateTime.now().difference(at) < _trendingTtl) {
      return cached;
    }

    try {
      final path = isTv ? '/trending/tv/week' : '/trending/movie/week';
      // ⚠️ §posterLang avait sorti `language` des `BaseOptions` (figés) et
      // cet appel n'en passait pas : les tendances revenaient en anglais, et
      // le croisement par titre avec des listes françaises ne trouvait plus
      // que les films à titre original anglais. Corrigé le 2026-09-05.
      final resp = await _dio!.get(path, queryParameters: {'language': _lang});
      final list = _parseTitles(resp.data['results'] as List?, isTv);
      _trendingCache[isTv] = list;
      _trendingCacheAt[isTv] = DateTime.now();
      return list;
    } catch (e) {
      debugPrint('❌ TMDB trending (isTv=$isTv) : $e');
      return cached ?? const [];
    }
  }

  /// Les champs qui servent au croisement avec la playlist : titre localisé,
  /// titre original, année. Partagé par les tendances et les rangées §tmdbRows.
  static List<TrendingTitle> _parseTitles(List? results, bool isTv) {
    final list = <TrendingTitle>[];
    for (final r in results ?? const []) {
      if (r is! Map<String, dynamic>) continue;
      final title = (isTv ? r['name'] : r['title']) as String?;
      final original =
          (isTv ? r['original_name'] : r['original_title']) as String?;
      // §trendingYear — "YYYY-MM-DD" → année (4 premiers chars). Peut être
      // absente/vide (films à venir sans date) → year null.
      final rawDate =
          (isTv ? r['first_air_date'] : r['release_date']) as String?;
      final year = (rawDate != null && rawDate.length >= 4)
          ? rawDate.substring(0, 4)
          : null;
      if (title != null && title.trim().isNotEmpty) {
        list.add(TrendingTitle(
            title: title, originalTitle: original, year: year));
      }
    }
    return list;
  }

  // ── §tmdbRows (2026-09-05) — Rangées éditoriales ──────────────────────────
  //
  // Pourquoi des RANGÉES et pas une taxonomie : classer tout le catalogue par
  // TMDB coûterait une recherche par titre (des dizaines de milliers d'appels
  // sur 120 000 entrées, ce que TMDB demande d'éviter) et ne marcherait
  // qu'avec une clé. Ici, un appel rend 20 titres qu'on croise avec la
  // playlist : « Parce que tu as regardé X », « Les mieux notés ». Cache 24 h.
  final Map<String, List<TrendingTitle>> _rowsCache = {};
  final Map<String, DateTime> _rowsCacheAt = {};

  /// Recommandations TMDB d'un titre (`/movie|tv/{id}/recommendations`).
  Future<List<TrendingTitle>> getRecommendations({
    required int tmdbId,
    required bool isTv,
  }) =>
      _cachedTitles(
        'rec/$isTv/$tmdbId',
        isTv,
        '/${isTv ? 'tv' : 'movie'}/$tmdbId/recommendations',
      );

  /// Les mieux notés (`/movie|tv/top_rated`, première page).
  Future<List<TrendingTitle>> getTopRated({required bool isTv}) =>
      _cachedTitles('top/$isTv', isTv, '/${isTv ? 'tv' : 'movie'}/top_rated');

  Future<List<TrendingTitle>> _cachedTitles(
      String key, bool isTv, String path) async {
    if (!await _init()) return const [];
    final cached = _rowsCache[key];
    final at = _rowsCacheAt[key];
    if (cached != null && at != null &&
        DateTime.now().difference(at) < _trendingTtl) {
      return cached;
    }
    try {
      final resp =
          await _dio!.get(path, queryParameters: {'language': _lang});
      final list = _parseTitles(resp.data['results'] as List?, isTv);
      _rowsCache[key] = list;
      _rowsCacheAt[key] = DateTime.now();
      return list;
    } catch (e) {
      debugPrint('❌ TMDB rangée $key : $e');
      return cached ?? const [];
    }
  }

  /// §tmdbRows — L'identifiant TMDB d'un titre de la playlist qui n'en porte
  /// pas (listes M3U sans `tmdb_id`). Une recherche, mémorisée par le cache
  /// de `_performSearch` côté Dio. `null` si introuvable ou sans clé.
  Future<int?> resolveTmdbId({
    required String query,
    required bool isTv,
    String? year,
  }) async {
    if (!await _init()) return null;
    final clean = _cleanQuery(query);
    if (clean.isEmpty) return null;
    try {
      Map<String, dynamic>? r;
      if (year != null) {
        r = await _performSearch(clean, isTv: isTv, language: _lang, year: year);
      }
      r ??= await _performSearch(clean, isTv: isTv, language: _lang);
      return r?['id'] as int?;
    } catch (_) {
      return null;
    }
  }
}
