import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/core/settings/performance_settings_service.dart';
import 'package:aetherStream/data/services/visual_language_service.dart';
import 'package:aetherStream/feature/settings/visual_language_page.dart';
import 'package:aetherStream/data/services/inferred_category_service.dart';
import 'package:aetherStream/data/services/tmdb_poster_cache.dart';
import 'package:aetherStream/data/services/tmdb_api_service.dart';
import 'package:aetherStream/data/services/tmdb_service.dart';
import 'package:aetherStream/feature/settings/web_console/web_console_page.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_ext.dart';

/// Sous-page Settings (§1g) : gestion de la clé API TMDB.
///
/// Extrait du card "API TheMovieDB" d'`AccountsPage` pour aligner avec le
/// hub `SettingsPage`. La clé est stockée dans `flutter_secure_storage` via
/// [TmdbApiService]. Une fois sauvée, le `TmdbService` singleton est réinitialisé
/// pour prendre en compte la nouvelle clé.
class TmdbKeyPage extends StatefulWidget {
  const TmdbKeyPage({super.key});

  @override
  State<TmdbKeyPage> createState() => _TmdbKeyPageState();
}

class _TmdbKeyPageState extends State<TmdbKeyPage> with TvInitialFocus {
  final _keyController = TextEditingController();
  bool _isKeyVisible = false;
  bool _hasSavedKey = false;
  bool _loading = true;
  // §3c-8 — Sur TV, le TextField est replié derrière un bouton "avancé"
  // pour éviter le piège de saisie au D-pad d'un Bearer JWT de 220 chars.
  bool _showAdvancedManual = false;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  /// §webConsoleOnly — Console web mobile→TV pour coller la clé TMDB depuis le
  /// téléphone (remplace l'ancien pairing QR mono-champ).
  ///
  /// Le QR ouvre directement la page « Clé TMDB » du panneau, qui enregistre
  /// elle-même via `TmdbApiService` + `TmdbService.resetInstance()`. On relit
  /// donc simplement la clé au retour pour rafraîchir l'affichage.
  Future<void> _openPhoneConfig() async {
    final messenger = ScaffoldMessenger.of(context);
    final hadKey = _hasSavedKey;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const WebConsolePage(initialView: 'tmdb'),
      ),
    );
    if (!mounted) return;
    await _loadKey();
    if (!mounted) return;
    if (!hadKey && _hasSavedKey) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('✅ TMDb connecté'),
          backgroundColor: kSuccess,
        ),
      );
    }
  }

  Future<void> _loadKey() async {
    final key = await TmdbApiService.getApiKey();
    if (!mounted) return;
    setState(() {
      _keyController.text = key ?? '';
      _hasSavedKey = key != null && key.isNotEmpty;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await TmdbApiService.saveApiKey(key);
    TmdbService.resetInstance();
    if (!mounted) return;
    setState(() => _hasSavedKey = true);
    FocusScope.of(context).unfocus();
    messenger.showSnackBar(
      SnackBar(
        content: Text('✅ TMDb connecté'),
        backgroundColor: kSuccess,
      ),
    );
  }

  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    await TmdbApiService.deleteApiKey();
    TmdbService.resetInstance();
    if (!mounted) return;
    setState(() {
      _keyController.clear();
      _hasSavedKey = false;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text('🗑️ Clé TMDB supprimée'),
        backgroundColor: kError,
      ),
    );
  }

  Future<void> _openTmdbSignup() async {
    final uri = Uri.parse('https://www.themoviedb.org/settings/api');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTv = PlatformTv.isTv;
    // §3c-8 — Sur TV, on cache le TextField par défaut (le coller au D-pad
    // d'un Bearer JWT 220 chars = ~8 minutes pour rien). Affiché seulement
    // si l'utilisateur choisit explicitement "Saisir manuellement".
    final showManualField = !isTv || _showAdvancedManual || _hasSavedKey;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.tmdbKeyTitle),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? null : cs.surface,
          gradient: isDark
              ? RadialGradient(
                  center: const Alignment(0, -1.5),
                  radius: 1.4,
                  colors: [
                    kAccentPrimary.withAlpha(20),
                    cs.surface,
                  ],
                )
              : null,
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusBanner(active: _hasSavedKey),
                    if (isTv) ...[
                      const SizedBox(height: 20),
                      _TvPairingCta(
                        hasKey: _hasSavedKey,
                        onTap: _openPhoneConfig,
                      ),
                    ],
                    if (showManualField) ...[
                      const SizedBox(height: 20),
                      Text(
                        isTv && !_hasSavedKey
                            ? 'Saisie manuelle (avancée)'
                            : 'Bearer Token (v4 API)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _keyController,
                        obscureText: !_isKeyVisible,
                        readOnly: _hasSavedKey,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                        style: TextStyle(
                          color: _hasSavedKey ? kAccentSecondary : cs.onSurface,
                          fontWeight: _hasSavedKey
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Coller ici votre token v4…',
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(_isKeyVisible
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () => setState(
                                () => _isKeyVisible = !_isKeyVisible),
                            tooltip: _isKeyVisible
                                ? 'Masquer'
                                : 'Afficher',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          if (_hasSavedKey)
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _delete,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Supprimer'),
                                // §detailsActions — bouton plein (cohérence : plus
                                // de mélange plein/contour). Rouge = destructif.
                                style: FilledButton.styleFrom(
                                  backgroundColor: kError,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _save,
                                icon: const Icon(Icons.save),
                                label: const Text('Sauvegarder'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  backgroundColor: kAccentPrimary,
                                  foregroundColor: Colors.black,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ] else if (isTv && !_hasSavedKey) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => _showAdvancedManual = true),
                          icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                          label: const Text(
                              'Saisir manuellement à la télécommande'),
                          style: TextButton.styleFrom(
                              foregroundColor: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                    // §posterLang — Les réglages TMDB vivent AVEC la clé
                    // TMDB (demande utilisateur du 2026-09-05). Ils étaient
                    // répartis entre Paramètres et Optimisation : deux endroits
                    // pour un même sujet, aucun des deux évident.
                    // Affichés seulement si une clé existe — sans clé, ils ne
                    // peuvent rien faire.
                    if (_hasSavedKey) ...[
                      const SizedBox(height: 32),
                      _TmdbOptionsBlock(onChanged: () => setState(() {})),
                    ],
                    const SizedBox(height: 32),
                    _InfoBlock(onOpenTmdb: _openTmdbSignup),
                  ],
                ),
              ),
      ),
    );
  }
}

