import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player.dart';
import '../models/property.dart';
import '../models/property_ownership.dart';
import '../models/result.dart';
import '../providers/game_provider.dart';
import '../services/game_client.dart';
import '../services/game_engine.dart';
import '../services/nfc_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import '../utils/snack.dart';
import '../widgets/auction_card.dart';
import '../widgets/player_avatar.dart';

/// Every property on the board with live ownership: buy, pay rent, build
/// houses, and register physical NFC cards.
class PropertiesScreen extends StatefulWidget {
  const PropertiesScreen({super.key, this.openPropertyId});

  /// When set, opens this property's action sheet right away (used by the
  /// NFC tap flow).
  final String? openPropertyId;

  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends State<PropertiesScreen> {
  final _nfc = NfcService.instance;
  bool _nfcAvailable = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _nfc.isAvailable().then((available) {
      if (mounted) setState(() => _nfcAvailable = available);
    });
    final openId = widget.openPropertyId;
    if (openId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final property = context.read<GameProvider>().propertyById(openId);
        if (property != null) _openProperty(property);
      });
    }
  }

  Future<void> _openProperty(Property property) async {
    final resolved = await showPropertySheet(
      context,
      propertyId: property.id,
      nfcAvailable: _nfcAvailable,
    );
    // Buying or paying rent settles the square you landed on — return
    // straight to the game screen instead of leaving this list in the way.
    if (resolved == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameProvider>();
    final board = session.game?.board;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (board == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final mine = session.propertiesOwnedBy(session.myPlayerId);
    final mineValue = mine.fold<int>(0, (sum, p) => sum + p.price);
    final query = _query.trim().toLowerCase();
    // Specials (GO, Jail, Tax, ...) aren't ownable — they live in the board
    // view, not this buy/rent/mortgage list.
    final ownable = board.properties.where((p) => p.kind.isOwnable);
    final visibleProperties = query.isEmpty
        ? ownable.toList()
        : ownable.where((p) => p.name.toLowerCase().contains(query)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Properties')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You own ${mine.length} '
                        'propert${mine.length == 1 ? 'y' : 'ies'}',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'List value '
                        '${formatMoney(mineValue, board.currencySymbol)}',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (mine.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    children: [
                      for (final property in mine.take(8))
                        Container(
                          width: 10,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Color(property.colorValue),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search properties…',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: scheme.surfaceContainerHigh,
            ),
          ),
          const SizedBox(height: 8),
          if (visibleProperties.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'No property matches "$_query".',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final property in visibleProperties)
              _PropertyTile(
                property: property,
                ownership: session.ownershipOf(property.id),
                session: session,
                currency: board.currencySymbol,
                onTap: () => _openProperty(property),
              ),
        ],
      ),
    );
  }
}

class _PropertyTile extends StatelessWidget {
  const _PropertyTile({
    required this.property,
    required this.ownership,
    required this.session,
    required this.currency,
    required this.onTap,
  });

  final Property property;
  final PropertyOwnership? ownership;
  final GameProvider session;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final owner = ownership == null
        ? null
        : session.playerById(ownership!.ownerId);
    final isMine = ownership?.ownerId == session.myPlayerId;

