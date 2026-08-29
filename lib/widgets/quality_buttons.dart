import 'package:flutter/material.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/data/models/quality_scale.dart';
import 'package:aetherStream/data/services/measured_quality_service.dart';
import 'package:aetherStream/widgets/tv/focusable_chip.dart';

/// Trie les versions par qualité décroissante et génère un label lisible.
///
/// §watchContext c — Désambiguïsation « sur quel produit suis-je ? » : si deux
/// flux portent le MÊME label de base (ex. 2× « FHD » provenant de comptes /
/// sources différents — le `dedupeTvVersions` n'enlève que les doublons d'un
/// MÊME compte), on suffixe par le **nom du compte** (multi-comptes) ou, à
/// défaut, un index → l'utilisateur distingue clairement les flux.
List<(M3uEntry, String)> labeledVersions(List<M3uEntry> versions) {
  // §camQuality — CAM classé APRÈS SD : un rip de salle est le pire flux
  // disponible, il ne doit jamais être proposé en premier.
  const order = {'4K': 0, 'UHD': 0, 'FHD': 1, 'HD': 2, 'SD': 3, 'CAM': 4};
  final sorted = List<M3uEntry>.from(versions)
    ..sort((a, b) => (order[a.title.quality] ?? 99)
        .compareTo(order[b.title.quality] ?? 99));

  // 1) Label de base (qualité > langue > versionLabel > marqueur > « Flux N »).
  // §providerTag — Le marqueur du fournisseur (FR, US, IT…) reste le DERNIER
  // recours avant « Flux N » : il distingue réellement deux versions, mais ce
  // n'est pas une qualité — d'où le libellé « version » et non « qualité » sur
  // le déroulant ci-dessous.
  // §versionLabel — Même ordre que les pastilles de la fiche : qualité, puis
  // langue, puis marqueur fournisseur. Quand la liste n'annonce aucune qualité,
  // on utilise celle qu'on a MESURÉE à la lecture (§qualityTruth), préfixée
  // d'un `~` : c'est ce que ce flux a servi, pas une promesse du fournisseur.
  String baseLabel(M3uEntry v, int i) {
    final q = v.title.quality;
    if (q != null) return q;
    final measured = MeasuredQualityService.get(v.url);
    if (measured != null) return '~${measured.definitionLabel}';
    return (v.title.languages.isNotEmpty ? v.title.languages.first : null) ??
        v.title.versionLabel ??
        v.title.providerTag ??
        'Flux ${i + 1}';
  }
  final bases = sorted.indexed.map((e) => baseLabel(e.$2, e.$1)).toList();

  // 2) Compte les collisions de label.
  final counts = <String, int>{};
  for (final b in bases) {
    counts[b] = (counts[b] ?? 0) + 1;
  }

  // 3) Suffixe les labels en collision par le nom du compte / un index.
  return sorted.indexed.map((e) {
    final i = e.$1;
    final v = e.$2;
    var label = bases[i];
    if ((counts[label] ?? 0) > 1) {
      final acc = ParsedPlaylistService.accountName(v.accountId);
      label = (acc != null && acc.isNotEmpty) ? '$label · $acc' : '$label · ${i + 1}';
    }
    return (v, label);
  }).toList();
}

/// Couleur sémantique d'une qualité (réutilise le code couleur de l'app).
Color _qualityColor(String? q) {
  switch ((q ?? '').toUpperCase()) {
    case '4K':
    case 'UHD':
      return kQuality4K;
    case 'FHD':
      return kQualityFHD;
    case 'HD':
      return kQualityHD;
    case 'SD':
      return kQualitySD;
    case 'CAM': // §camQuality — rip de salle
      return kQualityCam;
    default:
      return kQualityUnknown;
  }
}

/// §watchContext c — Sélecteur de qualité « meilleure + déroulant ».
///
/// Un **bouton principal** lance directement la **meilleure qualité** dispo
/// (1 geste pour regarder). S'il existe d'autres flux, un lien **« Changer la
/// qualité ▾ »** déplie des **pastilles colorées par qualité** (4K/FHD/HD/SD),
/// avec la source en suffixe quand deux flux partagent la même qualité
/// (cf. [labeledVersions]). Tout est focusable au D-pad (TV).
class QualityButtonsRow extends StatefulWidget {
  final List<M3uEntry> versions;
  final void Function(M3uEntry) onPlay;

  const QualityButtonsRow(
      {super.key, required this.versions, required this.onPlay});

