import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show FocusNode;

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
/// fuiter de mot de passe.
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

    // On délègue toujours à l'implémentation d'origine : en développement,
    // logcat continue de fonctionner exactement comme avant.
    _previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) add(message);
      _previousDebugPrint?.call(message, wrapWidth: wrapWidth);
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

  static void clear() {
    _lines.clear();
    _chars = 0;
    revision.value++;
  }

  @visibleForTesting
  static void resetForTest() {
    clear();
    keyTrace = false;
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
      add('⌨️ ${k.debugName ?? k.keyLabel} '
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
  static void traceFocus(FocusNode? node) {
    if (!_keyTrace) return;
    if (node == null) {
      add('🎯 focus perdu (plus aucun élément focalisé)');
      return;
    }
    final String label = node.debugLabel ?? node.context?.widget.runtimeType.toString() ?? '?';
    final String scope = node.enclosingScope?.debugLabel ?? 'scope?';
    add('🎯 focus → $label   [dans $scope]');
  }
}

/// §tvLogs — Masque les identifiants d'une ligne de log avant stockage.
///
/// Deux filets successifs :
///   1. toute URL `http(s)://…` passe par [redactUrl] (formes Xtream en path
///      `/movie/USER/PASS/…` **et** en query `?username=…&password=…`) ;
///   2. un `username=` / `password=` isolé (hors URL) est masqué par regex.
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
  return out;
}
