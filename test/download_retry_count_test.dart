import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/download_task.dart';

/// §dlWatchdog — Le compteur de relances doit SURVIVRE au dialogue.
///
/// Il vivait dans `TerminalDownloadDialog._retryCount`, une variable d'état de
/// widget : refermer le moniteur remettait le compteur à zéro alors que le
/// téléchargement, lui, continuait. La tuile ne pouvait donc rien dire d'un
/// fichier ayant déjà décroché cinq fois — or c'est exactement le signal qui
/// distingue « source lente » de « source qui bride ».
DownloadTask _task({int retryCount = 0}) => DownloadTask(
      id: 't1',
      url: 'http://example.invalid/f.mkv',
      displayName: 'Film',
      finalPath: '/movies/f.mkv',
      tempPath: '/cache/f.part',
      createdAt: DateTime(2026, 8, 29),
      retryCount: retryCount,
    );

void main() {
  test('le compteur survit à un aller-retour JSON', () {
    final restored = DownloadTask.fromJson(_task(retryCount: 5).toJson());
    expect(restored.retryCount, 5);
  });

  test('une tâche enregistrée AVANT §dlWatchdog repart de zéro, pas de null',
      () {
    final legacy = _task().toJson()..remove('retryCount');
    expect(DownloadTask.fromJson(legacy).retryCount, 0);
  });

  test('copyWith incrémente sans toucher au reste', () {
    final before = _task(retryCount: 2);
    final after = before.copyWith(retryCount: before.retryCount + 1);
    expect(after.retryCount, 3);
    expect(after.displayName, before.displayName);
    expect(after.tempPath, before.tempPath);
  });

  test('copyWith sans argument PRÉSERVE le compteur', () {
    // Le service enchaîne les `copyWith` sur le chemin chaud de la
    // progression : un compteur oublié dans la copie s'effacerait au premier
    // pourcent.
    final kept = _task(retryCount: 4).copyWith(progress: 0.5);
    expect(kept.retryCount, 4);
  });
}
