import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import '../models/xmltv_program.dart';

/// Service EPG basé sur un fichier XMLTV public (xmltvfr.fr — TNT France).
/// Télécharge et cache le fichier 12h. Expose les programmes par chaîne via tvg-id.
class XmltvService {
  static const _url = 'https://xmltvfr.fr/xmltv/xmltv_tnt.xml';
  // v2 : invalide l'ancien cache (encodage corrompu possible)
  static const _cacheFile = 'xmltv_tnt_cache_v2.xml';
  static const _cacheTtl = Duration(hours: 12);

  /// Timeout global pour `ensureLoaded()` (téléchargement + parsing inclus).
  static const _loadTimeout = Duration(seconds: 20);

  // Cache mémoire
  static Map<String, List<XmltvProgram>>? _programs; // tvgId normalisé → programmes
  static Map<String, String>? _channelIcons;          // tvgId normalisé → URL icône
  static DateTime? _loadedAt;
  static bool _isLoading = false; // garde contre les chargements concurrents

  // -------------------------------------------------------------------------
  // API publique
  // -------------------------------------------------------------------------

  /// Charge le fichier XMLTV si nécessaire (en mémoire ou depuis le cache fichier).
  /// Timeout global : $_loadTimeout. Protégé contre les appels concurrents.
  static Future<void> ensureLoaded() async {
    if (_programs != null && _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < _cacheTtl) { return; }

    // Si un chargement est déjà en cours, on attend qu'il se termine (max timeout).
    if (_isLoading) {
      final deadline = DateTime.now().add(_loadTimeout);
      while (_isLoading && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      return;
    }

    _isLoading = true;
    try {
      await Future.any([
        _doLoad(),
        Future.delayed(_loadTimeout),
      ]);
    } finally {
      _isLoading = false;
    }
  }

  static Future<void> _doLoad() async {
    try {
      final content = await _getContent();
      if (content != null) await _parse(content);
    } catch (e) {
      debugPrint('⚠️ XmltvService: chargement échoué → $e');
    }
  }

  /// Programme actuellement diffusé sur [tvgId], ou null.
  static Future<XmltvProgram?> getCurrentProgram(String tvgId) async {
    await ensureLoaded();
    final now = DateTime.now();
    return _forChannel(tvgId).where((p) => p.isCurrentAt(now)).firstOrNull;
  }

  /// Prochain programme après celui en cours (ou à venir le plus proche).
  static Future<XmltvProgram?> getNextProgram(String tvgId) async {
    await ensureLoaded();
    final now = DateTime.now();
    final list = _forChannel(tvgId).where((p) => p.start.isAfter(now)).toList();
    return list.isEmpty ? null : list.first;
  }

  /// Tous les programmes d'une chaîne pour un [date] donné (heure locale).
  static Future<List<XmltvProgram>> getProgramsForDay(
      String tvgId, DateTime date) async {
    await ensureLoaded();
    return _forChannel(tvgId).where((p) {
      return p.start.year == date.year &&
          p.start.month == date.month &&
          p.start.day == date.day;
    }).toList();
  }

  /// URL de l'icône de la chaîne, ou null si non trouvée.
  static Future<String?> getChannelIconUrl(String tvgId) async {
    await ensureLoaded();
    return _channelIcons?[_normalize(tvgId)];
  }

  /// Vide le cache mémoire (force un rechargement au prochain appel).
  /// Ne fait rien si un chargement est en cours.
  static void invalidate() {
    if (_isLoading) return;
    _programs = null;
    _channelIcons = null;
    _loadedAt = null;
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  static List<XmltvProgram> _forChannel(String tvgId) {
    if (_programs == null) return [];
    // Essai direct, puis sans suffixe .fr, puis juste le préfixe
    final key = _normalize(tvgId);
    return _programs![key] ??
        _programs![key.replaceAll('.fr', '')] ??
        _fuzzyMatch(key) ??
        [];
  }

  /// Fuzzy match en deux passes.
  /// Passe 1 : égalité alphanumérique stricte (ex : "tf1fr" == "tf1fr").
  /// Passe 2 : startsWith sans suffixes qualité — "tf1fhd" → base "tf1" → préfixe de "tf1fr".
  static List<XmltvProgram>? _fuzzyMatch(String key) {
    if (_programs == null) return null;
    final short = key.replaceAll(RegExp(r'[^a-z0-9]'), '');

    // Passe 1 : égalité alphanumérique exacte
    for (final k in _programs!.keys) {
      if (_normalize(k).replaceAll(RegExp(r'[^a-z0-9]'), '') == short) {
        return _programs![k];
      }
    }

    // Passe 2 : retire les suffixes qualité du tvgId, puis startsWith bidirectionnel
    final base = short
        .replaceAll(RegExp(r'(4k|uhd|fhd|hd|sd|bkp|backup|exclu[a-z]*)$'), '');
    if (base.length >= 2) {
      for (final k in _programs!.keys) {
        final kShort = _normalize(k).replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (kShort.length >= 2 &&
            (kShort.startsWith(base) || base.startsWith(kShort))) {
          return _programs![k];
        }
      }
    }
    return null;
  }

  static String _normalize(String s) => s.toLowerCase().trim();

  // ---- Décodage encodage-safe ----

  /// Décode un fichier XML en respectant sa déclaration d'encodage.
  ///
  /// Stratégie :
  /// 1. Lit les 300 premiers octets comme ASCII (la déclaration XML est toujours ASCII).
  /// 2. Extrait l'encodage déclaré : `<?xml ... encoding="ISO-8859-1"?>`.
  /// 3. Décode tout le fichier avec cet encodage.
  /// 4. Fallback : UTF-8 strict, puis Latin-1 si exception.
  ///
  /// Sans cette lecture, utf8.decode() peut réussir silencieusement sur du Latin-1
  /// (certaines séquences de bytes Latin-1 forment des UTF-8 valides mais incorrects).
  static String _decodeXmlBytes(List<int> bytes) {
    // Lit l'en-tête en ASCII pur (les 300 premiers bytes sont toujours ASCII dans une déclaration XML)
    final header = String.fromCharCodes(
      bytes.take(300).where((b) => b < 128),
    );
    // Cherche encoding="..." ou encoding='...' (double quotes = standard XML)
    final encodingMatch = RegExp(r'encoding="([^"]+)"', caseSensitive: false)
            .firstMatch(header) ??
        RegExp(r"encoding='([^']+)'", caseSensitive: false).firstMatch(header);
    final declared = encodingMatch?.group(1)?.toLowerCase() ?? 'utf-8';

    if (declared == 'iso-8859-1' ||
        declared == 'latin-1' ||
        declared == 'windows-1252') {
      debugPrint('📺 XmltvService: encodage XML déclaré → $declared → décodage Latin-1');
      return latin1.decode(bytes);
    }

    // UTF-8 déclaré (ou non déclaré) : tente strict, fallback Latin-1
    try {
      return utf8.decode(bytes);
    } catch (_) {
      debugPrint('⚠️ XmltvService: UTF-8 invalide malgré déclaration → fallback Latin-1');
      return latin1.decode(bytes);
    }
  }

  // ---- Téléchargement / cache fichier ----

  static Future<String?> _getContent() async {
    final cacheDir = await getTemporaryDirectory();
    final file = File('${cacheDir.path}/$_cacheFile');

    // Utilise le cache fichier s'il est récent
    if (file.existsSync()) {
      final age = DateTime.now().difference(file.lastModifiedSync());
      if (age < _cacheTtl) {
        debugPrint('📺 XmltvService: lecture cache fichier (${age.inMinutes}min)');
        return utf8.decode(file.readAsBytesSync()); // cache toujours écrit en UTF-8
      }
    }

    // Télécharge
    debugPrint('📡 XmltvService: téléchargement $_url');
    try {
      final resp = await http.get(Uri.parse(_url))
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        // Décode en respectant la déclaration d'encodage du fichier XML.
        // ⚠️ resp.body est trompeur : il utilise Latin-1 si pas de charset HTTP.
        // ⚠️ utf8.decode() peut réussir silencieusement sur du Latin-1 (faux positif)
        //    si les bytes forment par coïncidence des séquences UTF-8 valides.
        // → On lit la déclaration XML en ASCII (toujours ASCII) pour connaître l'encodage réel.
        final content = _decodeXmlBytes(resp.bodyBytes);
        // Sauvegarde toujours en UTF-8 pour le cache (encodage normalisé)
        await file.writeAsBytes(utf8.encode(content));
        debugPrint('✅ XmltvService: fichier téléchargé (${resp.bodyBytes.length ~/ 1024} Ko)');
        return content;
      }
      debugPrint('❌ XmltvService: HTTP ${resp.statusCode}');
    } catch (e) {
      debugPrint('❌ XmltvService: erreur réseau → $e');
      // Fallback : utilise le cache même périmé
      if (file.existsSync()) {
        debugPrint('⚠️ XmltvService: fallback cache périmé');
        return utf8.decode(file.readAsBytesSync());
      }
    }
    return null;
  }

  // ---- Parsing XML ----

  static Future<void> _parse(String content) async {
    final result = await compute(_parseXml, content);
    _programs = result['programs'] as Map<String, List<XmltvProgram>>;
    _channelIcons = result['icons'] as Map<String, String>;
    _loadedAt = DateTime.now();
    debugPrint('✅ XmltvService: ${_programs!.length} chaînes chargées, '
        '${_programs!.values.fold(0, (a, b) => a + b.length)} programmes');
  }

  /// Fonction top-level pour `compute()` (isolate).
  static Map<String, dynamic> _parseXml(String content) {
    final programs = <String, List<XmltvProgram>>{};
    final icons = <String, String>{};

    try {
      final doc = XmlDocument.parse(content);
      final tv = doc.rootElement;

      // Chaînes → icônes
      for (final ch in tv.findElements('channel')) {
        final id = ch.getAttribute('id');
        if (id == null) continue;
        final iconEl = ch.findElements('icon').firstOrNull;
        final src = iconEl?.getAttribute('src');
        if (src != null && src.isNotEmpty) {
          icons[id.toLowerCase().trim()] = src;
        }
      }

      // Programmes
      for (final prog in tv.findElements('programme')) {
        final channelId = prog.getAttribute('channel');
        final startRaw = prog.getAttribute('start');
        final stopRaw = prog.getAttribute('stop');
        if (channelId == null || startRaw == null || stopRaw == null) continue;

        DateTime start, stop;
        try {
          start = XmltvProgram.parseDate(startRaw);
          stop = XmltvProgram.parseDate(stopRaw);
        } catch (_) {
          continue;
        }

        final title = _text(prog, 'title') ?? '';
        if (title.isEmpty) continue;

        final program = XmltvProgram(
          channelId: channelId,
          start: start,
          stop: stop,
          title: title,
          subtitle: _text(prog, 'sub-title'),
          description: _text(prog, 'desc'),
          category: _text(prog, 'category'),
          iconUrl: prog.findElements('icon').firstOrNull?.getAttribute('src'),
          rating: prog.findElements('rating').firstOrNull
              ?.findElements('value').firstOrNull?.innerText.trim(),
        );

        final key = channelId.toLowerCase().trim();
        programs.putIfAbsent(key, () => []).add(program);
      }

      // Trie par heure de début
      for (final list in programs.values) {
        list.sort((a, b) => a.start.compareTo(b.start));
      }
    } catch (e) {
      debugPrint('💀 XmltvService._parseXml: $e');
    }

    return {'programs': programs, 'icons': icons};
  }

  static String? _text(XmlElement el, String tag) {
    final nodes = el.findElements(tag);
    if (nodes.isEmpty) return null;
    final t = nodes.first.innerText.trim();
    return t.isEmpty ? null : t;
  }
}
