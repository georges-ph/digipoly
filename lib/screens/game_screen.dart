import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import 'dart:math';

import '../models/board.dart';
import '../models/dice_roll.dart';
import '../models/player.dart';
import '../models/result.dart';
import '../providers/boards_provider.dart';
import '../providers/game_provider.dart';
import '../services/game_client.dart';
import '../services/nfc_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import '../utils/snack.dart';
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
  final _nfc = NfcService.instance;
  GameProvider? _session;
  bool _requestDialogOpen = false;
  PersistentBottomSheetController? _boardSheetController;

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

  void _enqueueRollUi(FutureOr<void> Function() action) {
    _rollUiChain = _rollUiChain.then((_) {
      if (!mounted) return null;
      return action();
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
      _enqueueRollUi(() => _showCardDialog(event).then((_) {
            // A "go to X" card moved me — offer the same landing actions as
            // a normal roll once the reveal dialog is out of the way.
            if (mounted && isMine) _maybeOpenLandedProperty();
            _cardHandledThisRoll = false;
          }));
    });
    // Every roll (anyone's) pops the board up so token movement is visible
    // wherever a player is looking — only on boards with a curated layout,
    // and only if it isn't already open. Non-modal, so it's fine to show
    // immediately rather than queuing behind the dice/card popups above.
    _diceRollSub = session.diceRolls.listen((roll) {
      if (!mounted) return;
      if (_boardSheetController == null &&
          (_session?.game?.board.goIndex ?? -1) >= 0) {
        _toggleBoardSheet();
      }
      // Only my own roll moves my own token — offer to buy/pay rent/build
      // right away instead of making the player dig through Properties.
      // Skipped when a card for this same roll already scheduled its own
      // check (see above) so the property sheet doesn't pop up twice.
      if (roll.playerId == _session?.myPlayerId) {
        if (_cardHandledThisRoll) {
          _cardHandledThisRoll = false;
        } else {
          _enqueueRollUi(_maybeOpenLandedProperty);
        }
      }
    });
    // Money requests pop as a dialog wherever the player currently is.
    session.addListener(_maybeShowRequestDialog);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowRequestDialog(),
    );
    _nfc.isAvailable().then((available) {
      if (!mounted || !available) return;
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
    _session?.removeListener(_maybeShowRequestDialog);
    _nfc.stopWatch();
    super.dispose();
  }

  /// Shows/hides the board as a non-modal panel docked to the bottom of the
  /// screen — stays out of the way of the rest of the app, and (unlike a
  /// modal sheet) doesn't get dismissed by tapping elsewhere.
  void _toggleBoardSheet() {
    final controller = _boardSheetController;
    if (controller != null) {
      controller.close();
      return;
    }
    final opened = _scaffoldKey.currentState?.showBottomSheet(
      (_) => _BoardSheet(onClose: _toggleBoardSheet),
    );
    if (opened == null) return;
    setState(() => _boardSheetController = opened);
    opened.closed.whenComplete(() {
      if (mounted) setState(() => _boardSheetController = null);
    });
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
    final deckName =
        event.deck == 'chest' ? 'Community Chest' : 'Chance';

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final textTheme = Theme.of(dialogContext).textTheme;
        final amount = event.card.amount;
        return AlertDialog(
          title: Text('$who drew $deckName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                event.card.text,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (amount != 0 && board != null) ...[
                const SizedBox(height: 12),
                Text(
                  amount > 0
                      ? '+${formatMoney(amount, board.currencySymbol)}'
                      : '−${formatMoney(amount.abs(), board.currencySymbol)}',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color:
                        amount > 0 ? AppColors.income : AppColors.expense,
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

  void _openProperties({String? propertyId}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertiesScreen(openPropertyId: propertyId),
      ),
    );
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
    _openProperties(propertyId: square.id);
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
          _openProperties(propertyId: propertyId);
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
    }
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
    final cards =
        deck == 'chest' ? board.communityChestCards : board.chanceCards;
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
                  style: textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
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
                          showSnack(
                              context,
                              'Join link copied — send it to the other '
                              'players');
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
                              Icon(Icons.copy_rounded,
                                  size: 16,
                                  color: scheme.onSurfaceVariant),
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
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
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
              onPressed: _toggleBoardSheet,
              icon: Icon(
                Icons.grid_view_rounded,
                color: _boardSheetController == null
                    ? null
                    : Theme.of(context).colorScheme.primary,
              ),
              tooltip: _boardSheetController == null
                  ? 'Show board'
                  : 'Hide board',
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
                    MaterialPageRoute(
                        builder: (_) => const DashboardScreen()),
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
            ),
            footer: turnPlayer == null
                ? null
                : _TurnChip(
                    label: [
                      session.isMyTurn
                          ? 'Your turn'
                          : "${turnPlayer.name}'s turn",
                      if (session.lastRoll != null)
                        '🎲 ${session.lastRoll!.total}',
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
                        'In jail — pay '
                        '${formatMoney(board.jailFine, board.currencySymbol)} '
                        'to leave, or roll for doubles.',
                        style: textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed:
                          session.canPayJailFine ? _payJailFine : null,
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
                    onPressed: session.canRoll ? _rollDice : null,
                    icon: const Icon(Icons.casino_rounded),
                    label: Text(
                      session.turnRolled
                          ? 'Rolled ${session.lastRoll?.total ?? ''}'
                          // A double by me with the turn still un-rolled
                          // means the server granted another throw.
                          : session.lastRoll?.isDouble == true &&
                                  session.lastRoll?.playerId ==
                                      session.myPlayerId
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
                    onPressed:
                        session.canEndTurn ? session.endTurn : null,
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
                onTap: connected
                    ? () => _openSend(mode: SendMode.request)
                    : null,
              ),
              if (canScanQr)
                QuickActionButton(
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Scan & pay',
                  onTap: canResolve ? _openScan : null,
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
                onTap: canResolve
                    ? () => _openSend(mode: SendMode.collect)
                    : null,
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
              separatorBuilder: (_, _) => const SizedBox(width: 14),
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
                    width: 72,
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
                            color: scheme.onSurfaceVariant,
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
              onPressed: _openProperties,
              child: const Text('View all'),
            ),
          ),
          InkWell(
            onTap: _openProperties,
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
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
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
                      MaterialPageRoute(
                          builder: (_) => const ActivityScreen()),
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
                style: textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
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

/// A compact, non-modal panel showing the board and every token — pops up
/// automatically on any roll (see `_diceRollSub` in [_GameScreenState]) and
/// toggles via the app-bar button. Non-modal so it doesn't block the rest
/// of the screen or get dismissed by tapping elsewhere.
class _BoardSheet extends StatelessWidget {
  const _BoardSheet({required this.onClose});

  // Persistent (non-modal) bottom sheets aren't on the Navigator stack —
  // there's no route to pop — so closing goes through the controller in
  // [_GameScreenState] instead.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameProvider>();
    final board = session.game?.board;
    if (board == null) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Board',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Hide board',
                ),
              ],
            ),
            // Capped so the 1:1 aspect ratio can't force the board taller
            // than the sheet has room for on a wide (e.g. maximized
            // Windows) window — it ties height to width.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: BoardLayoutView(
                board: board,
                players: session.players,
                ownerships: session.ownerships,
                onTapProperty: (property) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PropertiesScreen(openPropertyId: property.id),
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
        color: highlight
            ? Colors.white
            : Colors.black.withValues(alpha: 0.22),
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
              style: textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            if (session.canRoll || _rolling)
              FilledButton.icon(
                onPressed: _rolling ? null : () => _roll(session),
                icon: const Icon(Icons.casino_rounded),
                label: const Text('Roll'),
              )
            else
              Text(
                session.isMyTurn
                    ? 'Take your actions, then end your turn.'
                    : turnPlayer == null
                        ? ''
                        : "It's ${turnPlayer.name}'s turn to roll.",
                textAlign: TextAlign.center,
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
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
  State<_IncomingRequestDialog> createState() =>
      _IncomingRequestDialogState();
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
              style: textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
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
              style: textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
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
  const _ConnectionChip({required this.status, required this.hostEnded});

  final ClientStatus status;
  final bool hostEnded;

  @override
  Widget build(BuildContext context) {
    final (label, color) = hostEnded
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
