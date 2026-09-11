import '../../data/services/load_failure.dart';
import '../../data/services/xtream_api_service.dart';
import '../../l10n/app_localizations.dart';

/// Revue 2026-09-11, D4A-06 / D1A-07 — **Ce que la fiche montre** quand les
/// épisodes d'une série n'ont pas pu être chargés.
///
/// **Le défaut corrigé** : la fiche interpolait tel quel le motif produit par
/// le service (« serveur injoignable », « délai dépassé », « HTTP 503 »,
/// « identifiants Xtream inextractibles »…) dans une phrase traduite. Sur un
/// téléphone en anglais : « Episodes not loaded — serveur injoignable. » — une
/// violation de §l10nAll, et de §clientText (« HTTP 503 » est de la mécanique).
///
/// Désormais l'état de la fiche porte une NATURE d'échec, et le texte n'est
/// composé qu'à l'affichage, dans la langue de l'écran. Le motif français du
/// service ([episodesFailureReason]) reste le texte du JOURNAL.
enum EpisodesFailure {
  /// L'URL du stub ne porte pas d'identifiant de série lisible (constaté par
  /// la fiche elle-même).
  badSeriesId,

  /// Le compte du stub n'existe plus (constaté par la fiche elle-même).
  noAccount,

  /// Compte mal configuré (URL, identifiants).
  badAccount,

  /// Serveur injoignable, délai dépassé, erreur HTTP.
  network,

  /// Le fournisseur refuse pour excès de connexions.
  busy,

  /// Réponse reçue mais illisible.
  parse,
}

/// La nature d'échec à montrer pour une [LoadFailureKind] du service.
EpisodesFailure episodesFailureForKind(LoadFailureKind? kind) {
  switch (kind) {
    case LoadFailureKind.busy:
      return EpisodesFailure.busy;
    case LoadFailureKind.parse:
    case LoadFailureKind.amputated:
      return EpisodesFailure.parse;
    case LoadFailureKind.badAccount:
      return EpisodesFailure.badAccount;
    default:
      return EpisodesFailure.network;
  }
}

/// Verdict À AFFICHER d'un fetch réparti sur plusieurs comptes.
///
/// Même règle que [episodesFailureReason] (§episodeTruth) : dès qu'un compte a
/// répondu — même avec zéro épisode — il n'y a pas de panne à signaler. Sinon,
/// le premier échec l'emporte.
///
/// [local] donne, résultat par résultat, l'échec constaté par la fiche
/// elle-même avant tout appel réseau (`null` quand le service a été appelé) :
/// il prime, car la [LoadFailureKind] seule ne distingue pas « identifiant
/// illisible » de « compte introuvable ».
EpisodesFailure? episodesFailureOf(
  List<XtreamEpisodesResult> results, {
  List<EpisodesFailure?> local = const <EpisodesFailure?>[],
}) {
  if (results.isEmpty) return null;
  if (results.any((r) => r.episodes != null)) return null;
  for (int i = 0; i < results.length; i++) {
    final EpisodesFailure? own = i < local.length ? local[i] : null;
    if (own != null) return own;
    final LoadFailureKind? kind = results[i].kind;
    if (kind != null) return episodesFailureForKind(kind);
  }
  return EpisodesFailure.network;
}

/// Le motif, dans la langue de l'écran — à glisser dans `detEpisodesError`.
String episodesFailureText(AppLocalizations l, EpisodesFailure f) {
  switch (f) {
    case EpisodesFailure.badSeriesId:
      return l.detEpisodesBadSeriesId;
    case EpisodesFailure.noAccount:
      return l.detEpisodesNoAccount;
    case EpisodesFailure.badAccount:
      return l.detEpisodesReasonAccount;
    case EpisodesFailure.network:
      return l.detEpisodesReasonNetwork;
    case EpisodesFailure.busy:
      return l.detEpisodesReasonBusy;
    case EpisodesFailure.parse:
      return l.detEpisodesReasonParse;
  }
}
