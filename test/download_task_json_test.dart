import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/download_task.dart';

/// Revue 2026-09-11 (D3A-14) — Relire la liste des téléchargements sans jamais
/// tout perdre.
///
/// ⚠️ L'ÉCRITURE reste par index : un APK antérieur fait
/// `DownloadStatus.values[json['status'] as int]`, un nom lui rendrait la liste
/// illisible au retour arrière. Seule la LECTURE s'assouplit.
void main() {
  Map<String, dynamic> json(Object? status) => {
        'id': 't1',
        'url': 'http://h/1.mkv',
        'displayName': 'Film',
        'finalPath': '/m/Film.mkv',
        'tempPath': '/m/.Film.aetherpart.mkv',
        'status': status,
        'progress': 0.5,
        'totalSize': 100,
        'createdAt': '2026-09-11T10:00:00.000',
      };

  test('l\'index historique se relit à l\'identique', () {
    for (final s in DownloadStatus.values) {
      expect(DownloadTask.fromJson(json(s.index)).status, s);
    }
  });

  test('l\'écriture reste par INDEX (compatibilité d\'un retour arrière)', () {
    final t = DownloadTask.fromJson(json(DownloadStatus.finalizing.index));
    expect(t.toJson()['status'], DownloadStatus.finalizing.index);
  });

  test('un nom de statut est accepté à la lecture', () {
    expect(DownloadTask.fromJson(json('completed')).status,
        DownloadStatus.completed);
  });

  test('🔴 un statut inconnu devient « échec » (reprenable), sans lever', () {
    expect(DownloadTask.fromJson(json(99)).status, DownloadStatus.failed);
    expect(DownloadTask.fromJson(json('futur')).status, DownloadStatus.failed);
    expect(DownloadTask.fromJson(json(null)).status, DownloadStatus.failed);
    expect(DownloadTask.fromJson(json(-1)).status, DownloadStatus.failed);
  });

  test('⚠️ l\'ordre de l\'enum est FIGÉ (il est persisté par index)', () {
    // Insérer une valeur ailleurs qu'en fin décalerait toutes les tâches
    // enregistrées. Ce test casse si quelqu'un le fait.
    expect(DownloadStatus.values.map((s) => s.name).toList(), [
      'queued',
      'downloading',
      'completed',
      'failed',
      'canceled',
      'paused',
      'finalizing',
    ]);
  });
}
