// Recette AVD du 2026-09-17 — une coupure de téléchargement écrivait au journal
// « HttpException: …, uri = http://IP:8080/live/play/<jeton> » : l'adresse de
// REDIRECTION du fournisseur, dont le chemin est le jeton de lecture.
import 'package:aetherStream/core/diagnostics/log_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('derrière « uri = », seul l\'hôte survit', () {
    const String line = '💀 Erreur de flux : HttpException: Connection closed '
        'while receiving data, uri = http://102.0.0.1:8080/live/play/T1JETON/9';
    final String out = sanitizeForLog(line);
    expect(out, isNot(contains('T1JETON')));
    expect(out, contains('uri = http://102.0.0.1:8080/***'));
    expect(out, contains('Connection closed'));
  });

  test('une ligne sans « uri = » n\'est pas touchée par cette règle', () {
    const String line = '📥 §dlQueue — départ : Tony';
    expect(sanitizeForLog(line), line);
  });
}
