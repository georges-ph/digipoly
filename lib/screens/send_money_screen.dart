import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player.dart';
import '../models/result.dart';
import '../providers/game_provider.dart';
import '../services/game_client.dart';
import '../services/nfc_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import '../utils/snack.dart';
import '../widgets/amount_keypad.dart';
import '../widgets/player_avatar.dart';

enum SendMode {
  /// Me paying another player or the bank.
  pay,

  /// The bank paying me (card rewards, refunds — Pass GO has its own
  /// shortcut).
  collect,

  /// Me asking another player for money; they approve on their device.
  request,
}

/// The payment flow: pick recipient, type amount on the keypad, send.
/// Pops with `true` when the server confirmed the transaction.
class SendMoneyScreen extends StatefulWidget {
  const SendMoneyScreen({
    super.key,
    this.mode = SendMode.pay,
    this.initialRecipientId,
    this.initialAmount = 0,
  });

  final SendMode mode;
  final String? initialRecipientId;

  /// Prefilled amount (from a scanned payment QR); still editable.
  final int initialAmount;

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  late String _recipientId =
      widget.initialRecipientId ?? Player.bankId;
  late int _amount = widget.initialAmount;
  final _noteController = TextEditingController();
  bool _sending = false;
  bool _initializedRecipient = false;
  final _nfc = NfcService.instance;
  bool _nfcAvailable = false;
  GameProvider? _session;

