import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import 'dart:math';

import '../models/board.dart';
import '../models/dice_roll.dart';
import '../models/game_transaction.dart';
import '../models/player.dart';
import '../models/result.dart';
import '../providers/boards_provider.dart';
import '../providers/game_provider.dart';
import '../services/game_client.dart';
import '../services/nfc_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import '../utils/snack.dart';
import '../widgets/activity_banner.dart';
import '../widgets/activity_feed.dart';
import '../widgets/auction_card.dart';
import '../widgets/balance_card.dart';
import '../widgets/board_layout_view.dart';
import '../widgets/player_avatar.dart';
import '../widgets/quick_action_button.dart';
import '../widgets/player_card_sheet.dart';
import '../widgets/receive_money_sheet.dart';
import '../widgets/section_header.dart';
import 'activity_screen.dart';
import 'dashboard_screen.dart';
import 'properties_screen.dart';
import 'scan_pay_screen.dart';
import 'send_money_screen.dart';

/// The in-game banking screen: balance, quick actions, players, live
/// activity feed. Backing out keeps the session running — the game stays
/// "Live" on the home screen.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  StreamSubscription<String>? _errorSub;
  StreamSubscription<CardDrawEvent>? _cardDrawSub;
  StreamSubscription<DiceRoll>? _diceRollSub;
  StreamSubscription<PropertyTransferEvent>? _transferSub;
  StreamSubscription<BankCollectionEvent>? _bankCollectionSub;
  StreamSubscription<BankCollectionEvent>? _bankPaymentSub;
  StreamSubscription<PaymentReceivedEvent>? _paymentReceivedSub;
  StreamSubscription<PropertyPurchaseEvent>? _purchaseSub;
  StreamSubscription<AuctionStartEvent>? _auctionStartSub;
  StreamSubscription<Player>? _playerJoinSub;
  StreamSubscription<JailEvent>? _jailEntrySub;
  StreamSubscription<OtherTransactionEvent>? _otherTxSub;
  final _nfc = NfcService.instance;
  bool _nfcAvailable = false;
  GameProvider? _session;
  bool _requestDialogOpen = false;
  // Whether the board sheet is currently showing, and the BuildContext of
  // its own route — needed to pop it from outside (the app-bar toggle)
  // since it's a real modal route, not a persistent Scaffold sheet.
  bool _boardSheetOpen = false;
  BuildContext? _boardSheetContext;

  // My own roll can trigger up to three popups in a row (the dice sheet
  // itself, a card reveal if I landed on Chance/Chest, and the auto-opened
  // property sheet) — chaining them here instead of firing independently
  // guarantees they show one at a time, in that order, instead of racing:
  // without this, the card/property reactions used to land on top of the
  // still-open dice sheet before I'd even seen the roll.
  Future<void> _rollUiChain = Future.value();
  // A card draw that's part of my own roll already re-checks the landed
  // square once its dialog closes — set so the roll's own listener doesn't
  // also trigger a second, redundant property auto-open for the same square.
  bool _cardHandledThisRoll = false;
  // Counts queued-but-not-yet-finished steps of _rollUiChain (dice sheet
  // dismissal, board reveal, the auto-opened property sheet). The server
  // un-rolls the turn the instant a double lands, well before this local
  // reveal sequence finishes — without this, "Roll dice" re-enables that
  // same instant and a fast tap can fire the bonus roll before the player
  // ever sees the property sheet for the throw that just landed.
  int _pendingRollUi = 0;

  void _enqueueRollUi(FutureOr<void> Function() action) {
    if (mounted) setState(() => _pendingRollUi++);
    _rollUiChain = _rollUiChain.then((_) async {
      if (!mounted) return;
      try {
        await action();
      } finally {
        if (mounted) setState(() => _pendingRollUi--);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final session = context.read<GameProvider>();
    _session = session;
    _errorSub = session.errors.listen((message) {
      if (!mounted) return;
      _snack(message);
    });
    _cardDrawSub = session.cardDraws.listen((event) {
      if (!mounted) return;
      final isMine = event.playerId == _session?.myPlayerId;
      if (isMine) _cardHandledThisRoll = true;
      // A "go to X"/"go back N" card moves the drawer — everything else
      // (money, a jail card, repairs) leaves position untouched, so there's
      // no landing to re-check once the dialog closes.
      final moved =
          event.card.moveToPropertyId != null ||
          (event.card.moveBySpaces ?? 0) != 0;
      _enqueueRollUi(() async {
        // The server resolves a landing (drawing its card) before it even
        // broadcasts the roll itself, so this reaches every other device
        // before the drawer has necessarily seen their own dice result —
        // there's no dice sheet to wait on here since it's never their own
        // roll. Waiting for the drawer's own dismissRoll signal (see
        // GameProvider.rollDismissals, sent right below) means everyone
        // else reveals the instant the drawer actually has, not a guessed
        // delay — with a generous timeout as a fallback in case that signal
        // never arrives (the drawer's app crashed, got backgrounded, lost
        // connection). This works the same whether the draw came from a
        // dice roll (this action is already queued behind that device's own
        // dice-sheet dismissal via _rollUiChain, so by the time it fires
        // here the sheet is already gone) or a manual Chance/Chest quick
        // action (nothing queued ahead of it, so it fires right away) — both
        // cases boil down to "the drawer's own dialog is about to show".
        // Matched by drawId, not playerId: the same player can draw more
        // than once in a turn, and a bare playerId can't tell those signals
        // apart. wasDismissed() is checked first because the signal itself
        // can easily have already arrived by the time this closure gets its
        // turn in the queue (e.g. a spam-drawn burst fires several dismiss
        // signals faster than the receiving device works through its
        // backlog) — rollDismissals is a live stream, so listening for an
        // event that already happened would otherwise just hang until the
        // fallback timeout below, once per queued draw.
        if (isMine) {
          _session?.dismissRoll(event.drawId);
        } else if (_session?.wasDismissed(event.drawId) != true) {
          await _session?.rollDismissals
              .firstWhere((id) => id == event.drawId)
              .timeout(const Duration(seconds: 10), onTimeout: () => '');
        }
        if (!mounted) return;
        await _showCardDialog(event);
        if (mounted && isMine && moved) await _afterRollReveal();
        _cardHandledThisRoll = false;
      });
    });
    // Every roll (anyone's) pops the board up so token movement is visible
    // wherever a player is looking — only on boards with a curated layout,
    // and only if it isn't already open. It's a real modal now — blocks the
    // rest of the screen like any other sheet — and stays open until
    // whoever's looking at it closes it themselves; no timer, no auto-close.
    _diceRollSub = session.diceRolls.listen((roll) {
      if (!mounted) return;
      final session = _session;
      final isMine = roll.playerId == session?.myPlayerId;
      final hasLayout = (session?.game?.board.goIndex ?? -1) >= 0;
      // A landing that draws a Chance/Chest card broadcasts the card
      // *before* the roll itself (the server resolves the landing inside
      // the same call that produces the roll broadcast), so the card
      // listener above already enqueued that dialog onto _rollUiChain by
      // the time this fires. Enqueuing the board open the same way — rather
      // than firing it immediately — keeps it from stacking on top of and
      // hiding that still-open card dialog; it simply takes its turn after.
      if (hasLayout && !isMine) {
        _enqueueRollUi(() {
          if (!_boardSheetOpen) return _openBoardSheet();
        });
      }
      // Only the roller sees the dice sheet (opened from the "Roll dice"
      // button) — everyone else needs their own heads-up that a roll just
      // happened and what it was, especially on boards with no curated
      // layout where the board popup above never fires at all.
      if (!isMine && session != null) {
        showActivityBanner(
          context,
          ActivityBannerData(
            icon: Icons.casino_rounded,
            tone: BannerTone.neutral,
            title: '${session.accountName(roll.playerId)} rolled the dice',
            meta: roll.isDouble ? 'Double!' : null,
            amountText: '🎲 ${roll.total}',
          ),
        );
      }
      // Only my own roll moves my own token — offer to buy/pay rent/build
      // right away instead of making the player dig through Properties.
      // Skipped when a card for this same roll already scheduled its own
      // check (see above) so the property sheet doesn't pop up twice.
      if (isMine) {
        if (_cardHandledThisRoll) {
          _cardHandledThisRoll = false;
        } else {
          _enqueueRollUi(_afterRollReveal);
        }
      }
    });
    // Someone handed a property directly to another player (not a
    // landing/buy). The recipient gets a full dialog, same as an incoming
    // money request; everyone else at the table (neither side of the
    // trade) just gets a banner, same as any other transaction that isn't
    // theirs.
    _transferSub = session.propertyTransfers.listen((event) {
      if (!mounted) return;
      final session = _session;
      if (session == null) return;
      if (event.toId != session.myPlayerId &&
          event.fromId != session.myPlayerId) {
        showActivityBanner(
          context,
          ActivityBannerData(
            icon: Icons.swap_horiz_rounded,
            tone: BannerTone.neutral,
            title:
                '${session.accountName(event.fromId)} transferred '
                '${session.propertyNameOf(event.propertyId)} to '
                '${session.accountName(event.toId)}',
          ),
        );
      }
      if (event.toId != session.myPlayerId) return;
      final property = session.propertyById(event.propertyId);
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Property received'),
          content: Text(
            '${session.accountName(event.fromId)} gave you '
            '${property?.name ?? 'a property'}.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    });
    // Anyone can collect from the bank — flag it to the rest of the table
    // as it happens instead of leaving it to surface later in Activity.
    _bankCollectionSub = session.bankCollections.listen((event) {
      if (!mounted || event.playerId == _session?.myPlayerId) return;
      final session = _session;
      if (session == null) return;
      final board = session.game?.board;
      if (board == null) return;
      showActivityBanner(
        context,
        ActivityBannerData(
          icon: Icons.account_balance_rounded,
          tone: BannerTone.neutral,
          title:
              '${session.accountName(event.playerId)} collected from '
              'the bank',
          amountText: formatMoney(event.amount, board.currencySymbol),
        ),
      );
    });
    // The reverse: paying the bank back — just as invisible to everyone
    // else otherwise, since it doesn't land in anyone's account.
    _bankPaymentSub = session.bankPayments.listen((event) {
      if (!mounted || event.playerId == _session?.myPlayerId) return;
      final session = _session;
      if (session == null) return;
      final board = session.game?.board;
      if (board == null) return;
      showActivityBanner(
        context,
        ActivityBannerData(
          icon: Icons.account_balance_rounded,
          tone: BannerTone.neutral,
          title: '${session.accountName(event.playerId)} paid the bank',
          amountText: formatMoney(event.amount, board.currencySymbol),
        ),
      );
    });
    // A direct payment landing in my account — worth a heads-up wherever
    // I'm looking, same idea as the bank-collection notice above.
    _paymentReceivedSub = session.paymentsReceived.listen((event) {
      if (!mounted) return;
      final session = _session;
      final board = session?.game?.board;
      if (session == null || board == null) return;
      showActivityBanner(
        context,
        ActivityBannerData(
          icon: event.isRent
              ? Icons.real_estate_agent_outlined
              : Icons.arrow_downward_rounded,
          tone: BannerTone.income,
          title: event.isRent
              ? '${session.accountName(event.fromId)} paid you rent'
              : '${session.accountName(event.fromId)} sent you money',
          amountText: formatSignedMoney(
            event.amount,
            board.currencySymbol,
            incoming: true,
          ),
        ),
      );
    });
    // Someone else bought a property — the properties list/board update
    // quietly on their own, so flag it the same way a bank collection is.
    _purchaseSub = session.propertyPurchases.listen((event) {
      if (!mounted) return;
      final session = _session;
      final board = session?.game?.board;
      if (session == null || board == null) return;
      showActivityBanner(
        context,
        ActivityBannerData(
          icon: Icons.home_work_rounded,
          tone: BannerTone.neutral,
          title:
              '${session.accountName(event.playerId)} bought '
              '${session.propertyNameOf(event.propertyId)}',
          amountText: formatMoney(event.amount, board.currencySymbol),
        ),
      );
    });
    // A live auction just opened — everyone sees the running AuctionCard,
    // but nothing else calls out that it started for whoever isn't already
    // looking at that spot on screen.
    _auctionStartSub = session.auctionStarts.listen((event) {
      if (!mounted) return;
      final session = _session;
      if (session == null) return;
      if (event.startedBy == session.myPlayerId) return;
      showActivityBanner(
        context,
        ActivityBannerData(
          icon: Icons.gavel_rounded,
          tone: BannerTone.neutral,
          title:
              '${session.accountName(event.startedBy)} started an '
              'auction for ${session.propertyNameOf(event.propertyId)}',
        ),
      );
    });
    // A new player took a seat — a reconnect of someone already known
    // doesn't fire this (see GameProvider.playerJoins).
    _playerJoinSub = session.playerJoins.listen((player) {
      if (!mounted) return;
      showActivityBanner(
        context,
        ActivityBannerData(
          icon: Icons.person_add_alt_1_rounded,
          tone: BannerTone.neutral,
          title: '${player.name} joined the table',
        ),
      );
    });
    // Landing in jail only ever happens to the roller themselves — this is
    // purely a heads-up for everyone else, who'd otherwise only notice from
    // the board or the activity feed.
    _jailEntrySub = session.jailEntries.listen((event) {
      if (!mounted) return;
      final session = _session;
      if (session == null || event.playerId == session.myPlayerId) return;
      showActivityBanner(
        context,
        ActivityBannerData(
          icon: Icons.lock_outline_rounded,
          tone: BannerTone.expense,
          title: '${session.accountName(event.playerId)} went to jail',
        ),
      );
    });
    // Everything else that moves money and isn't already covered by a more
    // specific notice above (salary, houses, mortgage, tax, Free Parking).
    _otherTxSub = session.otherTransactions.listen((event) {
      if (!mounted) return;
      final session = _session;
      final board = session?.game?.board;
      if (session == null || board == null) return;
      final tx = event.tx;
      final currency = board.currencySymbol;
      final amountText = formatMoney(tx.amount, currency);
      // Salary and tax can now fire for my own roll too (see
      // GameProvider._applyPayment) — "You" reads better than my own name.
      String who(String id) =>
          id == session.myPlayerId ? 'You' : session.accountName(id);
      final (icon, title) = switch (tx.type) {
        TransactionType.salary => (
          Icons.flag_rounded,
          '${who(tx.toId)} passed GO',
        ),
        TransactionType.house => (
          Icons.home_rounded,
          tx.fromId == Player.bankId
              ? '${session.accountName(tx.toId)} sold houses · '
                    '${session.propertyNameOf(tx.propertyId ?? '')}'
              : '${session.accountName(tx.fromId)} built on '
                    '${session.propertyNameOf(tx.propertyId ?? '')}',
        ),
        TransactionType.mortgage => (
          Icons.account_balance_outlined,
          tx.fromId == Player.bankId
              ? '${session.accountName(tx.toId)} mortgaged '
                    '${session.propertyNameOf(tx.propertyId ?? '')}'
              : '${session.accountName(tx.fromId)} lifted the mortgage '
                    'on ${session.propertyNameOf(tx.propertyId ?? '')}',
        ),
        TransactionType.tax => (
          Icons.receipt_long_outlined,
          '${who(tx.fromId)} paid tax',
        ),
        TransactionType.freeParking => (
          Icons.local_parking_rounded,
          '${session.accountName(tx.toId)} collected Free Parking',
        ),
        _ => (Icons.swap_horiz_rounded, 'A transaction happened'),
      };
      showActivityBanner(
        context,
        ActivityBannerData(
          icon: icon,
          tone: BannerTone.neutral,
          title: title,
          amountText: amountText,
        ),
      );
    });
    // Money requests pop as a dialog wherever the player currently is.
    session.addListener(_maybeShowRequestDialog);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowRequestDialog(),
    );
    _nfc.isAvailable().then((available) {
      if (!mounted) return;
      setState(() => _nfcAvailable = available);
      if (!available) return;
      // Keep a reader session open for the whole game: any Digipoly card
      // tapped just works, and Android's own tag UI stays out of the way.
      _nfc.startWatch(_onCardTapped);
    });
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _cardDrawSub?.cancel();
    _diceRollSub?.cancel();
    _transferSub?.cancel();
    _bankCollectionSub?.cancel();
    _bankPaymentSub?.cancel();
    _paymentReceivedSub?.cancel();
    _purchaseSub?.cancel();
    _auctionStartSub?.cancel();
    _playerJoinSub?.cancel();
    _jailEntrySub?.cancel();
    _otherTxSub?.cancel();
    _session?.removeListener(_maybeShowRequestDialog);
    _nfc.stopWatch();
    super.dispose();
  }

  /// After my own roll (or a card that moved me) has been revealed: show
  /// the board — so the move is actually seen — then, a couple of seconds
  /// after it pops up (not after it's closed — the board stays open behind
  /// it), open the landed property's sheet on top of it. The delay is what
  /// keeps this from reading as a trap the way an instant chain did in an
  /// earlier version: the player gets a moment to actually look at where
  /// their token landed on the board before the sheet appears.
  Future<void> _afterRollReveal() async {
    if (!mounted) return;
    if ((_session?.game?.board.goIndex ?? -1) < 0) return;
    _openBoardSheet();
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) _maybeOpenLandedProperty();
  }

  /// The app-bar toggle and the sheet's own close button: an explicit,
  /// player-driven open/close.
  void _toggleBoardSheetManually() {
    if (_boardSheetOpen) {
      final ctx = _boardSheetContext;
      if (ctx != null) Navigator.of(ctx).pop();
    } else {
      _openBoardSheet();
    }
  }

  /// Shows the board as a modal sheet — blocks the rest of the screen like
  /// any other sheet, dismissible by its own close button, a drag, or
  /// tapping outside — and stays open until that happens on any device that
  /// isn't dismissing it; no timer, no auto-close. The returned future
  /// completes once it's actually been closed, so callers can wait for the
  /// player to be done looking at it before showing anything else.
  Future<void> _openBoardSheet() {
    if (_boardSheetOpen) return Future.value();
    setState(() => _boardSheetOpen = true);
    final closed = showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        _boardSheetContext = sheetContext;
        return _BoardSheet(
          onClose: () => Navigator.of(sheetContext).pop(),
          nfcAvailable: _nfcAvailable,
        );
      },
    );
    return closed.whenComplete(() {
      _boardSheetContext = null;
      if (mounted) setState(() => _boardSheetOpen = false);
    });
  }

  /// After my own token moves (a roll, or a "go to X" card), pop the
  /// property sheet straight open if I landed on an ownable square — buy,
  /// pay rent or manage buildings without digging through Properties.
  void _maybeOpenLandedProperty() {
    if (!mounted) return;
    final session = _session;
    final board = session?.game?.board;
    final position = session?.me?.position;
    if (session == null || board == null || board.goIndex < 0) return;
    if (position == null ||
        position < 0 ||
        position >= board.properties.length) {
      return;
    }
    final square = board.properties[position];
    if (!square.kind.isOwnable) return;
    showPropertySheet(
      context,
      propertyId: square.id,
      nfcAvailable: _nfcAvailable,
    );
  }

  void _maybeShowRequestDialog() {
    if (!mounted || _requestDialogOpen) return;
    final session = _session;
    if (session == null || session.incomingRequest == null) return;
    _requestDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _IncomingRequestDialog(),
    ).whenComplete(() => _requestDialogOpen = false);
  }

  /// A card drawn at the table, revealed on every device.
  Future<void> _showCardDialog(CardDrawEvent event) {
    final session = context.read<GameProvider>();
    final board = session.game?.board;
    final who = event.playerId == session.myPlayerId
        ? 'You'
        : session.accountName(event.playerId);
    final deckName = event.deck == 'chest' ? 'Community Chest' : 'Chance';

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final textTheme = Theme.of(dialogContext).textTheme;
        // A repairs card has no fixed amount — the real bill is computed
        // server-side from the drawer's own buildings at draw time.
        final amount = event.chargedAmount ?? event.card.amount;
        return AlertDialog(
          title: Text('$who drew $deckName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                event.card.text,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (amount != 0 && board != null) ...[
                const SizedBox(height: 12),
                Text(
                  amount > 0
                      ? '+${formatMoney(amount, board.currencySymbol)}'
                      : '−${formatMoney(amount.abs(), board.currencySymbol)}',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: amount > 0 ? AppColors.income : AppColors.expense,
                  ),
                ),
              ],
              if (event.card.grantsJailCard) ...[
                const SizedBox(height: 12),
                Text(
                  who == 'You'
                      ? "Kept until you're in jail and choose to use it."
                      : 'Kept until used to get out of jail free.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    showSnack(context, message);
  }

  Future<void> _openSend({SendMode mode = SendMode.pay, String? toId}) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SendMoneyScreen(mode: mode, initialRecipientId: toId),
      ),
    );
    if (sent == true && mounted) {
      showSnack(
        context,
        switch (mode) {
          SendMode.pay => 'Payment sent',
          SendMode.collect => 'Collected',
          SendMode.request => 'Request paid',
        },
      );
    }
  }

  /// The "View all" link — browsing the full list is the one case that
  /// should still navigate there, unlike a single known property (see
  /// [showPropertySheet], used everywhere else in this screen).
  void _openPropertiesList() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PropertiesScreen()),
    );
  }

  /// Any Digipoly card touching the phone lands here from the always-on
  /// watch: a property card opens that property, a player card opens Send
  /// with them selected. Only fires while this screen is on top — screens
  /// pushed above (send, properties) have their own card affordances, and
  /// holding the card too long must not stack duplicate screens.
  void _onCardTapped(NfcCardData card) {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final session = context.read<GameProvider>();
    final board = session.game?.board;
    if (board == null) return;

    switch (card) {
      case NfcPropertyCard(:final boardId, :final propertyId):
        if (boardId != board.id) {
          _snack('This card belongs to a different board.');
        } else if (session.propertyById(propertyId) == null) {
          _snack('Property not found on this board.');
        } else {
          showPropertySheet(
            context,
            propertyId: propertyId,
            nfcAvailable: _nfcAvailable,
          );
        }
      case NfcPlayerCard(:final playerId):
        final player = session.playerById(playerId);
        if (player == null || player.hasLeft) {
          _snack('That player is not in this game.');
        } else if (playerId == session.myPlayerId) {
          _snack('That is your own card.');
        } else if (!session.canResolve) {
          _snack('You can pay when it is your turn.');
        } else {
          _openSend(toId: playerId);
        }
    }
  }

  void _showPlayerCard(Player player) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PlayerCardSheet(player: player),
    );
  }

  /// Long-press on a player bubble.
  Future<void> _showPlayerSheet(Player player) async {
    final session = context.read<GameProvider>();
    final isMe = player.id == session.myPlayerId;
    final connected = session.connection == ClientStatus.connected;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: PlayerAvatar(player: player, size: 40),
              title: Text(
                isMe ? 'You' : player.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const Divider(height: 1),
            if (!isMe) ...[
              ListTile(
                enabled: connected && !player.hasLeft,
                leading: const Icon(Icons.send_rounded),
                title: Text('Send money to ${player.name}'),
                onTap: () => Navigator.pop(sheetContext, 'send'),
              ),
              ListTile(
                enabled: connected && !player.hasLeft,
                leading: const Icon(Icons.currency_exchange_rounded),
                title: Text('Request money from ${player.name}'),
                onTap: () => Navigator.pop(sheetContext, 'request'),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.credit_card_rounded),
              title: const Text('Payment card'),
              subtitle: const Text(
                'View the card or register a physical NFC card',
              ),
              onTap: () => Navigator.pop(sheetContext, 'card'),
            ),
            // Host-only moderation — not turn-gated, doesn't touch money.
            if (!isMe && session.isHost) ...[
              if (player.hasLeft)
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded),
                  title: Text('Replace ${player.name}'),
                  subtitle: const Text(
                    'A new device takes over their balance and properties',
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'replace'),
                )
              else
                ListTile(
                  leading: const Icon(
                    Icons.person_remove_alt_1_rounded,
                    color: AppColors.expense,
                  ),
                  title: Text(
                    'Remove ${player.name} from the game',
                    style: const TextStyle(color: AppColors.expense),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'kick'),
                ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'send':
        _openSend(toId: player.id);
      case 'request':
        _openSend(mode: SendMode.request, toId: player.id);
      case 'card':
        _showPlayerCard(player);
      case 'kick':
        _kickPlayer(player);
      case 'replace':
        _showReplaceSheet(player);
    }
  }

  /// Host-only: removes another player from the game. Their balance and
  /// properties stay exactly as they were — same as if they'd left
  /// themselves — until someone claims the now-open seat (see
  /// [_showReplaceSheet]).
  Future<void> _kickPlayer(Player player) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${player.name}?'),
        content: Text(
          '${player.name} is removed from the table. Their balance and '
          'properties stay as they are — replace them from this menu '
          'later to hand the seat to someone else.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.expense,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    context.read<GameProvider>().kickPlayer(player.id);
  }

  /// Host-only: shares a join link/QR tagged to [player]'s now-open seat —
  /// a new device scanning or opening it takes over their balance and
  /// properties instead of joining as a fresh player.
  Future<void> _showReplaceSheet(Player player) async {
    final session = context.read<GameProvider>();
    final endpoint = session.isHost
        ? await session.roomEndpoint()
        : '${session.record?.hostAddress}:${session.record?.hostPort}';
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final textTheme = Theme.of(sheetContext).textTheme;
        final scheme = Theme.of(sheetContext).colorScheme;
        final claimUrl =
            endpoint == null ? null : 'http://$endpoint/?claim=${player.id}';
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replace ${player.name}',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Whoever scans this takes over ${player.name}\'s balance '
                  'and properties — not a fresh seat.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (claimUrl != null) ...[
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: claimUrl,
                        size: 190,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                InkWell(
                  onTap: claimUrl == null
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: claimUrl));
                          showActivityBanner(
                            sheetContext,
                            ActivityBannerData(
                              icon: Icons.copy_rounded,
                              tone: BannerTone.neutral,
                              title: 'Replace link copied',
                              meta: 'Send it to ${player.name}\'s '
                                  'replacement',
                            ),
                          );
                        },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      claimUrl ?? 'Address unavailable',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _rollDice() {
    final closed = showModalBottomSheet<void>(
      context: context,
      builder: (_) => const _DiceSheet(),
    );
    // Any card/property popup triggered by this roll is enqueued onto
    // _rollUiChain as its broadcast arrives (see initState) — queuing this
    // sheet's own dismissal first guarantees those wait their turn instead
    // of surfacing on top of a dice result the player hasn't seen yet.
    _enqueueRollUi(() => closed);
  }

  void _openReceive() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ReceiveMoneySheet(),
    );
  }

  void _openScan() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScanPayScreen()),
    );
  }

  Future<void> _payJailFine() async {
    final session = context.read<GameProvider>();
    final result = await session.payJailFine();
    if (!mounted) return;
    if (!result.isOk) showSnack(context, result.error!);
  }

  Future<void> _useJailCard() async {
    final session = context.read<GameProvider>();
    final result = await session.useJailCard();
    if (!mounted) return;
    if (!result.isOk) showSnack(context, result.error!);
  }

  Future<void> _passGo() async {
    final session = context.read<GameProvider>();
    final board = session.game?.board;
    if (board == null) return;

    // Landing exactly on GO doubles the salary (common house rule).
    final landed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('GO!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                'Passed GO · '
                '+${formatMoney(board.salary, board.currencySymbol)}',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                'Landed on GO · '
                '+${formatMoney(board.salary * 2, board.currencySymbol)}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (landed == null || !mounted) return;

    final result = await session.collectSalary(landedOnGo: landed);
    if (result.isOk && mounted) {
      showSnack(
        context,
        '+${formatMoney(board.salary * (landed ? 2 : 1), board.currencySymbol)} salary',
      );
    }
  }

  void _drawCard(String deck) {
    final session = context.read<GameProvider>();
    final board = session.game?.board;
    if (board == null) return;
    final cards = deck == 'chest'
        ? board.communityChestCards
        : board.chanceCards;
    if (cards.isEmpty) {
      _snack(
        'This board has no ${deck == 'chest' ? 'Community Chest' : 'Chance'} '
        'cards yet — add them in the board editor.',
      );
      return;
    }
    session.drawCard(deck);
  }

  Future<void> _saveBoardToMyBoards() async {
    final session = context.read<GameProvider>();
    final board = session.game?.board;
    if (board == null) return;

    final copy = Board.fromJson(
      board.toJson()..['id'] = const Uuid().v4(),
    );
    await context.read<BoardsProvider>().saveBoard(copy);
    if (mounted) {
      showSnack(context, '"${board.name}" saved to My Boards');
    }
  }

  Future<void> _showRoomInfo() async {
    final session = context.read<GameProvider>();
    final endpoint = session.isHost
        ? await session.roomEndpoint()
        : '${session.record?.hostAddress}:${session.record?.hostPort}';
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final textTheme = Theme.of(sheetContext).textTheme;
        final scheme = Theme.of(sheetContext).colorScheme;
        final joinUrl = endpoint == null ? null : 'http://$endpoint/';
        // The port never changes; players only ever need the IP.
        final displayAddress = endpoint?.split(':').first;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Room info',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                if (joinUrl != null) ...[
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: joinUrl,
                        size: 190,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                InkWell(
                  // Copies the full join link, not just the IP — the link
                  // works when pasted anywhere: a browser opens the web
                  // app, and the app's Join field accepts it too.
                  onTap: joinUrl == null
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: joinUrl));
                          // A regular snackbar anchors to the Scaffold below
                          // this sheet and ends up hidden behind it — the
                          // overlay-based activity banner stays visible
                          // instead, and shares the same stacking host as
                          // every other in-game notice (a dice roll, rent
                          // landing) so it doesn't sit at the same top:0
                          // spot as one of those and get silently covered.
                          showActivityBanner(
                            sheetContext,
                            const ActivityBannerData(
                              icon: Icons.copy_rounded,
                              tone: BannerTone.neutral,
                              title: 'Join link copied',
                              meta: 'Send it to the other players',
                            ),
                          );
                        },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              displayAddress ?? 'Address unavailable',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                            if (joinUrl != null) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.copy_rounded,
                                size: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
                          ],
                        ),
                        if (joinUrl != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            joinUrl,
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  session.isHost
                      ? 'Players on the same wifi find this room '
                            'automatically in Join, or scan the QR to open '
                            'the game in a browser — no install needed. '
                            'Tap the address to copy the join link.'
                      : 'This is where the host was last seen. Reopening '
                            'the game reconnects here.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _leaveGame() async {
    final session = context.read<GameProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave game?'),
        content: Text(
          session.isHost
              ? 'You are the host — leaving closes the room for everyone. '
                    'The game is removed from this device.'
              : 'You give up your seat and the game is removed from this '
                    'device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.expense,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await session.leaveGame();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameProvider>();
    final game = session.game;

    if (game == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(game.name),
        actions: [
          if (game.board.goIndex >= 0)
            IconButton(
              onPressed: _toggleBoardSheetManually,
              icon: Icon(
                Icons.grid_view_rounded,
                color: _boardSheetOpen
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: _boardSheetOpen ? 'Hide board' : 'Show board',
            ),
          IconButton(
            onPressed: _showRoomInfo,
            icon: const Icon(Icons.qr_code_rounded),
            tooltip: 'Room info',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'myCard':
                  final me = context.read<GameProvider>().me;
                  if (me != null) _showPlayerCard(me);
                case 'dashboard':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DashboardScreen()),
                  );
                case 'saveBoard':
                  _saveBoardToMyBoards();
                case 'leave':
                  _leaveGame();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'myCard',
                child: Text('My payment card'),
              ),
              const PopupMenuItem(
                value: 'dashboard',
                child: Text('Dashboard'),
              ),
              const PopupMenuItem(
                value: 'saveBoard',
                child: Text('Save board to My Boards'),
              ),
              const PopupMenuItem(
                value: 'leave',
                child: Text('Leave game'),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(context, session),
    );
  }

  /// Responsive: phones get one scrolling column; wide windows get the
  /// banking column on the left and the activity feed as its own pane.
  Widget _buildBody(BuildContext context, GameProvider session) {
    final game = session.game!;
    final board = game.board;
    final connected = session.connection == ClientStatus.connected;
    final canResolve = session.canResolve;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final transactions = session.transactions;
    final myProperties = session.propertiesOwnedBy(session.myPlayerId);
    final turnPlayer = session.currentTurnPlayer;

    List<Widget> mainChildren({required bool wide}) => <Widget>[
      BalanceCard(
        balance: session.myBalance,
        currencySymbol: board.currencySymbol,
        gameName: game.name,
        boardName: board.name,
        trailing: _ConnectionChip(
          status: session.connection,
          hostEnded: session.hostEnded,
          kicked: session.kicked,
        ),
        footer: turnPlayer == null
            ? null
            : _TurnChip(
                label: [
                  session.isMyTurn ? 'Your turn' : "${turnPlayer.name}'s turn",
                  if (session.lastRoll != null) '🎲 ${session.lastRoll!.total}',
                ].join(' · '),
                highlight: session.isMyTurn,
              ),
      ),
      // Auctions aren't turn-gated — anyone can be bidding at any time,
      // so they're visible to the whole table regardless of whose turn
      // it is.
      if (session.auctions.isNotEmpty) ...[
        const SizedBox(height: 14),
        for (final auction in session.auctions.values)
          AuctionCard(auction: auction),
      ],
      // A turn is roll → act → end; the controls only show up when
      // it's actually this player's move.
      if (session.isMyTurn) ...[
        const SizedBox(height: 14),
        if (session.me?.inJail == true) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    (session.me?.jailCards ?? 0) > 0
                        ? 'In jail — use your Get Out of Jail Free '
                              'card, pay '
                              '${formatMoney(board.jailFine, board.currencySymbol)}, '
                              'or roll for doubles.'
                        : 'In jail — pay '
                              '${formatMoney(board.jailFine, board.currencySymbol)} '
                              'to leave, or roll for doubles.',
                    style: textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 10),
                // Bare in a Row (no Expanded): the theme's default
                // minimumSize is Size.fromHeight (infinite width), so
                // both buttons need an explicit finite-width override
                // here or they crash the whole Row's layout.
                if ((session.me?.jailCards ?? 0) > 0) ...[
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                    onPressed: session.canUseJailCard ? _useJailCard : null,
                    child: const Text('Use card'),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                  ),
                  onPressed: session.canPayJailFine ? _payJailFine : null,
                  child: const Text('Pay'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                onPressed: session.canRoll && _pendingRollUi == 0
                    ? _rollDice
                    : null,
                icon: const Icon(Icons.casino_rounded),
                label: Text(
                  session.turnRolled
                      ? 'Rolled ${session.lastRoll?.total ?? ''}'
                      // A double by me with the turn still un-rolled
                      // means the server granted another throw.
                      : session.lastRoll?.isDouble == true &&
                            session.lastRoll?.playerId == session.myPlayerId
                      ? 'Double — roll again'
                      : 'Roll dice',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                onPressed: session.canEndTurn ? session.endTurn : null,
                icon: const Icon(Icons.skip_next_rounded),
                label: const Text('End turn'),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 22),
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: wide ? 8 : 4,
          // Fixed cell height: the buttons keep their size instead of
          // scaling with the window width.
          mainAxisExtent: 104,
          mainAxisSpacing: 10,
        ),
        // Money moves work the whole turn — before or after the roll —
        // so landing effects (taxes, card payments) are payable right
        // away; Request and Receive are never turn-gated.
        children: [
          QuickActionButton(
            icon: Icons.send_rounded,
            label: 'Send',
            emphasized: true,
            onTap: canResolve ? () => _openSend() : null,
          ),
          QuickActionButton(
            icon: Icons.currency_exchange_rounded,
            label: 'Request',
            onTap: connected ? () => _openSend(mode: SendMode.request) : null,
          ),
          if (canScanQr)
            QuickActionButton(
              icon: Icons.qr_code_scanner_rounded,
              label: 'Scan & pay',
              // Not turn-gated: someone else's payment QR is the same
              // "you're being asked to pay" situation as a money
              // request, which is never turn-gated either.
              onTap: connected ? _openScan : null,
            ),
          QuickActionButton(
            icon: Icons.qr_code_2_rounded,
            label: 'Receive',
            onTap: connected ? _openReceive : null,
          ),
          // Once a board has a curated layout, landing on/passing GO
          // pays out automatically — this manual trigger would only
          // ever double-pay, so it's only offered without one.
          if (board.goIndex < 0)
            QuickActionButton(
              icon: Icons.flag_rounded,
              label: 'Pass GO',
              onTap: canResolve ? _passGo : null,
            ),
          QuickActionButton(
            icon: Icons.south_west_rounded,
            label: 'Collect',
            onTap: canResolve ? () => _openSend(mode: SendMode.collect) : null,
          ),
          QuickActionButton(
            icon: Icons.style_rounded,
            label: 'Chance',
            onTap: canResolve ? () => _drawCard('chance') : null,
          ),
          QuickActionButton(
            icon: Icons.inventory_2_outlined,
            label: 'Chest',
            onTap: canResolve ? () => _drawCard('chest') : null,
          ),
        ],
      ),
      const SizedBox(height: 22),
      const SectionHeader(title: 'Players'),
      SizedBox(
        height: 112,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: session.players.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final player = session.players[index];
            final isMe = player.id == session.myPlayerId;
            final isTurn = player.id == session.currentTurnId;
            return GestureDetector(
              onTap: !isMe && !player.hasLeft && canResolve
                  ? () => _openSend(toId: player.id)
                  : null,
              onLongPress: () => _showPlayerSheet(player),
              child: SizedBox(
                width: 64,
                child: Column(
                  children: [
                    PlayerAvatar(
                      player: player,
                      size: 54,
                      highlight: isTurn,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isMe ? 'You' : player.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      formatMoney(
                        player.balance,
                        board.currencySymbol,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: player.balance < 0
                            ? AppColors.expense
                            : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 18),
      SectionHeader(
        title: 'Properties',
        trailing: TextButton(
          onPressed: _openPropertiesList,
          child: const Text('View all'),
        ),
      ),
      InkWell(
        onTap: _openPropertiesList,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
          ),
          child: myProperties.isEmpty
              ? Text(
                  'You own nothing yet. Landed somewhere nice? '
                  'Buy it here.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final property in myProperties)
                      Tooltip(
                        message: property.name,
                        child: Container(
                          width: 14,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Color(property.colorValue),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    ];

    List<Widget> activitySection(int limit) => [
      SectionHeader(
        title: 'Activity',
        trailing: transactions.isEmpty
            ? null
            : TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ActivityScreen()),
                ),
                child: const Text('View all'),
              ),
      ),
      if (transactions.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No transactions yet.\nSend the first payment to get going.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        )
      else
        ...buildActivityFeed(context, session, limit: limit),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          // Wide window: the banking column stretches across the window,
          // with the activity feed as a proportional side pane.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  children: mainChildren(wide: true),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 3,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 24, 32),
                  children: activitySection(40),
                ),
              ),
            ],
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                ...mainChildren(wide: false),
                const SizedBox(height: 16),
                ...activitySection(10),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A compact modal panel showing the board and every token — pops up
/// automatically on any roll (see `_diceRollSub` in [_GameScreenState]) and
/// toggles via the app-bar button. Dismissible like any other sheet (its
/// own close button, a drag, or tapping outside).
class _BoardSheet extends StatelessWidget {
  const _BoardSheet({required this.onClose, required this.nfcAvailable});

  final VoidCallback onClose;
  final bool nfcAvailable;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameProvider>();
    final board = session.game?.board;
    if (board == null) return const SizedBox.shrink();

    // Capped by height as well as width — on a short window (resized down,
    // split-screen) the 1:1 board tied only to width would otherwise still
    // force itself taller than the sheet has room for and overflow off the
    // bottom; AspectRatio inside shrinks to whichever bound is tighter. The
    // outer scroll view is a last-resort fallback for anything still too
    // tall (title row included) rather than a way to pan/zoom the board
    // itself, which stays a static FittedBox.
    final maxBoardHeight = (MediaQuery.sizeOf(context).height * 0.8 - 90).clamp(
      160.0,
      420.0,
    );

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Board',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Hide board',
                ),
              ],
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: maxBoardHeight,
              ),
              child: BoardLayoutView(
                board: board,
                players: session.players,
                ownerships: session.ownerships,
                freeParkingPot: session.freeParkingPot,
                onTapProperty: (property) => showPropertySheet(
                  context,
                  propertyId: property.id,
                  nfcAvailable: nfcAvailable,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pill on the balance card's lower right corner showing whose
/// turn it is.
class _TurnChip extends StatelessWidget {
  const _TurnChip({required this.label, required this.highlight});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlight ? Colors.white : Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.casino_rounded,
            size: 14,
            color: highlight ? AppColors.accent : Colors.white70,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: highlight ? AppColors.accent : Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// The table's dice. Rolls are made by the server — one per turn, only by
/// the player whose turn it is — and every device sees the same result.
class _DiceSheet extends StatefulWidget {
  const _DiceSheet();

  @override
  State<_DiceSheet> createState() => _DiceSheetState();
}

class _DiceSheetState extends State<_DiceSheet> {
  final _random = Random();
  Timer? _spinner;
  bool _rolling = false;
  int _spin1 = 1;
  int _spin2 = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = context.read<GameProvider>();
      if (session.canRoll) _roll(session);
    });
  }

  @override
  void dispose() {
    _spinner?.cancel();
    super.dispose();
  }

  Future<void> _roll(GameProvider session) async {
    if (_rolling) return;
    setState(() => _rolling = true);
    // Shuffle the faces while the server decides the real result.
    _spinner = Timer.periodic(const Duration(milliseconds: 70), (_) {
      setState(() {
        _spin1 = _random.nextInt(6) + 1;
        _spin2 = _random.nextInt(6) + 1;
      });
    });
    final result = await session.rollDice();
    _spinner?.cancel();
    if (!mounted) return;
    setState(() => _rolling = false);
    if (!result.isOk) {
      showSnack(context, result.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameProvider>();
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final roll = session.lastRoll;
    final turnPlayer = session.currentTurnPlayer;

    final die1 = _rolling ? _spin1 : roll?.die1 ?? 0;
    final die2 = _rolling ? _spin2 : roll?.die2 ?? 0;

    final String label;
    if (_rolling) {
      label = '…';
    } else if (roll == null) {
      label = 'No roll yet';
    } else {
      final who = roll.playerId == session.myPlayerId
          ? 'You'
          : session.accountName(roll.playerId);
      label = '$who rolled ${roll.total}${roll.isDouble ? ' — double!' : ''}';
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Die(value: die1),
                const SizedBox(width: 20),
                _Die(value: die2),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            if (!_rolling)
              Text(
                roll != null &&
                        roll.isDouble &&
                        roll.playerId == session.myPlayerId &&
                        session.canRoll
                    ? 'Doubles! Close this and roll again.'
                    : session.isMyTurn
                    ? 'Take your actions, then end your turn.'
                    : turnPlayer == null
                    ? ''
                    : "It's ${turnPlayer.name}'s turn to roll.",
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Die extends StatelessWidget {
  const _Die({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Pip layout per face on a 3x3 grid.
    const pips = <int, List<int>>{
      1: [4],
      2: [0, 8],
      3: [0, 4, 8],
      4: [0, 2, 6, 8],
      5: [0, 2, 4, 6, 8],
      6: [0, 2, 3, 5, 6, 8],
    };

    return Container(
      width: 84,
      height: 84,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: GridView.count(
        crossAxisCount: 3,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 9; i++)
            Center(
              child: (pips[value] ?? const []).contains(i)
                  ? Container(
                      width: 13,
                      height: 13,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

/// Another player asked me for money — shown as a dialog so it reaches the
/// player wherever they are in the app. Auto-closes when the request is
/// settled from anywhere (paid, declined, or withdrawn by the requester).
class _IncomingRequestDialog extends StatefulWidget {
  const _IncomingRequestDialog();

  @override
  State<_IncomingRequestDialog> createState() => _IncomingRequestDialogState();
}

class _IncomingRequestDialogState extends State<_IncomingRequestDialog> {
  bool _paying = false;
  String? _error;

  Future<void> _respond(bool accept) async {
    if (_paying) return;
    final session = context.read<GameProvider>();
    setState(() {
      _paying = accept;
      _error = null;
    });
    final result = await session.respondToIncomingRequest(accept: accept);
    if (!mounted) return;
    setState(() {
      _paying = false;
      // On success the provider clears the request and build pops us.
      if (!result.isOk) _error = result.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameProvider>();
    final request = session.incomingRequest;
    final board = session.game?.board;
    if (request == null || board == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    final requester = session.playerById(request.requesterId);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          if (requester != null) ...[
            PlayerAvatar(player: requester, size: 36, showPresence: false),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              '${session.accountName(request.requesterId)} requests',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatMoney(request.amount, board.currencySymbol),
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          if (request.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              request.note,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Your balance ${formatMoney(session.myBalance, board.currencySymbol)}',
            style: textTheme.bodySmall?.copyWith(
              color: request.amount > session.myBalance
                  ? AppColors.expense
                  : scheme.onSurfaceVariant,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: AppColors.expense),
            ),
          ],
        ],
      ),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _paying ? null : () => _respond(false),
          child: const Text('Decline'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _paying ? null : () => _respond(true),
          child: _paying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'Pay ${formatMoney(request.amount, board.currencySymbol)}',
                ),
        ),
      ],
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({
    required this.status,
    required this.hostEnded,
    required this.kicked,
  });

  final ClientStatus status;
  final bool hostEnded;
  final bool kicked;

  @override
  Widget build(BuildContext context) {
    final (label, color) = kicked
        ? ('Removed', Colors.white70)
        : hostEnded
        ? ('Ended', Colors.white70)
        : switch (status) {
            ClientStatus.connected => ('Live', AppColors.income),
            ClientStatus.connecting => ('Connecting…', Colors.amber),
            ClientStatus.disconnected => ('Offline', Colors.white70),
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
