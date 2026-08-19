import 'package:flutter/material.dart';

import '../models/player.dart';
import '../providers/game_provider.dart';
import '../utils/formatting.dart';
import 'transaction_details_sheet.dart';
import 'transaction_tile.dart';

/// Transaction tiles with day headers (Today / Yesterday / date) and a
/// running balance right after that transaction, for whichever player it's
/// most relevant to — computed backwards from every player's *current*
/// balance (all live in [GameProvider.players], not just the viewer's own),
/// so this works the same for a row the viewer is a party to and one
/// between two other players. Shared by the game screen (teaser), the full
/// activity screen, and the dashboard.
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
  final runningByPlayer = <String, int>{
    for (final p in session.players) p.id: p.balance,
  };
  var shown = 0;
  for (final tx in session.transactions) {
    final involvesMe =
        tx.toId == session.myPlayerId || tx.fromId == session.myPlayerId;
    // The bank has no real balance to show — prefer the viewer's own side,
    // then whichever side is an actual player (the recipient first, since
    // that mirrors the "incoming" framing everywhere else in the feed).
    final String? balanceOwnerId;
    if (involvesMe) {
      balanceOwnerId = session.myPlayerId;
    } else if (tx.toId != Player.bankId) {
      balanceOwnerId = tx.toId;
    } else if (tx.fromId != Player.bankId) {
      balanceOwnerId = tx.fromId;
    } else {
      balanceOwnerId = null;
    }
    final balanceAfter = balanceOwnerId == null
        ? null
        : runningByPlayer[balanceOwnerId];
    if (tx.toId != Player.bankId) {
      runningByPlayer[tx.toId] = (runningByPlayer[tx.toId] ?? 0) - tx.amount;
    }
    if (tx.fromId != Player.bankId) {
      runningByPlayer[tx.fromId] =
          (runningByPlayer[tx.fromId] ?? 0) + tx.amount;
    }

    if (limit != null && shown >= limit) continue;
    shown++;

    final day = formatDay(tx.timestamp);
    if (day != lastDay) {
      lastDay = day;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(
            day,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ),
      );
    }
    widgets.add(
      TransactionTile(
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
            balanceAfterOwnerId: balanceOwnerId,
          ),
        ),
      ),
    );
  }
  return widgets;
}
