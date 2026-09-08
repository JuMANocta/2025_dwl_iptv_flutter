import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/services/download_manager_service.dart';

/// §dlEpisode (2026-09-08) — La finalisation ne doit JAMAIS écraser un fichier
/// qui ne lui appartient pas.
///
/// C'est le dernier garde-fou : `rename()` remplace sa cible **sans lever**,
/// et c'est ainsi que les épisodes d'une même série se sont effacés les uns les
/// autres. Le nom est déjà rendu unique à la création de la tâche, mais le
/// dossier public est PARTAGÉ — un fichier peut y apparaître entre-temps.
///
/// Ces tests tournent sur un VRAI système de fichiers (dossier temporaire) :
/// c'est le seul moyen d'exercer le `rename`, et donc le chemin de SUCCÈS —
/// celui dont le type de retour est passé de `bool` à `String?`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('aether_dl_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Écrit un fichier partiel de [size] octets et rend son chemin.
  Future<String> part(String name, {int size = 1024}) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(List<int>.filled(size, 42));
    return f.path;
  }

  test('cas nominal : rename, et le chemin RENDU est celui demandé', () async {
    final temp = await part('.film.mp4.part');
    final target = '${dir.path}/film.mp4';

    final written = await finalizeDownloadForTest(
      tempPath: temp,
      finalPath: target,
      expectedSize: 1024,
    );

    expect(written, target);
    expect(await File(target).exists(), isTrue);
    expect(await File(temp).exists(), isFalse, reason: 'le partiel est consommé');
  });

  test('🔴 un fichier existant n\'est PAS écrasé : on se pousse en « (2) »',
      () async {
    // L'occupant est un AUTRE contenu : c'est lui qu'on ne doit pas perdre.
    final occupant = File('${dir.path}/Heroes S01 E01.mkv');
    await occupant.writeAsString('EPISODE DEJA LA');

    final temp = await part('.Heroes S01 E01.mkv.part', size: 2048);
    final written = await finalizeDownloadForTest(
      tempPath: temp,
      finalPath: occupant.path,
    );

    expect(written, '${dir.path}/Heroes S01 E01 (2).mkv');
    expect(await occupant.readAsString(), 'EPISODE DEJA LA',
        reason: 'l\'occupant doit être intact — c\'est TOUT le défaut');
    expect(await File(written!).length(), 2048);
  });

  test('trois collisions de suite se numérotent sans se marcher dessus',
      () async {
    await File('${dir.path}/film.mp4').writeAsString('un');
    await File('${dir.path}/film (2).mp4').writeAsString('deux');

    final temp = await part('.film.mp4.part');
    final written = await finalizeDownloadForTest(
      tempPath: temp,
      finalPath: '${dir.path}/film.mp4',
    );

    expect(written, '${dir.path}/film (3).mp4');
    expect(await File('${dir.path}/film.mp4').readAsString(), 'un');
    expect(await File('${dir.path}/film (2).mp4').readAsString(), 'deux');
  });

  test('fichier TRONQUÉ : échec, et le nom n\'est pas rendu', () async {
    final temp = await part('.film.mp4.part', size: 100);
    final written = await finalizeDownloadForTest(
      tempPath: temp,
      finalPath: '${dir.path}/film.mp4',
      expectedSize: 999999,
    );
    expect(written, isNull);
  });

  test('taille attendue SUPÉRIEURE tolérée (asymétrie voulue)', () async {
    // Un serveur sans `content-length` fiable ne doit pas faire échouer un
    // téléchargement complet.
    final temp = await part('.film.mp4.part', size: 4096);
    final written = await finalizeDownloadForTest(
      tempPath: temp,
      finalPath: '${dir.path}/film.mp4',
      expectedSize: 1024,
    );
    expect(written, '${dir.path}/film.mp4');
  });

  test('source absente : échec net, sans exception', () async {
    final written = await finalizeDownloadForTest(
      tempPath: '${dir.path}/inexistant.part',
      finalPath: '${dir.path}/film.mp4',
    );
    expect(written, isNull);
  });
}
