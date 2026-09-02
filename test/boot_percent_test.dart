import 'dart:convert';
import 'dart:io';

import 'package:aetherStream/core/boot/boot_status.dart';
import 'package:aetherStream/core/utils/formatters.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/feature/search/xtream_catalog_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// §bootPercent — La progression du démarrage doit MESURER, pas décorer.
///
/// Ce que ces tests verrouillent, c'est le défaut d'origine : le parseur
/// publiait `0.05` puis `1.0`, avec 16 secondes d'immobilité entre les deux
/// (mesuré sur téléviseur). Une barre figée à 5 % ne dit pas « ça travaille »,
/// elle dit « c'est planté ».
void main() {
  group('formatCount', () {
    test('groupe les milliers par espace fine', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
      expect(formatCount(1000), '1 000');
      expect(formatCount(53781), '53 781');
      expect(formatCount(1234567), '1 234 567');
    });

    test('un nombre négatif ne perd pas son signe', () {
      expect(formatCount(-4200), '-4 200');
    });
  });

  group('BootStatus.setDetail', () {
    setUp(BootStatus.reset);

    test('le détail accompagne l\'étape sans toucher à la progression', () {
      BootStatus.set('// analyse…', progress: 0.4);
      BootStatus.setDetail('films · 100/200');

      expect(BootStatus.step.value.detail, 'films · 100/200');
      expect(BootStatus.step.value.progress, 0.4);
      expect(BootStatus.step.value.label, '// analyse…');
    });

    test('la progression ne perd pas le détail en cours de route', () {
      BootStatus.set('// analyse…', progress: 0);
      BootStatus.setDetail('films · 100/200');
      BootStatus.report(0.5);

      // ⚠️ `report` reconstruit un BootStep : sans reprise explicite du détail,
      // le compteur clignotait puis disparaissait à chaque palier.
      expect(BootStatus.step.value.detail, 'films · 100/200');
      expect(BootStatus.step.value.progress, 0.5);
    });

    test('un détail identique ne renotifie pas', () {
      BootStatus.set('// analyse…', progress: 0);
      int notifications = 0;
      void listener() => notifications++;
      BootStatus.step.addListener(listener);

      BootStatus.setDetail('films · 100/200');
      BootStatus.setDetail('films · 100/200');
      BootStatus.setDetail('films · 100/200');

      BootStatus.step.removeListener(listener);
      expect(notifications, 1);
    });

    test('changer d\'étape efface le détail de la précédente', () {
      BootStatus.set('// analyse…', progress: 0);
      BootStatus.setDetail('films · 100/200');
      BootStatus.set('// prêt.', progress: 1);

      // Sans ça, « films · 100/200 » restait affiché sous « // prêt. ».
      expect(BootStatus.step.value.detail, isNull);
    });

    test('reset efface le détail', () {
      BootStatus.set('// analyse…', progress: 0);
      BootStatus.setDetail('films · 100/200');
      BootStatus.reset();

      expect(BootStatus.step.value.detail, isNull);
    });

    test('le détail ne crée jamais d\'entrée dans le journal', () {
      BootStatus.set('// analyse…', progress: 0);
      for (int i = 0; i < 50; i++) {
        BootStatus.setDetail('films · $i/50');
      }
      expect(BootStatus.history.value, isEmpty);
    });
  });

  group('§bootLog — dumpToLog', () {
    setUp(BootStatus.reset);

    test('un journal vide ne produit rien', () {
      final lines = <String>[];
      final previous = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
      BootStatus.dumpToLog();
      debugPrint = previous;

      expect(lines, isEmpty);
    });

    test('chaque étape franchie sort avec sa durée', () {
      BootStatus.set('// première…');
      BootStatus.set('// deuxième…');
      BootStatus.set('// prêt.');

      final lines = <String>[];
      final previous = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
      BootStatus.dumpToLog();
      debugPrint = previous;

      // En-tête + les deux étapes closes (la courante n'est pas encore finie).
      expect(lines.first, contains('§bootLog'));
      expect(lines.length, 3);
      expect(lines[1], contains('// première…'));
      expect(lines[2], contains('// deuxième…'));
    });
  });

  group('§bootPercent — XtreamCatalogParser publie une progression RÉELLE', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('bootpercent'));
    tearDown(() => dir.deleteSync(recursive: true));

    /// Écrit un catalogue minimal mais structurellement authentique.
    String writeCatalog({
      required int live,
      required int vod,
      required int series,
    }) {
      final path = '${dir.path}/catalogue.json';
      File(path).writeAsStringSync(jsonEncode({
        'host': 'http://exemple.test:8080',
        'user': 'u',
        'pass': 'p',
        'live': [
          for (int i = 0; i < live; i++)
            {'stream_id': '$i', 'name': 'Chaîne $i', '_cat': 'France'},
        ],
        'vod': [
          for (int i = 0; i < vod; i++)
            {
              'stream_id': '$i',
              'name': 'Film $i (2024)',
              '_cat': 'Films | Action',
              'container_extension': 'mp4',
            },
        ],
        'series': [
          for (int i = 0; i < series; i++)
            {'series_id': '$i', 'name': 'Série $i', '_cat': 'Séries | Drame'},
        ],
      }));
      return path;
    }

    test('la barre avance vraiment : ni deux valeurs, ni recul', () async {
      final path = writeCatalog(live: 60, vod: 300, series: 120);
      final films = <M3uEntry>[];
      final series = <M3uEntry>[];
      final tv = <M3uEntry>[];
      final values = <double>[];

      await XtreamCatalogParser.parseFile(
        path,
        films,
        series,
        tv,
        accountId: 'test',
        onProgress: values.add,
      );

      expect(films.length, 300);
      expect(series.length, 120);
      expect(tv.length, 60);

      // Le défaut d'origine, exactement : deux valeurs et rien entre.
      expect(values.length, greaterThan(10),
          reason: 'une progression de 2 valeurs est le bug qu\'on corrige');

      // Monotone : une barre qui recule est pire que pas de barre.
      for (int i = 1; i < values.length; i++) {
        expect(values[i], greaterThanOrEqualTo(values[i - 1]),
            reason: 'recul à l\'index $i : ${values[i - 1]} → ${values[i]}');
      }

      expect(values.first, closeTo(0.09, 0.0001),
          reason: 'le premier repère est le poids MESURÉ du décodage');
      expect(values.last, 1.0);
    });

    test('le débit reste borné quelle que soit la taille du catalogue',
        () async {
      final path = writeCatalog(live: 200, vod: 2000, series: 800);
      final values = <double>[];

      await XtreamCatalogParser.parseFile(
        path,
        <M3uEntry>[],
        <M3uEntry>[],
        <M3uEntry>[],
        accountId: 'test',
        onProgress: values.add,
      );

      // 3 000 entrées ne doivent pas produire 3 000 messages : le throttle vit
      // DANS l'isolate, sinon on paierait 3 000 traversées de port pour faire
      // bouger une barre de 100 pixels.
      expect(values.length, lessThanOrEqualTo(105));
      expect(values.last, 1.0);
    });

    test('le détail nomme la section et compte les entrées', () async {
      final path = writeCatalog(live: 40, vod: 200, series: 60);
      final details = <String>[];

      await XtreamCatalogParser.parseFile(
        path,
        <M3uEntry>[],
        <M3uEntry>[],
        <M3uEntry>[],
        accountId: 'test',
        onDetail: details.add,
      );

      expect(details.first, contains('300 entrées'));
      expect(details.any((d) => d.startsWith('chaînes ·')), isTrue);
      expect(details.any((d) => d.startsWith('films ·')), isTrue);
      expect(details.any((d) => d.startsWith('séries ·')), isTrue);
    });

    test('un catalogue vide ne divise pas par zéro', () async {
      final path = writeCatalog(live: 0, vod: 0, series: 0);
      final values = <double>[];

      await XtreamCatalogParser.parseFile(
        path,
        <M3uEntry>[],
        <M3uEntry>[],
        <M3uEntry>[],
        accountId: 'test',
        onProgress: values.add,
      );

      expect(values.last, 1.0);
      expect(values.every((v) => v >= 0 && v <= 1), isTrue);
    });

    test('sans rappel, aucun port n\'est ouvert et le parsing marche', () async {
      final path = writeCatalog(live: 10, vod: 10, series: 10);
      final films = <M3uEntry>[];

      await XtreamCatalogParser.parseFile(
        path,
        films,
        <M3uEntry>[],
        <M3uEntry>[],
        accountId: 'test',
      );

      expect(films.length, 10);
    });
  });
}
