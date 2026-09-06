// §inferDelta (2026-09-06, lot 13) — Une catégorie apprise ne refait plus tout
// le rangement de l'accueil : elle déplace le groupe concerné. Ce fichier
// vérifie que le déplacement donne ce qu'un regroupement complet aurait
// donné (mêmes règles que `pickCategory`), et que le service sait dire ce
// qui a été appris depuis une version donnée.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/inferred_category_service.dart';
import 'package:aetherStream/feature/home/inferred_delta.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';

M3uEntry _entry(String title, {String? category, int? addedAt}) => M3uEntry(
      url: 'http://x/${title.hashCode}',
      accountId: 'a',
      type: M3uContentType.movie,
      title: TitleMetadata.parse(title),
      category: category,
      addedAt: addedAt,
    );

List<M3uEntry> _group(String title, {String? category, int? addedAt}) =>
    [_entry(title, category: category, addedAt: addedAt)];

bool _isGenre(String c) => c != 'Autres' && c != 'New';

void main() {
  group('applyInferredDelta — déplacer un groupe, pas tout refaire', () {
    late List<M3uEntry> zorro;
    late List<M3uEntry> alien;
    late List<M3uEntry> batman;
    late Map<String, List<List<M3uEntry>>> byCategory;
    late Map<String, List<List<M3uEntry>>> byKey;

    setUp(() {
      zorro = _group('Zorro (1975)');
      alien = _group('Alien (1979)');
      batman = _group('Batman (1989)');
      byCategory = {
        'Action': [alien],
        'Autres': [zorro, batman],
      };
      byKey = {
        for (final g in [zorro, alien, batman]) contentGroupKey(g.first): [g],
      };
    });

    test('depuis « Autres » vers une rangée existante, À SA PLACE (tri)', () {
      final changed = applyInferredDelta(
        byCategory: byCategory,
        groupsByKey: byKey,
        delta: {contentGroupKey(zorro.first): (previous: null, category: 'Action')},
        hasAddedData: true,
        rowFoldMin: 5,
        isSortedGenre: _isGenre,
      );
      expect(changed, isFalse, reason: 'aucune rangée créée ni vidée');
      expect(byCategory['Action'], [alien, zorro]);
      expect(byCategory['Autres'], [batman]);
    });

    test('insertion triée au MILIEU d une rangée', () {
      final changed = applyInferredDelta(
        byCategory: byCategory,
        groupsByKey: byKey,
        delta: {
          contentGroupKey(zorro.first): (previous: null, category: 'Action'),
          contentGroupKey(batman.first): (previous: null, category: 'Action'),
        },
        hasAddedData: true,
        rowFoldMin: 5,
        isSortedGenre: _isGenre,
      );
      expect(changed, isFalse);
      expect(byCategory['Action'], [alien, batman, zorro]);
      expect(byCategory['Autres'], isEmpty);
    });

    test('§rowFold : rangée ABSENTE → le groupe reste dans « Autres »', () {
      final changed = applyInferredDelta(
        byCategory: byCategory,
        groupsByKey: byKey,
        delta: {contentGroupKey(zorro.first): (previous: null, category: 'Western')},
        hasAddedData: true,
        rowFoldMin: 5,
        isSortedGenre: _isGenre,
      );
      expect(changed, isFalse);
      expect(byCategory.containsKey('Western'), isFalse);
      expect(byCategory['Autres'], [zorro, batman]);
    });

    test('repli désactivé (rowFoldMin 1) → la rangée est CRÉÉE', () {
      final changed = applyInferredDelta(
        byCategory: byCategory,
        groupsByKey: byKey,
        delta: {contentGroupKey(zorro.first): (previous: null, category: 'Western')},
        hasAddedData: true,
        rowFoldMin: 1,
        isSortedGenre: _isGenre,
      );
      expect(changed, isTrue, reason: 'une rangée de plus : retrier');
      expect(byCategory['Western'], [zorro]);
      expect(byCategory['Autres'], [batman]);
    });

    test('la catégorie FOURNIE par la liste gagne : le groupe ne bouge pas', () {
      final horror = _group('Alien (1979)', category: 'Horreur');
      final map = {
        'Horreur': [horror],
        'Autres': <List<M3uEntry>>[],
      };
      final changed = applyInferredDelta(
        byCategory: map,
        groupsByKey: {contentGroupKey(horror.first): [horror]},
        delta: {contentGroupKey(horror.first): (previous: null, category: 'Action')},
        hasAddedData: true,
        rowFoldMin: 5,
        isSortedGenre: _isGenre,
      );
      expect(changed, isFalse);
      expect(map['Horreur'], [horror]);
      expect(map.containsKey('Action'), isFalse);
    });

    test('réapprise : quitte l ancienne rangée déduite, qui disparaît si vide', () {
      final map = {
        'Action': [alien],
        'Comédie': [batman],
        'Autres': [zorro],
      };
      final changed = applyInferredDelta(
        byCategory: map,
        groupsByKey: byKey,
        delta: {
          contentGroupKey(alien.first): (previous: 'Action', category: 'Comédie'),
        },
        hasAddedData: true,
        rowFoldMin: 5,
        isSortedGenre: _isGenre,
      );
      expect(changed, isTrue, reason: 'la rangée Action est vidée');
      expect(map.containsKey('Action'), isFalse);
      expect(map['Comédie'], [alien, batman]);
    });

    test('« New » d une liste SANS horodatage est une vraie case : on en sort', () {
      final map = {
        'New': [zorro],
        'Action': [alien],
        'Autres': [batman],
      };
      applyInferredDelta(
        byCategory: map,
        groupsByKey: byKey,
        delta: {contentGroupKey(zorro.first): (previous: null, category: 'Action')},
        hasAddedData: false,
        rowFoldMin: 5,
        isSortedGenre: _isGenre,
      );
      expect(map.containsKey('New'), isFalse,
          reason: 'une rangée vidée disparaît, comme au regroupement complet');
      expect(map['Action'], [alien, zorro]);
    });

    test('⚠️ « New » VIRTUELLE (horodatée) duplique : on n y touche jamais', () {
      final map = {
        'New': [zorro],
        'Action': [alien],
        'Autres': [zorro, batman],
      };
      applyInferredDelta(
        byCategory: map,
        groupsByKey: byKey,
        delta: {contentGroupKey(zorro.first): (previous: null, category: 'Action')},
        hasAddedData: true,
        rowFoldMin: 5,
        isSortedGenre: _isGenre,
      );
      expect(map['New'], [zorro], reason: 'toujours dans New');
      expect(map['Action'], [alien, zorro]);
      expect(map['Autres'], [batman]);
    });

    test('clé inconnue du rangement (autre type) : aucun effet', () {
      final before = Map<String, List<List<M3uEntry>>>.of(byCategory);
      final changed = applyInferredDelta(
        byCategory: byCategory,
        groupsByKey: byKey,
        delta: {'une serie': (previous: null, category: 'Action')},
        hasAddedData: true,
        rowFoldMin: 5,
        isSortedGenre: _isGenre,
      );
      expect(changed, isFalse);
      expect(byCategory, before);
    });
  });

  group('InferredCategoryService.deltaSince — ce qui a été appris depuis', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await InferredCategoryService.clear();
    });

    test('vide si rien n a bougé ; les clés apprises entre deux versions', () {
      final int v0 = InferredCategoryService.version.value;
      expect(InferredCategoryService.deltaSince(v0), isEmpty);

      InferredCategoryService.learn('zorro', 'Western');
      InferredCategoryService.learn('alien', 'Horreur');
      expect(InferredCategoryService.deltaSince(v0), isEmpty,
          reason: 'pas encore publié : le signal est groupé');

      InferredCategoryService.publishPending();
      final d = InferredCategoryService.deltaSince(v0)!;
      expect(d.length, 2);
      expect(d['zorro'], (previous: null, category: 'Western'));
      expect(InferredCategoryService.get('alien'), 'Horreur');
    });

    test('deux fenêtres cumulées gardent l ORIGINE de la première', () {
      final int v0 = InferredCategoryService.version.value;
      InferredCategoryService.learn('zorro', 'Western');
      InferredCategoryService.publishPending();
      InferredCategoryService.learn('zorro', 'Aventure');
      InferredCategoryService.publishPending();

      final d = InferredCategoryService.deltaSince(v0)!;
      expect(d['zorro'], (previous: null, category: 'Aventure'));

      // Depuis la version intermédiaire : l'origine est Western.
      final d1 = InferredCategoryService.deltaSince(v0 + 1)!;
      expect(d1['zorro'], (previous: 'Western', category: 'Aventure'));
    });

    test('réapprise DANS la même fenêtre : l origine reste celle du rangement',
        () {
      InferredCategoryService.learn('zorro', 'Western');
      InferredCategoryService.publishPending();
      final int v1 = InferredCategoryService.version.value;
      InferredCategoryService.learn('zorro', 'Aventure');
      InferredCategoryService.learn('zorro', 'Comédie');
      InferredCategoryService.publishPending();
      expect(InferredCategoryService.deltaSince(v1)!['zorro'],
          (previous: 'Western', category: 'Comédie'));
    });

    test('fenêtre perdue (trop ancienne, ou clear) → null = tout refaire',
        () async {
      final int v0 = InferredCategoryService.version.value;
      for (var i = 0; i < 10; i++) {
        InferredCategoryService.learn('k$i', 'Action');
        InferredCategoryService.publishPending();
      }
      expect(InferredCategoryService.deltaSince(v0), isNull,
          reason: 'seules les 8 dernières fenêtres sont gardées');
      expect(InferredCategoryService.deltaSince(v0 + 5), isNotNull);

      final int vBefore = InferredCategoryService.version.value;
      await InferredCategoryService.clear();
      expect(InferredCategoryService.deltaSince(vBefore), isNull);
      expect(InferredCategoryService.deltaSince(vBefore + 5), isNull,
          reason: 'une version du FUTUR est inconnue aussi');
    });
  });
}
