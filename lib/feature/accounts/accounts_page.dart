import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/themes/aether_theme_extension.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/data/models/stream_account.dart';
import 'package:aetherStream/data/services/pairing_service.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/playlist_service.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:aetherStream/feature/accounts/edit_account_sheet.dart';
import 'package:aetherStream/feature/pairing/pairing_page.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/widgets/empty_state.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';
import 'package:aetherStream/widgets/tv/tv_adaptive_modal.dart';

/// Page de gestion des comptes IPTV (§1g — refonte).
///
/// Cette page se concentre **uniquement** sur les comptes IPTV. Les autres
/// réglages (TMDB, XMLTV, thème, statistiques playlist) ont leurs sous-pages
/// dédiées accessibles depuis `SettingsPage`.
///
/// UX :
///   - Bandeau compact en haut indiquant le compte actif
///   - Liste des comptes en design streaming (gradient bg, accent bars)
///   - Compte prioritaire : border kAccentPrimary + label "ACTIF" + glow
///   - Menu contextuel ⋯ par compte : Modifier · Vider le cache · Supprimer
///   - FAB "Ajouter" inchangé
class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key, this.initialPlaylistPath});

  /// Chemin pré-résolu de la playlist du compte courant — non utilisé dans
  /// la version refondue mais conservé pour la rétro-compatibilité du call site.
  final String? initialPlaylistPath;

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  late Future<List<StreamAccount>> _accountsFuture;
  String? _priorityAccountId;
  bool _priorityChanged = false;

  @override
  void initState() {
    super.initState();
    _accountsFuture = _loadAccounts();
  }

  Future<List<StreamAccount>> _loadAccounts() async {
    await StreamAccountService.migrateFromLegacyIfNeeded();
    final accounts = await StreamAccountService.listAccounts();
    final current = await StreamAccountService.getCurrentAccount();
    if (mounted) setState(() => _priorityAccountId = current?.id);
    return accounts;
  }

  Future<void> _refresh() async {
    setState(() {
      _accountsFuture = _loadAccounts();
    });
  }

  Future<void> _setPriority(String id) async {
    if (_priorityAccountId == id) return;
    await StreamAccountService.setCurrentAccount(id);
    if (!mounted) return;
    setState(() {
      _priorityAccountId = id;
      _priorityChanged = true;
    });
  }

  Future<void> _openEditor({StreamAccount? initial}) async {
    final result = await showModalBottomSheet<StreamAccount>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EditAccountSheet(initial: initial),
    );
    if (result != null) {
      await StreamAccountService.saveAccount(result);
      await StreamAccountService.setCurrentAccount(result.id);
      if (!mounted) return;
      _priorityChanged = true;
      _refresh();
    }
  }

  /// §3c-8 — Ajout d'un compte via pairing QR mobile→TV.
  Future<void> _openPairing() async {
    final result = await Navigator.of(context).push<PairingResult>(
      MaterialPageRoute(
        builder: (_) => PairingPage(
          kind: PairingKind.account,
          onManualFallback: () {
            Navigator.of(context).pop();
            _openEditor();
          },
        ),
      ),
    );
    if (result is PairingAccountResult) {
      await StreamAccountService.saveAccount(result.account);
      await StreamAccountService.setCurrentAccount(result.account.id);
      if (!mounted) return;
      _priorityChanged = true;
      _refresh();
    }
  }

  /// §3c-8 — Bifurcation du bouton "+" sur TV : mobile vs télécommande.
  Future<void> _onAddTap() async {
    if (!PlatformTv.isTv) {
      _openEditor();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Comment ajouter une playlist ?'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              autofocus: true,
              leading: Icon(Icons.phone_iphone, color: kAccentPrimary),
              title: const Text('Depuis mon téléphone'),
              subtitle: const Text('Recommandé — QR + saisie confortable'),
              onTap: () => Navigator.of(ctx).pop('pairing'),
            ),
            ListTile(
              leading: Icon(Icons.keyboard_alt_outlined,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              title: const Text('Avec la télécommande'),
              subtitle: const Text('Saisie touche par touche'),
              onTap: () => Navigator.of(ctx).pop('manual'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
    if (choice == 'pairing') {
      await _openPairing();
    } else if (choice == 'manual') {
      await _openEditor();
    }
  }

  Future<void> _clearCache(StreamAccount acc) async {
    final l10n = AppLocalizations.of(context)!;
    final isActive = acc.id == _priorityAccountId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vider le cache ?'),
        content: Text(
          isActive
              ? 'La playlist du compte "${acc.label}" sera re-téléchargée depuis le serveur maintenant.'
              : 'La playlist du compte "${acc.label}" sera re-téléchargée au prochain chargement de ce compte.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Vider', style: TextStyle(color: kWarning)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (isActive) {
      // §bugPrio — compte actif : on supprime, on re-télécharge et on
      // re-parse atomiquement pour éviter une home vide entre les deux.
      try {
        await PlaylistService.deleteForAccountId(acc.id);
        final path = await PlaylistService.downloadCurrentM3U();
        await ParsedPlaylistService.reloadFromDisk(acc.id, acc.label, path);
      } catch (e) {
        if (!mounted) return;
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(content: Text('Échec : $e')),
        );
        return;
      }
      _priorityChanged = true;
    } else {
      // Compte secondaire : invalidation lazy, le DL se fera quand l'utilisateur
      // basculera dessus (pas de home à rebuilder dans l'immédiat).
      await PlaylistService.deleteForAccountId(acc.id);
      ParsedPlaylistService.invalidate(acc.id);
    }
    if (!mounted) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(content: Text('✅ Cache vidé pour ${acc.label}')),
    );
  }

  Future<void> _delete(StreamAccount acc) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteAccountDialogTitle),
        content: Text(l10n.deleteAccountDialogContent),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.deleteAccountConfirm,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await StreamAccountService.deleteAccount(acc.id);
    ParsedPlaylistService.invalidate(acc.id);
    _priorityChanged = true;
    _refresh();
  }

  /// Menu contextuel ⋯ par compte.
  Future<void> _showAccountMenu(StreamAccount acc) async {
    // §3c-4 — bifurque mobile/TV pour le menu ⋯ du compte.
    await showAdaptiveActionSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final l10n = AppLocalizations.of(context)!;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  acc.label,
                  style: Theme.of(ctx).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.accountActionEdit),
                onTap: () {
                  Navigator.pop(ctx);
                  _openEditor(initial: acc);
                },
              ),
              ListTile(
                leading: Icon(Icons.sync, color: kAccentSecondary),
                title: const Text('Vider le cache playlist'),
                subtitle: const Text('Force un re-téléchargement depuis le serveur'),
                onTap: () {
                  Navigator.pop(ctx);
                  _clearCache(acc);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(l10n.accountActionDelete,
                    style: const TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _delete(acc);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_priorityChanged);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.accountsTitle),
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        floatingActionButton: FutureBuilder<List<StreamAccount>>(
          future: _accountsFuture,
          builder: (ctx, snap) {
            final accounts = snap.data;
            if (accounts == null || accounts.isEmpty) {
              return const SizedBox.shrink();
            }
            return FloatingActionButton.extended(
              onPressed: _onAddTap,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
              backgroundColor: kAccentPrimary,
              foregroundColor: Colors.black,
            );
          },
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
          child: FutureBuilder<List<StreamAccount>>(
            future: _accountsFuture,
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final accounts = snap.data ?? [];
              if (accounts.isEmpty) return _buildEmptyState(cs);
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 100),
                  itemCount: accounts.length + 1, // +1 pour le bandeau info
                  itemBuilder: (_, i) {
                    if (i == 0) return _buildPriorityBanner(accounts, cs);
                    final acc = accounts[i - 1];
                    final isPriority = _priorityAccountId == acc.id;
                    return _AccountTile(
                      account: acc,
                      isPriority: isPriority,
                      onTap: () => _setPriority(acc.id),
                      onMore: () => _showAccountMenu(acc),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    // §12-b — Widget EmptyState unifié.
    // §3c-8 — Sur TV, CTA = pairing QR mobile (la saisie au D-pad est piégeante).
    final isTv = PlatformTv.isTv;
    return EmptyState(
      icon: isTv ? Icons.qr_code_2 : Icons.account_circle_outlined,
      title: 'Aucun compte configuré',
      subtitle: isTv
          ? 'Scanne le QR code avec ton téléphone pour configurer ta playlist sans avoir à taper au D-pad.'
          : 'Ajoute une URL M3U complète ou un compte Xtream Codes pour commencer à streamer.',
      ctaLabel: isTv ? 'Configurer depuis mon téléphone' : 'Ajouter une playlist',
      ctaIcon: isTv ? Icons.phone_iphone : Icons.add,
      onCtaTap: isTv ? _openPairing : () => _openEditor(),
    );
  }

  Widget _buildPriorityBanner(List<StreamAccount> accounts, ColorScheme cs) {
    final active = accounts.firstWhere(
      (a) => a.id == _priorityAccountId,
      orElse: () => accounts.first,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: cs.surfaceContainerHighest,
        border: Border.all(color: cs.outlineVariant, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kAccentPrimary,
              boxShadow: [
                BoxShadow(color: kAccentPrimary.withAlpha(180), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'COMPTE ACTIF',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: cs.onSurfaceVariant.withAlpha(180),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  active.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (accounts.length > 1)
            Text(
              '${accounts.length} comptes',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Tile compte (design unifié avec _SettingsTile) ──────────────────────────

class _AccountTile extends StatefulWidget {
  final StreamAccount account;
  final bool isPriority;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _AccountTile({
    required this.account,
    required this.isPriority,
    required this.onTap,
    required this.onMore,
  });

  @override
  State<_AccountTile> createState() => _AccountTileState();
}

class _AccountTileState extends State<_AccountTile> {
  bool _focused = false;

  String get _host {
    final url = widget.account.mode == StreamAuthMode.separate
        ? (widget.account.baseUrl ?? '')
        : (widget.account.completeUrl ?? '');
    return Uri.tryParse(url)?.host ?? '?';
  }

  String get _subtitle => widget.account.mode == StreamAuthMode.completeUrl
      ? _host
      : '${widget.account.username ?? '?'} @ $_host';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeExt = Theme.of(context).extension<AetherThemeExtension>()!;

    // §3c-3 — Wrap focus TV en decorateOnly : on garde la bordure isPriority
    // (signale le compte actif) ET on ajoute par-dessus la bordure de focus
    // glow Matrix quand l'élément est focused via télécommande.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: FocusableCard(
        decorateOnly: true,
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Focus(
          onFocusChange: (v) => setState(() => _focused = v),
          child: Material(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(14),
              splashColor: kAccentPrimary.withAlpha(30),
              highlightColor: kAccentPrimary.withAlpha(15),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _focused
                        ? kAccentPrimary
                        : widget.isPriority
                            ? kAccentPrimary.withAlpha(150)
                            : cs.outline.withAlpha(60),
                    width: (widget.isPriority || _focused) ? 2.0 : 1.0,
                  ),
                  boxShadow: (widget.isPriority || _focused)
                      ? [
                          BoxShadow(
                              color: kAccentPrimary.withAlpha(_focused ? 60 : 30),
                              blurRadius: _focused ? 18 : 10),
                        ]
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      // Radio prioritaire.
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: widget.isPriority
                              ? kAccentPrimary.withAlpha(30)
                              : cs.surfaceContainerHighest,
                          border: Border.all(
                            color: widget.isPriority
                                ? kAccentPrimary
                                : cs.outline.withAlpha(60),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          widget.isPriority
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: widget.isPriority ? kAccentPrimary : cs.onSurfaceVariant,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Label + host.
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.account.label,
                                    style: TextStyle(
                                      fontWeight: widget.isPriority
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                      fontSize: 15,
                                      color: cs.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (widget.isPriority) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: kAccentPrimary.withAlpha(50),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: kAccentPrimary, width: 1),
                                    ),
                                    child: Text(
                                      'ACTIF',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.0,
                                        color: kAccentPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.more_vert,
                            color: cs.onSurfaceVariant.withAlpha(180)),
                        onPressed: widget.onMore,
                        tooltip: 'Actions',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

