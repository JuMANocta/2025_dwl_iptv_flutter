import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../models/stream_account.dart';
import 'load_failure.dart';
import 'parsed_playlist_service.dart';
import 'playlist_service.dart';
import 'stream_account_service.dart';

/// §fleetLoad — L'invariant : **toute liste configurée finit chargée en
/// mémoire, ou porte un état d'échec explicite et motivé.** Aucun troisième cas.
///
/// **Pourquoi ce service existe.** Le chargement d'une liste n'avait pas de
/// propriétaire : il était éparpillé entre `main._hydrateInBoot/_hydrateOne`,
/// `ParsedPlaylistService.loadActive/loadSecondary/preloadOthersFromDisk/
/// reloadFromDisk`, `PlaylistService.ensureDownloadedForAccount` et
/// `PlaylistReloadService.reloadAccount`. Chacun avait sa définition du succès,
/// aucun ne connaissait l'état final de la flotte — et six chemins différents
/// pouvaient abandonner un compte **en silence**. Constaté le 2026-09-03 sur
/// l'appareil : trois catalogues bruts sains sur le disque, seulement deux
/// caches analysés, et rien nulle part pour le dire ni pour le rattraper.
///
/// Un compte absent de `ParsedPlaylistService` est **totalement invisible** de
/// l'accueil, de la recherche, des favoris et de TMDB : il n'existe aucun
/// chargement paresseux au moment de l'affichage. D'où ce réconciliateur,
/// idempotent, qu'on appelle aux **moments** qui comptent — jamais en boucle.
abstract final class PlaylistFleetService {
  /// §fleetLoad — Une seule passe à la fois. Un second appel pendant qu'une
  /// passe tourne rend **le même** futur : c'est ce qui permet d'appeler ce
  /// service au démarrage, au retour sur l'accueil et à l'ouverture de la page
  /// Comptes sans jamais doubler un parsing (le parsing d'un gros catalogue
  /// coûte plusieurs centaines de Mo — cf. la règle « SÉQUENTIEL, jamais en
  /// parallèle » de « Tout recharger »).
  static Future<FleetReport>? _inFlight;

  static bool get isRunning => _inFlight != null;

  /// Plafond par compte : un panel injoignable ne doit pas manger le budget
  /// des autres listes. ⚠️ Sans lui, un seul fournisseur mort suffit à priver
  /// l'utilisateur de toutes ses autres listes.
  static const Duration defaultPerAccount = Duration(seconds: 25);

  /// Passe de réconciliation.
  ///
  /// [reason] apparaît dans le journal (`boot`, `accueil`, `comptes`,
  /// `reprise`, `manuel`) : c'est ce qui rend une trace lisible a posteriori.
  /// [allowNetwork] à `false` interdit tout téléchargement — le cas du retour
  /// sur l'accueil, où l'on veut rattraper la mémoire sans faire attendre
  /// quelqu'un qui vient de fermer le lecteur.
  /// [allowReparse] à `false` interdit la ré-analyse (coûteuse) et se contente
  /// du cache disque.
  static Future<FleetReport> ensureAllLoaded({
    required String reason,
    Duration? budget,
    Duration perAccount = defaultPerAccount,
    bool allowNetwork = true,
    bool allowReparse = true,
    void Function(double)? onProgress,
    void Function(String)? onDetail,
  }) {
    final Future<FleetReport>? running = _inFlight;
    if (running != null) {
      debugPrint('⏸️ §fleetLoad ($reason) : une passe est déjà en cours.');
      return running;
    }
    final Future<FleetReport> f = _run(
      reason: reason,
      budget: budget,
      perAccount: perAccount,
      allowNetwork: allowNetwork,
      allowReparse: allowReparse,
      onProgress: onProgress,
      onDetail: onDetail,
    );
    _inFlight = f;
    return f.whenComplete(() => _inFlight = null);
  }

