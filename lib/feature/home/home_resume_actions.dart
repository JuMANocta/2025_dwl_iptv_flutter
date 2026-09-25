import '../../data/models/m3u_entry.dart';
import '../player/group_resume.dart' show sameItemVersions;
import '../search/series_stub.dart' show isSeriesStubEntry;

/// R52 (2026-09-25) — Les reprises qu'efface « Lire depuis le début » dans la
/// feuille d'appui long d'une carte de l'accueil. **Pure** — testée
/// (`test/home_restart_resume_test.dart`).
///
/// **Le défaut réparé.** La tuile effaçait la reprise de TOUTES les versions
/// de la carte (§resumeUnify). Pour un film, c'est juste : ses versions sont
/// le même film. Pour une série, les « versions » d'un groupe sont TOUS ses
/// épisodes (et parfois son stub) : relancer S01E02 depuis le début effaçait
/// aussi la reprise de S01E03 — une soirée de visionnage perdue en un geste.
///
/// **La règle.** Seulement les versions du MÊME élément que [target]
/// (`sameItemVersions` : même saison et même numéro pour un épisode, toutes
/// les versions pour un film). Et quand la reprise AFFICHÉE est portée par le
/// stub de la série ([resumeOnStub], §heroSeriesResume), le stub aussi : c'est
/// elle que la tuile « Reprendre » montrait, la laisser la ferait réapparaître
/// juste après un « depuis le début ».
List<String> restartClearUrls(
  M3uEntry target,
  Iterable<M3uEntry> versions, {
  bool resumeOnStub = false,
}) =>
    <String>{
      for (final M3uEntry v in sameItemVersions(target, versions)) v.url,
      if (resumeOnStub)
        for (final M3uEntry v in versions)
          if (isSeriesStubEntry(v)) v.url,
    }.toList();
