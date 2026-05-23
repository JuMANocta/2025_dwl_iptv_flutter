import 'dart:io';
import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/models/stream_account.dart';
import 'package:aetherStream/data/services/expiration_alert_service.dart';
import 'package:aetherStream/data/services/pairing_service.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/playlist_service.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:aetherStream/data/services/tmdb_api_service.dart';
import 'package:aetherStream/data/services/tmdb_service.dart';
import 'package:aetherStream/data/models/account_info.dart';
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
    // §19 — Auto-focus initial sur TV (1ère tile compte ou bouton +).
    if (PlatformTv.isTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).nextFocus();
      });
    }
  }

  Future<List<StreamAccount>> _loadAccounts() async {
    await StreamAccountService.migrateFromLegacyIfNeeded();
    final accounts = await StreamAccountService.listAccounts();
    final current = await StreamAccountService.getCurrentAccount();
    if (mounted) setState(() => _priorityAccountId = current?.id);
    // §17b — Fetch background des AccountInfo (expiration / connexions).
    // Le résultat alimente `ExpirationAlertService.infos` qui est écouté par
    // les chips `_AccountTile` via ValueListenableBuilder.
    // Pas d'await ici : on laisse la page s'afficher, les chips apparaîtront
    // au fur et à mesure que les fetchs terminent.
    ExpirationAlertService.fetchAll(accounts);
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
      // §3c-8b — TMDB optionnel saisi dans le même form mobile.
      final t = result.tmdbToken;
      if (t != null && t.isNotEmpty) {
        await TmdbApiService.saveApiKey(t);
        TmdbService.resetInstance();
      }
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
                    return _AccountCard(
                      account: acc,
                      isPriority: isPriority,
                      onTap: () => _setPriority(acc.id),
                      onMore: () => _showAccountMenu(acc),
                      onReloaded: _refresh,
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
    // §16 — Bandeau renommé "COMPTE PRINCIPAL" (au lieu d'"ACTIF") + ligne
    // "X comptes secondaires chargés" pour clarifier que tous les comptes
    // cohabitent en mémoire, pas juste le principal.
    return ValueListenableBuilder<Map<String, AccountLoadState>>(
      valueListenable: ParsedPlaylistService.loadStates,
      builder: (context, states, _) {
        final loadedOthers = accounts
            .where((a) =>
                a.id != active.id &&
                states[a.id] == AccountLoadState.loaded)
            .length;
        final inProgressOthers = accounts
            .where((a) =>
                a.id != active.id &&
                (states[a.id] == AccountLoadState.downloading ||
                    states[a.id] == AccountLoadState.parsing))
            .length;
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
                    BoxShadow(
                        color: kAccentPrimary.withAlpha(180), blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'COMPTE PRINCIPAL',
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
                    if (accounts.length > 1) ...[
                      const SizedBox(height: 2),
                      Text(
                        _secondaryStatusLabel(loadedOthers, inProgressOthers,
                            accounts.length - 1),
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant.withAlpha(200),
                        ),
                      ),
                    ],
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
      },
    );
  }

  String _secondaryStatusLabel(int loaded, int inProgress, int total) {
    if (total == 0) return '';
    if (inProgress > 0) {
      return '✦ $loaded/$total comptes secondaires chargés · $inProgress en cours…';
    }
    return '✓ $loaded/$total comptes secondaires chargés';
  }
}

// ─── Tile compte (design unifié avec _SettingsTile) ──────────────────────────

/// §fusion — Grande carte « compte » regroupant la sélection (radio principal),
/// les chips d'état/expiration, le menu ⋯, ET les statistiques de la playlist
/// (compteurs films/séries/chaînes, taille M3U, âge cache, infos Xtream) +
/// bouton Recharger. Remplace l'ancienne page « Statistiques playlist ».
class _AccountCard extends StatefulWidget {
  final StreamAccount account;
  final bool isPriority;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final VoidCallback onReloaded;

  const _AccountCard({
    required this.account,
    required this.isPriority,
    required this.onTap,
    required this.onMore,
    required this.onReloaded,
  });

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  Future<AccountInfo?>? _accountInfoFuture;
  bool _reloading = false;

  @override
  void initState() {
    super.initState();
    // §17a — fetch infos Xtream (expiration / connexions). Marche aussi pour
    // les comptes completeUrl (extraction creds depuis l'URL). Renvoie null si
    // l'URL n'est pas Xtream-compatible.
    _accountInfoFuture = StreamAccountService.fetchAccountInfo(widget.account);
  }

