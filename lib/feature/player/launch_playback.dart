/// §dlPlayLocal (2026-09-16) — Le point d'entrée UNIQUE d'une lecture VOD ou
/// d'épisode.
///
/// **Pourquoi il existe.** Quatre endroits poussaient `PlayerPage` avec
/// `entry.url` : la fiche, l'enchaînement d'épisode, la feuille d'appui long
/// et la carte de l'accueil. Aucun ne regardait les téléchargements — un
/// épisode téléchargé ne se lisait hors ligne que depuis l'onglet
/// Téléchargements, jamais depuis sa propre fiche. Quatre copies d'une même
/// règle, c'est quatre occasions de diverger (§detailsLive l'a déjà montré) :
/// la règle vit ici, les quatre appelants s'y branchent.
///
/// **Ce que ce fichier décide** : le CHEMIN et la SOURCE. Rien d'autre. Le
/// titre, les badges, les clés de reprise, l'épisode suivant, la position de
/// départ restent construits par l'appelant et traversent inchangés — c'est le
/// sens du `build` passé en paramètre plutôt que d'une liste de champs
/// recopiée : un champ ajouté à `PlayerPage` ne peut pas se perdre en route.
///
/// ⚠️ La porte §deviceCaps (`PlaybackGate.allow`) reste chez l'appelant : la
/// feuille d'appui long se referme AVANT d'y passer et doit le faire sur le
/// navigateur racine, son propre contexte étant mort.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/themes/colors.dart';
import '../../data/models/account_info.dart';
import '../../data/models/download_task.dart';
import '../../data/models/stream_account.dart';
import '../../data/services/download_manager_service.dart';
import '../../data/services/stream_account_service.dart';
import '../../l10n/l10n_ext.dart';
import '../../widgets/tv/tv_adaptive_modal.dart';
import '../downloads/logic/local_playable.dart';
import 'player_media.dart';
import 'player_page.dart' show PlayerPage, VideoSourceType;

/// D'où le lecteur doit lire : un fichier de l'appareil, ou le flux.
///
/// [progressKey] — ⚠️ TOUJOURS l'URL RÉSEAU quand on lit un fichier : c'est
/// elle que l'accueil, la fiche et l'onglet Téléchargements interrogent
/// (§forgetResume). Lire le film téléchargé doit nourrir la même reprise que
/// le lire en flux. `null` en réseau : `PlayerMedia.resumeKey` retombe alors
/// sur le chemin, c'est-à-dire l'URL — le comportement d'avant, à l'identique.
typedef PlaybackSource = ({
  String path,
  VideoSourceType sourceType,
  String? progressKey,
});

/// Y a-t-il un fichier téléchargé pour ce titre, et lequel ?
///
/// [networkPath] — l'URL que l'appelant aurait jouée.
/// [groupUrls] — toutes les versions du titre, **l'URL choisie en tête**
/// (§endOfMovie les connaît déjà : ce sont les `siblingResumeKeys`).
///
/// Effet de bord assumé : une tâche TERMINÉE dont le fichier a disparu est
/// marquée en échec, avec sa raison. Sans ça, l'app repartirait en flux sans
/// un mot et la liste des téléchargements continuerait d'annoncer « Terminé »
/// pour un fichier qui n'existe plus (§userError : jamais un échec muet).
PlaybackSource resolvePlaybackSource({
  required String networkPath,
  required List<String> groupUrls,
  Iterable<DownloadTask>? tasks,
  bool Function(String path)? exists,
  void Function(DownloadTask task)? onMissing,
}) {
  final LocalPlayableChoice choice = pickLocalPlayable(
    tasks: tasks ?? DownloadManagerService().tasksNotifier.value,
    // L'URL demandée d'abord : on lit la version choisie, pas « la meilleure ».
    urls: <String>[networkPath, ...groupUrls],
    // §bootFast — l'existence se vérifie ICI, au moment du choix, jamais au
    // démarrage : c'est une poignée de `stat` sur les seules tâches du titre.
    exists: exists ?? (p) => File(p).existsSync(),
  );

  for (final DownloadTask t in choice.missing) {
    debugPrint('⚠️ §dlPlayLocal — fichier absent, lecture en flux : ${t.id}');
    (onMissing ?? _markFileMissing)(t);
  }

  final DownloadTask? local = choice.playable;
  if (local == null) {
    return (
      path: networkPath,
      sourceType: VideoSourceType.network,
      progressKey: null,
    );
  }
  debugPrint('🏪 §dlPlayLocal — lecture hors ligne du fichier telecharge : ${local.id}');
  return (
    path: local.finalPath,
    sourceType: VideoSourceType.file,
    // La clé de la TÂCHE, pas celle demandée : quand c'est une autre version
    // du groupe qui est sur le disque, sa progression doit rester la sienne —
    // la même que celle qu'écrit l'onglet Téléchargements. Les deux sont dans
    // le groupe, donc `getProgressForAny` les voit toutes les deux.
    progressKey: local.url,
  );
}

