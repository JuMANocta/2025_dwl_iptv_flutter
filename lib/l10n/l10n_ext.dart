import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// §l10nAll (2026-09-05) — **Tranche 0 : de quoi traduire sans friction.**
///
/// **Le constat qui a motivé ce fichier.** L'app compte ≈ 872 lignes de textes
/// français écrits en dur pour **116 clés** traduites, et seulement 19 fichiers
/// sur 159 appellent `AppLocalizations`. La cause n'est pas la paresse : écrire
/// `AppLocalizations.of(context)!.foo` à chaque fois est assez pénible pour
/// qu'on écrive la chaîne directement. On raccourcit donc le geste avant de
/// demander à qui que ce soit de le répéter 872 fois.
extension L10nX on BuildContext {
  /// Les textes traduits. `context.l10n.settingsTitle` au lieu de
  /// `AppLocalizations.of(context)!.settingsTitle`.
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

/// §l10nAll — **Les textes pour ce qui n'a pas de `BuildContext`.**
///
/// Une bonne partie des messages destinés à l'utilisateur ne naît pas dans un
/// widget : `describeError()`, `CastService`, `DownloadManagerService`,
/// `ParsedPlaylistService`. Ils ne peuvent pas appeler `AppLocalizations.of`.
///
/// ⚠️ **Deux pièges à ne jamais oublier ici :**
/// - **§isolateLeak** — ne JAMAIS lire `L10n.current` dans une fermeture passée
///   à `Isolate.run`. Un isolate n'a pas ce binding, et la fermeture
///   emporterait tout le contexte avec elle. Construire le message APRÈS le
///   retour de l'isolate.
/// - **§userErrorOwn** — un message déjà écrit pour l'utilisateur
///   (`UserFacingException`) se construit traduit **au point de lancement** et
///   ne doit jamais être retraduit ensuite.
abstract final class L10n {
  static AppLocalizations? _bound;

  /// Appelé une fois par frame depuis le `builder` de `MaterialApp`, où un
  /// `BuildContext` sous `Localizations` est disponible.
  static void bind(AppLocalizations value) => _bound = value;

  /// Les textes traduits, hors widget.
  ///
  /// Repli sur le français si le binding n'a pas encore eu lieu (message émis
  /// avant la première frame) : mieux vaut une phrase en français qu'une
  /// exception dans un chemin d'erreur — c'est justement là que ces messages
  /// servent le plus.
  static AppLocalizations get current =>
      _bound ?? lookupAppLocalizations(const Locale('fr'));

  /// Tests uniquement.
  @visibleForTesting
  static void resetForTest() => _bound = null;
}