  String get _host {
    final url = widget.account.mode == StreamAuthMode.separate
        ? (widget.account.baseUrl ?? '')
        : (widget.account.completeUrl ?? '');
    return Uri.tryParse(url)?.host ?? '?';
  }

  String get _subtitle => widget.account.mode == StreamAuthMode.completeUrl
      ? _host
      : '${widget.account.username ?? '?'} @ $_host';

  Future<void> _reload() async {
    if (_reloading) return;

    // Confirmation si la playlist a moins de 24h.
    final path = await PlaylistService.pathForAccountId(widget.account.id);
    final file = File(path);
    if (await file.exists()) {
      final age = DateTime.now().difference(await file.lastModified());
      if (age.inHours < 24) {
        final ok = await _confirmReload(age);
        if (ok != true) return;
      }
    }

    if (!mounted) return;
    setState(() => _reloading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PlaylistService.deleteForAccountId(widget.account.id);
      String? newPath;
      if (widget.isPriority) {
        // Compte principal → downloadCurrentM3U (messages d'erreur précis).
        newPath = await PlaylistService.downloadCurrentM3U();
      } else {
        newPath =
            await PlaylistService.ensureDownloadedForAccount(widget.account);
      }
      if (newPath == null) {
        throw const HttpException(
            'Téléchargement impossible (vérifie l\'URL ou la connexion).');
      }
      await ParsedPlaylistService.reloadFromDisk(
        widget.account.id,
        widget.account.label,
        newPath,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('✅ Playlist rechargée pour ${widget.account.label}'),
          backgroundColor: kAccentPrimary.withAlpha(180),
        ),
      );
      widget.onReloaded();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('❌ Échec : $e')));
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  Future<bool?> _confirmReload(Duration age) {
    final h = age.inHours;
    final m = age.inMinutes % 60;
    final ageStr = h > 0 ? '${h}h${m > 0 ? ' ${m}min' : ''}' : '${m}min';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recharger ?'),
        content: Text(
          'La playlist de "${widget.account.label}" a été téléchargée il y a $ageStr.\n'
          'Recharger quand même depuis le serveur ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Recharger',
                style: TextStyle(color: kWarning, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPriority = widget.isPriority;

    // §3c-3 — Wrap focus TV en decorateOnly : on garde la bordure isPriority
    // (signale le compte principal) ET on ajoute la bordure de focus glow
    // Matrix au D-pad. Le bouton Recharger et ⋯ restent focusables séparément.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: FocusableCard(
        decorateOnly: true,
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            splashColor: kAccentPrimary.withAlpha(30),
            highlightColor: kAccentPrimary.withAlpha(15),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isPriority ? kAccentPrimary : cs.outline.withAlpha(60),
                  width: isPriority ? 1.5 : 1,
                ),
                boxShadow: isPriority
                    ? [
                        BoxShadow(
                            color: kAccentPrimary.withAlpha(40), blurRadius: 14),
                      ]
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── En-tête : radio principal + label + chips + ⋯ ──────
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: isPriority
                                ? kAccentPrimary.withAlpha(30)
                                : cs.surfaceContainerHighest,
                            border: Border.all(
                              color: isPriority
                                  ? kAccentPrimary
                                  : cs.outline.withAlpha(60),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            isPriority
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color:
                                isPriority ? kAccentPrimary : cs.onSurfaceVariant,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.account.label,
                                style: TextStyle(
                                  fontWeight: isPriority
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  fontSize: 15,
                                  color: cs.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              // §16 + §17b — chips état + expiration.
                              _AccountStateChips(
                                accountId: widget.account.id,
                                isPriority: isPriority,
                              ),
                              const SizedBox(height: 4),
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
                    const SizedBox(height: 14),
                    // ── Stats playlist (live via ParsedPlaylistService) ─────
                    ListenableBuilder(
                      listenable: ParsedPlaylistService.version,
                      builder: (context, _) {
                        final parsed = ParsedPlaylistService.getAccount(
                            widget.account.id);
                        final entries = parsed?.entries ?? const <M3uEntry>[];
                        int films = 0, series = 0, tv = 0;
                        for (final e in entries) {
                          switch (e.type) {
                            case M3uContentType.movie:
                              films++;
                              break;
                            case M3uContentType.series:
                              series++;
                              break;
                            case M3uContentType.tv:
                              tv++;
                              break;
                          }
                        }
                        return Column(
                          children: [
                            _CountsRow(films: films, series: series, tv: tv),
                            const SizedBox(height: 12),
                            _FileStatsBlock(
                              accountId: widget.account.id,
                              hasParsed: parsed != null,
                            ),
                          ],
                        );
                      },
                    ),
                    if (widget.account.mode == StreamAuthMode.separate) ...[
                      const SizedBox(height: 10),
                      _XtreamInfoBlock(future: _accountInfoFuture),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _reloading ? null : _reload,
                        icon: _reloading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(
                          _reloading
                              ? 'Téléchargement…'
                              : 'Recharger la playlist',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: kAccentPrimary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Chips d'état compte (§16) + chip expiration (§17b) ─────────────────────

/// Affiche une ligne de chips d'état pour un compte :
///   - ⭐ `PRINCIPAL` (vert plein, glow) — si `isPriority`
///   - ✅ `DISPONIBLE` (vert opacity 60%) — sinon, `loaded`
///   - ⏳ `EN COURS…` (cyan, opacity pulse) — `downloading` ou `parsing`
///   - ⚠ `ERREUR` (rouge) — `error`
///   - ⚠ `X JOURS` ou `EXPIRÉE` (rouge / orange) — si AccountInfo expire <30j
///
/// Écoute deux notifiers : `ParsedPlaylistService.loadStates` (état chargement)
/// et `ExpirationAlertService.infos` (AccountInfo Xtream).
class _AccountStateChips extends StatelessWidget {
  final String accountId;
  final bool isPriority;
  const _AccountStateChips({
    required this.accountId,
    required this.isPriority,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, AccountLoadState>>(
      valueListenable: ParsedPlaylistService.loadStates,
      builder: (context, states, _) {
        return ValueListenableBuilder<Map<String, AccountInfo?>>(
          valueListenable: ExpirationAlertService.infos,
          builder: (context, infos, __) {
            final state = states[accountId] ?? AccountLoadState.notLoaded;
            final daysLeft =
                ExpirationAlertService.daysUntilExpiration(accountId);
            return Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _statusChip(state),
                if (daysLeft != null &&
                    daysLeft <= ExpirationAlertService.kAlertThresholdDays)
                  _expirationChip(daysLeft),
              ],
            );
          },
        );
      },
    );
  }

  Widget _statusChip(AccountLoadState state) {
    if (isPriority && state == AccountLoadState.loaded) {
      return _Chip(
        text: 'PRINCIPAL',
        color: kAccentPrimary,
        filled: true,
        glow: true,
      );
    }
    switch (state) {
      case AccountLoadState.loaded:
        return _Chip(text: 'DISPONIBLE', color: kAccentPrimary, opacity: 0.6);
      case AccountLoadState.downloading:
        return _Chip(text: 'TÉLÉCHARGEMENT…', color: kAccentSecondary);
      case AccountLoadState.parsing:
        return _Chip(text: 'CHARGEMENT…', color: kAccentSecondary);
      case AccountLoadState.error:
        return _Chip(text: 'ERREUR', color: Colors.red);
      case AccountLoadState.notLoaded:
        return _Chip(text: 'NON CHARGÉ', color: Colors.grey);
    }
  }

  Widget _expirationChip(int days) {
    if (days < 0) {
      return _Chip(
        text: 'EXPIRÉE',
        color: Colors.red,
        filled: true,
        icon: Icons.warning_amber_rounded,
      );
    }
    if (days == 0) {
      return _Chip(
        text: 'EXPIRE AUJOURD\'HUI',
        color: Colors.red,
        filled: true,
        icon: Icons.warning_amber_rounded,
      );
    }
    final critical = days <= 7;
    return _Chip(
      text: 'EXPIRE DANS $days J',
      color: critical ? Colors.red : kWarning,
      filled: critical,
      icon: Icons.warning_amber_rounded,
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;
  final bool glow;
  final double opacity;
  final IconData? icon;

  const _Chip({
    required this.text,
    required this.color,
    this.filled = false,
    this.glow = false,
    this.opacity = 1.0,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.black : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: filled
            ? color.withAlpha((255 * opacity).round())
            : color.withAlpha((40 * opacity).round()),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color.withAlpha((opacity * 255).round()),
          width: 1,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: color.withAlpha(80),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg.withAlpha((255 * opacity).round())),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: fg.withAlpha((255 * opacity).round()),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sous-blocs stats playlist (§fusion — déplacés depuis l'ancienne ─────────
// PlaylistManagementPage) ────────────────────────────────────────────────────

class _CountsRow extends StatelessWidget {
  final int films;
  final int series;
  final int tv;
  const _CountsRow({required this.films, required this.series, required this.tv});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _CountTile(icon: Icons.movie_outlined, value: films, label: 'Films', color: kAccentPrimary)),
        const SizedBox(width: 8),
        Expanded(child: _CountTile(icon: Icons.video_library_outlined, value: series, label: 'Séries', color: kAccentTertiary)),
        const SizedBox(width: 8),
        Expanded(child: _CountTile(icon: Icons.live_tv_outlined, value: tv, label: 'Chaînes', color: kAccentSecondary)),
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;
  final Color color;
  const _CountTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(70), width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(
            _formatCount(value),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatCount(int n) {
    if (n < 1000) return '$n';
    if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '${(n / 1000).round()}k';
  }
}

/// Bloc "Fichier M3U" : taille + âge du cache. FutureBuilder car on accède
/// à `File.length()` et `File.lastModified()` qui sont async.
class _FileStatsBlock extends StatelessWidget {
  final String accountId;
  final bool hasParsed;
  const _FileStatsBlock({required this.accountId, required this.hasParsed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<_FileStats?>(
      future: _readStats(),
      builder: (context, snap) {
        final stats = snap.data;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withAlpha(120),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.sd_storage_outlined,
                  label: 'Taille M3U',
                  value: stats == null ? '—' : _formatSize(stats.size),
                ),
              ),
              Container(width: 1, height: 26, color: cs.outlineVariant.withAlpha(80)),
              Expanded(
                child: _MiniStat(
                  icon: Icons.access_time,
                  label: 'Âge cache',
                  value: stats == null
                      ? 'Aucun cache'
                      : _formatAge(stats.modified),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<_FileStats?> _readStats() async {
    try {
      final path = await PlaylistService.pathForAccountId(accountId);
      final file = File(path);
      if (!await file.exists()) return null;
      return _FileStats(
        size: await file.length(),
        modified: await file.lastModified(),
      );
    } catch (_) {
      return null;
    }
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ko';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} Mo';
  }

  static String _formatAge(DateTime when) {
    final age = DateTime.now().difference(when);
    if (age.inMinutes < 1) return 'à l\'instant';
    if (age.inMinutes < 60) return 'il y a ${age.inMinutes} min';
    if (age.inHours < 24) return 'il y a ${age.inHours} h';
    return 'il y a ${age.inDays} j';
  }
}

class _FileStats {
  final int size;
  final DateTime modified;
  _FileStats({required this.size, required this.modified});
}

/// Bloc Xtream Codes : date d'expiration + connexions actives/max.
class _XtreamInfoBlock extends StatelessWidget {
  final Future<AccountInfo?>? future;
  const _XtreamInfoBlock({required this.future});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(10),
      ),
      child: FutureBuilder<AccountInfo?>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kAccentSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Lecture des infos Xtream…',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            );
          }
          final info = snap.data;
          if (info == null) {
            return _InlineError(message: 'Infos Xtream indisponibles');
          }
          return Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.event_outlined,
                  label: 'Expiration',
                  value: _formatExpiration(info.expirationDate),
                  valueColor: _expirationColor(info.expirationDate),
                ),
              ),
              Container(width: 1, height: 26, color: cs.outlineVariant.withAlpha(80)),
              Expanded(
                child: _MiniStat(
                  icon: Icons.cable,
                  label: 'Connexions',
                  value: info.maxConnections > 0
                      ? '${info.activeConnections} / ${info.maxConnections}'
                      : '${info.activeConnections}',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _formatExpiration(DateTime? exp) {
    if (exp == null) return 'Inconnue';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expDay = DateTime(exp.year, exp.month, exp.day);
    final days = expDay.difference(today).inDays;
    if (days < 0) return 'Expirée (${-days} j)';
    if (days == 0) return 'Expire aujourd\'hui';
    if (days == 1) return 'Expire demain';
    return 'Dans $days jours';
  }

  static Color? _expirationColor(DateTime? exp) {
    if (exp == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expDay = DateTime(exp.year, exp.month, exp.day);
    final days = expDay.difference(today).inDays;
    if (days < 0) return Colors.red;
    if (days <= 7) return Colors.red;
    if (days < ExpirationAlertService.kAlertThresholdDays) return kWarning;
    return kAccentPrimary;
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
