// §l10nAll tranche 9 — **La couche d'affichage ne doit rien changer en français.**
//
// `categoryDisplayLabel` traduit une CLÉ métier (« Comédie », « VO (non-FR) »)
// en texte lisible. Le piège serait de croire que c'est une simple traduction :
// c'est un **contrat**. Sur un appareil en français, l'utilisateur doit voir
// exactement ce qu'il voyait avant la tranche 9 — sinon la rangée « Comédie »
// devient « Comedie », « Humour » ou pire, et personne ne s'en rend compte
// avant la recette.
//
// Ce test fige donc l'aller-retour : pour chaque clé produite par
// `m3u_filter.dart`, `categoryDisplayLabel(clé, fr) == clé`.
//
// ⚠️ Il vérifie AUSSI le repli : une catégorie APPRISE par TMDB (§inferredCat)
// ou un libellé de fournisseur inconnu n'a pas de clé l10n — elle doit
// s'afficher telle quelle, jamais disparaître ni devenir vide.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/feature/search/category_labels.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:aetherStream/l10n/app_localizations.dart';

/// D5A-15 (revue 2026-09-11, lot 9) — Tout ce que `m3u_filter.dart` sait
/// PRODUIRE, lu dans son CODE et non recopié à la main : chaque `return 'X';`
/// de la cascade, plus les ensembles publics (régions, plateformes, formats).
///
/// **Pourquoi lire la source.** Les listes ci-dessous étaient recopiées à la
/// main, sans lien avec la cascade : une catégorie ajoutée à
/// `contentCategoryLabel` sans clé l10n s'affichait en français sur un
/// appareil anglais, et les trois tests l10n restaient verts (§l10nScreen).
/// Lire le fichier suffit à le voir, sans exporter une énième liste qu'il
/// faudrait elle aussi tenir à jour.
Set<String> _producedLabels() {
  final String src =
      File('lib/feature/search/m3u_filter.dart').readAsStringSync();
  return {
    for (final RegExpMatch m in RegExp(r"return '([^']+)';").allMatches(src))
      m.group(1)!,
    ...kForeignRegionLabels,
    ...kHideableRegionLabels,
    ...kPlatformCategoryLabels,
    ...kFormatCategoryLabels,
  };
}

/// Mots qui s'écrivent PAREIL en anglais : leur traduction égale la clé, et
/// c'est juste. Toute autre égalité clé = traduction est un OUBLI.
const Set<String> kSameInEnglish = {
  'Action', 'Animation', 'Biopic', 'Crime', 'Mafia', 'Maritime', 'Musical',
  'Prison', 'Romance', 'Sci-Fi', 'Thriller', 'Western', 'New',
  'Canada', 'Portugal', 'Ramadan', 'France',
};

/// Toutes les clés de catégorie que `contentCategoryLabel` sait produire, plus
/// les rangées virtuelles de l'accueil (⭐ Favoris, New, Autres).
const List<String> kAllCategoryKeys = [
  'Favoris', 'Autres', 'New', 'Coup de cœur', 'Sélection', 'Cultes',
  'Box Office', 'Oscar',
  'Action', 'Actualités', 'Animation', 'Arts martiaux', 'Aventure', 'Biopic',
  'Braquage', 'Catastrophe', 'Comédie', 'Crime', 'Danse', 'Documentaire',
  'Drame', 'Espionnage', 'Fantastique', 'Fêtes', 'Guerre', 'Histoire',
  'Horreur', 'Jeunesse', 'Juridique', 'Karaoké', 'Mafia', 'Manga', 'Maritime',
  'Médecine', 'Médiéval', 'Musical', 'Policier', 'Prison', 'Romance', 'Sci-Fi',
  'Spectacle', 'Sport', 'Super-Héros', 'Survie', 'Talk-show', 'Téléfilm',
  'Téléréalité', 'Thriller', 'Tueur en série', 'Vengeance', 'Voitures', 'Western',
];

/// Les régions et langues, mêmes règles.
const List<String> kAllRegionKeys = [
  'France', 'Français', 'Albanie', 'Algérie', 'Allemagne', 'Arabe', 'Arménie',
  'Asie', 'Belgique', 'Bosnie', 'Brésil', 'Canada', 'Coréen', 'Croatie',
  'Espagne', 'Grèce', 'Indien', 'Italie', 'Maghrébin', 'Pays-Bas', 'Pologne',
  'Portugal', 'Ramadan', 'Roumanie', 'Russie', 'Scandinavie', 'Suisse',
  'Tchéquie', 'Turc', 'Ex-Yougoslavie', 'Rép. Dominicaine', 'VO (non-FR)',
  'Legendado (sous-titré PT)',
];