  @override
  State<QualityButtonsRow> createState() => _QualityButtonsRowState();
}

class _QualityButtonsRowState extends State<QualityButtonsRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // §qualityTruth — Revenir du lecteur doit suffire à faire apparaître la
    // mesure : la feuille reste montée pendant la lecture.
    return ValueListenableBuilder<int>(
      valueListenable: MeasuredQualityService.version,
      builder: (_, __, ___) => _buildInner(context),
    );
  }

  Widget _buildInner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labeled = labeledVersions(widget.versions);
    if (labeled.isEmpty) return const SizedBox.shrink();

    // §watchContext c — Défaut CHAÎNES = FHD (les flux 4K en direct sont souvent
    // lourds/instables sur les box TV). Préférence du bouton principal :
    // FHD > HD > SD > 4K. Le 4K reste accessible dans le déroulant.
    const primaryPref = ['FHD', 'HD', 'SD', '4K', 'UHD'];
    int bestIdx = -1;
    for (final pref in primaryPref) {
      bestIdx = labeled.indexWhere((e) => e.$1.title.quality == pref);
      if (bestIdx >= 0) break;
    }
    if (bestIdx < 0) bestIdx = 0; // qualités inconnues → 1er dispo
    final best = labeled[bestIdx];
    final others = [
      for (var i = 0; i < labeled.length; i++)
        if (i != bestIdx) labeled[i],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bouton principal — lance la meilleure qualité.
        _primaryButton(best.$1, best.$2),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 6),
          // Toggle « Changer la qualité ▾ ».
          FocusableChip(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                          size: 18, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        _expanded
                            ? 'Masquer les versions'
                            : 'Changer de version',
                        style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: others.map((e) => _altChip(e.$1, e.$2)).toList(),
              ),
            ),
        ],
      ],
    );
  }

  /// Gros bouton plein largeur (dégradé app) « ▶ Regarder · {qualité} ».
  Widget _primaryButton(M3uEntry v, String label) {
    return FocusableChip(
      onTap: () => widget.onPlay(v),
      borderRadius: BorderRadius.circular(10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => widget.onPlay(v),
          child: Ink(
            decoration: BoxDecoration(
              gradient: kAetherGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Container(
              width: double.infinity,
              height: 46,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_arrow_rounded, color: kWhite, size: 20),
                  const SizedBox(width: 6),
                  Text('Regarder · $label',
                      style: const TextStyle(
                          color: kWhite,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  // §qualityTruth — Ce que ce flux a réellement servi la
                  // dernière fois. Sur une chaîne annoncée FHD qui sert du
                  // 720p, c'est ici que ça se voit — avant de lancer.
                  ..._measuredSuffix(v, onGradient: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// §qualityTruth — Suffixe « réel … » collé au libellé d'un flux.
  ///
  /// Ne dit rien tant que le flux n'a jamais été lu, et ne dit rien non plus
  /// quand la mesure CONFIRME l'annonce : le libellé porte déjà l'information,
  /// la répéter n'apprendrait rien et alourdirait chaque ligne. On ne parle que
  /// pour signaler un écart.
  ///
  /// [onGradient] : sur le bouton principal, le fond est le dégradé de l'app —
  /// une couleur de texte sombre y serait illisible.
  List<Widget> _measuredSuffix(M3uEntry v, {bool onGradient = false}) {
    final measured = MeasuredQualityService.get(v.url);
    if (measured == null) return const [];
    final verdict = measured.verdictFor(v.title.quality);
    if (verdict == QualityVerdict.conforme ||
        verdict == QualityVerdict.unknown) {
      return const [];
    }
    final survendu = verdict == QualityVerdict.survendu;
    return [
      const SizedBox(width: 6),
      Text(
        survendu
            ? '⚠ réel ${measured.definitionLabel}'
            : 'réel ${measured.definitionLabel}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: onGradient
              ? kWhite.withAlpha(survendu ? 255 : 200)
              : (survendu ? kError : kAccentSecondary),
        ),
      ),
    ];
  }

  /// Pastille colorée par qualité pour les flux alternatifs.
  Widget _altChip(M3uEntry v, String label) {
    final color = _qualityColor(v.title.quality);
    return FocusableChip(
      onTap: () => widget.onPlay(v),
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => widget.onPlay(v),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withAlpha(130)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded, color: color, size: 16),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                ..._measuredSuffix(v),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