    final String statusText;
    if (owner == null) {
      statusText = formatMoney(property.price, currency);
    } else if (isMine) {
      statusText = 'Yours';
    } else {
      statusText = owner.name;
    }

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 14,
        height: 44,
        decoration: BoxDecoration(
          color: Color(property.colorValue),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      title: Text(
        property.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: (textTheme.bodyLarge?.fontSize ?? 16) + 3.5,
        ),
      ),
      subtitle: ownership != null && ownership!.mortgaged
          ? Text(
              'Mortgaged',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.expense,
                fontWeight: FontWeight.w700,
              ),
            )
          : ownership != null && ownership!.houses > 0
          ? Row(
              children: [
                if (ownership!.houses >= PropertyOwnership.hotel)
                  const Icon(
                    Icons.apartment_rounded,
                    size: 16,
                    color: AppColors.expense,
                  )
                else
                  for (var i = 0; i < ownership!.houses; i++)
                    const Icon(
                      Icons.home_rounded,
                      size: 16,
                      color: AppColors.income,
                    ),
              ],
            )
          : Text(
              property.kind.name,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (owner != null) ...[
            PlayerAvatar(player: owner, size: 28, showPresence: false),
            const SizedBox(width: 8),
          ],
          Text(
            statusText,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: owner == null
                  ? scheme.onSurfaceVariant
                  : (isMine ? AppColors.income : scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Property action sheet
// ---------------------------------------------------------------------------

/// Opens [propertyId]'s action sheet directly — buy, pay rent, manage
/// buildings, register an NFC card — without navigating through the full
/// Properties list first. Used by the game screen for landings, NFC taps
/// and tapping a square on the board, as well as by [PropertiesScreen]
/// itself when browsing the full list. Returns true if a buy/rent action
/// completed inside the sheet, so the caller can react (e.g. dismiss
/// whatever else led here).
Future<bool?> showPropertySheet(
  BuildContext context, {
  required String propertyId,
  required bool nfcAvailable,
}) {
  final nfc = NfcService.instance;

  // Landing on an unowned square with no auction running is the one case
  // where the official rule forces a decision — buy it, or decline and it
  // goes to auction — so the sheet can't just be dragged or tapped away as
  // a silent third option, leaving it unowned indefinitely. Every other
  // case (browsing, an owned property, a running auction) stays freely
  // dismissible as normal.
  final session = context.read<GameProvider>();
  final board = session.game?.board;
  final property = session.propertyById(propertyId);
  final decisionRequired =
      board != null &&
      property != null &&
      property.kind.isOwnable &&
      session.ownershipOf(propertyId) == null &&
      session.auctionFor(propertyId) == null &&
      session.canResolve &&
      (board.goIndex < 0 ||
          session.me?.position == board.properties.indexOf(property));

  Future<void> writeCard() async {
    final session = context.read<GameProvider>();
    final board = session.game?.board;
    final property = session.propertyById(propertyId);
    if (board == null || property == null) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        content: const Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Hold an empty card near the device…')),
          ],
        ),
        actions: [
          TextButton(onPressed: nfc.cancel, child: const Text('Cancel')),
        ],
      ),
    );
    final result = await nfc.writeText(
      NfcService.propertyPayload(boardId: board.id, propertyId: property.id),
    );
    if (context.mounted) Navigator.of(context).pop(); // close the wait dialog
    if (result.error == NfcService.cancelled) return;
    if (context.mounted) {
      showSnack(
        context,
        result.isOk ? 'Card written: ${property.name}' : result.error!,
      );
    }
  }

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: !decisionRequired,
    enableDrag: !decisionRequired,
    showDragHandle: !decisionRequired,
    builder: (_) => _PropertySheet(
      propertyId: propertyId,
      nfcAvailable: nfcAvailable,
      onWriteCard: writeCard,
      decisionRequired: decisionRequired,
    ),
  );
}

class _PropertySheet extends StatefulWidget {
  const _PropertySheet({
    required this.propertyId,
    required this.nfcAvailable,
    required this.onWriteCard,
    required this.decisionRequired,
  });

  final String propertyId;
  final bool nfcAvailable;
  final VoidCallback onWriteCard;
  // Mirrors the isDismissible/enableDrag/showDragHandle: false the sheet was
  // opened with — a buy-or-auction decision is owed, so the system back
  // button/gesture (which a bare showModalBottomSheet route still honors
  // regardless of those three flags) needs blocking too, or it's still a
  // silent way to dismiss the decision.
  final bool decisionRequired;

  @override
  State<_PropertySheet> createState() => _PropertySheetState();
}

class _PropertySheetState extends State<_PropertySheet> {
  bool _busy = false;
  String? _error;
  final _nfc = NfcService.instance;

  @override
  void initState() {
    super.initState();
    // POS mode: while this sheet is open, tapping this property's card or
    // your own payment card triggers the primary action (buy or pay rent)
    // — with the usual confirmation dialog.
    if (widget.nfcAvailable) _nfc.setWatchOverride(_onNfcCard);
  }

  @override
  void dispose() {
    if (widget.nfcAvailable) _nfc.clearWatchOverride();
    super.dispose();
  }