/// Une tâche TERMINÉE dont le fichier a disparu redevient une tâche en ÉCHEC.
///
/// ⚠️ `failed` et pas `canceled` : la tuile d'une tâche en échec propose
/// « Relancer » (§dlErgo), ce qui est exactement le geste utile ici — et
/// `canceled` n'est pas un état final (§dlLoop).
void _markFileMissing(DownloadTask t) {
  unawaited(DownloadManagerService().updateTask(
    t.id,
    status: DownloadStatus.failed,
    errorMessage: L10n.current.dlErrFileMissing,
  ));
}

/// À écouter par un écran qui affiche « Lire hors ligne » : la liste des
/// téléchargements change pendant qu'une fiche est ouverte (un transfert se
/// termine, on supprime un fichier), et le bouton doit suivre.
Listenable get localFilesListenable => DownloadManagerService().tasksNotifier;

/// `true` si ce titre a un fichier lisible sur l'appareil — pour dire « Lire
/// hors ligne » plutôt que « Lire », et poser la pastille « Téléchargé ».
///
/// ⚠️ Ne marque RIEN : c'est une question posée pendant un `build`, elle ne
/// doit pas écrire. Le marquage d'un fichier disparu appartient au lancement.
bool hasLocalFileFor({
  required String networkPath,
  required List<String> groupUrls,
  Iterable<DownloadTask>? tasks,
  bool Function(String path)? exists,
}) {
  return pickLocalPlayable(
        tasks: tasks ?? DownloadManagerService().tasksNotifier.value,
        urls: <String>[networkPath, ...groupUrls],
        exists: exists ?? (p) => File(p).existsSync(),
      ).playable !=
      null;
}

/// §episodeMeta — Le contenu suivant, servi depuis le fichier local s'il y en
/// a un. Même règle que [launchPlayback], pour le chemin qui ne pousse pas de
/// route mais change de média en place.
///
/// [build] reçoit la source et rend le `PlayerMedia` complet : tous les autres
/// champs (titre, synopsis, clé de série, badges) restent à l'appelant.
PlayerMedia resolvePlayableMedia({
  required String networkPath,
  required List<String> groupUrls,
  required PlayerMedia Function(PlaybackSource source) build,
}) {
  return build(resolvePlaybackSource(
    networkPath: networkPath,
    groupUrls: groupUrls,
  ));
}

// ── R23 « Déjà en lecture sur cette liste » ─────────────────────────────────

/// Ce que l'app doit dire AVANT de lancer un flux sur un abonnement Xtream.
enum StreamingSlotVerdict {
  /// Une place est libre (ou la limite est inconnue) : on lance sans un mot.
  free,

  /// Toutes les places sont prises, et au moins une ne vient pas de nous :
  /// un autre écran regarde. Le panel répondra probablement `403`.
  busyElsewhere,

  /// Toutes les places sont prises par NOS propres transferts : le geste
  /// utile n'est pas « réessayer », c'est « mettre un téléchargement en
  /// pause ». Le dire autrement serait accuser un tiers à tort.
  busyOurselves,
}

