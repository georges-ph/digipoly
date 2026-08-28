import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/property_auction.dart';
import '../providers/game_provider.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';

/// One live, table-held auction: current bid, who's leading, a quick bid
/// box, and a close button anyone at the table can press to settle it —
/// sells to the top bidder, or cancels if nobody bid. Closing doesn't
/// settle instantly: it starts a brief, table-wide countdown
/// ([PropertyAuction.closingAt]) so a bid that's mid-flight has a real
/// chance to land instead of losing a race to a close that happened to
/// arrive first — bidding during the countdown cancels it. Shared by the
/// game screen, the dashboard and the property sheet, so everyone sees the
/// same live state no matter where they're looking.
class AuctionCard extends StatefulWidget {
  const AuctionCard({super.key, required this.auction});

  final PropertyAuction auction;

  @override
  State<AuctionCard> createState() => _AuctionCardState();
}

class _AuctionCardState extends State<AuctionCard> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _error;

  /// Ticks a rebuild while a close is pending so the countdown text stays
  /// live — only runs while [PropertyAuction.closingAt] is actually set.
  Timer? _countdownTicker;

  @override
  void initState() {
    super.initState();
    // The player just tapped "Bid"/"Start an auction" to get here — make
    // the field ready to type into immediately instead of making them tap
    // it again, and keep it scrolled into view once the keyboard opens.
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
          );
        }
      });
    });
    _syncCountdownTicker();
  }

  @override
  void didUpdateWidget(covariant AuctionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCountdownTicker();
  }

  void _syncCountdownTicker() {
    final closing = widget.auction.closingAt != null;
    if (closing && _countdownTicker == null) {
      _countdownTicker = Timer.periodic(const Duration(milliseconds: 200), (
        _,
      ) {
        if (mounted) setState(() {});
      });
    } else if (!closing && _countdownTicker != null) {
      _countdownTicker!.cancel();
      _countdownTicker = null;
    }
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _bid(GameProvider session) {
    final amount = int.tryParse(_controller.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a bid amount.');
      return;
    }
    if (amount <= widget.auction.currentBid) {
      setState(() => _error = 'Bid higher than the current bid.');
      return;
    }
    if (amount > session.myBalance) {
      setState(() => _error = "You don't have that much.");
      return;
    }
    setState(() => _error = null);
    session.placeBid(widget.auction.propertyId, amount);
    _controller.clear();
    FocusScope.of(context).unfocus();
  }

  /// Closing sells the property (or cancels it) for good, so it always asks
  /// first — and calls out explicitly when the person closing is also the
  /// one about to win, since that's exactly the "bid low, close to myself"
  /// move that shouldn't happen silently. Confirming doesn't settle it right
  /// away, though — it starts a brief countdown anyone can still bid through.
  Future<void> _confirmClose(
    GameProvider session, {
    required String? bidderId,
    required String? bidderName,
    required String currency,
  }) async {
    final auction = widget.auction;
    final sellingToSelf = bidderId == session.myPlayerId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          bidderId == null ? 'Cancel this auction?' : 'Close the auction?',
        ),
        content: Text(
          bidderId == null
              ? 'Nobody has bid — the property stays unowned. A last-second '
                    'bid still gets a few seconds to come in first.'
              : 'Sell for ${formatMoney(auction.currentBid, currency)} to '
                    '$bidderName?'
                    '${sellingToSelf ? ' You are the only bidder.' : ''} '
                    'A higher bid can still come in during a short countdown.',
        ),
        actions: [
          // A plain TextButton next to a FilledButton reads as two
          // different kinds of control rather than two options of the same
          // decision — worse once a narrow window stacks them vertically
          // (Flutter's default OverflowBar puts whichever is listed first
          // on top). An OutlinedButton carries the same visual weight as
          // the FilledButton beside it, same pairing as the incoming money
          // request dialog.
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Back'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(bidderId == null ? 'Cancel auction' : 'Close & sell'),
          ),
        ],
      ),
    );
    if (confirmed == true) session.closeAuction(auction.propertyId);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameProvider>();
    final board = session.game?.board;
    final property = session.propertyById(widget.auction.propertyId);
    if (board == null || property == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final auction = widget.auction;
    final bidderId = auction.currentBidderId;
    final iAmLeading = bidderId != null && bidderId == session.myPlayerId;
    final bidderName = bidderId == null
        ? null
        : (iAmLeading ? 'You' : session.accountName(bidderId));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.gavel_rounded,
                size: 18,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              if (property.kind.isOwnable) ...[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Color(property.colorValue),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  'Auction: ${property.name}',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            bidderName == null
                ? 'No bids yet'
                : '${formatMoney(auction.currentBid, board.currencySymbol)} '
                      '— $bidderName${iAmLeading ? " (you're leading)" : ''}',
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: iAmLeading ? AppColors.income : null,
            ),
          ),
          if (auction.closingAt != null) ...[
            const SizedBox(height: 8),
            _ClosingCountdown(closingAt: auction.closingAt!),
          ],
          if (!session.isSpectating) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    // Only the player who actually started this auction
                    // gets the keyboard opened on them automatically —
                    // everyone else sees this same card the instant the
                    // auction starts, and autofocus for all of them would
                    // pop every connected keyboard at once. AuctionCard is
                    // also shared across game screen/dashboard/property
                    // sheet, so the starter can have two instances mounted
                    // at once (e.g. the property sheet's, on top of the
                    // game screen's underneath) — without the isCurrent
                    // check both would autofocus and fight over focus,
                    // leaving the keyboard open but attached to the
                    // invisible one behind the sheet.
                    autofocus:
                        widget.auction.startedBy == session.myPlayerId &&
                        (ModalRoute.of(context)?.isCurrent ?? true),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Your bid',
                      prefixText: '${board.currencySymbol} ',
                    ),
                    onSubmitted: (_) => _bid(session),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  // The app theme's default minimumSize is Size.fromHeight
                  // (infinite width, meant for full-width buttons) — fatal
                  // for a button sitting directly in a Row without Expanded.
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => _bid(session),
                  child: const Text('Bid'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: textTheme.bodySmall?.copyWith(color: AppColors.expense),
              ),
            ],
            // Once a close is already counting down, a second request is a
            // no-op server-side — hide the button rather than let it invite
            // a confusing repeat tap.
            if (auction.closingAt == null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  // The leading bidder can't close their own auction —
                  // that would let them bid low once and sell it to
                  // themselves before anyone else gets a chance. Someone
                  // else at the table has to close it (the server enforces
                  // this too).
                  onPressed: iAmLeading
                      ? null
                      : () => _confirmClose(
                          session,
                          bidderId: bidderId,
                          bidderName: bidderName,
                          currency: board.currencySymbol,
                        ),
                  child: Text(
                    bidderId == null
                        ? 'Cancel auction'
                        : iAmLeading
                        ? "You're leading — someone else can close this"
                        : 'Close — sell to $bidderName',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// A live "closing in Ns" readout for a pending close — ticks down to zero
/// off the shared, server-set [closingAt] timestamp (not a locally-started
/// timer), so every device counts down the same window regardless of when
/// its own auctionClosing broadcast happened to arrive.
class _ClosingCountdown extends StatelessWidget {
  const _ClosingCountdown({required this.closingAt});

  final DateTime closingAt;

  @override
  Widget build(BuildContext context) {
    final remaining = closingAt.difference(DateTime.now());
    final seconds = (remaining.inMilliseconds / 1000).ceil().clamp(0, 999);
    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.expense,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          seconds > 0
              ? 'Closing in ${seconds}s — bid now to keep it open'
              : 'Closing…',
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.expense,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
