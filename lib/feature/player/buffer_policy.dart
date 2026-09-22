/// §bufferBudget (2026-09-21) — Ce que le tampon de lecture a le droit de
/// PRENDRE en mémoire, et ce qu'il garde derrière lui.
///
/// **Le constat, mesuré.** `PerfConfig.bufferSeconds` règle une DURÉE, mais
/// `DefaultLoadControl` (Media3 1.5) applique aussi un plafond en OCTETS que
/// personne n'avait choisi : ~125 Mo pour la vidéo, calculé à partir des
/// pistes, et il l'emporte sur la durée (`prioritizeTimeOverSizeThresholds`
/// vaut `false`). Ces octets sont alloués dans le tas JAVA de l'app, borné par
/// `memoryClass` (192 Mo sur l'AVD TV, souvent 128 Mo sur une box à 1 Go, sans
/// `largeHeap`). Sur l'AVD TV, un flux 960p à ~4 Mbit/s a fait passer le tas
/// Java de 11 à 39 Mo (30 s / 60 s) ; à 20–40 Mbit/s (4K, remux FHD), le
/// tampon monte jusqu'aux 125 Mo — un risque d'`OutOfMemoryError` en pleine
/// lecture sur une box à 128 Mo. Le profil Léger ne protégeait qu'à moitié :
/// il borne la durée, pas les octets.
///
/// **La règle.** Le plafond suit la mémoire RÉELLE de l'appareil (sonde
/// §deviceCaps) : 40 % de `memoryClass`, jamais moins de 32 Mo (sinon un flux
/// FHD ne tient plus quelques secondes), jamais plus que le défaut de Media3.
/// La durée choisie reste respectée tant qu'elle tient dans ce budget.
library;

/// Le défaut de Media3 pour la vidéo : 2 000 segments de 64 Kio.
const int kMedia3VideoBufferBytes = 2000 * 64 * 1024;

/// Plancher : en dessous, un flux FHD à 10 Mbit/s ne tient plus 25 s.
const int kMinBufferBudgetBytes = 32 * 1024 * 1024;

/// Budget quand la sonde n'a encore rien mesuré : sûr sur une box à 128 Mo
/// (≈ 50 s de FHD à 10 Mbit/s), sans affamer un appareil confortable.
const int kUnknownDeviceBufferBytes = 64 * 1024 * 1024;

/// §bufferBudget — Plafond du tampon, en octets, pour un tas Java de
/// [memoryClassMb] Mo (`null` ou ≤ 0 : pas encore mesuré). **Pure** — testée.
int bufferBudgetBytes({int? memoryClassMb}) {
  if (memoryClassMb == null || memoryClassMb <= 0) {
    return kUnknownDeviceBufferBytes;
  }
  final int share = (memoryClassMb * 1024 * 1024 * 0.4).round();
  if (share < kMinBufferBudgetBytes) return kMinBufferBudgetBytes;
  if (share > kMedia3VideoBufferBytes) return kMedia3VideoBufferBytes;
  return share;
}

/// §bufferBudget — Secondes gardées DERRIÈRE la position de lecture : « −10 s »
/// repart de la mémoire au lieu de retélécharger. Seulement quand le profil
/// garde un tampon confortable (Complet / Équilibré, 30 s et plus) ; le profil
/// Léger (15 s) n'en garde pas — c'est lui qu'on choisit quand la mémoire
/// manque. Les octets de l'arrière comptent DANS [bufferBudgetBytes] : le
/// plafond ne bouge pas. **Pure** — testée.
int backBufferMsFor(int bufferSeconds) => bufferSeconds >= 30 ? 10000 : 0;
