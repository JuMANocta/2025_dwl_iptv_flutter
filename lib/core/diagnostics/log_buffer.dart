import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart'
    show BuildContext, Element, FocusNode, FocusScopeNode, Text;

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