  @override
  void initState() {
    super.initState();
    _session = context.read<GameProvider>();
    if (widget.mode != SendMode.collect) {
      _nfc.isAvailable().then((available) {
        if (mounted) setState(() => _nfcAvailable = available);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Requests go to players, never the bank — default to the first one.
    if (!_initializedRecipient) {
      _initializedRecipient = true;
      if (widget.mode == SendMode.request &&
          widget.initialRecipientId == null) {
        final others = context.read<GameProvider>().otherActivePlayers;
        if (others.isNotEmpty) _recipientId = others.first.id;
      }
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    showSnack(context, message);
  }

  /// Tap another player's payment card to select them as the recipient.
  Future<void> _pickRecipientByCard() async {
    final session = context.read<GameProvider>();

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
            Expanded(child: Text("Hold the player's card near the device…")),
          ],
        ),
        actions: [
          TextButton(
            // Cancelling resolves the pending read; this flow closes the
            // dialog when it completes.
            onPressed: _nfc.cancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    final result = await _nfc.readText();
    if (mounted) Navigator.of(context).pop();
    if (!mounted || result.error == NfcService.cancelled) return;

    if (!result.isOk) {
      _snack(result.error!);
      return;
    }
    final card = NfcService.parsePayload(result.requireValue);
    if (card is! NfcPlayerCard) {
      _snack('Not a player card.');
      return;
    }
    final player = session.playerById(card.playerId);
    if (player == null || player.hasLeft) {
      _snack('That player is not in this game.');
      return;
    }
    if (player.id == session.myPlayerId) {
      _snack('That is your own card.');
      return;
    }
    setState(() => _recipientId = player.id);

    // Tap-to-pay: amount already on screen + card tapped = confirm and go.
    if (widget.mode == SendMode.pay && _amount > 0) {
      final board = session.game?.board;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Pay ${player.name}?'),
          content: Text(
            '${formatMoney(_amount, board?.currencySymbol ?? r'$')} '
            'will be sent to ${player.name}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Pay'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) await _submit();
    }
  }

  @override
  void dispose() {
    _nfc.cancel();
    // Backing out of a pending request withdraws it, so the other player's
    // approval prompt doesn't linger.
    if (widget.mode == SendMode.request) {
      _session?.cancelOutgoingRequest();
    }
    _noteController.dispose();
    super.dispose();
  }

  /// Paying someone directly moves real money with one tap — confirm first,
  /// same as the NFC tap-to-pay flow already does. Collecting from the
  /// bank and requesting money skip this: a collect is already flagged to
  /// the rest of the table as it happens, and a request doesn't move money
  /// until the other side accepts it.
  Future<void> _confirmAndSubmit() async {
    if (widget.mode != SendMode.pay) return _submit();
    final session = context.read<GameProvider>();
    final board = session.game?.board;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Pay ${session.accountName(_recipientId)}?'),
        content: Text(
          '${formatMoney(_amount, board?.currencySymbol ?? r'$')} '
          'will be sent to ${session.accountName(_recipientId)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Pay'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _submit();
  }

  Future<void> _submit() async {
    if (_amount <= 0 || _sending) return;
    final session = context.read<GameProvider>();
    final note = _noteController.text.trim();
    setState(() => _sending = true);

    final result = switch (widget.mode) {
      SendMode.pay => await session.sendPayment(
          toId: _recipientId,
          amount: _amount,
          note: note,
        ),
      SendMode.collect => await session.sendPayment(
          fromId: Player.bankId,
          toId: session.myPlayerId,
          amount: _amount,
          note: note,
        ),
      // Blocks until the other player answers on their device.
      SendMode.request => await session.requestMoney(
          targetId: _recipientId,
          amount: _amount,
          note: note,
        ),
    };

    if (!mounted) return;
    setState(() => _sending = false);

    if (result.isOk) {
      Navigator.of(context).pop(true);
    } else {
      showSnack(context, result.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameProvider>();
    final board = session.game?.board;
    final symbol = board?.currencySymbol ?? r'$';
    final isPay = widget.mode == SendMode.pay;
    final isRequest = widget.mode == SendMode.request;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final hasValidRecipient =
        !isRequest || _recipientId != Player.bankId;
    final targetBalance =
        isRequest ? session.playerById(_recipientId)?.balance : null;

    // Block overdrafts locally too (the server rejects them anyway): my
    // balance when paying, theirs when requesting. Paying and collecting
    // work the whole turn — before or after the roll, so taxes and card
    // effects are payable right after landing — while requests are allowed
    // anytime, like showing a Receive code.
    final turnOk = isRequest
        ? session.connection == ClientStatus.connected
        : session.canResolve;
    // The system keyboard (note field) and the amount keypad never show
    // together: the keyboard's inset would overflow the fixed column, and
    // you can't type in both places at once anyway.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final canSend = _amount > 0 &&
        !_sending &&
        hasValidRecipient &&
        turnOk &&
        (!isPay || _amount <= session.myBalance) &&
        (targetBalance == null || _amount <= targetBalance);

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (widget.mode) {
          SendMode.pay => 'Send money',
          SendMode.collect => 'Collect from bank',
          SendMode.request => 'Request money',
        }),
        actions: [
          if (_nfcAvailable && !_sending)
            IconButton(
              onPressed: _pickRecipientByCard,
              icon: const Icon(Icons.nfc_rounded),
              tooltip: "Tap a player's card",
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
          children: [
            if (isPay || isRequest)
              SizedBox(
                height: 100,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    // The bank never answers requests — players only.
                    if (isPay)
                      _RecipientBubble(
                        selected: _recipientId == Player.bankId,
                        label: Player.bankName,
                        onTap: () =>
                            setState(() => _recipientId = Player.bankId),
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.account_balance_rounded,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    for (final player in session.otherActivePlayers)
                      _RecipientBubble(
                        selected: _recipientId == player.id,
                        label: player.name,
                        onTap: () =>
                            setState(() => _recipientId = player.id),
                        child: PlayerAvatar(
                          player: player,
                          size: 54,
                          showPresence: false,
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          formatMoney(_amount, symbol),
                          style: textTheme.displayMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            color: _amount == 0
                                ? scheme.onSurfaceVariant
                                    .withValues(alpha: 0.5)
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    if (isRequest && targetBalance != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${session.accountName(_recipientId)} has '
                        '${formatMoney(targetBalance, symbol)}',
                        style: textTheme.bodySmall?.copyWith(
                          color: _amount > targetBalance
                              ? AppColors.expense
                              : scheme.onSurfaceVariant,
                          fontWeight: _amount > targetBalance
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                    if (isPay) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Balance ${formatMoney(session.myBalance, symbol)}',
                        style: textTheme.bodySmall?.copyWith(
                          color: _amount > session.myBalance
                              ? AppColors.expense
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _noteController,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 60,
                decoration: const InputDecoration(
                  hintText: 'Add a note (rent, chance card…)',
                  counterText: '',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
            ),
            if (!keyboardOpen)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AmountKeypad(
                  value: _amount,
                  onChanged: (value) => setState(() => _amount = value),
                ),
              ),
            if (!isRequest && !session.canResolve)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'You can send money on your turn.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton(
                onPressed: canSend ? _confirmAndSubmit : null,
                child: _sending
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          if (isRequest) ...[
                            const SizedBox(width: 12),
                            Text(
                              'Waiting for '
                              '${session.accountName(_recipientId)}…',
                            ),
                          ],
                        ],
                      )
                    : Text(switch (widget.mode) {
                        SendMode.pay =>
                          'Send to ${session.accountName(_recipientId)}',
                        SendMode.collect => 'Collect from the bank',
                        SendMode.request => hasValidRecipient
                            ? 'Request from '
                                '${session.accountName(_recipientId)}'
                            : 'No one to ask',
                      }),
              ),
            ),
          ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecipientBubble extends StatelessWidget {
  const _RecipientBubble({
    required this.selected,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 4),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      selected ? AppColors.accent : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: child,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