/// R23 — Reste-t-il une connexion pour cette lecture ?
///
/// [active] / [max] — `active_cons` / `max_connections` du panel, RAFRAÎCHIS
/// juste avant (la valeur affichée sur la carte du compte est périmée).
/// [own] — connexions que NOUS occupons déjà sur cet abonnement : nos
/// transferts en cours ([ownTransfersOn]) et nos lecteurs encore ouverts
/// ([openPlayersOn]). Sans elles, un téléchargement lancé par l'utilisateur
/// lui-même se serait dénoncé comme « un autre écran ».
///
/// ⚠️ **Jamais un refus, jamais une supposition.** Une limite inconnue
/// (`max <= 0`, panel muet) rend [StreamingSlotVerdict.free] : on n'invente
/// pas un obstacle à partir d'une absence de mesure.
///
/// [releasing] — §busyRelease (2026-09-21) : lecteurs que NOUS venons de
/// fermer sur cet abonnement, que le panel compte encore (il met ~5 min 30,
/// mesurées, à libérer une connexion). Signalé par l'utilisateur : « si je
/// sors d'une vidéo et que je reprends, il me dit que cet abonnement est
/// occupé ». Une
/// saturation qu'ils expliquent à eux seuls n'est pas un autre écran : on
/// lance sans un mot.
StreamingSlotVerdict alreadyStreamingVerdict({
  required int active,
  required int max,
  required int own,
  int releasing = 0,
}) {
  if (max <= 0 || active <= 0) return StreamingSlotVerdict.free;
  // Le panel refuse la connexion de trop, quel que soit qui tient les autres.
  if (active < max) return StreamingSlotVerdict.free;
  final int others = active - (own < 0 ? 0 : own);
  if (others <= 0) return StreamingSlotVerdict.busyOurselves;
  // §busyRelease — Ce qui reste est-il NOTRE connexion en cours de fermeture ?
  if (others - (releasing < 0 ? 0 : releasing) <= 0) {
    return StreamingSlotVerdict.free;
  }
  return StreamingSlotVerdict.busyElsewhere;
}

/// L'hôte (`serveur:port`) d'une URL, ou une chaîne vide si elle est illisible.
/// Sert à rapprocher une lecture et un transfert du MÊME abonnement.
String hostOfUrl(String url) {
  final Uri? u = Uri.tryParse(url.trim());
  if (u == null || u.host.isEmpty) return '';
  final String h = u.host.toLowerCase();
  return u.hasPort ? '$h:${u.port}' : h;
}

/// Combien de NOS transferts occupent une connexion sur [host] en ce moment.
int ownTransfersOn(String host, {Iterable<DownloadTask>? tasks}) {
  if (host.isEmpty) return 0;
  int n = 0;
  for (final t in tasks ?? DownloadManagerService().tasksNotifier.value) {
    // Seul un transfert EN COURS tient un socket ouvert : une tâche en file
    // ou en finalisation n'occupe rien côté panel.
    if (t.status == DownloadStatus.downloading &&
        hostOfUrl(t.url) == host) {
      n++;
    }
  }
  return n;
}

/// R23 — Combien de lecteurs CETTE app tient ouverts, par abonnement.
///
/// **Pourquoi ce compteur existe.** Rien dans l'app ne savait qu'elle occupait
/// déjà une connexion : `HostGate` ne compte que les appels d'API (son
/// en-tête le dit : « le lecteur vidéo ne passe JAMAIS par ici »),
/// `PlaybackHealthService` n'enregistre que des statistiques d'après-séance.
/// Un lecteur laissé ouvert en PiP pendant qu'on lance un second titre
/// s'accusait donc lui-même d'être « un autre écran ».
///
/// ⚠️ Un panel met plusieurs minutes (mesuré : ~5 min 30) à libérer une
/// connexion fermée : relancer juste
/// après avoir quitté le lecteur avertissait à tort. §busyRelease y répond par
/// [releasingPlayersOn] (les fermetures récentes, retenues [kPanelReleaseGrace]).
///
/// ⛔ Posé et relâché ICI, autour du `push` — `player_page.dart` n'est pas
/// touché : la route rend la main quand le lecteur se ferme.
final Map<String, int> _playersByAccount = <String, int>{};

