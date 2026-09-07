/// §fleetState — Pourquoi une liste n'est pas en mémoire.
///
/// **Le défaut corrigé** : `AccountLoadState.notLoaded` recouvrait quatre
/// situations indiscernables à l'écran — jamais tenté, déchargé pour libérer
/// de la mémoire (bénin), sauté au préchargement, ré-analyse avortée. La page
/// Comptes affichait « NON CHARGÉ » dans les quatre cas, et le journal ne
/// disait rien : `setLoadState` était muet.
///
/// Ce registre vit **à côté** de `AccountLoadState`, il ne le remplace pas :
/// les 5 valeurs de l'enum pilotent déjà les chips à quatre endroits, et une
/// migration complète coûterait plus cher qu'elle ne rapporte.
library;
import '../../l10n/l10n_ext.dart';


/// Ce qui empêche une liste d'être en mémoire.
///
/// Les trois premières valeurs ne sont **pas des échecs** : ce sont des
/// situations normales qu'il faut simplement nommer autrement que « NON
/// CHARGÉ », sous peine de faire passer un fonctionnement voulu pour une panne.
enum LoadFailureKind {
  /// Jamais tenté (compte fraîchement ajouté, ou boot pas encore arrivé là).
  never,

  /// §lazyUnload — Mémoire libérée volontairement, le cache disque est intact.
  /// Le compte revient en une cinquantaine de millisecondes.
  unloadedIdle,

  /// Le budget de démarrage a été épuisé avant ce compte : il sera repris.
  deferred,

  /// Serveur injoignable, DNS, TLS, délai dépassé.
  network,

  /// Le panel a refusé pour excès de connexions simultanées.
  busy,

  /// Le catalogue est arrivé amputé (une section a échoué) — refusé à
  /// l'écriture pour ne pas écraser un catalogue complet.
  amputated,

  /// L'analyse du catalogue a échoué (fichier corrompu, format inattendu).
  parse,

  /// Le cache analysé est absent ou illisible, et rien n'a pris le relais.
  cacheGone,

  /// Aucun fichier source sur le disque, et le réseau n'était pas autorisé.
  noSource,

  /// Compte mal configuré : URL vide, identifiants inextractibles.
  badAccount,
}

/// Un échec daté et motivé, pour une liste donnée.
class LoadFailure {
  final LoadFailureKind kind;

  /// Précision courte et **sans identifiants** : « get_vod_streams : 403 »,
  /// « schéma v16 obsolète »… Passer par `describeError` ou `sanitizeForLog`
  /// pour tout texte venant du réseau.
  final String? detail;

  final DateTime at;

  const LoadFailure(this.kind, {this.detail, required this.at});

  /// Vrai pour les trois situations qui ne sont pas des pannes.
  bool get isBenign =>
      kind == LoadFailureKind.never ||
      kind == LoadFailureKind.unloadedIdle ||
      kind == LoadFailureKind.deferred;

  @override
  String toString() => 'LoadFailure(${kind.name}${detail == null ? '' : ' — $detail'})';
}

/// Libellé de chip, en français (§frOnly). Fonction **pure**, donc testable
/// sans appareil : un test exhaustif sur `LoadFailureKind.values` garantit
/// qu'aucune valeur future ne retombera sur « NON CHARGÉ ».
String labelForFailure(LoadFailureKind kind) {
  switch (kind) {
    case LoadFailureKind.never:
      return L10n.current.failNotLoaded;
    case LoadFailureKind.unloadedIdle:
      return L10n.current.failOnDisk;
    case LoadFailureKind.deferred:
      return L10n.current.failWaiting;
    case LoadFailureKind.network:
      return L10n.current.failNetwork;
    case LoadFailureKind.busy:
      return L10n.current.failPanelBusy;
    case LoadFailureKind.amputated:
      return L10n.current.failIncomplete;
    case LoadFailureKind.parse:
      return L10n.current.failParse;
    case LoadFailureKind.cacheGone:
      return L10n.current.failCacheGone;
    case LoadFailureKind.noSource:
      return L10n.current.failNoData;
    case LoadFailureKind.badAccount:
      return L10n.current.failBadAccount;
  }
}

/// Phrase complète pour l'utilisateur, sous la chip.
String describeFailure(LoadFailure f) {
  final String base = switch (f.kind) {
    LoadFailureKind.never => L10n.current.failExplainNever,
    LoadFailureKind.unloadedIdle =>
        L10n.current.failExplainUnloaded,
    LoadFailureKind.deferred => L10n.current.failExplainDeferred,
    LoadFailureKind.network => L10n.current.failExplainNetwork,
    LoadFailureKind.busy =>
        L10n.current.failExplainPanelBusy,
    LoadFailureKind.amputated =>
        L10n.current.failExplainIncomplete,
    LoadFailureKind.parse => L10n.current.failExplainParse,
    LoadFailureKind.cacheGone => L10n.current.failExplainCacheGone,
    LoadFailureKind.noSource => L10n.current.failExplainNoSource,
    LoadFailureKind.badAccount => L10n.current.failExplainBadAccount,
  };
  final String? d = f.detail;
  return (d == null || d.isEmpty) ? base : '$base $d';
}
