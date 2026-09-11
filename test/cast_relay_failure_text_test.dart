import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/services/cast_relay_service.dart';
import 'package:aetherStream/l10n/app_localizations.dart';

/// Revue 2026-09-11, D2B-03 — Le refus d'un Dolby Vision profil 5 était une
/// PHRASE française écrite dans le Kotlin, affichée telle quelle. Le natif
/// remonte désormais un CODE, traduit ici.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final fr = lookupAppLocalizations(const Locale('fr'));

  test('le code de refus DV5 se traduit dans les deux langues', () {
    expect(
        relayFailureText(kRelayRefusalDvProfile5, userFacing: true, l10n: en),
        en.relayDolbyVisionP5);
    expect(
        relayFailureText(kRelayRefusalDvProfile5, userFacing: true, l10n: fr),
        fr.relayDolbyVisionP5);
    expect(en.relayDolbyVisionP5, contains('Dolby Vision profile 5'));
  });

  test('une phrase ou un code inconnu ne s\'affichent JAMAIS', () {
    // La phrase d'une version antérieure du natif : en français, jamais
    // montrée à un écran anglais.
    const String oldNativeSentence =
        'Ce film est en Dolby Vision profil 5 : sans décodeur…';
    expect(relayFailureText(oldNativeSentence, userFacing: true, l10n: en),
        en.relayFormatFailed);
    expect(relayFailureText('', userFacing: true, l10n: en),
        en.relayFormatFailed);
  });

  test('une cause technique (non motivée) donne le message générique', () {
    expect(
        relayFailureText(kRelayRefusalDvProfile5,
            userFacing: false, l10n: en),
        en.relayFormatFailed);
    expect(relayFailureText('ExportException 7001', userFacing: false,
            l10n: fr),
        fr.relayFormatFailed);
  });

  test('contrat Dart ↔ Kotlin : le même code des deux côtés', () {
    final File kt = File(
        'android/app/src/main/kotlin/com/juman/aetherstream/AetherCastRelay.kt');
    if (!kt.existsSync()) return;
    final String src = kt.readAsStringSync();
    expect(src, contains('REFUSAL_DV_PROFILE_5 = "$kRelayRefusalDvProfile5"'));
    expect(src, isNot(contains('Ce film est en Dolby Vision')),
        reason: 'Le natif ne doit plus écrire de phrase à afficher.');
  });
}
