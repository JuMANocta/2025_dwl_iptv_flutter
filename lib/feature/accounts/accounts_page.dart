import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:aetherStream/core/utils/user_error.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/themes/themes.dart';
import 'package:aetherStream/core/themes/light_palette.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/core/navigation/playlist_visibility.dart';
import 'package:aetherStream/data/models/parsed_playlist.dart';
import 'package:aetherStream/data/services/load_failure.dart';
import 'package:aetherStream/data/models/stream_account.dart';
import 'package:aetherStream/data/services/playback_health_service.dart';
import 'package:aetherStream/data/services/expiration_alert_service.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/playlist_service.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:aetherStream/data/services/storage_janitor.dart';
import 'package:aetherStream/data/services/playlist_reload_service.dart';
import 'package:aetherStream/core/utils/formatters.dart' show formatFileSize;
import 'package:aetherStream/data/models/account_info.dart';
import 'package:aetherStream/feature/accounts/edit_account_sheet.dart';
import 'package:aetherStream/feature/settings/web_console/web_console_page.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/l10n/l10n_ext.dart';
import 'package:aetherStream/widgets/empty_state.dart';
import 'package:aetherStream/widgets/reload_all_flow.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';
import 'package:aetherStream/widgets/tv/focusable_chip.dart';
import 'package:aetherStream/widgets/tv/tv_adaptive_modal.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';
import 'package:aetherStream/widgets/sheet_close_tile.dart';

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
  // Revue 2026-09-11, D4B-07 — `initialPlaylistPath` (non utilisé depuis la
  // refonte, passé par aucun appelant) : retiré.
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> with TvInitialFocus {
  late Future<List<StreamAccount>> _accountsFuture;
  String? _priorityAccountId;
  bool _priorityChanged = false;

  /// R18 / R22 (D4B-10) — La dernière liste de comptes RÉELLEMENT obtenue.
  ///
  /// ⛔ Un rafraîchissement ne doit pas faire disparaître la page. `_refresh()`
  /// remplace le `Future` du `FutureBuilder`, qui repassait alors par
  /// `ConnectionState.waiting` : la liste s'effaçait sous un spinner, puis se
  /// reconstruisait EN HAUT (la position du scrollable était perdue avec les
  /// éléments), et au D-pad le focus retombait au premier compte. Or on sait
  /// déjà quoi montrer — les comptes ne changent pas parce qu'on recharge une
  /// liste. On garde donc l'affichage et on le remplace quand la réponse
  /// arrive. Le spinner ne reste que pour le PREMIER chargement, quand on n'a
  /// effectivement rien à montrer.
  List<StreamAccount>? _lastAccounts;

  /// §reloadAll — Empêche un second lot pendant qu'un premier tourne.
  bool _reloadingAll = false;

  @override
  void dispose() {
    // §unloadGuard — On rend le jeton EXACTEMENT une fois, en miroir de
    // `initState`.
    PlaylistVisibility.release();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // §unloadGuard (généralisé) — Cette page AFFICHE l'état et les compteurs de
    // chaque liste : la laisser ouverte cinq minutes déclenchait le
    // déchargement paresseux sous les yeux de l'utilisateur, qui lisait alors
    // « NON CHARGÉ » sans qu'aucun échec n'ait eu lieu. Tant qu'elle est à
    // l'écran, elle détient un jeton et rien n'est déchargé.
    PlaylistVisibility.hold();
    _accountsFuture = _loadAccounts();
  }


  /// §reloadAll — Recharge TOUTES les listes, séquentiellement.
  ///
  /// §reloadScope — Le corps a été extrait dans `showReloadAllFlow` : le ↻ de
  /// l'accueil déclenche EXACTEMENT le même geste (même question, même
  /// progression, même bilan). Il ne rechargeait que la liste principale, et
  /// rien ne le disait.
  Future<void> _reloadAll(List<StreamAccount> accounts) async {
    if (_reloadingAll) return;
    setState(() => _reloadingAll = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ReloadBatchResult? result = await showReloadAllFlow(
        context,
        accounts: accounts,
        priorityAccountId: _priorityAccountId,
      );
      if (!mounted) return;
      setState(() {
        _reloadingAll = false;
        _accountsFuture = _loadAccounts();
      });
      if (result == null) return; // annulé : rien à annoncer
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(result.summary),
          duration: Duration(seconds: result.allOk ? 3 : 6),
        ));
    } finally {
      if (mounted && _reloadingAll) setState(() => _reloadingAll = false);
    }
  }

  Future<List<StreamAccount>> _loadAccounts() async {
    await StreamAccountService.migrateFromLegacyIfNeeded();
    final accounts = await StreamAccountService.listAccounts();
    // §reloadScope — Ajout ou suppression d'une liste : c'est ici qu'on
    // l'apprend en premier (cf. `ParsedPlaylistService.isMultiAccount`).
    ParsedPlaylistService.reportConfiguredAccounts(accounts.length);
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
    // §secondaryRefresh — En arrière-plan : si la playlist du nouveau principal
    // est périmée, elle est retéléchargée maintenant au lieu d'attendre le
    // prochain démarrage. Non attendu volontairement — la home se remet à jour
    // toute seule via `ParsedPlaylistService.version`.
    final acc = await StreamAccountService.getAccount(id);
    if (acc != null) unawaited(PlaylistService.refreshIfStale(acc));
  }

  Future<void> _openEditor({StreamAccount? initial}) async {
    // §3c Phase 3 — Modal adaptatif : bottom sheet sur mobile, Dialog centré +
    // focus trap sur TV. `scrollable: false` car EditAccountSheet a déjà son
    // propre SingleChildScrollView (évite le double scroll non borné).
    final result = await showAdaptiveActionSheet<StreamAccount>(
      context: context,
      scrollable: false,
      builder: (_) => EditAccountSheet(initial: initial),
    );
    if (result != null) {
      await StreamAccountService.saveAccount(result);
      // Recette S25 du 2026-09-11 — le nouveau nom va aussi aux pastilles de
      // version des fiches (elles lisent la table des listes chargées).
      if (initial != null) {
        ParsedPlaylistService.renameAccount(result.id, result.label);
      }
      // Revue 2026-09-11, D4B-03 — seul un compte NOUVEAU devient principal.
      // En édition, corriger le nom d'un secondaire le rendait principal sans
      // le dire (et l'accueil se rechargeait sur lui) : aucun commentaire ne
      // justifiait ce `setCurrentAccount`, il suivait création et édition.
      if (initial == null) {
        await StreamAccountService.setCurrentAccount(result.id);
      }
      if (!mounted) return;
      _priorityChanged = true;
      _refresh();
      // …et si ce qui sert à joindre le fournisseur a changé, le catalogue
      // analysé (qui embarque les anciens identifiants) est rechargé.
      if (initial != null && connectionChanged(initial, result)) {
        unawaited(_reloadAfterEdit(result));
      }
    }
  }

  /// Revue 2026-09-11, D4B-03 — Recharge la liste d'un compte dont l'URL ou
  /// les identifiants viennent d'être modifiés. Même chemin que le bouton
  /// « Recharger » de la carte (§reloadAll) ; le résultat est annoncé, un
  /// échec garde l'ancienne liste (§cacheKeep).
  Future<void> _reloadAfterEdit(StreamAccount acc) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await PlaylistReloadService.reloadAccount(
        acc,
        isPriority: acc.id == _priorityAccountId,
      );
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.acctReloadedFor(acc.label))));
    } catch (e) {
      debugPrint('❌ D4B-03 — rechargement après édition : $e');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(l10n.commonFailedWith(describeError(e)))));
    }
    if (mounted) _refresh();
  }

  /// §webConsoleOnly — Gestion des comptes depuis le téléphone via la Console
  /// web (remplace l'ancien pairing QR mono-formulaire).
  ///
  /// Le QR ouvre directement la page « Comptes » du panneau : on y ajoute un
  /// compte comme avant, mais on peut aussi le modifier, le recharger, le
  /// supprimer ou basculer le compte principal — ce que le formulaire de
  /// pairing ne permettait pas. La console enregistre elle-même côté service,
  /// d'où le simple `_refresh()` au retour (aucun résultat à récupérer).
  Future<void> _openPhoneConfig() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const WebConsolePage(initialView: 'accounts'),
      ),
    );
    if (!mounted) return;
    _priorityChanged = true;
    _refresh();
  }

  /// §3c-8 — Bifurcation du bouton "+" sur TV : mobile vs télécommande.
  Future<void> _onAddTap() async {
    if (!PlatformTv.isTv) {
      _openEditor();
      return;
    }
    final choice = await showAppDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.acctAddHowTitle),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              autofocus: true,
              leading: Icon(Icons.phone_iphone, color: kAccentPrimary),
              title: Text(ctx.l10n.acctAddFromPhone),
              subtitle: Text(ctx.l10n.acctAddFromPhoneSub),
              onTap: () => Navigator.of(ctx).pop('console'),
            ),
            ListTile(
              leading: Icon(Icons.keyboard_alt_outlined,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              title: Text(ctx.l10n.acctAddWithRemote),
              subtitle: Text(ctx.l10n.acctAddWithRemoteSub),
              onTap: () => Navigator.of(ctx).pop('manual'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
        ],
      ),
    );
    if (choice == 'console') {
      await _openPhoneConfig();
    } else if (choice == 'manual') {
      await _openEditor();
    }
  }

  Future<void> _delete(StreamAccount acc) async {
    final l10n = AppLocalizations.of(context)!;

    // §acctDeleteTruth — On MESURE ce qui va partir avant de le demander.
    // « Cette action est définitive » ne disait ni que la liste téléchargée
    // partait avec (jusqu'à 217 Mo mesurés, §acctPurge), ni que les favoris et
    // les reprises SURVIVENT — deux informations qui changent la réponse.
    final int footprint = await StorageJanitor.accountFootprint(acc.id);
    if (!mounted) return;

    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteAccountDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.acctDeleteBody(acc.label)),
            const SizedBox(height: 12),
            _DeleteBullet(
              icon: Icons.delete_sweep_outlined,
              color: kError,
              text: footprint > 0
                  ? l10n.acctDeleteListGone(
                      StorageJanitor.humanBytes(footprint))
                  : l10n.acctDeleteNoList,
            ),
            const SizedBox(height: 6),
            _DeleteBullet(
              icon: Icons.favorite_outline,
              color: kSuccess,
              text: l10n.acctDeleteKept,
            ),
          ],
        ),
        actions: [
          TextButton(
              // §safeFocus — Suppression de COMPTE : le focus d'entrée va sur
              // « Annuler ». C'est l'action la plus destructrice de l'app, et
              // sur TV, OK est le geste réflexe.
              autofocus: true,
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.deleteAccountConfirm,
                style: TextStyle(color: kError)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await StreamAccountService.deleteAccount(acc.id);
    ParsedPlaylistService.invalidate(acc.id);
    _priorityChanged = true;
    _refresh();
    // §acctDeleteTruth — Il ne se passait RIEN après coup : la carte
    // disparaissait, et c'était tout. On dit ce qui a été fait.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(footprint > 0
            ? l10n.acctDeletedWithSize(
                acc.label, StorageJanitor.humanBytes(footprint))
            : l10n.acctDeleted(acc.label)),
      ));
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
              // §reloadNaming — Il y avait ici « Vider le cache playlist »,
              // QUATRIÈME nom pour la même opération que « Recharger » (le
              // bouton de la carte, juste à côté), avec sa propre logique
              // dupliquée — qui supprimait encore la liste AVANT de la
              // retélécharger, le défaut que §reloadKeep avait corrigé sur les
              // trois autres chemins. Retiré : l'opération reste accessible au
              // même endroit, sous le nom qu'elle porte partout ailleurs.
              ListTile(
                leading: Icon(Icons.delete_outline, color: kError),
                title: Text(l10n.accountActionDelete,
                    style: TextStyle(color: kError)),
                onTap: () {
                  Navigator.pop(ctx);
                  _delete(acc);
                },
              ),
              // §tvOptionsBack — une feuille dont la dernière ligne est
              // DESTRUCTIVE doit d'autant plus offrir de n'en choisir aucune.
              SheetCloseTile(onTap: () => Navigator.pop(ctx)),
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
          // §reloadAll — L'action « Recharger toutes les listes » vivait ici,
          // en ↻ nu : personne ne devinait ce que rechargeait une icône sans
          // mot. Elle est devenue un bouton libellé en tête de la liste, cf.
          // `_buildReloadAllButton`.
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
              label: Text(ctx.l10n.acctAdd),
              backgroundColor: kAccentPrimary,
              // Revue 2026-09-11, D4B-08 — le texte suit le fond (Tron : blanc).
              foregroundColor: onColorFor(kAccentPrimary),
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
              // R18 / R22 (D4B-10) — cf. `_lastAccounts` : on ne retombe sur le
              // spinner que si on n'a VRAIMENT rien à montrer.
              final List<StreamAccount>? accounts =
                  snap.connectionState == ConnectionState.done
                      ? (snap.data ?? const <StreamAccount>[])
                      : _lastAccounts;
              if (accounts == null) {
                return const Center(child: CircularProgressIndicator());
              }
              _lastAccounts = accounts;
              if (accounts.isEmpty) return _buildEmptyState(cs);
              // §fabOverlap — Le FAB « Ajouter » flotte au-dessus de la liste
              // et recouvrait le bouton ⋯ de la dernière carte (constaté sur
              // TV). Le rembourrage bas du `ListView` ne suffit PAS à la
              // télécommande : `ensureVisible` gare l'élément focalisé contre
              // le bord BAS du *viewport*, donc sous le FAB, quel que soit le
              // rembourrage du contenu. Sur TV on raccourcit donc le viewport
              // lui-même (`Padding` À L'EXTÉRIEUR du scrollable) : plus rien ne
              // peut être garé sous le bouton. Au doigt on garde le défilement
              // sous le FAB (rendu Material habituel), avec la marge de contenu
              // qui met la dernière carte hors de portée du bouton.
              const double fabInset = 88; // 56 (FAB) + 16 marge + 16 respiration
              final bool isTv = PlatformTv.isTv;
              // §reloadAll — Un seul compte : le bouton de sa carte suffit, une
              // action de page ferait doublon.
              final bool showReloadAll = accounts.length >= 2;
              final int headerCount = showReloadAll ? 2 : 1;
              return Padding(
                padding: EdgeInsets.only(bottom: isTv ? fabInset : 0),
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    // §rowStorageKey — Sans clé propre, ce scrollable partage
                    // sa case de position avec les autres de la même route.
                    key: const PageStorageKey<String>('accounts_list'),
                    padding: EdgeInsets.fromLTRB(12, 16, 12, isTv ? 12 : 100),
                    // +1 pour le bandeau info, +1 pour « Recharger toutes les
                    // listes » à partir de deux comptes.
                    itemCount: accounts.length + headerCount,
                    itemBuilder: (_, i) {
                      if (i == 0) return _buildPriorityBanner(accounts, cs);
                      if (showReloadAll && i == 1) {
                        return _buildReloadAllButton(accounts);
                      }
                      final acc = accounts[i - headerCount];
                      final isPriority = _priorityAccountId == acc.id;
                      return _AccountCard(
                        // R22 (D4B-10) — La carte s'identifie par son COMPTE,
                        // pas par son rang : au retour d'un rafraîchissement,
                        // Flutter réapparie alors les états (et le focus
                        // D-pad) sur le bon compte, même si l'ordre a bougé.
                        key: ValueKey<String>(acc.id),
                        account: acc,
                        isPriority: isPriority,
                        onTap: () => _setPriority(acc.id),
                        onMore: () => _showAccountMenu(acc),
                        onReloaded: _refresh,
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// §reloadAll — Action de PAGE, pas de carte : avec quatre comptes, le
  /// rechargement un par un demandait quatre descentes, quatre confirmations
  /// et quatre attentes ; sur TV, chaque aller-retour au D-pad le doublait.
  ///
  /// §dpadChildFocus — Élément de la liste, FRÈRE des cartes : jamais dans une
  /// `FocusableCard`, sinon il n'est candidat nulle part au D-pad. Le bandeau
  /// au-dessus n'a rien de focusable : c'est la première étape du corps, la
  /// croix bas y mène depuis l'AppBar et en repart vers la première carte.
  ///
  /// §boundFocus — Pendant un rechargement, le bouton reste ACTIF : passer à
  /// `onPressed: null` le retirerait alors qu'il a le focus, et le focus
  /// sauterait ailleurs. `_reloadAll` ignore déjà un second appui.
  Widget _buildReloadAllButton(List<StreamAccount> accounts) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _reloadAll(accounts),
          icon: _reloadingAll
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: onColorFor(kAccentPrimary),
                  ),
                )
              : const Icon(Icons.refresh),
          label: Text(context.l10n.reloadAllTooltip),
          style: aetherFilledStyle(kAccentPrimary),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    // §12-b — Widget EmptyState unifié.
    // §webConsoleOnly — Sur TV, CTA = Console web (la saisie au D-pad est piégeante).
    final isTv = PlatformTv.isTv;
    return EmptyState(
      icon: isTv ? Icons.qr_code_2 : Icons.account_circle_outlined,
      title: context.l10n.acctEmptyTitle,
      subtitle: isTv
          ? context.l10n.acctEmptySubTv
          : context.l10n.acctEmptySubPhone,
      ctaLabel: isTv
          ? context.l10n.acctEmptyCtaTv
          : context.l10n.acctEmptyCtaPhone,
      ctaIcon: isTv ? Icons.phone_iphone : Icons.add,
      onCtaTap: isTv ? _openPhoneConfig : () => _openEditor(),
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
    // §bannerCount — On écoute AUSSI `version` : le décompte ci-dessous lit la
    // mémoire réelle, qui change sans que `loadStates` bouge (déchargement,
    // rechargement depuis le disque).
    // §fleetState — Et `loadFailures` : « 1 en échec » ne se déduit d'aucun des
    // deux autres notifiers.
    return ListenableBuilder(
      listenable: Listenable.merge([
        ParsedPlaylistService.loadStates,
        ParsedPlaylistService.loadFailures,
        ParsedPlaylistService.version,
      ]),
      builder: (context, _) {
        final states = ParsedPlaylistService.loadStates.value;
        // ⚠️ **Le décompte ne peut PAS venir de `loadStates`** : quand un
        // compte est déchargé, `setLoadState(notLoaded)` **supprime la clé**
        // de la map. Un secondaire déchargé disparaissait donc du décompte, et
        // le bandeau annonçait « 1/3 chargés » alors que rien n'avait échoué.
        //
        // `entriesCountOf` lit `_memory` directement — et, contrairement à
        // `getAccount()`, ne touche PAS `_lastAccess` : consulter le bandeau ne
        // doit pas repousser le déchargement (§secondaryCounts).
        final loadedOthers = accounts
            .where((a) =>
                a.id != active.id &&
                ParsedPlaylistService.entriesCountOf(a.id) > 0)
            .length;
        final inProgressOthers = accounts
            .where((a) =>
                a.id != active.id &&
                (states[a.id] == AccountLoadState.downloading ||
                    states[a.id] == AccountLoadState.parsing))
            .length;
        // §fleetState — Une liste manquante n'est un ÉCHEC que si son motif
        // n'est pas bénin : « SUR DISQUE » (mémoire libérée volontairement) et
        // « EN ATTENTE » sont des fonctionnements normaux, les compter en
        // échec ferait passer §lazyUnload pour une panne.
        //
        // Restreint aux secondaires, comme le reste du décompte : le principal
        // est compté chargé par construction (§bannerCount), l'annoncer en
        // échec sur la même ligne se lirait comme une contradiction. Sa carte,
        // elle, porte la chip et la raison complètes.
        final failedOthers = accounts
            .where((a) =>
                a.id != active.id &&
                ParsedPlaylistService.entriesCountOf(a.id) == 0 &&
                (ParsedPlaylistService.failureOf(a.id)?.isBenign == false))
            .length;
        return Container(
          margin: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          // §bannerSlim — Bandeau resserré : il occupait trois lignes de texte
          // et 20 px de marge intérieure pour une information de contexte.
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                      context.l10n.acctMainAccount,
                      style: TextStyle(
                        fontSize: 9,
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
              // §bannerSlim — Le statut des secondaires passe À DROITE, sur la
              // même ligne que le décompte : le bandeau tenait sur trois lignes
              // pour dire deux choses.
              if (accounts.length > 1)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.acctListsCount(accounts.length),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      // §bannerCount — Le décompte porte sur TOUTES les listes,
                      // pas seulement les secondaires.
                      //
                      // ⚠️ Il affichait « 2/2 » juste sous « 3 listes » : deux
                      // dénominateurs différents à deux lignes d'écart, ça se
                      // lit comme une contradiction. Le principal est chargé
                      // par construction (on est dessus), donc l'inclure ne
                      // fausse rien et rend les deux lignes cohérentes.
                      _secondaryStatusLabel(loadedOthers + 1, inProgressOthers,
                          accounts.length, failedOthers),
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant.withAlpha(190),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  /// §bannerSlim — Libellé court : il vit désormais à droite du bandeau, sur
  /// une largeur contrainte. « comptes secondaires chargés » était trop long et
  /// forçait le retour à la ligne, ce qui épaississait le bandeau.
  ///
  /// [loaded] et [total] portent sur TOUTES les listes (§bannerCount).
  ///
  /// §fleetState — [failed] compte les listes dont l'absence a un motif NON
  /// bénin. Le bandeau annonçait « ✓ 1/3 chargées » avec la coche de
  /// validation même quand deux listes avaient échoué : la coche est retirée
  /// dès qu'il y a un échec, et le nombre est dit.
  String _secondaryStatusLabel(
      int loaded, int inProgress, int total, int failed) {
    if (total == 0) return '';
    if (inProgress > 0) {
      final base = context.l10n.acctStatusInProgress(loaded, total, inProgress);
      return failed > 0 ? context.l10n.acctStatusWithFailed(base, failed) : base;
    }
    if (failed > 0) return context.l10n.acctStatusFailed(loaded, total, failed);
    return context.l10n.acctStatusLoaded(loaded, total);
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
    super.key,
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
    //
    // Revue 2026-09-11, D4B-10 — La requête que `_loadAccounts` vient de
    // lancer pour ce compte (`ExpirationAlertService.fetchAll`, juste avant
    // que la liste des cartes ne s'affiche), TANT QU'ELLE COURT, plutôt
    // qu'une seconde identique sur la connexion unique du panel. Terminée (ou
    // jamais lancée), la carte fait la sienne, comme avant : la liste est un
    // `ListView.builder`, une carte remontée au défilement doit montrer des
    // chiffres frais, pas ceux de l'ouverture de la page.
    _accountInfoFuture =
        ExpirationAlertService.pendingFor(widget.account.id) ??
            StreamAccountService.fetchAccountInfo(widget.account);
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
        // Revue 2026-09-11, D4B-11 — trois `await` depuis le tap : la carte
        // a pu disparaître, et `_confirmReload` lit `context`.
        if (!mounted) return;
        final ok = await _confirmReload(age);
        if (ok != true) return;
      }
    }

    if (!mounted) return;
    setState(() => _reloading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // §reloadAll — Logique extraite dans `PlaylistReloadService` : le
      // rechargement en LOT s'en sert aussi, et dupliquer aurait garanti la
      // divergence des deux chemins.
      await PlaylistReloadService.reloadAccount(
        widget.account,
        isPriority: widget.isPriority,
      );
      if (!mounted) return;
      // Revue 2026-09-11, D4B-08 — plus de fond d'accent : le thème impose un
      // texte BLANC aux snackbars, et l'accent du préréglage Tron EST blanc
      // (bande claire, texte illisible). Le fond du thème suffit.
      messenger..hideCurrentSnackBar()..showSnackBar(
        SnackBar(
          content: Text(context.l10n.acctReloadedFor(widget.account.label)),
        ),
      );
      widget.onReloaded();
    } catch (e) {
      if (!mounted) return;
      messenger..hideCurrentSnackBar()..showSnackBar(SnackBar(
          content: Text(context.l10n.commonFailedWith(describeError(e)))));
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  Future<bool?> _confirmReload(Duration age) {
    final h = age.inHours;
    final m = age.inMinutes % 60;
    final ageStr = h > 0
        // Revue 2026-09-11, lot 7 — plus de « min » en dur (écran anglais).
        ? context.l10n.acctAgeHoursMinutes(
            h, m > 0 ? ' ${context.l10n.acctAgeMinutesShort(m)}' : '')
        : context.l10n.acctAgeMinutesShort(m);
    return showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.acctReloadTitle),
        content: Text(
            ctx.l10n.acctReloadBody(widget.account.label, ageStr)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.acctReload,
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

    // §3c-3 → §dpadChildFocus — Le conteneur visuel (fond + bordure isPriority
    // + glow) reste UN bloc ; à l'intérieur, la zone « choisir ce compte » et
    // la rangée d'actions (Recharger / ⋯) sont des focusables FRÈRES, jamais
    // imbriqués, à rectangles disjoints (la rangée est SOUS la zone).
    //
    // ⚠️ L'ancien commentaire disait « Recharger et ⋯ restent focusables
    // séparément » : vrai sous dpad 2.x, FAUX depuis 3.0. `DpadFocusable`
    // enveloppe son enfant d'un `ExcludeFocus` → tout bouton imbriqué sort de
    // la traversée (modifier / vider le cache / SUPPRIMER / recharger étaient
    // inatteignables à la télécommande). Et `excludeChildFocus: false` ne
    // corrigerait rien : `DpadTraversalPolicy._isCandidate` exige que le
    // candidat DÉPASSE la source sur l'axe — un rect CONTENU dans la carte n'est
    // candidat dans aucune direction. Le correctif est donc structurel.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Zone « choisir ce compte » : un seul arrêt D-pad ──────────
              FocusableCard(
                decorateOnly: true,
                // §tvErgo — tuile pleine largeur : pas de scale (sinon
                // débordement écran).
                scaleOnFocus: false,
                onTap: widget.onTap,
                // Coins arrondis en HAUT seulement : la zone épouse le bord de
                // la carte, la rangée d'actions la prolonge en dessous.
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: InkWell(
                  onTap: widget.onTap,
                  // §tvErgo — InkWell non focusable : évite le doublon d'arrêt
                  // D-pad (FocusableCard + InkWell sur la même action) tout en
                  // gardant le tap tactile.
                  canRequestFocus: false,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  splashColor: kAccentPrimary.withAlpha(30),
                  highlightColor: kAccentPrimary.withAlpha(15),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: _buildInfoColumn(context),
                  ),
                ),
              ),
              // ── Rangée d'actions : FRÈRE de la zone, sous elle ────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: _buildActionsRow(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// En-tête (radio principal + label + chips) + compteurs + bloc Xtream.
  /// Aucun bouton ici : tout ce qui est actionnable vit dans [_buildActionsRow].
  Widget _buildInfoColumn(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPriority = widget.isPriority;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── En-tête : radio principal + label + chips ────────────────────
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
          ],
        ),
        const SizedBox(height: 14),
        // ── Stats playlist (live via ParsedPlaylistService) ─────
        // §secondaryCounts — Les compteurs ne dépendent plus de la
        // présence du compte EN MÉMOIRE.
        //
        // ⚠️ Deux défauts corrigés d'un coup :
        //   1. `getAccount()` **touche `_lastAccess`** — consulter
        //      les stats repoussait le déchargement du compte,
        //      alors que la page n'est pas un usage de la liste.
        //   2. On parcourait jusqu'à 153 000 entrées à CHAQUE
        //      reconstruction, juste pour compter — et le résultat
        //      tombait à **zéro** dès que le compte était déchargé,
        //      donnant l'impression d'une liste vide.
        //
        // `countsOf` lit les listes pré-splittées si le compte est
        // en mémoire, sinon l'EN-TÊTE du cache disque (une seule
        // ligne décompressée, mémoïsée).
        ListenableBuilder(
          listenable: ParsedPlaylistService.version,
          builder: (context, _) {
            return FutureBuilder<PlaylistCounts?>(
              future:
                  ParsedPlaylistService.countsOf(widget.account.id),
              builder: (context, snap) {
                final c = snap.data;
                return Column(
                  children: [
                    _CountsRow(
                      films: c?.films,
                      series: c?.series,
                      tv: c?.tv,
                    ),
                    _PlaybackHealthLine(
                        accountId: widget.account.id),
                    const SizedBox(height: 12),
                    _FileStatsBlock(
                      accountId: widget.account.id,
                      hasParsed: c != null,
                    ),
                  ],
                );
              },
            );
          },
        ),
        // §17c — Le bloc « Expiration / Connexions » était réservé
        // aux comptes en mode `separate`. Ce garde-fou est resté en
        // place alors que §17a a justement appris à
        // `fetchAccountInfo` à extraire les identifiants d'une URL
        // COMPLÈTE (la plupart des « .m3u complets » sont du Xtream
        // déguisé, `get.php?username=…&password=…`).
        //
        // Constaté sur appareil avec 4 listes : le journal dit
        // « ✅ Infos du compte 'Platinium' récupérées », mais la
        // carte n'affichait ni expiration ni connexions — parce
        // qu'elle est en mode URL complète. Seul Xeno, en mode
        // separate, les montrait.
        //
        // On s'aligne donc sur la vraie condition : le compte
        // sait-il produire une URL `player_api.php` ? Un M3U qui
        // n'est pas du Xtream déguisé renvoie `null` et reste,
        // comme avant, sans bloc.
        if (widget.account.buildPlayerApiUrl() != null) ...[
          const SizedBox(height: 10),
          _XtreamInfoBlock(future: _accountInfoFuture),
        ],
      ],
    );
  }

  /// §dpadChildFocus — « Recharger » et ⋯, chacun dans sa `FocusableChip`.
  ///
  /// Le bouton Material à l'intérieur garde son `onPressed` pour le TACTILE ;
  /// au D-pad il est exclu par l'`ExcludeFocus` du wrapper (voulu : un seul
  /// arrêt), c'est la chip qui reçoit le focus, peint le halo et relaie OK vers
  /// la même action. Pendant un rechargement, le bouton est désactivé ET la chip
  /// sort de la traversée (`enabled: !_reloading`).
  Widget _buildActionsRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          // R18 — Le bouton disait « Téléchargement… » du premier octet à la
          // dernière entrée, alors que le téléchargement est fini depuis
          // longtemps quand la liste se lit. La phase EXISTE déjà
          // (`AccountLoadState`, c'est elle qui peint la chip juste au-dessus) :
          // il suffisait de la lire au lieu d'un booléen local.
          child: ValueListenableBuilder<Map<String, AccountLoadState>>(
            valueListenable: ParsedPlaylistService.loadStates,
            builder: (context, states, _) {
              final AccountLoadState? phase = states[widget.account.id];
              // ⚠️ Sans état publié, on ne devine pas : le premier libellé
              // reste celui du téléchargement, qui est bien ce qui commence.
              final String busyLabel =
                  phase == AccountLoadState.parsing
                      ? context.l10n.acctReadingPlaylist
                      : context.l10n.acctDownloading;
              return FocusableChip(
                enabled: !_reloading,
                onTap: _reload,
                borderRadius: BorderRadius.circular(12),
                child: FilledButton.icon(
                  onPressed: _reloading ? null : _reload,
                  icon: _reloading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            // §lightTheme — le contraste se dérive du fond du
                            // bouton, il ne se décrète pas noir.
                            color: onColorFor(kAccentPrimary),
                          ),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    _reloading ? busyLabel : context.l10n.acctReloadPlaylist,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  // Le style commun, plus des coins alignés sur le halo de la
                  // chip (le stadium M3 par défaut laisserait le halo déborder
                  // dans les angles).
                  style: aetherFilledStyle(kAccentPrimary).copyWith(
                    shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        FocusableChip(
          onTap: widget.onMore,
          borderRadius: BorderRadius.circular(12),
          child: IconButton.outlined(
            icon: Icon(Icons.more_vert,
                color: cs.onSurfaceVariant.withAlpha(180)),
            onPressed: widget.onMore,
            tooltip: context.l10n.acctCardActions, // D4B-05 (lu par TalkBack)
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              side: BorderSide(color: cs.outline.withAlpha(60)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
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
    final cs = Theme.of(context).colorScheme;
    // §fleetState — On écoute AUSSI le registre des motifs d'échec : il change
    // sans que `loadStates` bouge (un `notLoaded` reste `notLoaded` que la
    // liste ait été déchargée volontairement ou refusée par le panel).
    return ValueListenableBuilder<Map<String, AccountLoadState>>(
      valueListenable: ParsedPlaylistService.loadStates,
      builder: (context, states, _) {
        return ValueListenableBuilder<Map<String, LoadFailure>>(
          valueListenable: ParsedPlaylistService.loadFailures,
          builder: (context, failures, ___) {
            return ValueListenableBuilder<Map<String, AccountInfo?>>(
              valueListenable: ExpirationAlertService.infos,
              builder: (context, infos, __) {
                final state = states[accountId] ?? AccountLoadState.notLoaded;
                final daysLeft =
                    ExpirationAlertService.daysUntilExpiration(accountId);
                final LoadFailure? failure = failures[accountId];
                // La raison ne s'affiche que si elle apporte quelque chose :
                // une liste chargée n'a rien à expliquer, et un motif bénin
                // (mémoire libérée volontairement) tient déjà dans la chip.
                final bool showReason = failure != null &&
                    !failure.isBenign &&
                    (state == AccountLoadState.notLoaded ||
                        state == AccountLoadState.error);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _statusChip(state, failure, cs.onSurfaceVariant),
                        if (daysLeft != null &&
                            daysLeft <=
                                ExpirationAlertService.kAlertThresholdDays)
                          _expirationChip(daysLeft),
                      ],
                    ),
                    if (showReason)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          describeFailure(failure),
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.25,
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// §fleetState — « NON CHARGÉ » disait la même chose de quatre situations
  /// différentes : jamais tentée, mémoire libérée volontairement, reportée
  /// après le démarrage, ou réellement en échec. Le motif enregistré nomme
  /// laquelle.
  ///
  /// ⚠️ **Une chip bénigne ne prend pas la couleur d'alerte.** « SUR DISQUE »
  /// décrit un fonctionnement voulu (§lazyUnload libère la mémoire, le cache
  /// reste) : le peindre en rouge ferait chercher une panne là où il n'y en a
  /// pas. On garde donc le gris neutre pour le bénin, et `kError` uniquement
  /// pour ce qui a vraiment échoué.
  /// [neutralChipColor] — le gris d'une chip BÉNIGNE (« SUR DISQUE »,
  /// « NON CHARGÉ ») : celui du thème, jamais `Colors.grey`, qui restait
  /// identique en clair et en sombre et disparaissait sur le fond clair.
  /// Passé en paramètre parce que cette méthode n'a pas de `BuildContext`.
  Widget _statusChip(AccountLoadState state, LoadFailure? failure,
      Color neutralChipColor) {
    if (isPriority && state == AccountLoadState.loaded) {
      return _Chip(
        text: L10n.current.acctChipMain,
        color: kAccentPrimary,
        filled: true,
        glow: true,
      );
    }
    switch (state) {
      case AccountLoadState.loaded:
        return _Chip(text: L10n.current.acctChipAvailable, color: kAccentPrimary, opacity: 0.6);
      case AccountLoadState.downloading:
        return _Chip(text: L10n.current.acctChipDownloading, color: kAccentSecondary);
      case AccountLoadState.parsing:
        return _Chip(text: L10n.current.acctChipLoading, color: kAccentSecondary);
      case AccountLoadState.error:
      case AccountLoadState.notLoaded:
        // Sans motif enregistré, on retombe sur l'ancien libellé : mieux vaut
        // une chip vague qu'une chip qui invente une cause.
        if (failure == null) {
          return state == AccountLoadState.error
              ? _Chip(text: L10n.current.acctChipError, color: kError)
              : _Chip(
                  text: L10n.current.acctChipNotLoaded,
                  color: neutralChipColor);
        }
        return _Chip(
          text: labelForFailure(failure.kind),
          color: failure.isBenign ? neutralChipColor : kError,
        );
    }
  }

  Widget _expirationChip(int days) {
    if (days < 0) {
      return _Chip(
        text: L10n.current.acctChipExpired,
        color: kError,
        filled: true,
        icon: Icons.warning_amber_rounded,
      );
    }
    if (days == 0) {
      return _Chip(
        text: L10n.current.acctChipExpiresToday,
        color: kError,
        filled: true,
        icon: Icons.warning_amber_rounded,
      );
    }
    final critical = days <= 7;
    return _Chip(
      text: L10n.current.acctChipExpiresIn(days),
      color: critical ? kError : kWarning,
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
    // §lightTheme — Le contraste se DÉRIVE du fond, il ne se décrète pas :
    // un accent clair (préréglage Tron) laissait un texte noir illisible sur
    // une chip pleine, et un accent sombre l'inverse.
    final fg = filled ? onColorFor(color) : color;
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
  /// §secondaryCounts — `null` = total INCONNU (cache d'avant §secondaryCounts,
  /// ou aucun cache). On affiche « — » : un faux « 0 » se lit comme une liste
  /// vide, ce qui était précisément le bug.
  final int? films;
  final int? series;
  final int? tv;
  const _CountsRow({required this.films, required this.series, required this.tv});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _CountTile(icon: Icons.movie_outlined, value: films, label: context.l10n.acctCountFilms, color: kAccentPrimary)),
        const SizedBox(width: 8),
        Expanded(child: _CountTile(icon: Icons.video_library_outlined, value: series, label: context.l10n.acctCountSeries, color: kAccentTertiary)),
        const SizedBox(width: 8),
        Expanded(child: _CountTile(icon: Icons.live_tv_outlined, value: tv, label: context.l10n.acctCountTv, color: kAccentSecondary)),
      ],
    );
  }
}

/// §stallCount — Ce que CE fournisseur a réellement servi.
///
/// Placée juste sous les compteurs de catalogue, et c'est délibéré : la carte
/// disait jusqu'ici combien un compte contient, jamais s'il **fonctionne**. Un
/// abonnement à 50 000 films qui bloque toutes les dix minutes n'est pas un bon
/// abonnement, et rien ne le montrait.
///
/// ⚠️ Rien n'est affiché tant qu'aucune session n'a été mesurée : une ligne
/// « 0 blocage » sur un compte jamais lu serait un compliment non mérité.
class _PlaybackHealthLine extends StatelessWidget {
  final String accountId;
  const _PlaybackHealthLine({required this.accountId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: PlaybackHealthService.version,
      builder: (_, __, ___) {
        final h = PlaybackHealthService.forAccount(accountId);
        if (h == null || h.sessions == 0) return const SizedBox.shrink();
        final perHour = h.stallsPerHour;
        // Seuil délibérément indulgent : sous un blocage par heure, une liaison
        // domestique normale suffit à l'expliquer. Au-delà, c'est un motif.
        final bad = perHour != null && perHour >= 1.0;
        final startup = h.averageStartup;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Icon(
                bad ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                size: 14,
                color: bad ? kWarning : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    // Revue 2026-09-11, D1B-07 — `summary` est le texte du
                    // journal ; l'écran lit la version traduite.
                    h.displaySummary(L10n.current),
                    if (startup != null)
                      L10n.current.acctStartupTime(
                          (startup.inMilliseconds / 1000).toStringAsFixed(1)),
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 11,
                    color: bad ? kWarning : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CountTile extends StatelessWidget {
  final IconData icon;
  final int? value;
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
            value == null ? '—' : _formatCount(value!),
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
                  label: L10n.current.acctM3uSize,
                  // R8 — Un QUATRIÈME formateur de tailles vivait ici, avec
                  // ses propres clés `unit*`, son propre arrondi et un point
                  // décimal en dur : « 12.3 Mo » sur un écran français, à côté
                  // de « 12,3 Mo » ailleurs dans l'app. Un seul formateur
                  // désormais (`formatFileSize`), qui suit la locale.
                  value: stats == null ? '—' : formatFileSize(stats.size),
                ),
              ),
              Container(width: 1, height: 26, color: cs.outlineVariant.withAlpha(80)),
              Expanded(
                child: _MiniStat(
                  icon: Icons.access_time,
                  label: L10n.current.acctCacheAge,
                  value: stats == null
                      ? L10n.current.acctNoCache
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

  static String _formatAge(DateTime when) {
    final age = DateTime.now().difference(when);
    if (age.inMinutes < 1) return L10n.current.acctAgeJustNow;
    if (age.inMinutes < 60) return L10n.current.acctAgeMinutes(age.inMinutes);
    if (age.inHours < 24) return L10n.current.acctAgeHours(age.inHours);
    return L10n.current.acctAgeDays(age.inDays);
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
                  L10n.current.acctXtreamLoading,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            );
          }
          final info = snap.data;
          if (info == null) {
            return _InlineError(message: L10n.current.acctXtreamUnavailable);
          }
          return Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.event_outlined,
                  label: L10n.current.acctExpiration,
                  value: _formatExpiration(info.expirationDate),
                  valueColor: _expirationColor(info.expirationDate),
                ),
              ),
              Container(width: 1, height: 26, color: cs.outlineVariant.withAlpha(80)),
              Expanded(
                child: _MiniStat(
                  icon: Icons.cable,
                  label: L10n.current.acctConnections,
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
    if (exp == null) return L10n.current.acctExpiryUnknown;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expDay = DateTime(exp.year, exp.month, exp.day);
    final days = expDay.difference(today).inDays;
    if (days < 0) return L10n.current.acctExpiryPast(-days);
    if (days == 0) return L10n.current.acctExpiryToday;
    if (days == 1) return L10n.current.acctExpiryTomorrow;
    return L10n.current.acctExpiryInDays(days);
  }

  static Color? _expirationColor(DateTime? exp) {
    if (exp == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expDay = DateTime(exp.year, exp.month, exp.day);
    final days = expDay.difference(today).inDays;
    if (days < 0) return kError;
    if (days <= 7) return kError;
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

/// §acctDeleteTruth — Une ligne du dialogue de suppression : ce qui part, ce
/// qui reste. Deux couleurs plutôt qu'un paragraphe — à 3 m d'un téléviseur,
/// un bloc de texte n'est pas lu.
class _DeleteBullet extends StatelessWidget {
  const _DeleteBullet({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
