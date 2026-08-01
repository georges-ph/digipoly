import 'package:flutter/material.dart';

import '../providers/game_provider.dart';
import '../utils/formatting.dart';
import 'transaction_details_sheet.dart';
import 'transaction_tile.dart';

/// Transaction tiles with day headers (Today / Yesterday / date) and, on
/// rows the viewer is actually a party to, their own running balance right
/// after that transaction — computed backwards from their current balance.
/// Rows between two other players carry no balance annotation: this feed is
/// shared across every device, but there's only ever one player's balance
/// (the viewer's own) to walk backwards from, so showing it next to a
/// transaction that isn't theirs would just be someone else's number
/// mislabeled. Shared by the game screen (teaser) and the full activity
/// screen.
List<Widget> buildActivityFeed(
  BuildContext context,
  GameProvider session, {
  int? limit,
}) {
  final textTheme = Theme.of(context).textTheme;
  final scheme = Theme.of(context).colorScheme;
  final currency = session.game?.board.currencySymbol ?? r'$';

  final widgets = <Widget>[];
  String? lastDay;
  var running = session.myBalance;
  var shown = 0;
  for (final tx in session.transactions) {
    final involvesMe =
        tx.toId == session.myPlayerId || tx.fromId == session.myPlayerId;
    final balanceAfter = involvesMe ? running : null;
    if (tx.toId == session.myPlayerId) running -= tx.amount;
    if (tx.fromId == session.myPlayerId) running += tx.amount;

    if (limit != null && shown >= limit) continue;
    shown++;

    final day = formatDay(tx.timestamp);
    if (day != lastDay) {
      lastDay = day;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(
          day,
          style: textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ));
    }
    widgets.add(TransactionTile(
      transaction: tx,
      myPlayerId: session.myPlayerId,
      currencySymbol: currency,
      nameOf: session.accountName,
      propertyNameOf: session.propertyNameOf,
      balanceAfter: balanceAfter,
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => TransactionDetailsSheet(
          transaction: tx,
          session: session,
          balanceAfter: balanceAfter,
        ),
      ),
    ));
  }
  return widgets;
}
