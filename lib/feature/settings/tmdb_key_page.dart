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
import '../../l10n/l10n_ext.dart';

/// Sous-page Settings (§1g) : gestion de la clé API TMDB.
///
/// Extrait du card "API TheMovieDB" d'`AccountsPage` pour aligner avec le
/// hub `SettingsPage`. La clé est stockée dans `flutter_secure_storage` via
/// [TmdbApiService]. Une fois sauvée, le `TmdbService` singleton est réinitialisé
/// pour prendre en compte la nouvelle clé.
///
/// §tmdbPageOrder (2026-09-05) — La page se lit dans l'ordre de ce que
/// l'utilisateur a À FAIRE, pas dans l'ordre où le code a été écrit :
/// - **sans clé** : comment en obtenir une, puis où la coller. Rien d'autre —
///   les options ne peuvent rien sans clé, on ne les montre pas ;
/// - **avec clé** : les options d'abord (c'est pour elles qu'on revient ici),
///   les données mémorisées ensuite, la clé TOUT EN BAS (on n'y touche qu'une
///   fois). Le mode d'emploi disparaît.
/// Les textes s'adressent à quelqu'un qui n'a jamais entendu parler d'une
/// API : pas de « v4 », pas de « Bearer », pas de compteurs de recherches.
/// Le lien d'inscription est `/signup` — `/settings/api` répond 401 à qui
/// n'est pas connecté, l'utilisateur voyait une page d'erreur.
class TmdbKeyPage extends StatefulWidget {
  const TmdbKeyPage({super.key});

  @override
  State<TmdbKeyPage> createState() => _TmdbKeyPageState();
}

class _TmdbKeyPageState extends State<TmdbKeyPage> with TvInitialFocus {
  static const _signupUrl = 'https://www.themoviedb.org/signup';
  static const _loginUrl = 'https://www.themoviedb.org/login';

  final _keyController = TextEditingController();
  bool _isKeyVisible = false;
  bool _hasSavedKey = false;
  bool _loading = true;

  /// §tmdbKeyCheck — Vrai pendant la vérification auprès de TMDB : le bouton
  /// montre « Vérification… » et refuse un second départ.
  bool _saving = false;

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
    final l10n = context.l10n;
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
          content: Text(l10n.tmdbKeyConnected),
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
    if (key.isEmpty || _saving) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _saving = true);
    // §tmdbKeyCheck — On demande à TMDB AVANT d'enregistrer : une clé mal
    // copiée donnait « TMDB connecté » et une app sans affiche, sans un mot.
    final bool? accepted = await TmdbService.probeKey(key);
    if (!mounted) return;
    if (accepted == false) {
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.tmdbKeyRejected),
          backgroundColor: kError,
        ),
      );
      return;
    }
    await TmdbApiService.saveApiKey(key);
    TmdbService.resetInstance();
    if (!mounted) return;
    setState(() {
      _hasSavedKey = true;
      _saving = false;
    });
    FocusScope.of(context).unfocus();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
            accepted == true ? l10n.tmdbKeyConnected : l10n.tmdbKeyUnverified),
        backgroundColor: accepted == true ? kSuccess : kWarning,
      ),
    );
  }

  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    await TmdbApiService.deleteApiKey();
    TmdbService.resetInstance();
    if (!mounted) return;
    setState(() {
      _keyController.clear();
      _hasSavedKey = false;
      _isKeyVisible = false;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.tmdbKeyRemoved),
        backgroundColor: kError,
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
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
    final l10n = context.l10n;
    // §3c-8 — Sur TV, on cache le TextField par défaut (le coller au D-pad
    // d'un Bearer JWT 220 chars = ~8 minutes pour rien). Affiché seulement
    // si l'utilisateur choisit explicitement "Saisir manuellement".
    final showManualField = !isTv || _showAdvancedManual || _hasSavedKey;

    // §tmdbPageOrder — Deux pages en une, selon qu'une clé existe ou non.
    final children = <Widget>[
      _StatusBanner(active: _hasSavedKey),
      if (isTv) ...[
        const SizedBox(height: 20),
        _TvPairingCta(hasKey: _hasSavedKey, onTap: _openPhoneConfig),
      ],
      if (_hasSavedKey) ...[
        const SizedBox(height: 28),
        _TmdbOptionsBlock(onChanged: () => setState(() {})),
        const SizedBox(height: 28),
        const _TmdbMaintenanceBlock(),
        const SizedBox(height: 28),
        _buildKeySection(context),
      ] else ...[
        const SizedBox(height: 20),
        _InfoBlock(
          onSignup: () => _openUrl(_signupUrl),
          onLogin: () => _openUrl(_loginUrl),
        ),
        if (showManualField) ...[
          const SizedBox(height: 20),
          _buildKeySection(context),
        ] else ...[
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _showAdvancedManual = true),
              icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
              label: Text(l10n.tmdbKeyManualEntry),
              style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
            ),
          ),
        ],
      ],
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tmdbKeyTitle),
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
                  children: children,
                ),
              ),
      ),
    );
  }

  /// Le champ de la clé et son bouton (Enregistrer ou Retirer).
  Widget _buildKeySection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isTv = PlatformTv.isTv;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isTv && !_hasSavedKey ? l10n.tmdbKeySectionManual : l10n.tmdbKeySection,
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
            fontWeight: _hasSavedKey ? FontWeight.bold : FontWeight.normal,
            fontFamily: 'monospace',
            fontSize: 13,
          ),
          decoration: InputDecoration(
            hintText: l10n.tmdbKeyHint,
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                  _isKeyVisible ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _isKeyVisible = !_isKeyVisible),
              tooltip: _isKeyVisible ? l10n.tmdbKeyHide : l10n.tmdbKeyShow,
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
                  label: Text(l10n.tmdbKeyRemove),
                  // §detailsActions — bouton plein (cohérence : plus de mélange
                  // plein/contour). Rouge = destructif.
                  style: FilledButton.styleFrom(
                    backgroundColor: kError,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              )
            else
              Expanded(
                child: FilledButton.icon(
                  // ⚠️ §boundFocus — jamais `null` pendant la vérification :
                  // le bouton a le focus, il sortirait de la traversée. C'est
                  // `_save` qui refuse un second départ.
                  onPressed: _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.save),
                  label: Text(_saving ? l10n.tmdbKeyChecking : l10n.tmdbKeySave),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: kAccentPrimary,
                    foregroundColor: Colors.black,
                  ),
                ),
              ),
          ],
        ),
      ],
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
    final l10n = context.l10n;
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
              border:
                  Border.all(color: kAccentPrimary.withAlpha(140), width: 1.5),
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
                    border: Border.all(
                        color: kAccentPrimary.withAlpha(150), width: 1),
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
                        hasKey ? l10n.tmdbPairReplace : l10n.tmdbPairSetup,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.tmdbPairSub,
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
    final l10n = context.l10n;
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
              active ? l10n.tmdbStatusOn : l10n.tmdbStatusOff,
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