  void _onNfcCard(NfcCardData card) {
    if (!mounted || _busy) return;
    final session = context.read<GameProvider>();
    final ownership = session.ownershipOf(widget.propertyId);
    final iOwnIt = ownership?.ownerId == session.myPlayerId;

    // Owner-side POS: I own this property, so my open sheet is a payment
    // terminal — another player taps THEIR card on my device and the rent
    // is charged to their account, like tap-to-pay at a till.
    if (iOwnIt) {
      if (card is NfcPlayerCard && card.playerId != session.myPlayerId) {
        final payer = session.playerById(card.playerId);
        if (payer == null || payer.hasLeft) {
          setState(() => _error = 'That player is not in this game.');
          return;
        }
        _chargeRentFlow(payer);
      } else {
        setState(
          () => _error = "To collect rent, have the payer tap their own card.",
        );
      }
      return;
    }

    final matchesProperty =
        card is NfcPropertyCard && card.propertyId == widget.propertyId;
    final isMyCard =
        card is NfcPlayerCard && card.playerId == session.myPlayerId;
    if (!matchesProperty && !isMyCard) {
      setState(
        () => _error = "Tap this property's card or your own payment card.",
      );
      return;
    }
    if (!session.canResolve) {
      setState(() => _error = 'Buying and paying rent unlock on your turn.');
      return;
    }
    if (ownership == null) {
      _buyFlow();
    } else {
      _rentFlow();
    }
  }

  /// Owner-side POS: charge [payer] this property's rent after they tapped
  /// their card on my device. Their in-app roll powers utility rent; the
  /// server rejects the charge if I'm not the owner.
  Future<void> _chargeRentFlow(Player payer) async {
    final session = context.read<GameProvider>();
    final board = session.game?.board;
    final property = session.propertyById(widget.propertyId);
    if (board == null || property == null) return;

    final payerRoll = session.lastRoll?.playerId == payer.id
        ? session.lastRoll
        : null;
    int? dice = payerRoll?.total;
    if (property.kind == PropertyKind.utility && dice == null) {
      dice = await _askDiceTotal();
      if (dice == null) return;
    }
    if (!mounted) return;

    final rent = GameEngine.computeRent(
      board: board,
      ownerships: session.ownerships,
      propertyId: property.id,
      diceTotal: dice,
    );
    final rentDue = rent.isOk ? rent.requireValue : null;

    if (!await _confirm(
      'Charge ${payer.name}?',
      rentDue != null
          ? '${formatMoney(rentDue, board.currencySymbol)} will be '
                'collected from ${payer.name} — their card tap is the '
                'authorization.'
          : 'The rent will be collected from ${payer.name}.',
    )) {
      return;
    }
    await _run(
      () => session.payRent(property.id, diceTotal: dice, payerId: payer.id),
      success: 'Collected rent from ${payer.name}',
      resolved: true,
    );
  }

  Future<void> _buyFlow() async {
    final session = context.read<GameProvider>();
    final board = session.game?.board;
    final property = session.propertyById(widget.propertyId);
    if (board == null || property == null) return;

    if (!await _confirm(
      'Buy ${property.name}?',
      '${formatMoney(property.price, board.currencySymbol)} will be '
          'paid to the bank.',
    )) {
      return;
    }
    await _run(
      () => session.buyProperty(property.id),
      success: 'You bought ${property.name}',
      resolved: true,
    );
  }

  Future<void> _rentFlow() async {
    final session = context.read<GameProvider>();
    final board = session.game?.board;
    final property = session.propertyById(widget.propertyId);
    final ownership = session.ownershipOf(widget.propertyId);
    if (board == null || property == null || ownership == null) return;
    final ownerName =
        session.playerById(ownership.ownerId)?.name ?? 'the owner';

    final myRoll = session.lastRoll?.playerId == session.myPlayerId
        ? session.lastRoll
        : null;
    int? dice = myRoll?.total;
    if (property.kind == PropertyKind.utility && dice == null) {
      dice = await _askDiceTotal();
      if (dice == null) return;
    }
    if (!mounted) return;

    final rent = GameEngine.computeRent(
      board: board,
      ownerships: session.ownerships,
      propertyId: property.id,
      diceTotal: dice,
    );
    final rentDue = rent.isOk ? rent.requireValue : null;

    if (!await _confirm(
      'Pay rent?',
      rentDue != null
          ? '${formatMoney(rentDue, board.currencySymbol)} goes '
                'to $ownerName.'
          : 'The rent goes to $ownerName.',
    )) {
      return;
    }
    await _run(
      () => session.payRent(property.id, diceTotal: dice),
      success: 'Rent paid to $ownerName',
      resolved: true,
    );
  }

