import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/themes/themes.dart';
import 'package:aetherStream/core/utils/app_snackbar.dart';
import 'package:aetherStream/data/services/online_subtitles_service.dart';
import 'package:aetherStream/data/services/subtitle_api_service.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';
import '../../l10n/l10n_ext.dart';

/// Lot 11 — La clé du fournisseur de sous-titres en ligne, saisie par
/// l'utilisateur. Page calquée sur `TmdbKeyPage`, dont elle reprend les deux
/// leçons qui ont coûté quelque chose :
///
/// - **§tmdbPageOrder** — la page se lit dans l'ordre de ce qu'il y a À FAIRE :
///   sans clé, comment en obtenir une puis où la coller, et rien d'autre ;
///   avec clé, l'état d'abord et la clé tout en bas, on n'y touche qu'une fois.
/// - **§clientText** — les textes disent ce que la clé PERMET, pas ce qu'est
///   une API ni combien de requêtes par jour elle autorise.
///
/// ⚠️ Ce qu'elle N'a PAS repris : le repli §3c-8 du champ de saisie sur
/// téléviseur. Il existe parce que la clé TMDB est un jeton de 220 caractères ;
/// celle-ci en tient une trentaine. Le repli n'aurait de sens qu'avec une page
/// de console web pour cette clé — il n'y en a pas (à reprendre si elle arrive).
///
/// ⛔ Aucune clé n'est intégrée à l'application : c'est celle de l'utilisateur,
/// et c'est aussi ce que le fournisseur exige (cf. `OnlineSubtitlesService`).
class SubtitleProviderPage extends StatefulWidget {
  const SubtitleProviderPage({super.key});

  @override
  State<SubtitleProviderPage> createState() => _SubtitleProviderPageState();
}

class _SubtitleProviderPageState extends State<SubtitleProviderPage>
    with TvInitialFocus {
  final _keyController = TextEditingController();
  bool _isKeyVisible = false;
  bool _hasSavedKey = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadKey() async {
    final key = await SubtitleApiService.getApiKey();
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
    await SubtitleApiService.saveApiKey(key);
    if (!mounted) return;
    setState(() => _hasSavedKey = true);
    FocusScope.of(context).unfocus();
    AppSnackBar.show(context, context.l10n.subProviderSaved);
  }

  Future<void> _delete() async {
    await SubtitleApiService.deleteApiKey();
    if (!mounted) return;
    setState(() {
      _hasSavedKey = false;
      _keyController.clear();
      _isKeyVisible = false;
    });
    AppSnackBar.show(context, context.l10n.subProviderRemoved);
  }

  Future<void> _openSignup() async {
    final uri = Uri.parse(OnlineSubtitlesService.signupUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = context.l10n;

    // §tmdbPageOrder — Sans clé : comment en obtenir une, puis où la coller.
    // Avec clé : l'état, et la clé en bas (on n'y touche qu'une fois).
    //
    // ⚠️ Pas de repli §3c-8 ici, et c'est délibéré : le champ est montré même
    // sur téléviseur. §3c-8 replie le champ TMDB parce qu'il attend un jeton
    // de 220 caractères ; une clé de sous-titres en tient une trentaine. La
    // console web ferait mieux, mais elle n'a pas de page pour CETTE clé —
    // proposer « configurer depuis le téléphone » serait promettre un écran
    // qui n'existe pas.
    final children = <Widget>[
      _StatusBanner(active: _hasSavedKey),
      if (!_hasSavedKey) ...[
        const SizedBox(height: 20),
        _InfoBlock(onSignup: _openSignup),
        const SizedBox(height: 20),
        _buildKeySection(context),
      ] else ...[
        const SizedBox(height: 28),
        _buildKeySection(context),
      ],
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.subProviderTitle),
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
                  colors: [kAccentSecondary.withAlpha(20), cs.surface],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.subProviderSection,
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
            hintText: l10n.subProviderHint,
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
              tooltip:
                  _isKeyVisible ? l10n.subProviderHide : l10n.subProviderShow,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: _hasSavedKey
              ? FilledButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.subProviderRemove),
                  style: aetherFilledStyle(kError),
                )
              : FilledButton.icon(
                  // ⚠️ §boundFocus — jamais `null` : un bouton désactivé qui
                  // porte le focus sort de la traversée D-pad.
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: Text(l10n.subProviderSave),
                  style: aetherFilledStyle(kAccentSecondary),
                ),
        ),
      ],
    );
  }
}

/// L'état, en une ligne : ce que l'app peut faire, ou pas encore.
class _StatusBanner extends StatelessWidget {
  final bool active;
  const _StatusBanner({required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final Color tone = active ? kSuccess : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withAlpha(90)),
      ),
      child: Row(
        children: [
          Icon(active ? Icons.check_circle_outline : Icons.subtitles_off_outlined,
              color: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? l10n.subProviderActive : l10n.subProviderInactive,
                  style: TextStyle(
                      color: cs.onSurface, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  active
                      ? l10n.subProviderActiveSub
                      : l10n.subProviderInactiveSub,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Comment obtenir une clé — trois étapes, aucune notion technique.
class _InfoBlock extends StatelessWidget {
  final VoidCallback onSignup;
  const _InfoBlock({required this.onSignup});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.subProviderIntro,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        _step(context, 1, l10n.subProviderStep1),
        _step(context, 2, l10n.subProviderStep2),
        _step(context, 3, l10n.subProviderStep3),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onSignup,
            icon: const Icon(Icons.open_in_new),
            label: Text(l10n.subProviderGetKey),
            style: aetherFilledStyle(kAccentSecondary),
          ),
        ),
      ],
    );
  }

  Widget _step(BuildContext context, int n, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kAccentSecondary.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Text('$n',
                style: TextStyle(
                    color: kAccentSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: cs.onSurface, fontSize: 13, height: 1.35)),
          ),
        ],
      ),
    );
  }
}
