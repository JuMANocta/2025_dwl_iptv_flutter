import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/person_model.dart';

/// Revue 2026-09-11, D4A-11 — TMDB rend une biographie VIDE (pas `null`)
/// quand elle manque dans la langue demandée : la fiche acteur affichait une
/// zone vide au lieu de « biographie non disponible » (`biography ?? repli`).
void main() {
  Map<String, dynamic> person(Object? bio) => <String, dynamic>{
        'id': 1,
        'name': 'Acteur secondaire',
        'biography': bio,
      };

  group('Person.fromJson — biographie (D4A-11)', () {
    test('chaîne vide → null (le repli de la fiche s\'affiche)', () {
      expect(Person.fromJson(person('')).biography, isNull);
    });

    test('blancs seuls → null', () {
      expect(Person.fromJson(person('  \n ')).biography, isNull);
    });

    test('absente → null', () {
      expect(Person.fromJson(person(null)).biography, isNull);
    });

    test('une vraie biographie est gardée telle quelle', () {
      expect(Person.fromJson(person('Née à Lyon.')).biography, 'Née à Lyon.');
    });
  });
}
