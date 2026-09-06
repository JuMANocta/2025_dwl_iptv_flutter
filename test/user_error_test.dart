import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/core/utils/user_error.dart';

/// §userError — [describeError] est la SEULE porte par laquelle une exception
/// atteint l'écran (snackbars, `EmptyState`, écran d'erreur du lecteur).
///
/// Le piège payé : `'❌ Échec : $e'` affichait le `toString()` d'une
/// `DioException`, qui pour certains types embarque l'URL de requête complète —
/// donc `?username=…&password=…` en clair sur l'écran de la TV. Le journal
/// §tvLogs était protégé par `sanitizeForLog`, l'écran ne l'était pas.
///
/// Trois invariants testés ici : jamais d'identifiant ni d'URL, un texte
/// français court (≤ 180 caractères, une seule ligne), et un mapping qui ne
/// laisse passer aucun jargon Dart (« Exception », « Bad state »).
void main() {
  const String leakyUrl =
      'http://h.example/get.php?username=SECRETU&password=SECRETP';
  final RequestOptions leakyRequest = RequestOptions(path: leakyUrl);

  /// Vérifie qu'aucun des deux identifiants ne traverse.
  void expectNoLeak(String out) {
    expect(out, isNot(contains('SECRETU')));
    expect(out, isNot(contains('SECRETP')));
  }

  group('describeError — DioException : jamais de credentials', () {
    test('type unknown avec SocketException en cause', () {
      final e = DioException(
        requestOptions: leakyRequest,
        type: DioExceptionType.unknown,
        error: const SocketException('x'),
      );
      final out = describeError(e);
      expectNoLeak(out);
      expect(out, isNotEmpty);
      // La cause est traduite, pas recopiée.
      expect(out, contains('Connexion impossible'));
    });

    test('type badResponse 401 : le code HTTP est conservé, pas l\'URL', () {
      final e = DioException(
        requestOptions: leakyRequest,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: leakyRequest, statusCode: 401),
      );
      final out = describeError(e);
      expectNoLeak(out);
      expect(out, contains('401'));
      expect(out, isNot(contains('h.example')));
    });

    test('type unknown SANS cause, message = requête brute → pas de fuite', () {
      // ⚠️ C'est LE type dont le `toString()` recopie la requête.
      final e = DioException(
        requestOptions: leakyRequest,
        type: DioExceptionType.unknown,
        message: 'Requête échouée : $leakyUrl',
      );
      final out = describeError(e);
      expectNoLeak(out);
      expect(out, isNot(contains('http')));
      expect(out, isNotEmpty);
    });

    test('chaque DioExceptionType → texte non vide, sans jargon ni URL', () {
      for (final type in DioExceptionType.values) {
        final e = DioException(requestOptions: leakyRequest, type: type);
        final out = describeError(e);
        expect(out, isNotEmpty, reason: '$type');
        expect(out, isNot(contains('Exception')), reason: '$type');
        expect(out, isNot(contains('http')), reason: '$type');
        expectNoLeak(out);
      }
    });
  });

  group('describeError — autres exceptions', () {
    test('HttpException dont le message porte une URL Xtream → masquée', () {
      final out = describeError(
          const HttpException('Erreur http://h/live/USER/PASS/1.ts'));
      expect(out, contains('***'));
      expect(out, isNot(contains('USER')));
      expect(out, isNot(contains('PASS')));
      // Le message métier (déjà en français dans l'app) est conservé.
      expect(out, startsWith('Erreur'));
    });

    test(
        'HttpException native (couche socket, anglais) → traduite, pas recopiée',
        () {
      // ⚠️ Constaté sur appareil réel : dart:io/l'adaptateur IO de Dio lancent
      // une HttpException NATIVE (pas la nôtre) pour un accident de socket en
      // cours de flux — « Connection reset by peer » traversait tel quel.
      final cases = <String>[
        'Connection reset by peer',
        'Connection reset by peer (OS Error: Connection reset by peer, errno = 104)',
        'Connection refused',
        'Connection closed before full header was received',
      ];
      for (final msg in cases) {
        final out = describeError(HttpException(msg));
        expect(out, isNot(contains('Connection')), reason: msg);
        expect(out, isNot(contains('errno')), reason: msg);
        expect(out, contains('Connexion impossible'), reason: msg);
      }
    });

    test('SocketException / Timeout / Format / FileSystem / StateError', () {
      final cases = <Object>[
        const SocketException('x'),
        TimeoutException('t'),
        const FormatException('f'),
        const FileSystemException('fs', '/chemin'),
        StateError('s'),
      ];
      for (final c in cases) {
        final out = describeError(c);
        expect(out, isNotEmpty, reason: '${c.runtimeType}');
        expect(out, isNot(contains('Exception')), reason: '${c.runtimeType}');
      }
    });

    test('Exception(\'Bad state: foo\') → les préfixes empilés sont retirés', () {
      final out = describeError(Exception('Bad state: foo'));
      expect(out, 'foo');
    });

    test('null → phrase générique non vide', () {
      final out = describeError(null);
      expect(out, isNotEmpty);
      expect(out, isNot(contains('null')));
    });
  });

  group('describeError — forme : court, une seule ligne', () {
    test('toString() de 500 caractères → ≤ 180 et terminé par …', () {
      final out = describeError(Exception('a' * 500));
      expect(out.length, lessThanOrEqualTo(180));
      expect(out, endsWith('…'));
    });

    test('jamais de saut de ligne', () {
      final cases = <Object?>[
        Exception('ligne 1\nligne 2\n\n  ligne 3'),
        const HttpException('a\nb'),
        DioException(
          requestOptions: leakyRequest,
          type: DioExceptionType.unknown,
          error: Exception('x\ny'),
        ),
        null,
      ];
      for (final c in cases) {
        expect(describeError(c), isNot(contains('\n')), reason: '$c');
      }
    });
  });
}
