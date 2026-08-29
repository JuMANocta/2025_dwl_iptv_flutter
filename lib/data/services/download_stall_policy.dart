/// §dlWatchdog — Décide SEULE si un transfert qui ralentit doit être reconnecté.
///
/// Extraite du service pour être testable : le reste de
/// `DownloadManagerService` traîne un Dio, des fichiers et un singleton, alors
/// que la règle, elle, est arithmétique.
library;

/// Sous quelle fraction de son meilleur débit un transfert est considéré comme
/// bridé. Volontairement bas : mieux vaut rater un bridage léger que couper une
/// connexion simplement lente.
const double kStallRatio = 0.25;

/// Délai minimal entre deux relances automatiques. Une reconnexion coûte une
/// poignée de secondes (DNS + TLS + `Range`) : les enchaîner ferait moins
/// avancer le fichier que de laisser filer un débit médiocre.
const Duration kAutoRestartCooldown = Duration(seconds: 30);

/// En dessous de ce gain entre deux relances, on arrête d'essayer : ce n'est
/// plus un bridage, c'est une source morte, et boucler dessus la martèlerait
/// sans jamais finir le fichier.
const int kMinGainBetweenRestarts = 1 << 20; // 1 Mo

/// `true` si le débit observé s'est effondré par rapport au meilleur atteint.
///
/// `peak == null` = on n'a pas encore de référence (première mesure) : sans
/// point de comparaison, un démarrage lent passerait pour un décrochage.
bool isStalled({required double speed, double? peak}) =>
    peak != null && peak > 0 && speed < peak * kStallRatio;

/// `true` si une relance automatique est justifiée MAINTENANT.
///
/// - [sinceLastRestart] : `null` si aucune relance automatique n'a eu lieu.
/// - [gainSinceLastRestart] : octets gagnés depuis la dernière relance
///   automatique, `null` s'il n'y en a pas eu.
bool shouldAutoRestart({
  required Duration? sinceLastRestart,
  required int? gainSinceLastRestart,
}) {
  if (sinceLastRestart != null && sinceLastRestart < kAutoRestartCooldown) {
    return false;
  }
  // ⚠️ Garde-fou anti-boucle : si la relance précédente n'a presque rien
  // rapporté, relancer encore ne servira pas davantage.
  if (gainSinceLastRestart != null &&
      gainSinceLastRestart < kMinGainBetweenRestarts) {
    return false;
  }
  return true;
}
