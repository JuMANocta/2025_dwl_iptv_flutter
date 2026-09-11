/// §catalogTruth + §cacheKeep — revue 2026-09-11, D1A-01 — Le repli `get.php`
/// a-t-il le DROIT de remplacer le catalogue JSON ?
///
/// **Le défaut corrigé.** Les deux téléchargeurs (`ensureDownloadedForAccount`
/// et `downloadCurrentM3U`) enchaînaient sur `get.php` QUEL QUE SOIT le motif
/// du refus du catalogue JSON — y compris `busy` (panel saturé), `amputated`
/// (une section en échec, ou chute à zéro) et `noSource` (panel qui répond
/// `200 []`). Or le contrat de `CatalogDownloadResult` dit l'inverse : garder
/// le catalogue précédent. Et le repli n'était validé que par « taille > 0 » :
/// la page d'erreur de 2 Ko que renvoie un panel en panne était renommée en
/// `.m3u`, le `.json` SAIN était supprimé, et la ré-analyse rendait zéro
/// entrée. La liste disparaissait jusqu'au prochain téléchargement réussi.
///
/// Deux règles, pures, donc testables sans réseau ni disque :
///   1. [shouldFallbackToGetPhp] — le repli n'est permis que s'il n'y a RIEN à
///      protéger (premier téléchargement, ou compte déjà servi par `get.php`),
///      ou si le compte n'a pas d'identifiants Xtream (`badAccount` : le JSON
///      n'a jamais été possible pour lui) ;
///   2. [isCredibleM3u] — ce que `get.php` a rendu doit RESSEMBLER à une liste
///      avant d'être publié.
library;

import 'dart:convert';

import 'load_failure.dart';

/// Octets lus en tête du fichier rendu par `get.php` pour le reconnaître.
///
/// Quatre kilo-octets : largement de quoi voir l'en-tête `#EXTM3U` et la
/// première ligne `#EXTINF`, même derrière une longue ligne d'attributs.
const int m3uHeadBytes = 4096;

/// Le repli `get.php` est-il autorisé après un refus du catalogue JSON ?
///
/// [failure] est le motif rendu par `XtreamCatalogService.downloadCatalog`
/// (`null` si le téléchargement a levé une exception au lieu de refuser).
/// [hasJsonSource] dit si un catalogue `.json` CRÉDIBLE (présent et au-dessus
/// du plancher §cacheKeep) existe déjà pour ce compte.
///
/// ⚠️ Un refus MOTIVÉ (`busy`, `amputated`, `noSource`, écriture impossible)
/// n'est jamais une raison de détruire un catalogue sain : c'est précisément
/// quand le panel va mal que `get.php` renvoie une page d'erreur.
bool shouldFallbackToGetPhp({
  required LoadFailureKind? failure,
  required bool hasJsonSource,
}) {
  // Rien à protéger : premier téléchargement, ou compte déjà en `get.php`.
  if (!hasJsonSource) return true;
  // Pas d'identifiants Xtream : le JSON n'a jamais été possible pour ce
  // compte, `get.php` est son SEUL chemin.
  return failure == LoadFailureKind.badAccount;
}

/// Ce que `get.php` a rendu est-il une liste de lecture ?
///
/// Reconnue par son CONTENU, pas par sa taille : au moins un TITRE — une ligne
/// `#EXTINF`, ou une adresse (liste « simple », que le parseur M3U sait lire)
/// — derrière d'éventuelles lignes de directive (`#EXTM3U`, `#EXTGRP`…). La
/// première ligne qui n'est ni l'une ni l'autre (`<!DOCTYPE html>`, un
/// « Access denied », un JSON `{"user_info":{"auth":0}}`) trahit une page
/// d'erreur.
///
/// ⚠️ **L'en-tête SEUL ne suffit pas** (relecture de la revue) : `#EXTM3U`
/// sans aucun titre derrière est ce que rend un panel qui n'a rien à servir
/// (abonnement suspendu, panne). Le publier remplaçait la liste d'hier par une
/// liste vide — exactement ce que §catalogTruth interdit côté catalogue JSON.
///
/// ⚠️ **Pourquoi PAS le plancher de 4 Ko ici** (écart assumé avec la fiche de
/// revue) : `needsDownload` l'applique déjà, mais son faux positif y est
/// RÉVERSIBLE (une petite liste écrite à la main est simplement retéléchargée
/// à chaque contrôle — §cacheKeep l'assume). Appliqué à l'ACCEPTATION du
/// repli, le même faux positif deviendrait définitif : une liste de quelques
/// chaînes ne serait plus jamais publiée, et le compte n'aurait plus rien. Le
/// contenu, lui, sépare sans ambiguïté une liste d'une page d'erreur.
///
/// [head] : les premiers octets du fichier (au plus [m3uHeadBytes]) ; décodés
/// en tolérant l'invalide — un fichier Latin-1 reste reconnaissable, les
/// marqueurs sont en ASCII.
bool isCredibleM3u({required int lengthBytes, required List<int> head}) {
  if (lengthBytes <= 0 || head.isEmpty) return false;
  String text = utf8.decode(head, allowMalformed: true);
  // Marque d'ordre des octets (UTF-8 avec BOM) : invisible, mais elle ferait
  // échouer le `startsWith`. ⚠️ Construite par son code, pas par un
  // échappement : la couche d'édition décode les échappements (§catWords).
  final String bom = String.fromCharCode(0xFEFF);
  if (text.startsWith(bom)) text = text.substring(1);
  for (final String raw in const LineSplitter().convert(text)) {
    final String line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF')) return true;
    // Liste « simple » : une adresse par ligne.
    if (line.toLowerCase().startsWith('http')) return true;
    // Directive ou en-tête (`#EXTM3U`, `#EXTGRP`, `#PLAYLIST`…) : on continue.
    if (line.startsWith('#')) continue;
    // Ni directive, ni titre, ni adresse : ce n'est pas une liste.
    return false;
  }
  // Rien que des directives (ou l'en-tête seul) : aucun titre à publier.
  return false;
}