  /// Declines to buy the square I'm standing on, on my own turn, sending
  /// it to a live, table-held auction instead — the only way one starts
  /// (the server enforces both the turn and position check too).
  void _startAuction() {
    // A failed "Buy" attempt (usually why you're declining in the first
    // place — can't afford the list price) leaves its error showing here;
    // the AuctionCard replaces Buy/Decline in the same sheet instance
    // rather than reopening it, so that stale message would otherwise
    // linger underneath it for the rest of the auction, even once you go
    // on to actually win it at a bid you could afford.
    setState(() => _error = null);
    context.read<GameProvider>().startAuction(widget.propertyId);
  }

  /// Trade: pick another player and hand them this property. The deal's
  /// cash side (if any) is settled separately with Send.
  Future<void> _transferFlow() async {
    final session = context.read<GameProvider>();
    final property = session.propertyById(widget.propertyId);
    if (property == null) return;
    final others = session.otherActivePlayers;
    if (others.isEmpty) {
      setState(() => _error = 'No one to transfer to.');
      return;
    }

    final target = await showDialog<Player>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Transfer ${property.name} to…'),
        children: [
          for (final player in others)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, player),
              child: Row(
                children: [
                  PlayerAvatar(
                    player: player,
                    size: 36,
                    showPresence: false,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(player.name)),
                ],
              ),
            ),
        ],
      ),
    );
    if (target == null || !mounted) return;

    if (!await _confirm(
      'Transfer ${property.name}?',
      '${target.name} becomes the owner. If money is part of the deal, '
          'settle it separately with Send.',
    )) {
      return;
    }
    await _run(
      () => session.transferProperty(property.id, target.id),
      success: '${property.name} transferred to ${target.name}',
    );
  }

  /// Mortgage or lift the mortgage on my own property, with the usual
  /// confirmation. The bank pays the mortgage value; lifting costs +10%.
  Future<void> _mortgageFlow({required bool mortgage}) async {
    final session = context.read<GameProvider>();
    final board = session.game?.board;
    final property = session.propertyById(widget.propertyId);
    if (board == null || property == null) return;
    final currency = board.currencySymbol;
    final liftCost = GameEngine.mortgageLiftCost(property);

    if (!await _confirm(
      mortgage ? 'Mortgage ${property.name}?' : 'Lift the mortgage?',
      mortgage
          ? 'The bank pays you '
                '${formatMoney(property.mortgageValue, currency)}. No rent '
                'can be collected until you lift the mortgage for '
                '${formatMoney(liftCost, currency)}.'
          : '${formatMoney(liftCost, currency)} (value + 10% interest) '
                'will be paid to the bank.',
    )) {
      return;
    }
    await _run(
      () => session.setMortgaged(property.id, mortgage),
      success: mortgage
          ? '${property.name} mortgaged'
          : 'Mortgage lifted on ${property.name}',
    );
  }

  /// [resolved] marks actions that settle the landed-on square (buy, pay
  /// rent); the sheet pops with it so the screen underneath can close too.
  Future<void> _run(
    Future<Result<void>> Function() action, {
    String? success,
    bool resolved = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isOk) {
      Navigator.of(context).pop(resolved);
      if (success != null) {
        showSnack(context, success);
      }
    } else {
      // Snackbars hide behind the sheet — show the error inside it.
      setState(() => _error = result.error);
    }
  }

  /// Money leaves the account on confirmation only — never on a stray tap.
  Future<bool> _confirm(String title, String detail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<int?> _askDiceTotal() => showDialog<int>(
    context: context,
    builder: (dialogContext) {
      final controller = TextEditingController();
      return AlertDialog(
        title: const Text('Dice total'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'What did the dice show?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(controller.text.trim()),
            ),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameProvider>();
    final board = session.game?.board;
    final property = session.propertyById(widget.propertyId);
    if (board == null || property == null) {
      return const SizedBox(height: 200);
    }

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final currency = board.currencySymbol;
    final ownership = session.ownershipOf(property.id);
    final owner = ownership == null
        ? null
        : session.playerById(ownership.ownerId);
    final isMine = ownership?.ownerId == session.myPlayerId;
    // Turn rules: buying the square you're on and paying its rent are
    // landing effects — allowed the whole turn, before or after the roll.
    // Building is housekeeping: your turn, before you roll.
    final canAct = session.canAct;
    final canResolve = session.canResolve;
    final isStreet = property.kind == PropertyKind.street;
    // Building needs the whole color group owned — show the section only
    // once it'd actually work, rather than showing controls that just
    // error out when you don't have the monopoly yet.
    final ownsGroup =
        isStreet && GameEngine.ownsWholeGroup(board, session.ownerships, property);
    // A plain buy is only for the square you're actually standing on — a
    // table-held auction (below) is the exception, since its winner needn't
    // be the one who landed here. Boards with no curated layout track no
    // position at all, so the restriction doesn't apply to them.
    final onThisSquare =
        board.goIndex < 0 ||
        session.me?.position == board.properties.indexOf(property);

    // Live, not the frozen widget.decisionRequired the sheet was opened
    // with: a decision that was owed when this popped up (landing on an
    // unowned square) can get resolved out from under it by someone else —
    // most notably a table-held auction it turned into getting closed and
    // won. Without re-checking, the sheet stayed locked (no back button, no
    // tap-outside, no drag) even once there was nothing left to decide.
    final stillDecisionRequired =
        property.kind.isOwnable &&
        owner == null &&
        session.auctionFor(property.id) == null &&
        canResolve &&
        onThisSquare;

    return PopScope(
      canPop: !stillDecisionRequired,
      child: SafeArea(
        child: SingleChildScrollView(
          // No drag handle above this content when a decision is owed (see
          // showPropertySheet) — without its built-in spacing, the content
          // otherwise sits flush against the sheet's top edge. The bottom
          // inset grows with the keyboard: without it, the scroll viewport
          // never shrinks for the keyboard, so AuctionCard's own
          // Scrollable.ensureVisible has no obscured region to scroll the
          // bid field clear of — the keyboard just covers it in place.
          padding: EdgeInsets.fromLTRB(
            24,
            widget.decisionRequired ? 20 : 0,
            24,
            24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Color(property.colorValue),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          property.name,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          owner == null
                              ? 'Unowned · ${formatMoney(property.price, currency)}'
                              : 'Owned by ${isMine ? 'you' : owner.name} · '
                                    'Listed at '
                                    '${formatMoney(property.price, currency)}'
                                    '${(ownership?.mortgaged ?? false) ? ' · Mortgaged' : ''}',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.nfcAvailable)
                    IconButton(
                      tooltip: 'Write to NFC card',
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onWriteCard();
                      },
                      icon: const Icon(Icons.nfc_rounded),
                    ),
                  // The sheet was opened non-dismissible (no drag handle,
                  // no tap-outside) because a decision was owed at the
                  // time — once that's no longer true, an explicit close
                  // button is the only way out, since the modal route's
                  // own isDismissible/enableDrag were fixed at open time.
                  if (widget.decisionRequired && !stillDecisionRequired)
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _RentTable(property: property, currency: currency),
              const SizedBox(height: 20),
              if (owner == null) ...[
                if (session.auctionFor(property.id) case final auction?)
                  AuctionCard(auction: auction)
                else if (canResolve && onThisSquare) ...[
                  // Standing here, my turn: the official rule — buy it, or
                  // decline and it goes to auction, not just left unowned.
                  FilledButton.icon(
                    onPressed: !_busy ? _buyFlow : null,
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: Text(
                      'Buy for ${formatMoney(property.price, currency)}',
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Only one live auction at a table at a time — this one
                  // waits its turn if another is already running elsewhere
                  // (the server enforces this too).
                  OutlinedButton(
                    onPressed: !_busy && session.auctions.isEmpty
                        ? _startAuction
                        : null,
                    child: Text(
                      session.auctions.isEmpty
                          ? 'Decline — start an auction'
                          : 'Decline — an auction is already running',
                    ),
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: Text(
                      'Buy for ${formatMoney(property.price, currency)}',
                    ),
                  ),
                  if (canResolve) ...[
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        "You're not standing here — land on it to buy at "
                        'list price.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ] else if (!isMine && (ownership?.mortgaged ?? false))
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Mortgaged to the bank — no rent is due until '
                    '${owner.name} lifts the mortgage.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              else if (!isMine) ...[
                Builder(
                  builder: (context) {
                    // Preview the rent the server will charge. Utilities use
                    // my own in-app roll automatically; only when there is no
                    // roll of mine does a dice dialog appear.
                    final isUtility = property.kind == PropertyKind.utility;
                    final myRoll =
                        session.lastRoll?.playerId == session.myPlayerId
                        ? session.lastRoll
                        : null;
                    int? rentDue;
                    if (!isUtility || myRoll != null) {
                      final rent = GameEngine.computeRent(
                        board: board,
                        ownerships: session.ownerships,
                        propertyId: property.id,
                        diceTotal: myRoll?.total,
                      );
                      if (rent.isOk) rentDue = rent.requireValue;
                    }
                    // Still flagged in red as a heads-up, but no longer blocks
                    // paying — balances are allowed to go negative rather than
                    // leaving rent stuck unpayable.
                    final insufficient =
                        rentDue != null && rentDue > session.myBalance;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Rent due',
                                style: textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                rentDue != null
                                    ? formatMoney(rentDue, currency)
                                    : 'dice roll × multiplier',
                                style: textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Your balance '
                                '${formatMoney(session.myBalance, currency)}',
                                style: textTheme.bodySmall?.copyWith(
                                  color: insufficient
                                      ? AppColors.expense
                                      : scheme.onSurfaceVariant,
                                  fontWeight: insufficient
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: canResolve && !_busy && onThisSquare
                              ? _rentFlow
                              : null,
                          icon: const Icon(Icons.real_estate_agent_outlined),
                          label: Text(
                            rentDue != null
                                ? 'Pay ${formatMoney(rentDue, currency)} '
                                      'to ${owner.name}'
                                : 'Pay rent to ${owner.name}',
                          ),
                        ),
                        // Rent is only owed by whoever's actually on the
                        // square, same as a plain buy — boards with no
                        // curated layout track no position, so this only
                        // shows where the restriction actually applies.
                        if (canResolve && !onThisSquare) ...[
                          const SizedBox(height: 6),
                          Center(
                            child: Text(
                              "You're not standing here — land on it to "
                              'owe rent.',
                              textAlign: TextAlign.center,
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ] else if (isStreet && ownsGroup) ...[
                Text(
                  'Buildings',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed:
                          canAct && !_busy && (ownership?.houses ?? 0) > 0
                          ? () async {
                              final refund = property.housePrice ~/ 2;
                              if (!await _confirm(
                                'Sell a building?',
                                'The bank pays you back '
                                    '${formatMoney(refund, currency)}.',
                              )) {
                                return;
                              }
                              await _run(
                                () => session.setHouses(
                                  property.id,
                                  ownership!.houses - 1,
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          switch (ownership?.houses ?? 0) {
                            0 => 'No houses',
                            PropertyOwnership.hotel => 'Hotel',
                            final n => '$n house${n == 1 ? '' : 's'}',
                          },
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed:
                          canAct &&
                              !_busy &&
                              (ownership?.houses ?? 0) < PropertyOwnership.hotel
                          ? () async {
                              final next = ownership!.houses + 1;
                              if (!await _confirm(
                                next == PropertyOwnership.hotel
                                    ? 'Build a hotel?'
                                    : 'Build a house?',
                                '${formatMoney(property.housePrice, currency)} '
                                'will be paid to the bank.',
                              )) {
                                return;
                              }
                              await _run(
                                () => session.setHouses(property.id, next),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    'House ${formatMoney(property.housePrice, currency)} · '
                    'sells back for half',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ] else if (isStreet)
                Center(
                  child: Text(
                    'Own every street in this color group to build here.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Center(
                  child: Text(
                    'You own this. Rent is collected via Pay rent on the '
                    "payer's device.",
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              // Mortgaging is a bank move like sends/collects: allowed the
              // whole turn. Hidden when the board defines no mortgage value.
              if (isMine && property.mortgageValue > 0) ...[
                const SizedBox(height: 14),
                if (ownership?.mortgaged ?? false)
                  FilledButton.tonalIcon(
                    onPressed: canResolve && !_busy
                        ? () => _mortgageFlow(mortgage: false)
                        : null,
                    icon: const Icon(Icons.lock_open_rounded),
                    label: Text(
                      'Lift mortgage for '
                      '${formatMoney(GameEngine.mortgageLiftCost(property), currency)}',
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: canResolve && !_busy
                        ? () => _mortgageFlow(mortgage: true)
                        : null,
                    icon: const Icon(Icons.account_balance_outlined),
                    label: Text(
                      'Mortgage for '
                      '${formatMoney(property.mortgageValue, currency)}',
                    ),
                  ),
              ],
              // Trades happen at the table anytime; only the owner can hand
              // the deed over, so no turn gate — just a live connection.
              if (isMine) ...[
                const SizedBox(height: 4),
                Center(
                  child: TextButton.icon(
                    onPressed:
                        session.connection == ClientStatus.connected && !_busy
                        ? _transferFlow
                        : null,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Transfer to another player'),
                  ),
                ),
              ],
              // Only the owner benefits from an NFC hint here: buying or
              // paying rent already has a button right in front of whoever's
              // holding this phone, so tapping a card to trigger the same
              // action would be pointless. The owner's phone, though, doubles
              // as a payment terminal — another player taps their own card on
              // it to pay rent, so that's worth calling out.
              if (widget.nfcAvailable && isMine && owner != null) ...[
                const SizedBox(height: 10),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.nfc_rounded,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Have them tap their card here to charge rent',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (!canResolve && ownership?.ownerId != session.myPlayerId) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'Buying and paying rent unlock on your turn.',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              if (isMine && ownsGroup && !canAct) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'Buildings change on your turn, before you roll.',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.expense,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RentTable extends StatelessWidget {
  const _RentTable({required this.property, required this.currency});

  final Property property;
  final String currency;

  List<(String, String)> _rows() {
    final tiers = property.rentTiers;
    switch (property.kind) {
      case PropertyKind.street:
        const labels = [
          'Rent',
          'With 1 house',
          'With 2 houses',
          'With 3 houses',
          'With 4 houses',
          'With hotel',
        ];
        return [
          for (var i = 0; i < tiers.length && i < labels.length; i++)
            (labels[i], formatMoney(tiers[i], currency)),
        ];
      case PropertyKind.railroad:
        return [
          for (var i = 0; i < tiers.length; i++)
            ('Owning ${i + 1}', formatMoney(tiers[i], currency)),
        ];
      case PropertyKind.utility:
        return [
          for (var i = 0; i < tiers.length; i++)
            ('Owning ${i + 1}', '${tiers[i]} × dice'),
        ];
      case PropertyKind.go:
      case PropertyKind.jail:
      case PropertyKind.freeParking:
      case PropertyKind.goToJail:
      case PropertyKind.tax:
      case PropertyKind.chance:
      case PropertyKind.communityChest:
        return const []; // Unreachable: this sheet only opens for ownable kinds.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (final (label, value) in _rows())
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    value,
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          if (property.mortgageValue > 0 || property.housePrice > 0) ...[
            const Divider(height: 16),
            const SizedBox(height: 4),
            Row(
              children: [
                if (property.housePrice > 0)
                  Expanded(
                    child: Text(
                      'House ${formatMoney(property.housePrice, currency)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (property.mortgageValue > 0)
                  Text(
                    'Mortgage '
                    '${formatMoney(property.mortgageValue, currency)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
