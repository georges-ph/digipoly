import 'package:flutter/material.dart';

import '../models/game_transaction.dart';
import '../models/player.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';

/// One row of the activity feed, from the viewing player's perspective:
/// green incoming, red outgoing, neutral for money moving between others.
/// Typed transactions (rent, purchase, salary, houses) label themselves.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.myPlayerId,
    required this.currencySymbol,
    required this.nameOf,
    this.propertyNameOf,
    this.balanceAfter,
    this.onTap,
  });

  final GameTransaction transaction;
  final String myPlayerId;
  final String currencySymbol;
  final String Function(String accountId) nameOf;
  final String Function(String propertyId)? propertyNameOf;

  /// The balance right after this transaction, to follow the money over
  /// time — whose balance depends on the row (see `activity_feed.dart`).
  final int? balanceAfter;

  final VoidCallback? onTap;

  String get _property {
    final id = transaction.propertyId;
    if (id == null) return 'a property';
    return propertyNameOf?.call(id) ?? 'a property';
  }

  String _title(bool incoming, bool outgoing) {
    final from = nameOf(transaction.fromId);
    final to = nameOf(transaction.toId);
    switch (transaction.type) {
      case TransactionType.purchase:
        return outgoing ? 'Bought $_property' : '$from bought $_property';
      case TransactionType.rent:
        if (incoming) return 'Rent from $from · $_property';
        if (outgoing) return 'Rent to $to · $_property';
        return '$from paid rent · $_property';
      case TransactionType.salary:
        return incoming ? 'Passed GO' : '$to passed GO';
      case TransactionType.house:
        final sold = transaction.fromId == Player.bankId;
        if (incoming) return 'Sold houses · $_property';
        if (outgoing) return 'Built on $_property';
        return sold
            ? '$to sold houses · $_property'
            : '$from built on $_property';
      case TransactionType.card:
        final drawer = transaction.fromId == Player.bankId ? to : from;
        if (incoming || outgoing) return 'Card drawn';
        return '$drawer drew a card';
      case TransactionType.mortgage:
        final lifted = transaction.fromId != Player.bankId;
        if (incoming) return 'Mortgaged $_property';
        if (outgoing) return 'Lifted mortgage · $_property';
        return lifted
            ? '$from lifted the mortgage · $_property'
            : '$to mortgaged $_property';
      case TransactionType.tax:
        if (outgoing) return 'Tax paid';
        return '$from paid tax';
      case TransactionType.freeParking:
        if (incoming) return 'Free Parking pot';
        return '$to collected Free Parking';
      case TransactionType.transfer:
        if (outgoing) return 'Transferred $_property to $to';
        if (incoming) return 'Received $_property from $from';
        return '$from transferred $_property to $to';
      case TransactionType.jailCardTransfer:
        if (outgoing) return 'Gave a Get Out of Jail Free card to $to';
        if (incoming) return 'Got a Get Out of Jail Free card from $from';
        return '$from gave a Get Out of Jail Free card to $to';
      case TransactionType.loan:
        // incoming only happens on the take side (bank → me), outgoing
        // only on the repay side (me → bank) — fromId/toId never let both
        // combine the other way.
        if (incoming) return 'Borrowed from the bank';
        if (outgoing) return 'Repaid loan';
        return transaction.fromId == Player.bankId
            ? '$to took out a loan'
            : '$from repaid a loan';
      case TransactionType.loanInterest:
        if (incoming || outgoing) return 'Loan interest';
        return '$from accrued loan interest';
      case TransactionType.payment:
      case TransactionType.request:
        if (incoming) return 'From $from';
        if (outgoing) return 'To $to';
        return '$from → $to';
    }
  }

  IconData _icon(bool incoming, bool outgoing) => switch (transaction.type) {
    TransactionType.purchase => Icons.shopping_bag_outlined,
    TransactionType.rent => Icons.real_estate_agent_outlined,
    TransactionType.salary => Icons.flag_rounded,
    TransactionType.house => Icons.home_rounded,
    TransactionType.card => Icons.style_rounded,
    TransactionType.mortgage => Icons.account_balance_outlined,
    TransactionType.tax => Icons.receipt_long_outlined,
    TransactionType.freeParking => Icons.local_parking_rounded,
    TransactionType.transfer => Icons.swap_horiz_rounded,
    TransactionType.jailCardTransfer => Icons.confirmation_number_rounded,
    TransactionType.loan => Icons.account_balance_rounded,
    TransactionType.loanInterest => Icons.trending_up_rounded,
    _ =>
      incoming
          ? Icons.south_west_rounded
          : (outgoing ? Icons.north_east_rounded : Icons.swap_horiz_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final incoming = transaction.toId == myPlayerId;
    final outgoing = transaction.fromId == myPlayerId;

    final Color color;
    final String amountText;
    if (incoming) {
      color = AppColors.income;
      amountText = formatSignedMoney(
        transaction.amount,
        currencySymbol,
        incoming: true,
      );
    } else if (outgoing) {
      color = AppColors.expense;
      amountText = formatSignedMoney(
        transaction.amount,
        currencySymbol,
        incoming: false,
      );
    } else {
      color = scheme.onSurfaceVariant;
      // Not my transaction, but still show a direction: money leaving the
      // bank reads as a collection (+), everything else — including one
      // player paying another — reads from the payer's side (-), matching
      // how the title itself is worded ("$from paid…", "$from → $to").
      // A $0 transfer has no direction to show.
      amountText = transaction.amount == 0
          ? formatMoney(0, currencySymbol)
          : formatSignedMoney(
              transaction.amount,
              currencySymbol,
              incoming: transaction.fromId == Player.bankId,
            );
    }

    final subtitleParts = [
      if (transaction.note.isNotEmpty) transaction.note,
      formatWhen(transaction.timestamp),
    ];

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(_icon(incoming, outgoing), color: color, size: 22),
      ),
      title: Text(
        _title(incoming, outgoing),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            amountText,
            style: textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: incoming || outgoing ? color : scheme.onSurface,
            ),
          ),
          if (balanceAfter != null)
            Text(
              'bal ${formatMoney(balanceAfter!, currencySymbol)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
