import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player.dart';
import '../models/property_ownership.dart';
import '../providers/game_provider.dart';
import '../services/game_client.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import '../widgets/activity_feed.dart';
import '../widgets/auction_card.dart';
import '../widgets/board_layout_view.dart';
import '../widgets/player_avatar.dart';
import 'properties_screen.dart';

/// The game-over banner's headline — [players] is already sorted richest
/// net-worth-first, so the winner is just its first (non-departed) entry.
String _gameOverTitle(GameProvider session, List<Player> players) {
  if (players.isEmpty) return 'Game over';
  final winner = players.first;
  return winner.id == session.myPlayerId
      ? 'Game over — you win'
      : 'Game over — ${winner.name} wins';
}

/// Table-wide view for any big screen: every balance, who owns what, whose
/// turn it is, and the live activity ticker. Works in any orientation.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameProvider>();
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // A spectator session belongs to nothing but this screen — leaving
        // it (back button, close) should tear the connection down. A
        // normal player reaching the dashboard from the in-game popup menu
        // keeps their session alive underneath, same as any other push.
        if (didPop && session.isSpectating) session.closeSession();
      },
      child: _DashboardBody(session: session),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.session});

  final GameProvider session;

  @override
  Widget build(BuildContext context) {
    final game = session.game;
    if (game == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Ranked richest-first so the table can see who's winning at a glance —
    // the turn highlight (isTurn, below) still tracks seat via
    // currentTurnId, independent of this order.
    final players = session.players.where((p) => !p.hasLeft).toList()
      ..sort((a, b) => session.netWorthOf(b).compareTo(session.netWorthOf(a)));
    final turnPlayer = session.currentTurnPlayer;

    final playersPane = SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (session.gameEnded) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.emoji_events_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _gameOverTitle(session, players),
                      style: textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else if (turnPlayer != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.casino_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      turnPlayer.id == session.myPlayerId
                          ? 'Your turn'
                          : "${turnPlayer.name}'s turn",
                      style: textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (session.lastRoll != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '🎲 ${session.lastRoll!.die1} + '
                        '${session.lastRoll!.die2} = '
                        '${session.lastRoll!.total}',
                        style: textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (session.auctions.isNotEmpty) ...[
            for (final auction in session.auctions.values)
              AuctionCard(auction: auction),
            const SizedBox(height: 4),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < players.length; i++)
                _PlayerCard(
                  player: players[i],
                  session: session,
                  currency: game.board.currencySymbol,
                  isTurn: players[i].id == session.currentTurnId,
                  isWinner: session.gameEnded && i == 0,
                ),
            ],
          ),
          if (game.board.goIndex >= 0) ...[
            const SizedBox(height: 20),
            Text(
              'Board',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            BoardLayoutView(
              board: game.board,
              players: session.players,
              ownerships: session.ownerships,
              freeParkingPot: session.freeParkingPot,
              // No NFC concept on a dashboard (a TV, a spectator's device) —
              // the "register a card" icon inside the sheet just stays off.
              onTapProperty: (property) => showPropertySheet(
                context,
                propertyId: property.id,
                nfcAvailable: false,
              ),
            ),
          ],
        ],
      ),
    );

    final activityPane = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text(
            'Activity',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: session.transactions.isEmpty
              ? Center(
                  child: Text(
                    'No transactions yet.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: buildActivityFeed(context, session, limit: 30),
                ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('${game.name} · ${game.board.name}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                session.connection == ClientStatus.connected
                    ? '● Live'
                    : '○ Offline',
                style: textTheme.labelLarge?.copyWith(
                  color: session.connection == ClientStatus.connected
                      ? AppColors.income
                      : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 760) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: playersPane),
                SizedBox(
                  width: 340,
                  height: constraints.maxHeight,
                  child: activityPane,
                ),
              ],
            );
          }
          return Column(
            children: [
              Expanded(flex: 3, child: playersPane),
              const Divider(height: 1),
              Expanded(flex: 2, child: activityPane),
            ],
          );
        },
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.player,
    required this.session,
    required this.currency,
    required this.isTurn,
    this.isWinner = false,
  });

  final Player player;
  final GameProvider session;
  final String currency;
  final bool isTurn;

  /// Highest net worth once the game's been called — see
  /// [GameProvider.gameEnded].
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final owned = session.propertiesOwnedBy(player.id);
    final myOwnerships = session.ownerships.values.where(
      (o) => o.ownerId == player.id,
    );
    // A hotel is stored as houses == 5 (PropertyOwnership.hotel), not 5
    // houses — counted separately so "3 houses" doesn't silently include
    // properties that are actually hotels.
    final houseCount = myOwnerships
        .where((o) => o.houses > 0 && o.houses < PropertyOwnership.hotel)
        .fold<int>(0, (sum, o) => sum + o.houses);
    final hotelCount = myOwnerships
        .where((o) => o.houses == PropertyOwnership.hotel)
        .length;
    final mortgagedCount = myOwnerships.where((o) => o.mortgaged).length;

    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: isWinner
              ? AppColors.income
              : isTurn
              ? AppColors.accent
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlayerAvatar(player: player, size: 40),
              if (isWinner) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.emoji_events_rounded,
                  size: 18,
                  color: AppColors.income,
                ),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.id == session.myPlayerId ? 'You' : player.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (player.loanBalance > 0)
                      Text(
                        'Owes ${formatMoney(player.loanBalance, currency)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: AppColors.expense,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              if (player.inJail) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.local_police_rounded,
                  size: 18,
                  color: AppColors.jailCard,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(player.balance, currency),
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: player.balance < 0 ? AppColors.expense : null,
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Cash plus everything liquidated at sell-back value — the
          // table's own rank order (this list is already sorted richest
          // net-worth-first) so anyone deciding whether to call the game
          // can see who's actually ahead, not just who's holding more cash.
          Text(
            'Net worth ${formatMoney(session.netWorthOf(player), currency)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (houseCount > 0 || hotelCount > 0 || mortgagedCount > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (houseCount > 0)
                  _StatusChip(
                    icon: Icons.house_rounded,
                    label: '$houseCount',
                    color: scheme.onSurfaceVariant,
                  ),
                if (hotelCount > 0)
                  _StatusChip(
                    icon: Icons.apartment_rounded,
                    label: '$hotelCount',
                    color: scheme.onSurfaceVariant,
                  ),
                if (mortgagedCount > 0)
                  _StatusChip(
                    icon: Icons.money_off_rounded,
                    label: '$mortgagedCount',
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (owned.isEmpty)
            Text(
              'No properties',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 3,
              runSpacing: 3,
              children: [
                for (final property in owned)
                  Tooltip(
                    message: property.name,
                    child: Container(
                      width: 12,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Color(property.colorValue),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A small tinted pill for a player-card status callout (owes money, in
/// jail) — kept separate from [PlayerAvatar]'s own jail-card badge, which
/// marks *holding* a Get Out of Jail Free card rather than *being* jailed.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, this.label, required this.color});

  final IconData icon;

  /// Null renders an icon-only badge (e.g. jail — the color already reads
  /// as "stuck", a count/label would be redundant).
  final String? label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          if (label != null) ...[
            const SizedBox(width: 4),
            Text(
              label!,
              style: textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
