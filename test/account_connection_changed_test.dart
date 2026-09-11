import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/stream_account.dart';

/// Revue 2026-09-11, D4B-03 — Modifier un compte le rendait principal sans le
/// dire, et gardait le catalogue analysé de l'ANCIENNE URL / des anciens
/// identifiants (les URL de flux Xtream les embarquent : toutes les lectures
/// échouaient jusqu'au rafraîchissement de 24 h). `connectionChanged` décide
/// quand l'édition doit recharger la liste.
void main() {
  final StreamAccount xtream = StreamAccount(
    id: 'acc_1',
    label: 'Mon Xtream',
    mode: StreamAuthMode.separate,
    baseUrl: 'http://panel.tv:8080',
    username: 'jean',
    password: 'secret',
  );
  final StreamAccount url = StreamAccount(
    id: 'acc_2',
    label: 'Ma liste',
    mode: StreamAuthMode.completeUrl,
    completeUrl: 'http://panel.tv/get.php?username=a&password=b',
  );

  group('connectionChanged (D4B-03)', () {
    test('renommer seulement → rien à recharger', () {
      expect(connectionChanged(xtream, xtream.copyWith(label: 'Autre')), isFalse);
      expect(connectionChanged(url, url.copyWith(label: 'Autre')), isFalse);
    });

    test('mot de passe changé → recharger (le cas du signalement)', () {
      expect(connectionChanged(xtream, xtream.copyWith(password: 'neuf')),
          isTrue);
    });

    test('identifiant ou serveur changé → recharger', () {
      expect(connectionChanged(xtream, xtream.copyWith(username: 'paul')),
          isTrue);
      expect(
          connectionChanged(
              xtream, xtream.copyWith(baseUrl: 'http://autre.tv:8080')),
          isTrue);
    });

    test('URL complète changée → recharger', () {
      expect(
          connectionChanged(
              url, url.copyWith(completeUrl: 'http://autre.tv/liste.m3u')),
          isTrue);
    });

    test('changement de mode → recharger', () {
      expect(
          connectionChanged(
              xtream,
              StreamAccount(
                id: xtream.id,
                label: xtream.label,
                mode: StreamAuthMode.completeUrl,
                completeUrl: 'http://panel.tv/get.php?username=jean&password=secret',
              )),
          isTrue);
    });

    test('espaces autour d\'une valeur identique → pas un changement', () {
      expect(connectionChanged(xtream, xtream.copyWith(password: ' secret ')),
          isFalse);
    });

    test('les champs de l\'AUTRE mode ne comptent pas', () {
      // Le formulaire remet à null les champs du mode non choisi ; un vieux
      // compte URL peut encore porter un serveur : ce n'est pas un changement.
      final StreamAccount legacy = StreamAccount(
        id: url.id,
        label: url.label,
        mode: StreamAuthMode.completeUrl,
        completeUrl: url.completeUrl,
        baseUrl: 'http://vieux.tv',
        username: 'x',
        password: 'y',
      );
      expect(connectionChanged(legacy, url), isFalse);
    });

    test('type de liste changé → recharger', () {
      expect(
          connectionChanged(
              xtream, xtream.copyWith(playlistType: PlaylistType.simple)),
          isTrue);
    });
  });
}
