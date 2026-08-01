import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player.dart';
import '../providers/game_provider.dart';
import '../services/game_client.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import '../widgets/activity_feed.dart';
import '../widgets/auction_card.dart';
import '../widgets/board_layout_view.dart';
import '../widgets/player_avatar.dart';
import 'properties_screen.dart';

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
    final players =
        session.players.where((p) => !p.hasLeft).toList();
    final turnPlayer = session.currentTurnPlayer;

    final playersPane = SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (turnPlayer != null) ...[
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(Icons.casino_rounded,
                      color: Colors.white, size: 26),
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
              for (final player in players)
                _PlayerCard(
                  player: player,
                  session: session,
                  currency: game.board.currencySymbol,
                  isTurn: player.id == session.currentTurnId,
                ),
            ],
          ),
          if (game.board.goIndex >= 0) ...[
            const SizedBox(height: 20),
            Text(
              'Board',
              style:
                  textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            BoardLayoutView(
              board: game.board,
              players: session.players,
              ownerships: session.ownerships,
              onTapProperty: (property) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PropertiesScreen(openPropertyId: property.id),
                ),
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
            style:
                textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: ListView(
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
  });

  final Player player;
  final GameProvider session;
  final String currency;
  final bool isTurn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final owned = session.propertiesOwnedBy(player.id);

    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: isTurn ? AppColors.accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlayerAvatar(player: player, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  player.id == session.myPlayerId ? 'You' : player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            formatMoney(player.balance, currency),
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: player.balance < 0 ? AppColors.expense : null,
            ),
          ),
          const SizedBox(height: 10),
          if (owned.isEmpty)
            Text(
              'No properties',
              style: textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
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
