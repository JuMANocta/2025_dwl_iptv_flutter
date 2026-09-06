import 'package:flutter/material.dart';

import '../../core/themes/colors.dart';
import '../../core/utils/user_error.dart';
import '../../data/services/hidden_regions_service.dart';
import '../../data/services/parsed_playlist_service.dart';
import '../../data/services/playlist_service.dart';
import '../../data/services/stream_account_service.dart';
import '../search/m3u_filter.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';
import '../../l10n/app_localizations.dart';

/// §langFilter — Réglage des langues/régions à MASQUER du catalogue.
///
/// Les entrées dont le préfixe `|XX|` correspond à une région cochée sont
/// **filtrées au parsing** (jamais stockées) → RAM + cache réduits. À
/// l'application, le compte actif est re-parsé immédiatement (catalogue brut
/// conservé → pas de re-téléchargement) et les comptes secondaires invalidés.
class RegionFilterPage extends StatefulWidget {
  const RegionFilterPage({super.key});

  @override
  State<RegionFilterPage> createState() => _RegionFilterPageState();
}

class _RegionFilterPageState extends State<RegionFilterPage>
    with TvInitialFocus {
  late Set<String> _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selected = {...HiddenRegionsService.hidden};
  }

  bool get _dirty =>
      _selected.length != HiddenRegionsService.hidden.length ||
      !_selected.containsAll(HiddenRegionsService.hidden);

  Future<void> _apply() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final changed = await HiddenRegionsService.setHidden(_selected);
      if (changed) {
        // Re-parse du compte actif (filtre appliqué) + invalidation des autres.
        final accounts = await StreamAccountService.listAccounts();
        final active = await StreamAccountService.getCurrentAccount();
        if (active != null) {
          final path = await PlaylistService.pathForAccountId(active.id);
          await ParsedPlaylistService.reloadFromDisk(
              active.id, active.label, path);
        }
        for (final a in accounts) {
          if (a.id != active?.id) ParsedPlaylistService.invalidate(a.id);
        }
      }
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(changed
              ? '✅ Filtre appliqué — catalogue rechargé'
              : 'Aucun changement'),
          backgroundColor: kSuccess,
        ));
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text('❌ Échec : ${describeError(e)}'),
            backgroundColor: kError));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // ⚠️ Quitter pendant la ré-analyse laisserait un catalogue à moitié
    // rechargé : on retient la page le temps de l'opération.
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.regionFilterTitle),
          elevation: 0,
          scrolledUnderElevation: 0,
          // Barre de progression sous le titre : visible même quand le
          // bouton flottant, lui, n'est plus là.
          bottom: _busy
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(3),
                  child: LinearProgressIndicator(minHeight: 3),
                )
              : null,
          actions: [
            // §langFilter — Tout masquer / tout afficher d'un coup.
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        if (_selected.length == kHideableRegionLabels.length) {
                          _selected.clear();
                        } else {
                          _selected = {...kHideableRegionLabels};
                        }
                      }),
              child: Text(
                _selected.length == kHideableRegionLabels.length
                    ? 'Tout afficher'
                    : 'Tout masquer',
                style: TextStyle(
                    color: kAccentPrimary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        // ⚠️ **`_dirty` retombe à faux dès la PREMIÈRE ligne du travail** :
        // `setHidden` écrit la sélection, donc elle devient égale à l'état
        // enregistré. Le bouton — et son indicateur — disparaissaient donc
        // pile au moment où l'attente commençait, laissant l'utilisateur
        // devant un écran muet pendant la ré-analyse (constaté 2026-09-05).
        // D'où `|| _busy` : l'indicateur survit à sa propre condition.
        floatingActionButton: (_dirty || _busy)
            ? FloatingActionButton.extended(
                backgroundColor: kAccentPrimary,
                foregroundColor: Colors.black,
                onPressed: _busy ? null : _apply,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.check),
                label: Text(_busy ? 'Application…' : 'Appliquer'),
              )
            : null,
        body: Stack(
          children: [
            // ⚠️ Le voile arrête le doigt, pas la télécommande : sans
            // `ExcludeFocus`, les cases restaient cochables au D-pad pendant
            // la ré-analyse.
            ExcludeFocus(
              excluding: _busy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Coche les langues/régions à MASQUER du catalogue. Le contenu '
                      'français (|FR|), québécois et VOSTFR est toujours conservé.\n'
                      '• Mémoire allégée immédiatement après « Appliquer ».\n'
                      '• La taille du catalogue sur disque diminue au prochain '
                      'rechargement de la playlist (auto 24 h ou bouton ⟳ de l\'accueil).',
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...kHideableRegionLabels.map((region) {
                    final hidden = _selected.contains(region);
                    return CheckboxThemeListTile(
                      region: region,
                      hidden: hidden,
                      onChanged: (v) => setState(() {
                        if (v) {
                          _selected.add(region);
                        } else {
                          _selected.remove(region);
                        }
                      }),
                    );
                  }),
                ],
              ),
            ),
            // Ce que l'attente signifie, et pourquoi elle dure : le catalogue
            // entier est ré-analysé. Le voile empêche de re-cocher pendant.
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withAlpha(160),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 18),
                          const Text(
                            'Application du filtre…',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Le catalogue est ré-analysé. Cela peut prendre '
                            'quelques secondes sur une grande liste.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withAlpha(200),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CheckboxThemeListTile extends StatelessWidget {
  final String region;
  final bool hidden;
  final ValueChanged<bool> onChanged;
  const CheckboxThemeListTile({
    super.key,
    required this.region,
    required this.hidden,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: hidden,
      onChanged: (v) => onChanged(v ?? false),
      activeColor: kAccentPrimary,
      title: Text(region),
      secondary: Icon(
        hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color:
            hidden ? kWarning : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      subtitle: Text(hidden ? 'Masqué' : 'Visible',
          style: TextStyle(
              fontSize: 11,
              color: hidden
                  ? kWarning
                  : Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}