  static Future<FleetReport> _run({
    required String reason,
    required Duration? budget,
    required Duration perAccount,
    required bool allowNetwork,
    required bool allowReparse,
    void Function(double)? onProgress,
    void Function(String)? onDetail,
  }) async {
    final List<StreamAccount> accounts =
        await StreamAccountService.listAccounts();
    if (accounts.isEmpty) {
      return const FleetReport(total: 0);
    }

    final DateTime? deadline =
        budget == null ? null : DateTime.now().add(budget);
    int loaded = 0, fromCache = 0, reparsed = 0, downloaded = 0;
    final Map<String, LoadFailure> failed = <String, LoadFailure>{};
    final List<String> deferred = <String>[];

    for (int i = 0; i < accounts.length; i++) {
      final StreamAccount acc = accounts[i];
      onProgress?.call(accounts.isEmpty ? 1 : i / accounts.length);

      // ⚠️ SÉQUENTIEL, toujours — y compris au-delà du budget. L'ancien code
      // lançait tous les comptes restants d'un coup dès que le budget était
      // épuisé, c'est-à-dire précisément quand le fournisseur ramait : la
      // lenteur fabriquait le parallélisme qui aggravait la lenteur.
      if (deadline != null && DateTime.now().isAfter(deadline)) {
        deferred.add(acc.label);
        ParsedPlaylistService.setLoadState(
          acc.id,
          AccountLoadState.notLoaded,
          kind: LoadFailureKind.deferred,
          detail: 'budget de $reason épuisé',
        );
        continue;
      }

      final _AccountFacts facts = await _factsFor(acc);
      final FleetStep step = FleetPolicy.nextStep(
        inMemory: facts.inMemory,
        entriesInMemory: facts.entriesInMemory,
        hasParsedCache: facts.hasParsedCache,
        hasSourceFile: facts.hasSourceFile,
        sourceIsStale: facts.sourceIsStale,
        allowNetwork: allowNetwork,
        allowReparse: allowReparse,
      );

      if (step == FleetStep.none) {
        loaded++;
        continue;
      }

      onDetail?.call(acc.label);
      try {
        switch (step) {
          case FleetStep.none:
            break;
          case FleetStep.loadCache:
          case FleetStep.reparse:
            await ParsedPlaylistService.loadSecondary(
              acc.id,
              acc.label,
              facts.sourcePath!,
            ).timeout(perAccount);
            if (step == FleetStep.loadCache) {
              fromCache++;
            } else {
              reparsed++;
            }
          case FleetStep.download:
            final res = await PlaylistService.ensureDownloadedForAccount(
              acc,
              force: facts.sourceIsStale && !facts.inMemory,
            ).timeout(perAccount);
            if (res.path == null) {
              failed[acc.id] = LoadFailure(
                LoadFailureKind.network,
                detail: 'téléchargement impossible',
                at: DateTime.now(),
              );
              ParsedPlaylistService.setLoadState(
                acc.id,
                AccountLoadState.error,
                kind: LoadFailureKind.network,
                detail: 'téléchargement impossible',
              );
              continue;
            }
            downloaded++;
            await ParsedPlaylistService.loadSecondary(
              acc.id,
              acc.label,
              res.path!,
            ).timeout(perAccount);
          case FleetStep.fail:
            final LoadFailureKind kind = allowNetwork
                ? LoadFailureKind.noSource
                : LoadFailureKind.cacheGone;
            failed[acc.id] =
                LoadFailure(kind, detail: null, at: DateTime.now());
            ParsedPlaylistService.setLoadState(
              acc.id,
              AccountLoadState.error,
              kind: kind,
            );
            continue;
        }

        if (ParsedPlaylistService.entriesCountOf(acc.id) > 0) {
          loaded++;
        } else {
          // ⚠️ Une liste à zéro entrée n'est JAMAIS un succès : c'est le
          // symptôme d'un catalogue amputé (une section de l'API a échoué et
          // a rendu une liste vide, indiscernable d'un vrai vide).
          failed[acc.id] = LoadFailure(
            LoadFailureKind.amputated,
            detail: 'aucune entrée après analyse',
            at: DateTime.now(),
          );
          ParsedPlaylistService.setLoadState(
            acc.id,
            AccountLoadState.error,
            kind: LoadFailureKind.amputated,
            detail: 'aucune entrée après analyse',
          );
        }
      } on TimeoutException {
        deferred.add(acc.label);
        ParsedPlaylistService.setLoadState(
          acc.id,
          AccountLoadState.notLoaded,
          kind: LoadFailureKind.deferred,
          detail: 'délai de ${perAccount.inSeconds} s dépassé',
        );
        debugPrint('⏳ §fleetLoad : « ${acc.label} » dépasse '
            '${perAccount.inSeconds} s — reportée.');
      } catch (e) {
        failed[acc.id] = LoadFailure(
          LoadFailureKind.parse,
          detail: e.runtimeType.toString(),
          at: DateTime.now(),
        );
        ParsedPlaylistService.setLoadState(
          acc.id,
          AccountLoadState.error,
          kind: LoadFailureKind.parse,
          detail: e.runtimeType.toString(),
        );
        debugPrint('❌ §fleetLoad : « ${acc.label} » a échoué ($e)');
      }
    }

    onProgress?.call(1);
    final FleetReport report = FleetReport(
      total: accounts.length,
      loaded: loaded,
      fromCache: fromCache,
      reparsed: reparsed,
      downloaded: downloaded,
      failed: failed,
      deferred: deferred,
    );
    debugPrint('📋 §fleetLoad ($reason) — ${report.summary}');
    return report;
  }

  /// Les faits observables pour un compte, au moment de la décision.
  static Future<_AccountFacts> _factsFor(StreamAccount acc) async {
    final int inMem = ParsedPlaylistService.entriesCountOf(acc.id);
    final bool inMemory =
        ParsedPlaylistService.stateOf(acc.id) == AccountLoadState.loaded ||
            inMem > 0;

    // §23 — Même convention que `PlaylistService.pathForAccountId` : catalogue
    // JSON prioritaire, sinon M3U legacy.
    final String? source = await _sourcePathFor(acc.id);
    bool stale = true;
    if (source != null) {
      try {
        stale = await PlaylistService.hasPendingWork(acc);
      } catch (_) {
        stale = true;
      }
    }

    return _AccountFacts(
      inMemory: inMemory,
      entriesInMemory: inMem,
      hasParsedCache: await _hasParsedCache(acc.id),
      hasSourceFile: source != null,
      sourcePath: source,
      sourceIsStale: stale,
    );
  }

