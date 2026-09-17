/// §bgAudio (2026-09-16) — Faut-il couper la piste VIDÉO quand l'application
/// passe en arrière-plan (écran éteint, autre application devant) ?
///
/// **Le constat** (fiche §bgAudio) : le son continue déjà écran éteint (wake
/// mode réseau du lecteur vendoré, service §nowPlaying), mais à la destruction
/// de la surface le rendu vidéo continue de décoder sur une surface de
/// substitution — de la batterie dépensée pour personne. Couper le TYPE vidéo
/// (`setTrackTypeDisabled`, patch 26) arrête ce décodage ; le rallumer au
/// retour au premier plan rend l'image sans rouvrir le flux.
///
/// **Où on ne coupe pas** :
///   - TV : pas de service de lecture en arrière-plan sur téléviseur
///     (`mediaInfo == null`, §nowPlaying) et la veille arrête l'app ;
///   - PiP : la fenêtre reste VISIBLE, l'image doit continuer (§pipPhone) ;
///   - diffusion Cast en cours : le lecteur local est déjà en pause, et c'est
///     le téléviseur qui décode.
///
/// Fonction pure : c'est elle qu'on teste. La lecture en pause n'entre pas en
/// ligne de compte : une reprise depuis la notification, écran éteint,
/// relancerait le décodage vidéo — autant que le type soit déjà coupé.
bool shouldDropVideoInBackground({
  required bool isTv,
  required bool inPip,
  required bool casting,
}) =>
    !isTv && !inPip && !casting;
