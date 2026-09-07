import 'package:flutter/material.dart';

import '../../core/themes/colors.dart';
import '../../data/services/visual_language_service.dart';
import '../../widgets/tv/focusable_card.dart';
import '../../l10n/l10n_ext.dart';

/// §posterLang (2026-09-05) — « Langue des visuels ».
///
/// **Ce que ce réglage change, et ce qu'il ne change pas.** Il agit sur ce qui
/// vient de TMDB : affiche de repli, image de fond de la fiche, synopsis,
/// casting. Il ne touche **pas** l'interface (français imposé, §frOnly) ni les
/// affiches fournies par les listes IPTV elles-mêmes — celles-là sont servies
/// telles quelles par le fournisseur, dans sa langue à lui, et c'est
/// précisément pour ça que ce réglage existe.
class VisualLanguagePage extends StatefulWidget {
  const VisualLanguagePage({super.key});

  @override
  State<VisualLanguagePage> createState() => _VisualLanguagePageState();
}

class _VisualLanguagePageState extends State<VisualLanguagePage> {
  late VisualLanguage _selected = VisualLanguageService.value;
  bool _busy = false;

  Future<void> _choose(VisualLanguage v) async {
    if (v == _selected || _busy) return;
    setState(() {
      _selected = v;
      _busy = true;
    });
    await VisualLanguageService.set(v);
    // ⚠️ Les affiches déjà résolues sont mémorisées AVEC leur langue dans la
    // clé (§tmdbUrlPersist) : rien à purger, les prochaines résolutions
    // repartiront dans la nouvelle langue. On vide seulement le cache mémoire
    // des images déjà décodées pour que l'accueil se repeigne.
    if (!mounted) return;
    setState(() => _busy = false);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(
        context.l10n.visualLangApplied(
            VisualLanguageService.labelOf(v).toLowerCase()),
      ),
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.visualLangTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            context.l10n.visualLangUiStaysFrench,
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 16),
          for (final v in VisualLanguage.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FocusableCard(
                onTap: () => _choose(v),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: Icon(
                    _selected == v
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: _selected == v ? kAccentPrimary : cs.outline,
                  ),
                  title: Text(VisualLanguageService.labelOf(v)),
                  subtitle: Text(_subtitleOf(v),
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.visualLangNote,
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitleOf(VisualLanguage v) => switch (v) {
        VisualLanguage.auto =>
          context.l10n.visualLangCurrently(VisualLanguageService.resolvedTag),
        VisualLanguage.fr => context.l10n.visualLangSubFr,
        VisualLanguage.en => context.l10n.visualLangSubEn,
        VisualLanguage.original =>
          context.l10n.visualLangSubOriginal,
      };
}