/// Nombre de lecteurs que NOUS tenons ouverts sur [accountId].
int openPlayersOn(String accountId) => _playersByAccount[accountId] ?? 0;

/// §busyRelease — Combien de temps une connexion que nous venons de fermer
/// peut encore être comptée par le panel.
///
/// ⚠️ MESURÉ, pas supposé (2026-09-21, abonnement de test, deux AVD) : lecteur
/// fermé sur la TV à 19:36:13, le panel répondait encore « 1/1 » à 19:41:19 et
/// « 0/1 » à 19:41:49 — entre 5 min 06 et 5 min 36. L'ancien commentaire
/// disait « 30 à 60 s » : c'était une supposition. Six minutes, marge incluse.
/// Le prix, assumé : pendant ce délai, un AUTRE écran qui prendrait la place
/// ne serait pas signalé — l'avertissement n'est jamais un refus.
const Duration kPanelReleaseGrace = Duration(minutes: 6);

/// §busyRelease — Heures de fermeture de NOS lecteurs, par abonnement.
final Map<String, List<DateTime>> _closedPlayersByAccount =
    <String, List<DateTime>>{};

/// §busyRelease — Lecteurs fermés depuis moins de [kPanelReleaseGrace] sur
/// [accountId] : le panel peut encore les compter. Purge au passage.
int releasingPlayersOn(String accountId, {DateTime? now}) {
  final List<DateTime>? closed = _closedPlayersByAccount[accountId];
  if (closed == null) return 0;
  final DateTime t = now ?? DateTime.now();
  closed.removeWhere((d) => t.difference(d) >= kPanelReleaseGrace);
  if (closed.isEmpty) _closedPlayersByAccount.remove(accountId);
  return closed.length;
}

/// §busyRelease — Note la fermeture d'un de nos lecteurs (et en tests, à une
/// heure choisie).
void notePlayerClosed(String accountId, {DateTime? at}) {
  if (accountId.isEmpty) return;
  (_closedPlayersByAccount[accountId] ??= <DateTime>[])
      .add(at ?? DateTime.now());
}

/// Remet les compteurs à zéro (tests uniquement).
@visibleForTesting
void resetOpenPlayersForTest() {
  _playersByAccount.clear();
  _closedPlayersByAccount.clear();
}

/// R23 — Combien de temps on accepte d'attendre le panel avant de lancer.
///
/// ⚠️ Court À DESSEIN : cette requête retarde l'ouverture du lecteur. Un panel
/// lent ne doit pas coûter une seconde de plus que ce qu'on est prêt à perdre
/// — au-delà, on lance sans avertir (un avertissement manqué vaut mieux
/// qu'une lecture qui n'arrive pas).
const Duration kStreamingSlotTimeout = Duration(seconds: 3);

/// Ouvre le lecteur sur ce titre : le fichier téléchargé s'il existe, le flux
/// sinon.
///
/// [build] construit la `PlayerPage` avec la source résolue — l'appelant garde
/// la main sur TOUS ses autres paramètres.
/// [accountId] — l'abonnement d'où vient le flux : sert à R23 (avertir quand
/// il n'y a plus de connexion libre). Vide = pas de compte connu, pas de
/// question posée.
Future<void> launchPlayback(
  BuildContext context, {
  required String networkPath,
  required List<String> groupUrls,
  required PlayerPage Function(PlaybackSource source) build,
  String accountId = '',
}) async {
  final PlaybackSource source = resolvePlaybackSource(
    networkPath: networkPath,
    groupUrls: groupUrls,
  );
  // R23 — ⚠️ Un fichier de l'appareil n'ouvre AUCUNE connexion chez le
  // fournisseur : lui poser la question serait perdre trois secondes pour
  // rien, et avertir serait faux.
  if (source.sourceType == VideoSourceType.network && accountId.isNotEmpty) {
    if (!context.mounted) return;
    final bool go = await _confirmStreamingSlot(
      context,
      accountId: accountId,
      url: networkPath,
    );
    if (!go) return;
  }
  if (!context.mounted) return;
  // R23 — ⚠️ Le `finally` est le cœur du compteur : une route qui sortirait
  // par une exception laisserait l'abonnement marqué « occupé par nous » à
  // vie, et tout lancement ultérieur mentirait.
  final bool counts =
      source.sourceType == VideoSourceType.network && accountId.isNotEmpty;
  if (counts) {
    _playersByAccount[accountId] = openPlayersOn(accountId) + 1;
  }
  try {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => build(source)),
    );
  } finally {
    if (counts) {
      notePlayerClosed(accountId); // §busyRelease
      final int n = openPlayersOn(accountId) - 1;
      if (n <= 0) {
        _playersByAccount.remove(accountId);
      } else {
        _playersByAccount[accountId] = n;
      }
    }
  }
}