/// §3c-8 — Card "Configurer depuis mobile" affichée en tête sur TV.
class _TvPairingCta extends StatelessWidget {
  final bool hasKey;
  final VoidCallback onTap;
  const _TvPairingCta({required this.hasKey, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // §tvErgo — Wrap FocusableCard pour le glow Matrix au focus D-pad (cohérence
    // avec les autres CTA TV). scaleOnFocus:false (CTA pleine largeur) +
    // InkWell non focusable (évite le doublon d'arrêt D-pad).
    return FocusableCard(
      decorateOnly: true,
      scaleOnFocus: false,
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kAccentPrimary.withAlpha(140), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: kAccentPrimary.withAlpha(50),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: kAccentPrimary.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: kAccentPrimary.withAlpha(150), width: 1),
                ),
                child:
                    Icon(Icons.phone_iphone, color: kAccentPrimary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasKey
                          ? 'Remplacer depuis mon téléphone'
                          : 'Configurer depuis mon téléphone',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Scanne un QR et colle le Bearer Token côté mobile',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final bool active;
  const _StatusBanner({required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? kAccentPrimary : cs.outlineVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: active ? kAccentPrimary.withAlpha(20) : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: active ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_circle : Icons.info_outline,
            color: active ? kAccentPrimary : cs.onSurfaceVariant,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              active
                  ? 'TMDb connecté — affiches et synopsis disponibles'
                  : 'Aucune clé enregistrée — fonctionne sans, mais sans enrichissement visuel',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: active ? kAccentPrimary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final VoidCallback onOpenTmdb;
  const _InfoBlock({required this.onOpenTmdb});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, size: 18, color: kAccentSecondary),
              const SizedBox(width: 8),
              Text(
                'Comment obtenir un token ?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '1. Crée un compte gratuit sur themoviedb.org\n'
            '2. Va dans Paramètres → API\n'
            '3. Demande une clé v4 (Read Access Token)\n'
            '4. Colle le token ici',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onOpenTmdb,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Ouvrir themoviedb.org',
                style: TextStyle(fontWeight: FontWeight.bold)),
            // §detailsActions — plein (cohérence page : plus de bouton contour).
            style: FilledButton.styleFrom(
              backgroundColor: kAccentSecondary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}


/// §posterLang — Les réglages qui décident **comment** TMDB est utilisé.
///
/// Ils vivent ici, avec la clé, parce que c'est le seul endroit où l'on pense
/// à TMDB. Auparavant la langue était dans Paramètres → Affichage et la
/// préférence d'affiche dans Optimisation : personne ne les aurait rapprochés.
class _TmdbOptionsBlock extends StatefulWidget {
  const _TmdbOptionsBlock({required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<_TmdbOptionsBlock> createState() => _TmdbOptionsBlockState();
}

class _TmdbOptionsBlockState extends State<_TmdbOptionsBlock> {
  Future<void> _openVisualLanguage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VisualLanguagePage()),
    );
    if (mounted) setState(() {});
  }

  void _togglePostersFirst(bool v) {
    PerformanceSettingsService.save(
      PerformanceSettingsService.config.value.copyWith(tmdbPostersFirst: v),
    );
    setState(() {});
    widget.onChanged();
  }

  // §tmdbRows — Les deux rangées éditoriales de l'accueil.
  void _toggleRowBecause(bool v) {
    PerformanceSettingsService.save(
      PerformanceSettingsService.config.value.copyWith(tmdbRowBecause: v),
    );
    setState(() {});
    widget.onChanged();
  }

  void _toggleRowTopRated(bool v) {
    PerformanceSettingsService.save(
      PerformanceSettingsService.config.value.copyWith(tmdbRowTopRated: v),
    );
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final perf = PerformanceSettingsService.config.value;
    final bool postersFirst = perf.tmdbPostersFirst;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tune_rounded, size: 18, color: kAccentSecondary),
            const SizedBox(width: 8),
            Text(
              'Utilisation de TMDB',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Langue des visuels ────────────────────────────────────────────
        FocusableCard(
          decorateOnly: true,
          scaleOnFocus: false,
          onTap: _openVisualLanguage,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Icon(Icons.translate_rounded, color: kAccentSecondary),
            title: const Text('Langue des visuels'),
            subtitle: Text(
              '${VisualLanguageService.labelOf(VisualLanguageService.value)} '
              '— affiches, résumés et casting',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openVisualLanguage,
          ),
        ),
        const SizedBox(height: 8),

        // ── Jaquettes TMDB d'abord ────────────────────────────────────────
        FocusableCard(
          decorateOnly: true,
          scaleOnFocus: false,
          onTap: () => _togglePostersFirst(!postersFirst),
          borderRadius: BorderRadius.circular(12),
          child: SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            secondary:
                Icon(Icons.image_search_rounded, color: kAccentSecondary),
            title: const Text("Jaquettes TMDB d'abord"),
            subtitle: Text(
              postersFirst
                  ? "L'affiche TMDB passe avant celle de vos listes"
                  : "Vos listes fournissent l'affiche ; TMDB ne sert qu'en "
                      'secours',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            value: postersFirst,
            onChanged: _togglePostersFirst,
          ),
        ),
        const SizedBox(height: 8),

        // ── §tmdbRows — « Parce que tu as regardé » ──────────────────────
        FocusableCard(
          decorateOnly: true,
          scaleOnFocus: false,
          onTap: () => _toggleRowBecause(!perf.tmdbRowBecause),
          borderRadius: BorderRadius.circular(12),
          child: SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            secondary: Icon(Icons.recommend_outlined, color: kAccentSecondary),
            title: Text(l10n.tmdbRowsBecauseTitle),
            subtitle: Text(
              l10n.tmdbRowsBecauseSub,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            value: perf.tmdbRowBecause,
            onChanged: _toggleRowBecause,
          ),
        ),
        const SizedBox(height: 8),

        // ── §tmdbRows — « Les mieux notés » ───────────────────────────────
        FocusableCard(
          decorateOnly: true,
          scaleOnFocus: false,
          onTap: () => _toggleRowTopRated(!perf.tmdbRowTopRated),
          borderRadius: BorderRadius.circular(12),
          child: SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            secondary: Icon(Icons.workspace_premium_outlined,
                color: kAccentSecondary),
            title: Text(l10n.tmdbRowsTopRatedTitle),
            subtitle: Text(
              l10n.tmdbRowsTopRatedSub,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            value: perf.tmdbRowTopRated,
            onChanged: _toggleRowTopRated,
          ),
        ),
        const SizedBox(height: 20),
        const _TmdbMaintenanceBlock(),
      ],
    );
  }
}

/// §tmdbCacheUi (2026-09-05) — Rendre VISIBLE ce que l'app a mémorisé de TMDB,
/// et donner de quoi repartir de zéro.
///
/// **Pourquoi ça manquait.** Deux caches persistés travaillent en silence :
/// les affiches résolues (§tmdbUrlPersist) et les catégories devinées pour les
/// listes qui n'en fournissent aucune (§inferredCat). Aucun écran ne les
/// montrait, et **rien ne permettait de les vider** — il fallait changer le
/// suffixe de version dans le code. Une affiche mal appariée ou une catégorie
/// mal devinée restait donc là pour toujours.
class _TmdbMaintenanceBlock extends StatefulWidget {
  const _TmdbMaintenanceBlock();

