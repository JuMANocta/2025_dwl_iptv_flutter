import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/core/diagnostics/log_buffer.dart';

/// §tvLogs — Le journal est servi sur le **réseau local** (console web) et
/// destiné à être exporté puis transmis. Deux invariants s'y jouent :
///
///   1. **aucun identifiant ne doit en sortir** — la rédaction est faite au
///      niveau du puits justement parce qu'on ne peut pas garantir que chaque
///      `debugPrint` de l'app pense à masquer son URL ;
///   2. le tampon reste **borné** — il tourne en permanence sur un Fire Stick.
void main() {
  setUp(DiagnosticLog.resetForTest);

  group('sanitizeForLog — rédaction des identifiants', () {
    test('URL Xtream en path : user et pass masqués, host conservé', () {
      const url = 'http://panel.example.com:8080/movie/jean/s3cr3t/12345.mkv';
      final out = sanitizeForLog('▶️ Lecture $url');
      expect(out, contains('panel.example.com'));
      expect(out, isNot(contains('jean')));
      expect(out, isNot(contains('s3cr3t')));
    });

    test('URL Xtream en query : username/password masqués', () {
      const url =
          'http://panel.example.com/player_api.php?username=jean&password=s3cr3t&action=get_vod';
      final out = sanitizeForLog(url);
      expect(out, isNot(contains('jean')));
      expect(out, isNot(contains('s3cr3t')));
      // L'action reste lisible : c'est elle qui a une valeur de diagnostic.
      expect(out, contains('get_vod'));
    });

    test('timeshift : les segments credentials sont masqués', () {
      const url =
          'http://host.tv:8080/timeshift/jean/s3cr3t/120/2026-08-14:20-00/55.ts';
      final out = sanitizeForLog(url);
      expect(out, isNot(contains('jean')));
      expect(out, isNot(contains('s3cr3t')));
    });

    test('password= hors URL (log applicatif brut) est masqué aussi', () {
      final out = sanitizeForLog('config chargée password: hunter2 ; ok');
      expect(out, isNot(contains('hunter2')));
      expect(out, contains('***'));
    });

    test('une ligne sans identifiant traverse intacte', () {
      const line = '✅ Playlist parsée : 134992 entrées en 2.4s';
      expect(sanitizeForLog(line), line);
    });
  });

  group('DiagnosticLog — tampon', () {
    test('add() horodate et conserve le message', () {
      DiagnosticLog.add('🚀 démarrage');
      expect(DiagnosticLog.lineCount, 1);
      expect(DiagnosticLog.dump(), contains('🚀 démarrage'));
      // Horodatage HH:mm:ss.SSS en tête de ligne.
      expect(DiagnosticLog.dump(), matches(RegExp(r'^\d{2}:\d{2}:\d{2}\.\d{3}')));
    });

    test('un message multiligne devient plusieurs lignes horodatées', () {
      DiagnosticLog.add('ligne 1\nligne 2\nligne 3');
      expect(DiagnosticLog.lineCount, 3);
    });

    test('la rédaction est appliquée à l\'écriture, pas à la lecture', () {
      DiagnosticLog.add('GET http://h.tv/movie/jean/s3cr3t/1.mkv');
      expect(DiagnosticLog.dump(), isNot(contains('s3cr3t')));
    });

    test('le tampon est plafonné et évince les plus anciennes lignes', () {
      for (int i = 0; i < DiagnosticLog.maxLines + 250; i++) {
        DiagnosticLog.add('ligne $i');
      }
      expect(DiagnosticLog.lineCount, DiagnosticLog.maxLines);
      // La plus ancienne est partie, la plus récente est là.
      expect(DiagnosticLog.dump(), isNot(contains('ligne 0 ')));
      expect(DiagnosticLog.dump(),
          contains('ligne ${DiagnosticLog.maxLines + 249}'));
    });

    test('tail(n) renvoie les n dernières lignes', () {
      for (int i = 0; i < 10; i++) {
        DiagnosticLog.add('l$i');
      }
      final last3 = DiagnosticLog.tail(3);
      expect(last3, hasLength(3));
      expect(last3.last, contains('l9'));
      // Demander plus que disponible ne déborde pas.
      expect(DiagnosticLog.tail(999), hasLength(10));
    });

    test('clear() vide le tampon et notifie', () {
      DiagnosticLog.add('a');
      final before = DiagnosticLog.revision.value;
      DiagnosticLog.clear();
      expect(DiagnosticLog.lineCount, 0);
      expect(DiagnosticLog.revision.value, greaterThan(before));
    });
  });
}