/// R23 — Demande au panel s'il reste une connexion, et AVERTIT si non.
///
/// Rend `true` quand la lecture doit partir. ⛔ **Jamais un refus** : c'est
/// l'utilisateur qui tranche, et tout ce qui ne se mesure pas (panel muet,
/// compte introuvable, liste M3U simple, délai dépassé) laisse partir la
/// lecture sans un mot.
Future<bool> _confirmStreamingSlot(
  BuildContext context, {
  required String accountId,
  required String url,
}) async {
  final StreamingSlotVerdict verdict;
  try {
    // Le stockage sécurisé est une I/O : bornée elle aussi, pour qu'aucun
    // chemin de cette vérification ne puisse retarder une lecture sans fin.
    final StreamAccount? account = await StreamAccountService.getAccount(accountId)
        .timeout(kStreamingSlotTimeout);
    // Une liste M3U simple n'a pas d'API de connexions : rien à demander.
    if (account == null || account.resolveXtreamCredentials() == null) {
      return true;
    }
    // ⚠️ La valeur de la carte du compte est PÉRIMÉE (elle date du
    // démarrage) : c'est un rafraîchissement, pas une lecture de cache.
    final AccountInfo? info = await StreamAccountService.fetchAccountInfo(account)
        .timeout(kStreamingSlotTimeout);
    if (info == null) return true;
    verdict = alreadyStreamingVerdict(
      active: info.activeConnections,
      max: info.maxConnections,
      // Nos transferts EN COURS sur ce panel, plus nos propres lecteurs
      // encore ouverts (PiP) : tout ce que le panel compte et qui vient de
      // nous. Sans ça, l'app accuserait « un autre écran » d'être elle-même.
      own: ownTransfersOn(hostOfUrl(url)) + openPlayersOn(accountId),
      releasing: releasingPlayersOn(accountId),
    );
    debugPrint('🔌 R23 — connexions ${info.activeConnections}/${info.maxConnections} (dont ${releasingPlayersOn(accountId)} fermée(s) par nous il y a < 6 min) : ${verdict.name}');
  } catch (e) {
    // §userError — rien à l'écran : une question sans réponse n'est pas une
    // panne, et bloquer la lecture sur un panel lent serait pire que se taire.
    debugPrint('⚠️ R23 — connexions du compte inconnues, lecture lancee sans avertir');
    return true;
  }
  if (verdict == StreamingSlotVerdict.free) return true;
  if (!context.mounted) return true;

  final l10n = context.l10n;
  final bool? go = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.tv_off, size: 40, color: kWarning),
      title: Text(l10n.playBusyTitle),
      content: Text(verdict == StreamingSlotVerdict.busyElsewhere
          ? l10n.playBusyElsewhere
          : l10n.playBusyOwnTransfer),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          // §tvOptionsBack — la sortie existe des deux côtés : le Retour de la
          // télécommande referme la boîte (donc annule), et le bouton focalisé
          // d'entrée est celui qui LANCE, jamais celui qui annule.
          autofocus: true,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.playBusyContinue),
        ),
      ],
    ),
  );
  // Retour / clic hors de la boîte = on ne lance pas : l'utilisateur n'a pas
  // dit oui.
  return go ?? false;
}
