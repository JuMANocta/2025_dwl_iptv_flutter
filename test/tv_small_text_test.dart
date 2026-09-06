import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/core/utils/tv_text_scaler.dart';

/// §tvSmallText — 144 `fontSize` en dur entre 9 et 12 px, aucun conditionné à
/// la TV, alors que l'échelle système y est verrouillée à ×1.0 (§audit0903,
/// points TV). Ces tests verrouillent la règle : **un plancher, pas un zoom**.
void main() {
  test('le petit texte monte', () {
    expect(tvSmallTextSize(9), closeTo(11.25, 0.001));
    expect(tvSmallTextSize(10), closeTo(12.5, 0.001));
  });

  test('la montée est plafonnée : la hiérarchie ne s\'inverse pas', () {
    // 12 × 1.25 = 15, rabotté à 14 — sinon une mention passerait au-dessus
    // d'un sous-titre à 13 px, qui lui n'est pas touché.
    expect(tvSmallTextSize(12), 14);
    expect(tvSmallTextSize(12.9), 14);
  });

  test('le texte normal n\'est PAS touché', () {
    // ⚠️ C'est tout l'objet du correctif : deux tentatives d'échelle uniforme
    // (×1.3 puis ×1.15) ont été abandonnées pour cause d'interface zoomée.
    for (final f in [13.0, 14.0, 16.0, 20.0, 34.0]) {
      expect(tvSmallTextSize(f), f, reason: '$f ne doit pas bouger');
    }
  });

  test('valeurs dégénérées : rendues telles quelles', () {
    expect(tvSmallTextSize(0), 0);
    expect(tvSmallTextSize(-4), -4);
  });

  test('deux instances sont égales — sinon MediaQuery repeint sans cesse', () {
    // ⚠️ Le `builder` de MaterialApp reconstruit ce scaler à chaque frame :
    // sans égalité de valeur, `MediaQuery` notifierait tout l'arbre.
    expect(const TvSmallTextScaler(), const TvSmallTextScaler());
    expect(const TvSmallTextScaler().hashCode,
        const TvSmallTextScaler().hashCode);
  });

  testWidgets('appliqué via MediaQuery, un Text à 10 px est peint plus grand',
      (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TvSmallTextScaler()),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('mention', style: TextStyle(fontSize: 10)),
        ),
      ),
    );
    final RenderBox box = tester.renderObject(find.text('mention'));
    // 10 px non scalé donnerait une hauteur de ligne d'environ 12 ; à 12,5 px
    // la ligne dépasse 14. On teste la conséquence, pas la valeur exacte.
    expect(box.size.height, greaterThan(13));
  });
}