/// Le mode d'emploi, montré SEULEMENT tant qu'aucune clé n'existe.
class _InfoBlock extends StatelessWidget {
  final VoidCallback onSignup;
  final VoidCallback onLogin;
  const _InfoBlock({required this.onSignup, required this.onLogin});

  Widget _step(BuildContext context, int n, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kAccentSecondary.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: kAccentSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
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
                l10n.tmdbHowTitle,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _step(context, 1, l10n.tmdbHowStep1),
          _step(context, 2, l10n.tmdbHowStep2),
          _step(context, 3, l10n.tmdbHowStep3),
          _step(context, 4, l10n.tmdbHowStep4),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.icon(
                onPressed: onSignup,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l10n.tmdbSignup,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                // §detailsActions — plein (cohérence page : plus de bouton contour).
                style: FilledButton.styleFrom(
                  backgroundColor: kAccentSecondary,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onLogin,
                style: TextButton.styleFrom(
                  foregroundColor: kAccentSecondary,
                  minimumSize: const Size(0, 48), // §touchTarget
                ),
                child: Text(l10n.tmdbLogin),
              ),
            ],
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

  // §perfNotify — `save()` notifie par identité : la valeur en mémoire change
  // tout de suite, et le `setState` qui suit relit la bonne. Avant, ces quatre
  // interrupteurs restaient muets jusqu'au prochain lancement.
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
              l10n.tmdbOptionsTitle,
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
            title: Text(l10n.tmdbVisualLangTitle),
            subtitle: Text(
              l10n.tmdbVisualLangSub(
                  VisualLanguageService.labelOf(VisualLanguageService.value)),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openVisualLanguage,
          ),
        ),
        const SizedBox(height: 8),

        // ── Affiches TMDB en priorité (§posterScope : carrousel + Favoris) ─
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
            title: Text(l10n.tmdbPostersFirstTitle),
            subtitle: Text(
              postersFirst ? l10n.tmdbPostersFirstOn : l10n.tmdbPostersFirstOff,
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
///
/// §tmdbPageOrder — Les chiffres se limitent à ce qu'un utilisateur peut
/// comprendre : COMBIEN d'affiches, COMBIEN de titres rangés. Le détail des
/// titres introuvables et des recherches réseau (instrument de §tmdbUrlPersist)
/// a été retiré : il se lisait comme une panne. Il reste lisible dans le
/// journal de la console web.
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
    final l10n = context.l10n;
    setState(() => _busy = true);
    await TmdbPosterCache.clear();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(l10n.tmdbMemoryPostersCleared)));
  }

  /// Oublie les catégories devinées par TMDB (§inferredCat).
  ///
  /// ⚠️ Ne touche PAS aux catégories venues des listes elles-mêmes
  /// (`group-title`) : seulement celles que l'app a déduites pour les listes
  /// qui n'en fournissent aucune — le format « Ultimate », où 100 % des
  /// entrées arrivent sans groupe.
  Future<void> _relearnCategories() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _busy = true);
    await InferredCategoryService.clear();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(l10n.tmdbMemorySortingCleared)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final int posters = TmdbPosterCache.resolvedCount;
    final int cats = InferredCategoryService.count;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.storage_rounded, size: 18, color: kAccentSecondary),
            const SizedBox(width: 8),
            Text(
              l10n.tmdbMemoryTitle,
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
          title: l10n.tmdbMemoryPosters,
          detail: posters == 0
              ? l10n.tmdbMemoryPostersNone
              : l10n.tmdbMemoryPostersCount(posters),
          actionLabel: l10n.tmdbMemoryClear,
          onAction: _busy || posters == 0 ? null : _clearPosters,
        ),
        const SizedBox(height: 8),

        // ── Rangement automatique (catégories déduites) ───────────────────
        _MaintenanceTile(
          icon: Icons.category_outlined,
          title: l10n.tmdbMemorySorting,
          detail: cats == 0
              ? l10n.tmdbMemorySortingNone
              : l10n.tmdbMemorySortingCount(cats),
          actionLabel: l10n.tmdbMemoryRelearn,
          onAction: _busy || cats == 0 ? null : _relearnCategories,
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
