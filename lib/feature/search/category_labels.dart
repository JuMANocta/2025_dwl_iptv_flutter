/// §l10nAll tranche 9 — **La couche d'AFFICHAGE des catégories et des régions.**
///
/// **Pourquoi elle existe.** `m3u_filter.dart` produit des libellés français
/// (« Comédie », « Jeunesse », « VO (non-FR) »…) qui ne sont PAS des textes
/// d'interface : ce sont des **valeurs métier**. Elles sont écrites dans
/// `M3uEntry.category`, sérialisées dans le cache `JSON.gz` (`schemaVersion`),
/// persistées dans le `.aether` (langues masquées), comparées entre elles pour
/// trier les rangées et pour filtrer. Les traduire EN PLACE casserait le filtre
/// régions et le regroupement de l'accueil — c'est écrit noir sur blanc dans
/// `test/l10n_guard_test.dart`, qui exclut ce fichier du cliquet.
///
/// La règle est donc : **la clé reste française et stable, seul l'affichage
/// change.** Ces deux fonctions sont le SEUL endroit où une catégorie devient
/// un texte lisible ; partout ailleurs, on manipule la clé.
///
/// ⚠️ **Ne jamais comparer le résultat de ces fonctions.** Un
/// `if (label == 'Favoris')` écrit sur la valeur AFFICHÉE deviendrait faux dès
/// que l'appareil n'est pas en français. Les comparaisons se font sur la clé.
///
/// ⚠️ Le repli est la clé elle-même : une catégorie apprise par TMDB
/// (§inferredCat) ou un libellé de fournisseur inconnu s'affiche tel quel,
/// plutôt que de disparaître.
library;

import '../../l10n/app_localizations.dart';

/// Libellé affichable d'une catégorie, à partir de sa **clé** française.
String categoryDisplayLabel(String key, AppLocalizations l10n) {
  switch (key) {
    // ── Rangées spéciales de l'accueil ──────────────────────────────────────
    case 'Favoris':
      return l10n.catFavorites;
    case 'Autres':
      return l10n.catOthers;
    case 'New':
      return l10n.catNew;
    case 'Coup de cœur':
      return l10n.catStaffPick;
    case 'Sélection':
      return l10n.catSelection;
    case 'Cultes':
      return l10n.catCult;
    case 'Box Office':
      return l10n.catBoxOffice;
    case 'Oscar':
      return l10n.catOscar;
    // ── Genres ──────────────────────────────────────────────────────────────
    case 'Action':
      return l10n.catAction;
    case 'Actualités':
      return l10n.catNews;
    case 'Animation':
      return l10n.catAnimation;
    case 'Arts martiaux':
      return l10n.catMartialArts;
    case 'Aventure':
      return l10n.catAdventure;
    case 'Biopic':
      return l10n.catBiopic;
    case 'Braquage':
      return l10n.catHeist;
    case 'Catastrophe':
      return l10n.catDisaster;
    case 'Comédie':
      return l10n.catComedy;
    case 'Crime':
      return l10n.catCrime;
    case 'Danse':
      return l10n.catDance;
    case 'Documentaire':
      return l10n.catDocumentary;
    case 'Drame':
      return l10n.catDrama;
    case 'Espionnage':
      return l10n.catSpy;
    case 'Fantastique':
      return l10n.catFantasy;
    case 'Fêtes':
      return l10n.catHolidays;
    case 'Guerre':
      return l10n.catWar;
    case 'Histoire':
      return l10n.catHistory;
    case 'Horreur':
      return l10n.catHorror;
    case 'Jeunesse':
      return l10n.catKids;
    case 'Juridique':
      return l10n.catLegal;
    case 'Karaoké':
      return l10n.catKaraoke;
    case 'Mafia':
      return l10n.catMafia;
    case 'Manga':
      return l10n.catManga;
    case 'Maritime':
      return l10n.catMaritime;
    case 'Médecine':
      return l10n.catMedical;
    case 'Médiéval':
      return l10n.catMedieval;
    case 'Musical':
      return l10n.catMusical;
    case 'Policier':
      return l10n.catPolice;
    case 'Prison':
      return l10n.catPrison;
    case 'Romance':
      return l10n.catRomance;
    case 'Sci-Fi':
      return l10n.catSciFi;
    case 'Spectacle':
      return l10n.catStandUp;
    case 'Sport':
      return l10n.catSport;
    case 'Super-Héros':
      return l10n.catSuperheroes;
    case 'Survie':
      return l10n.catSurvival;
    case 'Téléfilm':
      return l10n.catTvMovie;
    case 'Téléréalité':
      return l10n.catRealityTv;
    case 'Thriller':
      return l10n.catThriller;
    case 'Tueur en série':
      return l10n.catSerialKiller;
    case 'Vengeance':
      return l10n.catRevenge;
    case 'Voitures':
      return l10n.catCars;
    case 'Western':
      return l10n.catWestern;
    // ── Régions et langues ──────────────────────────────────────────────────
    default:
      return regionDisplayLabel(key, l10n);
  }
}

/// Libellé affichable d'une **région / langue**, à partir de sa clé française.
///
/// Sert à la fois aux rangées de l'accueil (une région EST une catégorie) et à
/// la page « Langues / régions » — c'est le même vocabulaire.
String regionDisplayLabel(String key, AppLocalizations l10n) {
  switch (key) {
    case 'France':
      return l10n.regFrance;
    case 'Français':
      return l10n.langFrench;
    case 'Albanie':
      return l10n.regAlbania;
    case 'Algérie':
      return l10n.regAlgeria;
    case 'Allemagne':
      return l10n.regGermany;
    case 'Arabe':
      return l10n.langArabic;
    case 'Arménie':
      return l10n.regArmenia;
    case 'Asie':
      return l10n.regAsia;
    case 'Belgique':
      return l10n.regBelgium;
    case 'Bosnie':
      return l10n.regBosnia;
    case 'Brésil':
      return l10n.regBrazil;
    case 'Canada':
      return l10n.regCanada;
    case 'Coréen':
      return l10n.langKorean;
    case 'Croatie':
      return l10n.regCroatia;
    case 'Espagne':
      return l10n.regSpain;
    case 'Grèce':
      return l10n.regGreece;
    case 'Indien':
      return l10n.regIndian;
    case 'Italie':
      return l10n.regItaly;
    case 'Maghrébin':
      return l10n.regMaghreb;
    case 'Pays-Bas':
      return l10n.regNetherlands;
    case 'Pologne':
      return l10n.regPoland;
    case 'Portugal':
      return l10n.regPortugal;
    case 'Ramadan':
      return l10n.regRamadan;
    case 'Roumanie':
      return l10n.regRomania;
    case 'Russie':
      return l10n.regRussia;
    case 'Scandinavie':
      return l10n.regScandinavia;
    case 'Suisse':
      return l10n.regSwitzerland;
    case 'Tchéquie':
      return l10n.regCzechia;
    case 'Turc':
      return l10n.langTurkish;
    case 'Ex-Yougoslavie':
      return l10n.regExYugoslavia;
    case 'Rép. Dominicaine':
      return l10n.regDominicanRepublic;
    case 'VO (non-FR)':
      return l10n.regOriginalNonFrench;
    case 'Legendado (sous-titré PT)':
      return l10n.regLegendado;
    // Noms propres et sigles (Netflix, Disney+, HBO, IMAX, 3D, 4K, USA, UK,
    // VOSTFR, Novidades…) : ils s'écrivent pareil partout, et une catégorie
    // apprise ou inconnue doit rester visible telle quelle.
    default:
      return key;
  }
}
