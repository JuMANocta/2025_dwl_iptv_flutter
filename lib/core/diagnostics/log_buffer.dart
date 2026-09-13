import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart'
    show BuildContext, Element, FocusNode, FocusScopeNode, Text;
import 'package:path_provider/path_provider.dart';

import '../utils/log_sanitizer.dart';

/// §tvLogs — Journal de diagnostic embarqué, consultable depuis la console web.
///
/// **Pourquoi.** Sur Android TV / Fire Stick il n'y a pas de logcat accessible :
/// chaque bug se valide « à l'œil », un changement à la fois. Ce tampon capture
/// tout ce que l'application écrit déjà via `debugPrint` (aucun appel existant à
/// modifier) plus les exceptions non interceptées, et l'expose sur la console
/// web du téléphone — avec un export texte à transmettre.
///
/// **Sécurité.** Les URLs IPTV portent les identifiants dans le path
/// (`/movie/USER/PASS/123.mkv`) ou en query. La page est servie sur le réseau
/// local : la rédaction est donc faite **au niveau du puits**, pas au niveau des
/// appelants. Même un `debugPrint` qui oublie [redactUrl] ne peut plus faire
/// fuiter de mot de passe. ⚠️ §tourFix — cette promesse était vraie pour le
/// tampon mais fausse pour logcat : le wrapper déléguait aussi le message BRUT
/// à l'implémentation d'origine, release comprise. En release, on ne délègue
/// plus du tout (voir [install]).
///
/// **§tvLogsPersist (2026-09-09).** Le tampon ci-dessus vit ENTIÈREMENT en
/// mémoire — une `Queue` plafonnée, rien de plus. Un démarrage qui semble
/// bloqué et que l'utilisateur tue (le seul geste qu'il a) efface donc
/// structurellement toute trace : on est aveugle exactement quand on aurait
/// besoin de voir. Ce module ajoute une persistance disque **best-effort** :
///   - [add] continue d'écrire en mémoire de façon SYNCHRONE, inchangé ; il se
///     contente en plus de marquer le tampon « sale » ;
///   - un [Timer] périodique (≈1,5 s, jamais par ligne) recopie l'état courant
///     du tampon — donc déjà REDIGÉ, cf. [sanitizeForLog] dans [add] — vers un
///     fichier de stockage PRIVÉ de l'app (`getApplicationSupportDirectory`,
///     jamais le dossier public des téléchargements) ; l'écriture est async et
///     jamais attendue, elle ne peut donc jamais geler l'appelant ;
///   - au prochain lancement, [install] fait tourner la rotation AVANT que la
///     session courante n'écrive une seule ligne : le fichier laissé par la
///     session PRÉCÉDENTE (tuée ou non) devient lisible via
///     [awaitPreviousSession] / [previousSessionDump], et un fichier neuf
///     s'ouvre pour la session en cours.
/// Rien de tout cela n'est un préalable au démarrage : toute erreur (dossier
/// inaccessible, disque plein…) est avalée, et le journal continue de vivre en
/// mémoire exactement comme avant ce lot.
abstract final class DiagnosticLog {
  /// Bornes volontairement basses : sur un Fire Stick, chaque mégaoctet compte.
  static const int maxLines = 2000;
  static const int maxChars = 512 * 1024;

  static final Queue<String> _lines = Queue<String>();
  static int _chars = 0;

  static DebugPrintCallback? _previousDebugPrint;
  static bool _installed = false;

  /// Incrémenté à chaque nouvelle ligne — permet à l'UI de se rafraîchir.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool get isInstalled => _installed;
  static int get lineCount => _lines.length;

  // ── Installation ─────────────────────────────────────────────────────────

