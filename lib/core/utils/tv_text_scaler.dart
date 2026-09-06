import 'package:flutter/widgets.dart';

/// §tvSmallText — Taille finale d'un texte sur téléviseur.
///
/// **Le défaut corrigé** : l'app porte 144 `fontSize` en dur entre 9 et 12 px,
/// et **aucun** n'est conditionné à `PlatformTv.isTv` — alors que l'échelle
/// système est verrouillée à ×1.0 sur TV (§3c-7). Un « 9 px » pensé pour un
/// téléphone tenu à 30 cm est illisible sur un écran regardé à trois mètres.
///
/// ⚠️ **Ce n'est PAS un agrandissement global.** Deux tentatives d'échelle
/// uniforme (×1.3 puis ×1.15) ont été essayées et ABANDONNÉES : elles donnaient
/// une interface « ultra-zoomée », parce que la TV applique déjà sa propre
/// densité physique généreuse. Ne pas les réessayer sous une autre forme.
///
/// Ce qui change ici, c'est un **plancher** : seules les tailles sous
/// [smallBelow] montent, et jamais au-dessus de [ceiling]. Un titre à 16 px
/// n'est pas touché ; une mention à 9 px passe à 11,25.
double tvSmallTextSize(double fontSize) {
  if (fontSize <= 0 || fontSize >= smallBelow) return fontSize;
  final double lifted = fontSize * smallBoost;
  return lifted > ceiling ? ceiling : lifted;
}

/// Au-dessus de cette taille, le texte est déjà lisible de loin : on n'y touche
/// pas.
const double smallBelow = 13;

/// Facteur appliqué aux petites tailles. +25 % fait passer 9 → 11,25 et
/// 12 → 15 (rabotté à [ceiling]).
const double smallBoost = 1.25;

/// Plafond : au-delà, on déformerait la hiérarchie typographique (une mention
/// deviendrait plus grosse qu'un sous-titre à 13 px).
const double ceiling = 14;

/// §tvSmallText — [TextScaler] qui n'agrandit QUE le petit texte.
///
/// ⚠️ [operator ==] et [hashCode] sont indispensables : `MediaQuery` compare
/// ses données pour décider de propager une notification. Deux instances
/// distinctes mais équivalentes feraient repeindre tout l'arbre à chaque
/// reconstruction du `builder` de `MaterialApp`.
@immutable
class TvSmallTextScaler extends TextScaler {
  const TvSmallTextScaler();

  @override
  double scale(double fontSize) => tvSmallTextSize(fontSize);

  /// L'API dépréciée n'a pas de sens ici (le facteur dépend de la taille) :
  /// on rend 1.0, la valeur neutre, comme le fait `TextScaler.noScaling`.
  @override
  double get textScaleFactor => 1.0;

  @override
  bool operator ==(Object other) => other is TvSmallTextScaler;

  @override
  int get hashCode => (TvSmallTextScaler).hashCode;

  @override
  String toString() => 'TvSmallTextScaler(<${smallBelow}px → ×$smallBoost, '
      'plafond ${ceiling}px)';
}
