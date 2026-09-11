// §acctPurge + §restoreOnboarding — revue 2026-09-11, D1B-05.
//
// La restauration `.aether` effaçait TOUS les comptes (et leurs fichiers,
// §acctPurge) AVANT de relire ceux de la sauvegarde, en avalant chaque échec
// de lecture. Une sauvegarde mal formée — ou écrite par une version future —
// laissait donc l'app sans aucun compte, et l'écran annonçait une
// restauration réussie. Les identifiants étaient perdus.
import 'dart:convert';

import 'package:aetherStream/core/utils/user_error.dart';
import 'package:aetherStream/data/models/stream_account.dart';
import 'package:aetherStream/data/services/backup_service.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

StreamAccount _local() => StreamAccount(
      id: 'acc_local',
      label: 'Liste locale',
      mode: StreamAuthMode.separate,
      baseUrl: 'http://panel.test',
      username: 'u',
      password: 'p',
    );

Map<String, dynamic> _backup(List<Object?> accounts) => <String, dynamic>{
      'appVersion': '1.18.18+151',
      'exportedAt': '2026-09-11T08:00:00.000',
      'accounts': accounts,
      'activeAccountId': null,
      'tmdbKey': null,
      'theme': null,
      'perf': null,
      'favorites': <String>[],
      'watchProgress': <String, dynamic>{},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final StreamAccount a = _local();
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'accounts_index': jsonEncode(<String>[a.id]),
      'account:${a.id}': jsonEncode(a.toJson()),
      'current_account_id': a.id,
    });
  });

  test('aucun compte lisible → refus AVANT tout effacement', () async {
    final BackupContent content = BackupContent.fromJson(_backup(<Object?>[
      <String, dynamic>{'label': 'sans identifiant'},
      'pas un objet',
    ]));
    expect(content.accounts, hasLength(2),
        reason: 'un élément illisible est COMPTÉ, pas escamoté en silence');

    await expectLater(
      BackupService.applyBackup(content),
      throwsA(isA<UserFacingException>()),
    );

    final List<StreamAccount> restants =
        await StreamAccountService.listAccounts();
    expect(restants.map((a) => a.id), <String>['acc_local'],
        reason: 'le compte local doit survivre à une sauvegarde illisible');
  });

  test('un type de liste inconnu (version future) reste LISIBLE', () {
    final Map<String, dynamic> json = _local().toJson()
      ..['playlistType'] = 'futur';
    final StreamAccount acc = StreamAccount.fromJson(json);
    expect(acc.playlistType, PlaylistType.m3u);
    expect(acc.id, 'acc_local');
  });

  test('readAccounts écarte l\'illisible et garde le lisible', () {
    final Map<String, dynamic> lisible = _local().toJson()..['id'] = 'acc_2';
    final List<StreamAccount> lus = BackupService.readAccounts(
        <Map<String, dynamic>>[lisible, <String, dynamic>{'label': 'x'}]);
    expect(lus.map((a) => a.id), <String>['acc_2']);
  });

  test('un champ « accounts » qui n\'est pas une liste lève à la LECTURE '
      '(avant toute restauration), comme avant', () {
    expect(
      () => BackupContent.fromJson(_backup(const <Object?>[])
        ..['accounts'] = 'corrompu'),
      throwsA(isA<TypeError>()),
    );
  });
}