  /// Branche la capture. Idempotent (appelé une fois depuis `main()`).
  static void install() {
    if (_installed) return;
    _installed = true;

    _previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) add(message);
      // §tourFix — En release, ne PAS déléguer à l'implémentation d'origine :
      // le tampon reçoit la version RÉDIGÉE, mais l'original recevrait le
      // message BRUT — les URLs avec credentials finissaient sur logcat, en
      // release aussi. Le tampon §tvLogs rédigé reste le canal de diagnostic
      // (c'est LE canal sur TV, où il n'y a pas de logcat). En debug, rien ne
      // change : logcat continue de fonctionner exactement comme avant.
      if (!kReleaseMode) {
        _previousDebugPrint?.call(message, wrapWidth: wrapWidth);
      }
    };

    final FlutterExceptionHandler? previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      add('💀 ${details.exceptionAsString()}');
      final String? stack = details.stack?.toString();
      if (stack != null) add(_firstFrames(stack));
      previousOnError?.call(details);
    };

    final bool Function(Object, StackTrace)? previousPlatformError =
        PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      add('💀 (async) $error');
      add(_firstFrames(stack.toString()));
      return previousPlatformError?.call(error, stack) ?? false;
    };

    add('📝 Journal de diagnostic démarré');

    // §focusTrace — Traceur armé dès le boot avec
    // `--dart-define=AS_KEYTRACE=true`. Sans ça, il faut ouvrir la console web
    // AVANT le geste à observer : impossible pour tout ce qui se passe au
    // démarrage, et fastidieux à chaque réinstallation pendant un diagnostic.
    // Absent du build normal (constante de compilation à `false`).
    if (const bool.fromEnvironment('AS_KEYTRACE')) keyTrace = true;

    // §tvLogsPersist — Amorcée en DERNIER : la rotation lit/renomme un fichier
    // sur disque (async), jamais attendue ici. Les quelques lignes écrites
    // avant qu'elle ne termine restent captées par le tampon mémoire, comme
    // toujours, et rejoindront le disque au premier flush.
    unawaited(_ensurePersistence());
  }

  /// Garde les premières lignes d'une stack trace : au-delà, on remplit le
  /// tampon de bruit qui chasse les lignes utiles.
  static String _firstFrames(String stack, {int frames = 6}) {
    final List<String> lines = stack.trimRight().split('\n');
    if (lines.length <= frames) return stack.trimRight();
    return '${lines.take(frames).join('\n')}\n   … (${lines.length - frames} lignes)';
  }

  // ── Écriture ─────────────────────────────────────────────────────────────

  static void add(String message) {
    final String stamp = _stamp(DateTime.now());
    for (final String raw in message.split('\n')) {
      _push('$stamp  ${sanitizeForLog(raw)}');
    }
    revision.value++;
    // §tvLogsPersist — Ne déclenche AUCUNE écriture ici : juste un drapeau que
    // le Timer périodique regardera. Un parsing qui publie des milliers de
    // lignes ne doit jamais devenir des milliers d'écritures disque.
    _dirty = true;
  }

  static void _push(String line) {
    _lines.addLast(line);
    _chars += line.length + 1;
    while (_lines.length > maxLines || _chars > maxChars) {
      final String dropped = _lines.removeFirst();
      _chars -= dropped.length + 1;
    }
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
  }

  // ── Lecture ──────────────────────────────────────────────────────────────

  /// Journal complet, du plus ancien au plus récent.
  static String dump() => _lines.join('\n');

  /// [count] dernières lignes (pour un rafraîchissement léger).
  static List<String> tail(int count) {
    if (count >= _lines.length) return _lines.toList();
    return _lines.toList().sublist(_lines.length - count);
  }

  /// Vide le journal — mémoire ET disque.
  ///
  /// R41 (2026-09-13) — ⚠️ **« Vider » n'effaçait que la moitié du journal.**
  /// Le tampon mémoire partait et le fichier de la session COURANTE était
  /// marqué à réécrire, mais `diagnostic_session_previous.log` restait intact
  /// sur le disque — et la console continuait de le servir sur le réseau local
  /// via `/logs.txt?session=previous`. Mesuré sur le S25 le 2026-09-13 : les
  /// deux fichiers coexistaient après un « Vider », seul un `rm` faisait partir
  /// le second. Depuis R35, on sait que ces journaux peuvent porter le jeton de
  /// nos serveurs locaux : quelqu'un qui vide son journal en croyant l'effacer
  /// gardait donc potentiellement un secret exposé sur son réseau.
  ///
  /// Rend `true` si le disque est propre au retour, `false` si un fichier a
  /// résisté — et ce booléen va jusqu'à l'écran.
  ///
  /// **F1** — Sur un ticket de sécurité, un succès affiché à tort est le pire
  /// résultat : la fuite réseau est bien fermée à l'instant même (plus rien
  /// n'est servi, cf. [_clearMemory]), mais elle est seulement DIFFÉRÉE — au
  /// prochain lancement, la rotation relit le fichier survivant et la console
  /// le ressert, pendant que la personne croit avoir effacé.
  ///
  /// **F5** — Il n'existe qu'UN seul chemin de vidage, et il est attendu de
  /// bout en bout. Une variante synchrone a existé le temps d'une relecture :
  /// sans appelant de production, elle ne pouvait qu'avaler le verdict — et
  /// toute ligne non gardée ajoutée un jour dans la purge serait remontée à
  /// `PlatformDispatcher.onError`, qui écrit `💀 (async)` dans le journal qu'on
  /// vient précisément de vider.
  static Future<bool> clearAll() async {
    _clearMemory();
    return _purgePersistedSessions();
  }

  /// Vide le tampon — et avec lui TOUT ce que la console sait servir.
  ///
  /// **F4a** — La copie mémoire de la session précédente est annulée ICI, pas
  /// dans la purge disque : les deux chemins de lecture de la console
  /// ([dump] et [previousSessionDump] / [awaitPreviousSession]) passent par la
  /// mémoire, donc c'est cette moitié-là qui ferme réellement la fuite sur le
  /// réseau. La subordonner à la précondition de la moitié DISQUE en ferait un
  /// invariant suspendu à un autre fichier, au lieu d'être local et évident.
  static void _clearMemory() {
    _lines.clear();
    _chars = 0;
    _previousSessionText = null;
    _previousSessionLines = 0;
    revision.value++;
    // §tvLogsPersist — Le fichier de la session courante doit refléter le
    // tampon vidé lui aussi, sinon un « Vider » suivi d'un kill ferait
    // réapparaître l'ancien contenu au prochain démarrage.
    _dirty = true;
  }

  @visibleForTesting
  static void resetForTest() {
    // R41 — La moitié MÉMOIRE seulement : un test ne doit pas déclencher un
    // effacement disque qui courrait avec son `tearDown`.
    _clearMemory();
    keyTrace = false;
    // §tvLogsPersist — Si un test a appelé [install] (donc amorcé la
    // persistance), on coupe le Timer : sans ça il continuerait de tourner
    // entre deux tests et pourrait toucher au disque hors de tout contexte.
    resetPersistenceForTest();
  }

  // ── Persistance disque (§tvLogsPersist) ─────────────────────────────────

  /// Nom du fichier de la session EN COURS, dans le stockage privé de l'app.
  static const String _currentFileName = 'diagnostic_session_current.log';

  /// Nom du fichier de la session PRÉCÉDENTE — ce que [install] a trouvé en
  /// place au moment de la rotation.
  static const String _previousFileName = 'diagnostic_session_previous.log';

  /// Au plus une écriture disque toutes les [_flushInterval] — jamais par
  /// ligne. 1,5 s : assez réactif pour qu'un kill n'efface qu'une poignée de
  /// lignes récentes, assez espacé pour ne jamais peser sur un parsing qui
  /// publie des centaines de lignes par seconde.
  static const Duration _flushInterval = Duration(milliseconds: 1500);

  /// Mémorise l'amorçage pour ne le lancer qu'une fois, et pour que
  /// [awaitPreviousSession] puisse l'attendre sans le relancer.
  static Future<void>? _persistInit;

  static File? _currentFile;
  static Timer? _flushTimer;
  static bool _dirty = false;

  static String? _previousSessionText;
  static int _previousSessionLines = 0;

  /// Contenu de la session PRÉCÉDENTE (celle d'avant ce lancement), déjà
  /// rédigé — c'est une copie de ce que le tampon mémoire contenait à
  /// l'écriture. `null` tant que la rotation n'a pas encore tourné (tout
  /// début du boot), que la persistance est indisponible, ou qu'il n'y a pas
  /// eu de session précédente (premier lancement).
  ///
  /// Voir [awaitPreviousSession] pour la version qui ATTEND la rotation.
  static String? get previousSessionDump => _previousSessionText;

  /// Nombre de lignes de la session précédente (0 si absente).
  static int get previousSessionLineCount =>
      _previousSessionText == null ? 0 : _previousSessionLines;

  /// `true` une fois que la rotation a tourné (avec ou sans succès) : au-delà
  /// de ce point, [previousSessionDump] a sa valeur définitive pour cette
  /// session.
  static bool get previousSessionReady => _persistInitDone;
  static bool _persistInitDone = false;

  /// Amorce la persistance (idempotent). Ne lève jamais : une erreur laisse
  /// simplement le journal vivre en mémoire seule, comme avant ce lot.
  static Future<void> _ensurePersistence() => _persistInit ??= _initPersistence();

  static Future<void> _initPersistence() async {
    try {
      // Stockage PRIVÉ de l'app (jamais le dossier public `/Movies/…` des
      // téléchargements) — c'est déjà là que vit le cache playlist parsé.
      final Directory dir = await getApplicationSupportDirectory();
      final File current = File('${dir.path}/$_currentFileName');
      final File previous = File('${dir.path}/$_previousFileName');

      // §tvLogsPersist — Rotation AVANT toute écriture de la session en
      // cours : ce que la session précédente (tuée ou non) a laissé devient
      // LA session précédente lisible. `File.rename` sur Android (POSIX)
      // remplace atomiquement la cible existante — l'app est Android-only,
      // cette hypothèse est sûre ici (elle ne le serait pas sur Windows).
      // revue 2026-09-11, D3B-12 — Un `.tmp` qui traîne est une écriture
      // qu'un kill a interrompue : il peut être coupé n'importe où. Le fichier
      // courant (le flush précédent, complet) fait foi ; le `.tmp` est jeté.
      final File staleTmp = File('${current.path}$_tmpSuffix');
      if (await staleTmp.exists()) {
        try {
          await staleTmp.delete();
        } catch (_) {}
      }
      if (await current.exists()) {
        await current.rename(previous.path);
      }
      if (await previous.exists()) {
        try {
          // revue 2026-09-11, D3B-12 — `readAsString` décode en UTF-8 STRICT :
          // un emoji coupé en fin de fichier levait, et TOUTE la session
          // précédente était perdue pour un seul caractère. Les octets
          // invalides deviennent un caractère de remplacement, le reste reste
          // lisible.
          final String text = utf8.decode(await previous.readAsBytes(),
              allowMalformed: true);
          _previousSessionText = text;
          _previousSessionLines = text.isEmpty ? 0 : '\n'.allMatches(text).length + 1;
        } catch (_) {
          // Fichier illisible (encodage, tronqué par un kill en plein
          // milieu d'une écriture) : pas de session précédente exploitable,
          // mais la session courante n'en souffre pas.
          _previousSessionText = null;
        }
      }

      _currentFile = current;
      _startFlushTimer();
    } catch (e) {
      // La persistance est un CONFORT, jamais un préalable : sans elle le
      // journal continue de vivre en mémoire exactement comme avant ce lot.
      debugPrint('⚠️ §tvLogsPersist : persistance disque indisponible ($e).');
    } finally {
      _persistInitDone = true;
    }
  }

  /// [flushNow] — R41/F3 : un flush immédiat n'a de sens qu'après la ROTATION
  /// (avoir quelque chose sur disque même si le process meurt aussitôt). Après
  /// une PURGE, il ne ferait que recréer sur-le-champ le fichier qu'on vient
  /// d'effacer, et son `.tmp` avec — du vide, mais du vide qui tient un
  /// descripteur ouvert pendant qu'on annonce un disque propre.
  static void _startFlushTimer({bool flushNow = true}) {
    _flushTimer?.cancel();
    // Timer d'une seconde et demie, annulable — jamais de travail par frame
    // (§bootCursorTimer a déjà coûté deux tiers du CPU d'un boot pour cette
    // raison précise, ailleurs dans l'app).
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flushIfDirty());
    // Un premier flush immédiat : si le process meurt tout de suite après la
    // rotation, on ne dépend pas d'un premier tour d'horloge pour avoir
    // quelque chose sur disque.
    if (flushNow) _flushIfDirty();
  }

  /// revue 2026-09-11, D3B-12 — Une écriture est en cours : le tour d'horloge
  /// suivant ne doit pas en lancer une seconde par-dessus (deux écritures
  /// concurrentes du même `.tmp`). `_dirty` reste vrai, rien n'est perdu.
  static bool _writing = false;

  /// R41 — L'écriture en vol, pour qu'un effacement puisse l'ATTENDRE : elle a
  /// photographié le tampon avant le vidage, et son renommage final recréerait
  /// le fichier qu'on vient d'effacer.
  static Future<void>? _writeInFlight;

  static void _flushIfDirty() {
    if (!_dirty || _writing) return;
    final File? f = _currentFile;
    if (f == null) return;
    _writeInFlight = _writeSnapshot(f);
    unawaited(_writeInFlight!);
  }

  /// Recopie l'état ENTIER du tampon (déjà plafonné à `maxLines`/`maxChars`)
  /// plutôt que d'ajouter la ligne : ça borne trivialement la taille du
  /// fichier à la taille du tampon mémoire. Le contenu est déjà rédigé
  /// (chaque ligne l'a été à l'entrée dans [add]) : le puits disque n'a
  /// jamais accès à une ligne en clair.
  ///
  /// §logPersist — revue 2026-09-11, D3B-12 — ⚠️ **La promesse « jamais un
  /// fichier corrompu » était FAUSSE** : `writeAsString` ouvre en
  /// `FileMode.write`, qui TRONQUE la destination avant d'écrire. Un kill en
  /// plein flush — le cas même pour lequel §logPersist existe — laissait un
  /// fichier coupé, et la session précédente était perdue. On écrit donc dans
  /// un `.tmp` puis on renomme (atomique sur Android) : un kill laisse au pire
  /// l'état du flush PRÉCÉDENT, intact. Pas de `flush: true` (fsync) : il ne
  /// protège que d'une coupure de courant, et coûterait une synchronisation
  /// de la mémoire flash toutes les 1,5 s sur une box.
  static Future<void> _writeSnapshot(File f) async {
    _dirty = false;
    _writing = true;
    final String content = dump();
    final File tmp = File('${f.path}$_tmpSuffix');
    try {
      // R41 — Point d'arrêt de TEST, `null` en production (voir
      // [pauseBeforeWriteForTest]). Il s'insère APRÈS la photo du tampon et
      // AVANT toute écriture : c'est le seul endroit d'où l'on peut reproduire
      // à coup sûr l'interleaving dangereux du vidage.
      final Future<void> Function()? pause = pauseBeforeWriteForTest;
      if (pause != null) await pause();
      await tmp.writeAsString(content);
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('⚠️ §tvLogsPersist : écriture disque échouée ($e).');
    } finally {
      _writing = false;
    }
  }

  /// Suffixe du fichier temporaire d'un flush (cf. [_writeSnapshot]).
  static const String _tmpSuffix = '.tmp';

  /// R41 — Retient une écriture juste avant qu'elle ne touche au disque, pour
  /// qu'un test puisse tenir la course « écriture en vol ». `null` partout
  /// ailleurs : en production, [_writeSnapshot] ne fait qu'un test de nullité.
  ///
  /// ⚠️ **Pourquoi une couture, alors qu'un test de timing suffirait en
  /// apparence.** Il ne suffit pas : mesuré, un test qui lance simplement une
  /// grosse écriture puis un vidage produit l'interleaving BÉNIN — la purge
  /// efface le `.tmp`, le renommage échoue (`errno 2`) et rien n'est
  /// ressuscité. Il restait donc vert même en retirant la garde qu'il
  /// prétendait tenir. Le cas DANGEREUX est l'autre : les trois suppressions
  /// passent AVANT l'écriture, qui recrée ensuite son `.tmp` et le renomme sur
  /// `current` — le fichier renaît avec le contenu d'avant le vidage.
  @visibleForTesting
  static Future<void> Function()? pauseBeforeWriteForTest;

  /// R41 — Efface les DEUX fichiers de session, plus un `.tmp` en vol. Rend
  /// `true` si le disque est propre, `false` si un fichier a résisté.
  ///
  /// ⚠️ **L'ordre des ATTENTES.**
  ///   - L'amorçage d'abord : si la rotation n'a pas encore tourné (console
  ///     ouverte très tôt après le boot), elle renommerait le fichier courant
  ///     en « précédent » APRÈS notre effacement — elle ressusciterait
  ///     exactement ce qu'on vient de détruire.
  ///   - L'écriture en vol ensuite : [_writeSnapshot] a photographié le tampon
  ///     AVANT le vidage, et son renommage recréerait le fichier courant avec
  ///     l'ancien contenu.
  ///
  /// ⚠️ **F2 — L'ordre des SUPPRESSIONS : `previous` en premier.** Chaque
  /// suppression est un point de suspension, et le geste que §tvLogsPersist
  /// documente est précisément celui d'une personne qui TUE l'application.
  /// Mourir entre deux suppressions en ayant commencé par `current` laissait
  /// intact le seul fichier qui motive ce ticket — et le privait du renommage
  /// qui l'aurait écrasé au démarrage suivant : le fichier qu'on voulait
  /// détruire devenait plus durable qu'avant le correctif.
  ///
  /// ⚠️ **F4b — Pourquoi le garde-fou `_persistInit == null` est sûr.** Pas
  /// « parce que ce sont des tests » : parce que [install] amorce la
  /// persistance inconditionnellement et qu'il est appelé une seule fois, très
  /// tôt (`main.dart:103`, unique appel du dépôt). Sans cet amorçage, un vidage
  /// serait un no-op, puis [awaitPreviousSession] appellerait
  /// [_ensurePersistence] : la rotation ferait RENAÎTRE `previous` à partir de
  /// `current`, et le vidage aurait ressuscité ce qu'il devait détruire.
  /// Déplacer [install] plus tard dans le démarrage casserait ce raisonnement.
  static Future<bool> _purgePersistedSessions() async {
    if (_persistInit == null) return true; // rien sur disque : rien à effacer
    try {
      await _ensurePersistence();
      await _writeInFlight;
    } catch (_) {}

    // ⚠️ **Le second effacement mémoire n'est PAS un doublon de [_clearMemory].**
    // La rotation qu'on vient d'attendre LIT le fichier « précédent » et
    // repeuple ces deux champs : sans cette seconde annulation, un vidage
    // déclenché avant la fin de l'amorçage rendait la session précédente à la
    // console juste après l'avoir effacée. Mesuré — c'est le test « un vidage
    // lancé AVANT la fin de la rotation ». L'annulation de [_clearMemory] reste
    // nécessaire, elle : elle ferme la lecture réseau tout de suite, sans
    // dépendre de ce qui se passe ici.
    _previousSessionText = null;
    _previousSessionLines = 0;

    final File? current = _currentFile;
    if (current == null) return true; // persistance indisponible : rien d'écrit

    // F3 — Le timer ne doit pas réécrire un fichier pendant qu'on l'efface, et
    // son rétablissement va dans un `finally` : sans ça, une sortie anticipée
    // laisserait la persistance morte pour toute la session.
    //
    // ⚠️ **Ce qu'on observe après un vidage** : `current` est ABSENT au retour,
    // et réapparaît vide au tour d'horloge suivant (≤ 1,5 s) ou à la première
    // ligne écrite. Il n'est pas recréé sur-le-champ — c'est le sens du
    // `flushNow: false` du `finally` : recréer immédiatement le fichier qu'on
    // vient d'effacer, avec son `.tmp` et un descripteur ouvert, pendant qu'on
    // s'apprête à annoncer un disque propre, serait un mensonge.
    _flushTimer?.cancel();
    _flushTimer = null;
    try {
      bool toutEfface = true;
      for (final File f in <File>[
        File('${current.parent.path}/$_previousFileName'),
        current,
        File('${current.path}$_tmpSuffix'),
      ]) {
        try {
          // Suppression INCONDITIONNELLE : un `exists()` préalable n'ajouterait
          // qu'une fenêtre entre le test et l'effacement. « Déjà absent » est
          // le résultat voulu, pas un échec.
          await f.delete();
        } on PathNotFoundException {
          // Le fichier n'était pas là : c'est exactement ce qu'on voulait.
        } catch (e) {
          // ⚠️ L'exception ne dit pas l'état FINAL. Mesuré sous Windows : deux
          // « Vider » rapprochés se croisent, et la seconde suppression du même
          // fichier rend « accès refusé » (errno 5) pendant que la première est
          // encore en attente — alors que le fichier part bel et bien. Seul le
          // résultat compte : reste-t-il quelque chose à ce chemin ?
          if (await FileSystemEntity.type(f.path) !=
              FileSystemEntityType.notFound) {
            toutEfface = false;
            debugPrint('⚠️ R41 : effacement de ${f.uri.pathSegments.last} refusé ($e).');
          }
        }
      }
      return toutEfface;
    } finally {
      // F3 — Sans `flushNow: false`, on recréerait immédiatement le fichier
      // qu'on vient d'effacer (vide, mais avec un `.tmp` en vol).
      _startFlushTimer(flushNow: false);
    }
  }

  /// Attend que la rotation ait tourné (best effort, ne lève jamais) puis
  /// renvoie [previousSessionDump]. À utiliser côté console web : elle peut
  /// être ouverte très tôt après le boot, avant que l'amorçage disque (async)
  /// n'ait eu le temps de finir.
  static Future<String?> awaitPreviousSession() async {
    final Future<void> init = _ensurePersistence();
    try {
      await init;
    } catch (_) {
      // _initPersistence n'est pas censée relancer, mais on ne fait
      // jamais confiance à du code I/O pour ça.
    }
    return _previousSessionText;
  }

  @visibleForTesting
  static void resetPersistenceForTest() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _persistInit = null;
    _persistInitDone = false;
    _currentFile = null;
    _previousSessionText = null;
    _previousSessionLines = 0;
    _dirty = false;
    _writing = false;
    _writeInFlight = null;
    pauseBeforeWriteForTest = null;
  }

  /// revue 2026-09-11, D3B-12 — Amorce la persistance (rotation comprise)
  /// SANS [install], qui détournerait `debugPrint` et les gestionnaires
  /// d'erreurs du processus de test.
  @visibleForTesting
  static Future<void> initPersistenceForTest() => _ensurePersistence();

  /// revue 2026-09-11, D3B-12 — Un flush immédiat et ATTENDU (le vrai est
  /// déclenché par le `Timer`, jamais attendu).
  ///
  /// ⚠️ **F7** — Cette couture de test alimente un état de PRODUCTION :
  /// `_writeInFlight` est lu par [_purgePersistedSessions], qui l'attend avant
  /// d'effacer. C'est voulu — c'est ce qui rend la course « écriture en vol »
  /// testable — mais ça veut dire qu'un changement ici touche le vidage réel.
  @visibleForTesting
  static Future<void> flushNowForTest() {
    final File? f = _currentFile;
    if (f == null || _writing) return Future<void>.value();
    return _writeInFlight = _writeSnapshot(f);
  }

  // ── Traceur de touches ───────────────────────────────────────────────────

  static bool _keyTrace = false;
  static bool _handlerAttached = false;

  /// Journalise chaque touche reçue — le seul moyen de savoir ce qu'une
  /// télécommande émet réellement quand on ne peut pas brancher logcat.
  ///
  /// Le handler est un **observateur pur** : il retourne toujours `false`, donc
  /// il ne consomme jamais l'événement et ne peut pas casser la navigation.
  static bool get keyTrace => _keyTrace;

  static set keyTrace(bool value) {
    if (_keyTrace == value) return;
    _keyTrace = value;
    if (value && !_handlerAttached) {
      HardwareKeyboard.instance.addHandler(_onKey);
      _handlerAttached = true;
    } else if (!value && _handlerAttached) {
      HardwareKeyboard.instance.removeHandler(_onKey);
      _handlerAttached = false;
    }
    add(value ? '⌨️ Traceur de touches ACTIVÉ' : '⌨️ Traceur de touches désactivé');
  }

  static bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      final LogicalKeyboardKey k = event.logicalKey;
      trace('⌨️ ${k.debugName ?? k.keyLabel} '
          '(logical 0x${k.keyId.toRadixString(16)}, '
          'physical 0x${event.physicalKey.usbHidUsage.toRadixString(16)})');
    }
    return false; // observateur pur — ne consomme jamais
  }

  /// §focusTrace — Journalise le nœud qui prend le focus.
  ///
  /// Quand la télécommande « ne fait plus rien », la question n'est presque
  /// jamais « la touche arrive-t-elle ? » mais **« qu'est-ce qui a le focus ? »**
  /// — un focus resté sur l'écran du dessous fait avaler les flèches par
  /// celui-ci. C'est invisible sans logcat ; cette trace le rend lisible.
  ///
  /// Branché sur `Dpad(onFocusChange:)`, actif en même temps que le traceur de
  /// touches pour pouvoir lire touche et focus dans le même fil.
  ///
  /// ⚠️ **§focusName (2026-08-30)** — la première version imprimait
  /// `node.debugLabel ?? node.context?.widget.runtimeType`, ce qui donnait
  /// invariablement `focus → Focus [dans scope?]` : aucun `FocusNode` de l'app
  /// n'a de `debugLabel`, et le widget porteur est toujours le `Focus` interne
  /// de Flutter. La trace existait mais **ne nommait rien** — donc les deux
  /// tickets qu'elle devait trancher (§tvExitPage, §trackSheetFocus) restaient
  /// indécidables. On remonte désormais aux widgets applicatifs porteurs et au
  /// premier texte affiché à l'intérieur du nœud.
  static void traceFocus(FocusNode? node) {
    if (!_keyTrace) return;
    if (node == null) {
      trace('🎯 focus perdu (plus aucun élément focalisé)');
      return;
    }
    trace('🎯 focus → ${describeFocusNode(node)}');
  }

  /// §focusTrace — Ligne de trace libre, muette tant que le traceur est éteint.
  ///
  /// Sert aux traces de diagnostic ponctuelles (index de `PageView`, ancrage de
  /// rangée…) : elles seraient du bruit permanent dans un `debugPrint` nu.
  ///
  /// ⚠️ Passe par `debugPrint`, **pas** par [add] : la capture installée par
  /// [install] renvoie déjà tout `debugPrint` vers le tampon, donc la ligne
  /// arrive au même endroit — mais elle sort AUSSI sur logcat. Sur un appareil
  /// branché en adb (émulateur, box en débogage sans fil) la trace devient
  /// lisible sans ouvrir la console web. (§tourFix : en release, logcat est
  /// coupé — la trace ne vit plus que dans le tampon.)
  static void trace(String message) {
    if (!_keyTrace) return;
    debugPrint(message);
  }

  /// §focusName — Description LISIBLE d'un nœud de focus :
  /// `« TF1 FHD » FocusableCard < _HomeCard [dans _ModalScope…]`.
  static String describeFocusNode(FocusNode node) {
    final String? label = node.debugLabel;
    final BuildContext? ctx = node.context;
    // ⚠️ Un nœud mémorisé peut être DÉMONTÉ au moment où on le décrit (c'est
    // même le cas intéressant : « quel écran mort garde le focus ? »). Lire
    // `Element.widget` sur un élément défunt lève — une trace ne doit jamais
    // faire tomber l'application qu'elle observe.
    final bool alive = ctx != null && ctx.mounted;
    String widgets = '?';
    String? text;
    if (alive) {
      try {
        widgets = _widgetChain(ctx);
        text = _firstText(ctx);
      } catch (_) {
        widgets = 'nœud en cours de démontage';
      }
    } else if (ctx != null) {
      widgets = 'nœud DÉMONTÉ (${_safeType(ctx)})';
    }
    final String scope = _scopeLabel(node);
    final StringBuffer out = StringBuffer();
    if (text != null) out.write('« $text » ');
    out.write(widgets);
    if (label != null && label.isNotEmpty) out.write(' ($label)');
    out.write('   [dans $scope]');
    return out.toString();
  }

  static String _safeType(BuildContext ctx) {
    try {
      return ctx.widget.runtimeType.toString();
    } catch (_) {
      return '?';
    }
  }

  /// Widgets **applicatifs** qui portent le nœud, du plus proche au plus
  /// lointain. Les emballages structurels de Flutter sont écartés : ce sont eux
  /// qui masquaient l'information dans la version d'origine.
  static const Set<String> _structuralWidgets = <String>{
    'Focus', 'FocusScope', 'ExcludeFocus', 'Semantics', 'KeyedSubtree',
    'Builder', 'RepaintBoundary', 'MouseRegion', 'Listener', 'GestureDetector',
    'RawGestureDetector', 'InkWell', 'InkResponse', 'Material', 'Container',
    'Padding', 'SizedBox', 'DecoratedBox', 'ColoredBox', 'Align', 'Center',
    'ConstrainedBox', 'LayoutBuilder', 'AnimatedContainer', 'ClipRRect',
    'ClipRect', 'Opacity', 'AnimatedOpacity', 'Transform', 'Stack',
    'Positioned', 'Row', 'Column', 'Expanded', 'Flexible', 'IntrinsicWidth',
    'SafeArea', 'MediaQuery', 'DefaultTextStyle', 'IconTheme', 'Directionality',
    'Actions', 'Shortcuts', 'ValueListenableBuilder', 'AnimatedBuilder',
    'ListenableBuilder', 'InheritedTheme', 'Theme', 'TweenAnimationBuilder',
    'FocusTraversalGroup', 'FocusTraversalOrder', 'TapRegion',
    // Internes Material/Ink : présents sous TOUS les boutons, ils chassaient
    // les widgets applicatifs de la fenêtre des 3 noms retenus.
    '_ActionsScope', '_ActionsMarker', '_ParentInkResponseProvider',
    '_InkResponseStateWidget', '_InkFeatures', '_ShortcutsMarker',
    '_EffectiveTickerMode', '_ModalScopeStatus', 'AnimatedSize',
    'IgnorePointer', 'AbsorbPointer', 'Visibility', 'Offstage', 'SelectionArea',
    'DefaultSelectionStyle', 'TextFieldTapRegion', 'CustomPaint', 'Flex',
  };

  static String _widgetChain(BuildContext ctx, {int keep = 3}) {
    final List<String> names = <String>[];
    // Le nœud lui-même d'abord, puis ses ancêtres.
    for (final String n in <String>[ctx.widget.runtimeType.toString()]) {
      if (!_structuralWidgets.contains(n)) names.add(n);
    }
    ctx.visitAncestorElements((Element el) {
      if (!el.mounted) return false;
      final String n = el.widget.runtimeType.toString();
      if (!_structuralWidgets.contains(n) &&
          !n.startsWith('_Inherited') &&
          !n.startsWith('_Focus') &&
          !names.contains(n)) {
        names.add(n);
      }
      return names.length < keep;
    });
    return names.isEmpty ? ctx.widget.runtimeType.toString() : names.join(' < ');
  }

  /// Premier texte affiché SOUS le nœud : c'est ce que l'utilisateur voit, donc
  /// la seule étiquette qui permette de reconnaître la carte à l'écran.
  /// Budget borné — un sous-arbre de carte peut être profond.
  static String? _firstText(BuildContext ctx, {int budget = 80}) {
    String? found;
    int left = budget;
    void walk(Element el) {
      if (found != null || left-- <= 0 || !el.mounted) return;
      final Object w = el.widget;
      if (w is Text) {
        final String? d = w.data?.trim();
        if (d != null && d.isNotEmpty) {
          found = d.length > 40 ? '${d.substring(0, 40)}…' : d;
          return;
        }
      } else if (w is Tooltip) {
        final String? m = w.message?.trim();
        if (m != null && m.isNotEmpty) {
          found = m;
          return;
        }
      }
      el.visitChildren(walk);
    }

    if (ctx is Element) ctx.visitChildren(walk);
    return found;
  }

  /// Premier scope de focus **nommé** au-dessus du nœud. Les routes modales de
  /// Flutter portent un `debugLabel` (`ModalRoute Focus Scope`) : c'est lui qui
  /// dit à quel ÉCRAN appartient le focus — l'information décisive quand une
  /// feuille se ferme pendant qu'une autre s'ouvre.
  static String _scopeLabel(FocusNode node) {
    for (final FocusNode a in <FocusNode>[node, ...node.ancestors]) {
      if (a is FocusScopeNode) {
        final String? l = a.debugLabel;
        if (l != null && l.isNotEmpty) return l;
      }
    }
    return 'scope sans nom';
  }
}

