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
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
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
              onPressed: () => session.closeAuction(auction.propertyId),
              child: Text(
                bidderId == null
                    ? 'Cancel auction'
                    : 'Close — sell to $bidderName',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