  static Future<String?> _sourcePathFor(String accountId) async {
    final dir = await getApplicationDocumentsDirectory();
    final String json = '${dir.path}/playlist_$accountId.json';
    if (File(json).existsSync()) return json;
    final String m3u = '${dir.path}/playlist_$accountId.m3u';
    if (File(m3u).existsSync()) return m3u;
    return null;
  }

  /// ⚠️ Convention dupliquée de `ParsedPlaylistService._diskCachePath`, comme
  /// `preloadOthersFromDisk` duplique déjà celle des sources : garder les deux
  /// alignées si le chemin change.
  static Future<bool> _hasParsedCache(String accountId) async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/parsed_playlist_$accountId.json.gz')
          .existsSync();
    } catch (_) {
      return false;
    }
  }
}

class _AccountFacts {
  final bool inMemory;
  final int entriesInMemory;
  final bool hasParsedCache;
  final bool hasSourceFile;
  final String? sourcePath;
  final bool sourceIsStale;

  const _AccountFacts({
    required this.inMemory,
    required this.entriesInMemory,
    required this.hasParsedCache,
    required this.hasSourceFile,
    required this.sourcePath,
    required this.sourceIsStale,
  });
}

/// L'escalade, de la marche la moins chère à la plus chère.
enum FleetStep {
  /// Déjà en mémoire avec des entrées : ne rien faire.
  none,

  /// Cache analysé présent : lecture disque, ~50 ms.
  loadCache,

  /// Pas de cache mais un catalogue brut : ré-analyse en isolate, ~4 s.
  reparse,

  /// Rien d'exploitable sur le disque, ou source périmée : réseau.
  download,

  /// Rien à faire et rien d'autorisé : échec motivé.
  fail,
}

/// §fleetLoad — **Le cœur de l'invariant, en fonction pure.** Toute la
/// décision « que faire de cette liste » tient ici, donc elle se teste sans
/// appareil, sans réseau et sans disque.
abstract final class FleetPolicy {
  static FleetStep nextStep({
    required bool inMemory,
    required int entriesInMemory,
    required bool hasParsedCache,
    required bool hasSourceFile,
    required bool sourceIsStale,
    required bool allowNetwork,
    required bool allowReparse,
  }) {
    // En mémoire ET non vide → rien. ⚠️ Le test sur les entrées est
    // essentiel : un compte « chargé » à zéro entrée était compté comme un
    // succès alors que c'est le symptôme d'un catalogue amputé.
    if (inMemory && entriesInMemory > 0) {
      if (sourceIsStale && allowNetwork) return FleetStep.download;
      return FleetStep.none;
    }

    if (hasParsedCache && !sourceIsStale) return FleetStep.loadCache;

    // Source périmée : on préfère rafraîchir, mais seulement si on a le droit.
    if (sourceIsStale && hasSourceFile && allowNetwork) {
      return FleetStep.download;
    }

    // ⚠️ Périmé vaut mieux que rien : sans réseau, on sert quand même.
    if (hasParsedCache) return FleetStep.loadCache;

    // Le repli qui manquait : un catalogue brut est là, mais aucun cache
    // analysé — on ré-analyse au lieu d'abandonner en silence.
    if (hasSourceFile && allowReparse) return FleetStep.reparse;

    if (allowNetwork) return FleetStep.download;

    return FleetStep.fail;
  }
}

/// Bilan d'une passe. Sur le patron de `ReloadBatchResult.summary`, qui est
/// déjà la bonne façon de rendre un lot compréhensible en une phrase.
class FleetReport {
  final int total;
  final int loaded;
  final int fromCache;
  final int reparsed;
  final int downloaded;
  final Map<String, LoadFailure> failed;
  final List<String> deferred;

  const FleetReport({
    required this.total,
    this.loaded = 0,
    this.fromCache = 0,
    this.reparsed = 0,
    this.downloaded = 0,
    this.failed = const <String, LoadFailure>{},
    this.deferred = const <String>[],
  });

  bool get allLoaded => total > 0 && loaded == total;

  String get summary {
    if (total == 0) return 'aucun compte configuré.';
    final StringBuffer b = StringBuffer('$loaded/$total liste(s) en mémoire');
    if (fromCache > 0) b.write(' · $fromCache depuis le cache');
    if (reparsed > 0) b.write(' · $reparsed ré-analysée(s)');
    if (downloaded > 0) b.write(' · $downloaded téléchargée(s)');
    if (failed.isNotEmpty) b.write(' · ${failed.length} en échec');
    if (deferred.isNotEmpty) b.write(' · ${deferred.length} reportée(s)');
    return '$b.';
  }
}