/// §cookieScope — Un en-tête `Cookie:` / `Set-Cookie:` et TOUT ce qui suit.
///
/// ⚠️ **La valeur va jusqu'au bout de la ligne, volontairement.** Contrairement
/// à `password=hunter2`, une valeur de cookie contient des `;`, des espaces et
/// parfois des virgules (`PHPSESSID=abc; path=/; HttpOnly`, ou plusieurs
/// cookies dans un même `Set-Cookie`) : la borne `[^\s,;&)\]}"]+` de la règle
/// générique s'arrêterait au premier point-virgule et laisserait le reste en
/// clair. Seul `}` arrête le masquage, pour qu'un `debugPrint` d'une Map
/// d'en-têtes (`{cookie: …, content-type: …}`) garde sa fin lisible.
///
/// `set-cookie` est placé EN PREMIER dans l'alternative : sinon l'alternative
/// `cookie` s'appliquerait à partir du milieu du mot et laisserait `Set-` seul.
final RegExp _cookieHeader = RegExp(
  r'\b(set-cookie|cookie)\s*[:=]\s*[^\n}]*',
  caseSensitive: false,
);

/// §tvLogs — Masque les identifiants d'une ligne de log avant stockage.
///
/// Trois filets successifs :
///   1. toute URL `http(s)://…` passe par [redactUrl] (formes Xtream en path
///      `/movie/USER/PASS/…` **et** en query `?username=…&password=…`) ;
///   2. un `username=` / `password=` isolé (hors URL) est masqué par regex ;
///   3. §cookieScope — un en-tête `Cookie:` / `Set-Cookie:`.
///
/// ⚠️ **Pourquoi les cookies MAINTENANT** : un panel Xtream authentifie souvent
/// par session, et un cookie de session vaut exactement ce que vaut le couple
/// identifiant/mot de passe — il ouvre l'abonnement. Le journal §tvLogs étant
/// servi en HTTP clair sur le réseau local, un `Set-Cookie:` qui traverse est
/// une fuite de la même gravité qu'une URL non masquée. Invariant §tourFix : ce
/// qu'on sait extraire d'une trace réseau, on doit savoir le masquer.
String sanitizeForLog(String line) {
  String out = line.replaceAllMapped(
    RegExp(r'https?://[^\s"' r"'" r'<>\\]+'),
    (Match m) => redactUrl(m.group(0)),
  );
  out = out.replaceAllMapped(
    RegExp(r'\b(username|password|pass|pwd|token)\s*[=:]\s*([^\s,;&)\]}"]+)',
        caseSensitive: false),
    (Match m) => '${m.group(1)}=***',
  );
  out = out.replaceAllMapped(
    _cookieHeader,
    (Match m) => '${m.group(1)}=***',
  );
  return out;
}
