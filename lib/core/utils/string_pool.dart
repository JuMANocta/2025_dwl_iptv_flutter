/// §ramDiet — Internement de chaînes, à durée de vie d'UN chargement.
///
/// ## Le problème mesuré
///
/// Une playlist réelle compte ~350 000 entrées. Sur chacune, des champs
/// **fortement répétitifs** — `groupTitle`, `category`, `genre`, `quality`,
/// `versionLabel`, `providerTag`, `accountId`, les langues — ne prennent en
/// pratique que quelques centaines de valeurs distinctes.
///
/// Or ni `jsonDecode` ni `TitleMetadata.parse` ne partagent quoi que ce soit :
/// chaque entrée alloue SA propre copie de « Films | Action », de « FHD », de
/// l'identifiant de compte… 350 000 fois. Ces copies ne sont pas transitoires,
/// elles restent **résidentes** tant que la playlist est en mémoire — c'est-à-
/// dire toute la vie de l'application.
///
/// ## Ce que fait ce pool
///
/// `of(s)` renvoie l'instance **canonique** de `s` : la première rencontrée.
/// Toutes les entrées suivantes portant la même valeur pointent alors sur le
/// même objet au lieu d'en allouer un. Le contenu ne change pas d'un
/// caractère : `==` et `hashCode` d'une `String` Dart sont structurels, donc
/// rien en aval ne peut faire la différence.
///
/// ⚠️ **Aucun bump de `schemaVersion`** : ni le texte des champs ni les clés de
/// regroupement ne bougent. Interner, c'est partager une copie, pas la modifier.
///
/// ## Durée de vie
///
/// Le pool est **local à un parsing** et jeté ensuite. Sa table disparaît, mais
/// les chaînes canoniques restent — retenues par les entrées qui les utilisent.
/// Un pool statique, lui, retiendrait à vie les chaînes de listes déchargées.
class StringPool {
  final Map<String, String>? _map;

  /// Pool actif : à créer pour la durée d'un parsing, puis à laisser mourir.
  StringPool() : _map = <String, String>{};

  /// Pool inerte : `of` rend son argument tel quel. Sert de valeur par défaut
  /// aux chemins où l'internement n'a rien à gagner — parsing d'un titre isolé
  /// (`DetailsPage`, `XtreamApiService`), tests unitaires.
  const StringPool.disabled() : _map = null;

  /// Valeur par défaut de tous les paramètres `pool` du modèle.
  static const StringPool none = StringPool.disabled();

  /// Au-delà de ce nombre de valeurs DISTINCTES, on cesse d'alimenter la table.
  ///
  /// Garde-fou contre le cas dégénéré : si un fournisseur écrit un `group-title`
  /// unique par entrée, la table grossirait jusqu'à une entrée par ligne — soit
  /// la mémoire qu'on cherchait à économiser, plus le coût de la table. Passé ce
  /// seuil, le champ n'est manifestement pas répétitif et l'internement ne peut
  /// plus rien rapporter ; les valeurs déjà mémorisées continuent d'être
  /// partagées, les nouvelles passent en direct.
  static const int maxDistinct = 20000;

  /// L'instance canonique de [s] (`null` reste `null`).
  String? of(String? s) {
    if (s == null) return null;
    final map = _map;
    if (map == null) return s;
    final canonical = map[s];
    if (canonical != null) return canonical;
    if (map.length >= maxDistinct) return s;
    map[s] = s;
    return s;
  }

  /// Variante liste — pour `TitleMetadata.languages`, où chaque entrée
  /// reconstruisait sa propre `['VF']`.
  ///
  /// Renvoie `const []` quand il n'y a rien : une liste vide littérale est elle
  /// aussi une allocation, et il y en avait une par entrée sans langue.
  List<String> ofList(List<String> items) {
    if (items.isEmpty) return const [];
    return List<String>.generate(items.length, (i) => of(items[i])!,
        growable: false);
  }

  /// Nombre de valeurs distinctes mémorisées — pour les journaux de parsing.
  int get distinct => _map?.length ?? 0;
}
