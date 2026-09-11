import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Revue 2026-09-11, D1A-11 — Le mémo de catégorie et le prédicat qui reçoit
/// la catégorie déjà calculée doivent être INTERCHANGEABLES avec
/// `contentCategoryLabel` / `isRegionHidden`. (Sur les vraies listes, c'est
/// l'instantané §parseSpeed qui le prouve ; ici, les cas limites.)
void main() {
  const List<String?> groupTitles = <String?>[
    null,
    '',
    'FILMS | ACTION',
    'Films | Action',
    'COMEDIE ( NETFLIX| PRIME | HBO | APPLE TV+ | STARZ | PARAMOUNT+ )',
    'COMÉDIE',
    '|IT| ITALIAN SERIES',
    '|FR| SERIES ANCIENNES',
    '|VOD| 4K (HDR)',
    'FILMES | AÇÃO',
    'VOD-LEGENDADA',
    'FILMS DE FIN D’ANNÉE',
    'THÉATRES',
    'FILMES',
    'Films Italiens',
    'DISNEY +',
    'SÉRIES ASIATIQUES',
    'Un libellé inconnu très très long pour le repli',
    '   ',
  ];

  test('CategoryLabelMemo.of ≡ contentCategoryLabel (1er et 2e appel)', () {
    final CategoryLabelMemo memo = CategoryLabelMemo();
    for (int pass = 0; pass < 2; pass++) {
      for (final String? g in groupTitles) {
        expect(memo.of(g), contentCategoryLabel(g), reason: 'passe $pass : $g');
      }
    }
    // null et '' ne sont pas mémorisés (court-circuit, comme la cascade).
    expect(memo.distinct, groupTitles.length - 2);
  });

  test('au-delà du plafond : valeurs toujours justes, table bornée', () {
    final CategoryLabelMemo memo = CategoryLabelMemo(maxEntries: 3);
    for (int pass = 0; pass < 2; pass++) {
      for (final String? g in groupTitles) {
        expect(memo.of(g), contentCategoryLabel(g));
      }
    }
    expect(memo.distinct, 3);
  });

  test('isRegionHiddenForCategory ≡ isRegionHidden', () {
    const List<String> names = <String>[
      '|IT| Film',
      '|FR| Film',
      '|VO| Film',
      '|VO-LEG.| Série',
      '|4K-LEG.| Film',
      '|VO|STFR| Film',
      'Film sans préfixe',
      '',
    ];
    const List<Set<String>> hiddenSets = <Set<String>>[
      <String>{},
      <String>{'Italie'},
      <String>{kVoRegionLabel},
      <String>{kLegRegionLabel},
      <String>{'Asie', 'Arabe'},
      <String>{'Italie', kVoRegionLabel, kLegRegionLabel, 'Asie'},
    ];
    final CategoryLabelMemo memo = CategoryLabelMemo();
    for (final String n in names) {
      for (final String? g in groupTitles) {
        for (final Set<String> h in hiddenSets) {
          expect(
            isRegionHiddenForCategory(
                name: n, category: memo.of(g), hidden: h),
            isRegionHidden(name: n, groupTitle: g, hidden: h),
            reason: 'name=$n group=$g hidden=$h',
          );
        }
      }
    }
  });
}