  @override
  State<_TmdbMaintenanceBlock> createState() => _TmdbMaintenanceBlockState();
}

class _TmdbMaintenanceBlockState extends State<_TmdbMaintenanceBlock> {
  bool _busy = false;

  /// Vide les affiches mémorisées. Non destructif : elles se résolvent à
  /// nouveau à l'affichage. On agit donc directement, avec un compte rendu —
  /// même parti que « Vider le cache images » dans Optimisation.
  Future<void> _clearPosters() async {
    final messenger = ScaffoldMessenger.of(context);
    final int had = TmdbPosterCache.resolvedCount;
    setState(() => _busy = true);
    await TmdbPosterCache.clear();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(had == 0
          ? 'Aucune affiche mémorisée'
          : '🧹 $had affiche(s) oubliée(s) — elles seront recherchées à '
              'nouveau au prochain affichage'),
    ));
  }

  /// Oublie les catégories devinées par TMDB (§inferredCat).
  ///
  /// ⚠️ Ne touche PAS aux catégories venues des listes elles-mêmes
  /// (`group-title`) : seulement celles que l'app a déduites pour les listes
  /// qui n'en fournissent aucune — le format « Ultimate », où 100 % des
  /// entrées arrivent sans groupe.
  Future<void> _relearnCategories() async {
    final messenger = ScaffoldMessenger.of(context);
    final int had = InferredCategoryService.count;
    setState(() => _busy = true);
    await InferredCategoryService.clear();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(had == 0
          ? 'Aucune catégorie déduite à oublier'
          : '🧹 $had catégorie(s) oubliée(s) — elles seront réapprises en '
              "parcourant l'accueil"),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final int posters = TmdbPosterCache.resolvedCount;
    final int unknown = TmdbPosterCache.unknownCount;
    final int network = TmdbPosterCache.networkResolutions;
    final int cats = InferredCategoryService.count;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.storage_rounded, size: 18, color: kAccentSecondary),
            const SizedBox(width: 8),
            Text(
              'Mémoire TMDB',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Affiches mémorisées ───────────────────────────────────────────
        _MaintenanceTile(
          icon: Icons.photo_library_outlined,
          title: 'Affiches mémorisées',
          detail: posters == 0
              ? "Rien de mémorisé pour l'instant"
              : '$posters titre(s) résolu(s), dont $unknown inconnu(s) de TMDB'
                  '${network > 0 ? ' · $network recherche(s) réseau depuis le lancement' : ''}',
          actionLabel: 'Vider',
          onAction: _busy || posters == 0 ? null : _clearPosters,
        ),
        const SizedBox(height: 8),

        // ── Catégories déduites ───────────────────────────────────────────
        _MaintenanceTile(
          icon: Icons.category_outlined,
          title: 'Catégories déduites',
          detail: cats == 0
              ? 'Aucune — vos listes fournissent leurs propres catégories'
              : '$cats titre(s) rangé(s) grâce à TMDB, faute de catégorie '
                  'dans la liste',
          actionLabel: 'Réapprendre',
          onAction: _busy || cats == 0 ? null : _relearnCategories,
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Les titres introuvables sont mémorisés exprès : sans ça, '
                "l'application relancerait la même recherche vaine à chaque "
                "lancement. Un titre n'est cherché qu'une seule fois.",
                style: TextStyle(
                    color: cs.onSurfaceVariant, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Une ligne d'entretien : ce que contient un cache, et le bouton qui le vide.
/// Le bouton est DÉSACTIVÉ quand il n'y a rien à faire — plutôt qu'actif et
/// sans effet, ce qui laisserait croire à une panne.
class _MaintenanceTile extends StatelessWidget {
  const _MaintenanceTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool enabled = onAction != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(60),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withAlpha(90)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: cs.onSurface, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(detail,
                    style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ⚠️ §boundFocus — un bouton `onPressed: null` sort de la traversée
          // D-pad. Ici c'est sans piège : la tuile n'est pas une borne de page,
          // il reste des focusables avant et après.
          if (enabled)
            FocusableCard(
              decorateOnly: true,
              scaleOnFocus: false,
              onTap: onAction!,
              borderRadius: BorderRadius.circular(8),
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: kAccentSecondary,
                  minimumSize: const Size(0, 48), // §touchTarget
                ),
                child: Text(actionLabel),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(actionLabel,
                  style: TextStyle(color: cs.outline, fontSize: 14)),
            ),
        ],
      ),
    );
  }
}