/// Noms propres et sigles : ils n'ont PAS de clé, et c'est délibéré.
const List<String> kProperNouns = [
  'Netflix', 'Disney+', 'Paramount+', 'Prime Video', 'HBO', 'Apple TV+',
  'BrutX', 'Rakuten TV', 'IMAX', '3D', '4K', '4K HDR', 'USA', 'UK', 'VOSTFR',
  'Novidades',
];

void main() {
  late AppLocalizations fr;
  late AppLocalizations en;

  setUp(() {
    fr = lookupAppLocalizations(const Locale('fr'));
    en = lookupAppLocalizations(const Locale('en'));
  });

  group('§l10nAll tranche 9 — en français, rien ne bouge', () {
    test('chaque clé de catégorie s\'affiche à l\'identique', () {
      // D5A-15 — Les rangées virtuelles de l'accueil (liste ci-dessus) ET tout
      // ce que la cascade de m3u_filter.dart produit réellement.
      for (final key in {...kAllCategoryKeys, ..._producedLabels()}) {
        expect(categoryDisplayLabel(key, fr), key,
            reason: 'La rangée « $key » ne doit pas changer de nom en '
                'français : la clé et la traduction fr DOIVENT coïncider.');
      }
    });

    test('chaque clé de région s\'affiche à l\'identique', () {
      for (final key in kAllRegionKeys) {
        expect(regionDisplayLabel(key, fr), key,
            reason: 'La région « $key » ne doit pas changer de nom en '
                'français — la page « Langues / régions » écrit la CLÉ dans '
                'le `.aether`, l\'écran doit montrer la même chose.');
      }
    });
  });

  group('§l10nAll tranche 9 — en anglais, tout est traduit', () {
    test('les genres du vocabulaire courant changent bien de langue', () {
      expect(categoryDisplayLabel('Comédie', en), 'Comedy');
      expect(categoryDisplayLabel('Jeunesse', en), 'Kids');
      expect(categoryDisplayLabel('Favoris', en), 'Favorites');
      expect(categoryDisplayLabel('Autres', en), 'Other');
      expect(regionDisplayLabel('Allemagne', en), 'Germany');
      expect(regionDisplayLabel('VO (non-FR)', en), 'Original (non-French)');
    });

    // D5A-15 — Remplace « aucune clé ne rend une chaîne vide », qui passait
    // même SANS traduction (le repli rend la clé elle-même) et appliquait
    // `categoryDisplayLabel` aux clés de RÉGION.
    test('tout libellé produit par m3u_filter.dart est traduit en anglais', () {
      final List<String> untranslated = [];
      for (final String key in {...kAllCategoryKeys, ..._producedLabels()}) {
        if (kSameInEnglish.contains(key) || kProperNouns.contains(key)) {
          continue;
        }
        if (categoryDisplayLabel(key, en) == key) untranslated.add(key);
      }
      expect(untranslated, isEmpty,
          reason: 'Affichés en français sur un appareil anglais : ajouter la '
              'clé l10n et son `case` dans category_labels.dart (ou, si le mot '
              's\'écrit pareil en anglais, l\'ajouter à kSameInEnglish).');
    });

    test('chaque région passe par regionDisplayLabel, traduite', () {
      for (final String key in {...kAllRegionKeys, ...kHideableRegionLabels}) {
        if (kSameInEnglish.contains(key) || kProperNouns.contains(key)) {
          continue;
        }
        expect(regionDisplayLabel(key, en), isNot(key), reason: key);
      }
    });
  });

  group('§inferredCat — le repli laisse passer l\'inconnu', () {
    test('un nom propre s\'affiche tel quel, dans les deux langues', () {
      for (final key in kProperNouns) {
        expect(categoryDisplayLabel(key, fr), key);
        expect(categoryDisplayLabel(key, en), key);
      }
    });

    test('une catégorie apprise par TMDB survit au passage', () {
      // §inferredCat : une liste Ultimate ne fournit AUCUN `group-title` ;
      // la catégorie vient de TMDB et peut être n'importe quoi.
      expect(categoryDisplayLabel('Téléfilms allemands 1998', en),
          'Téléfilms allemands 1998');
      expect(categoryDisplayLabel('', en), '');
    });
  });
}
