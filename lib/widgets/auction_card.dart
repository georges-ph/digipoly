import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/property_auction.dart';
import '../providers/game_provider.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';

/// One live, table-held auction: current bid, who's leading, a quick bid
/// box, and a close button anyone at the table can press to settle it —
/// sells to the top bidder, or cancels if nobody bid. Shared by the game
/// screen, the dashboard and the property sheet, so everyone sees the same
/// live state no matter where they're looking.
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
  }

  @override
  void dispose() {
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
  /// move that shouldn't happen silently.
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
        title: Text(bidderId == null ? 'Cancel this auction?' : 'Close the auction?'),
        content: Text(
          bidderId == null
              ? 'Nobody has bid — the property stays unowned.'
              : 'Sell for ${formatMoney(auction.currentBid, currency)} to '
                  '$bidderName?'
                  '${sellingToSelf ? ' You are the only bidder.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Back'),
          ),
          FilledButton(
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
    final bidderName =
        bidderId == null ? null : (iAmLeading ? 'You' : session.accountName(bidderId));

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
              const Icon(Icons.gavel_rounded, size: 18, color: AppColors.accent),
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
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
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
          if (!session.isSpectating) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
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
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _confirmClose(
                  session,
                  bidderId: bidderId,
                  bidderName: bidderName,
                  currency: board.currencySymbol,
                ),
                child: Text(
                  bidderId == null
                      ? 'Cancel auction'
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
