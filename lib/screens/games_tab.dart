import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game.dart';
import '../models/result.dart';
import '../providers/game_provider.dart';
import '../providers/games_provider.dart';
import '../services/game_client.dart';
import '../services/identity_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import '../utils/snack.dart';
import '../widgets/empty_state.dart';
import '../widgets/name_sheet.dart';
import 'game_screen.dart';
import 'host_game_screen.dart';
import 'join_game_screen.dart';

/// Home tab listing every game this device belongs to, with entry points to
/// host a new room or join one on the network.
class GamesTab extends StatefulWidget {
  const GamesTab({super.key});

  @override
  State<GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends State<GamesTab> {
  Future<void> _openGame(GameRecord record) async {
    final session = context.read<GameProvider>();
    final messenger = ScaffoldMessenger.of(context);

    // Open instantly like a banking app; the connection happens in the
    // background and the game screen reflects it live in the status chip.
    session.resumeGame(record).then((result) {
      if (!result.isOk) {
        showSnackWith(messenger, result.error!);
      }
    });
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GameScreen()),
    );
    if (mounted) context.read<GamesProvider>().load();
  }

  Future<void> _confirmRemove(GameRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove "${record.game.name}"?'),
        content: const Text(
          'This only removes the game from this device. '
          'Your seat and balance stay in the game on the host.',
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<GamesProvider>().deleteGame(record.game.id);
    }
  }

  Future<void> _host() async {
    final identity = context.read<IdentityService>();
    if (!await ensurePlayerName(context, identity)) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HostGameScreen()),
    );
    if (mounted) context.read<GamesProvider>().load();
  }

  Future<void> _join() async {
    final identity = context.read<IdentityService>();
    if (!await ensurePlayerName(context, identity)) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const JoinGameScreen()),
    );
    if (mounted) context.read<GamesProvider>().load();
  }

  @override
  Widget build(BuildContext context) {
    final games = context.watch<GamesProvider>();
    final session = context.watch<GameProvider>();
    final identity = context.read<IdentityService>();
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                identity.hasName ? 'Hi, ${identity.displayName}' : 'Welcome',
                style: textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'Ready to bankrupt your friends?',
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: games.records.isEmpty
              ? const EmptyState(
                  icon: Icons.sports_esports_outlined,
                  title: 'No games yet',
                  message:
                      'Host a room for your board, or join one running on '
                      'your wifi.',
                )
              : RefreshIndicator(
                  onRefresh: games.load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    itemCount: games.records.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final record = games.records[index];
                      // "Live" means actually connected right now — a
                      // session whose host has vanished is not live.
                      final isLive = session.hasActiveSession &&
                          session.record?.game.id == record.game.id &&
                          session.connection == ClientStatus.connected;
                      return _GameCard(
                        record: record,
                        balance: games.myBalanceIn(record),
                        playerCount: games.playerCountIn(record),
                        isLive: isLive,
                        onTap: () => _openGame(record),
                        onLongPress: () => _confirmRemove(record),
                      );
                    },
                  ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _host,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Host game'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _join,
                    icon: const Icon(Icons.wifi_tethering_rounded),
                    label: const Text('Join'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.record,
    required this.balance,
    required this.playerCount,
    required this.isLive,
    required this.onTap,
    required this.onLongPress,
  });

  final GameRecord record;
  final int? balance;
  final int playerCount;
  final bool isLive;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = AppColors.avatarColor(record.game.id);
    final roleLabel =
        record.role == GameRole.host ? 'Hosting' : 'Joined';

    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.casino_rounded, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            record.game.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (isLive) ...[
                          const SizedBox(width: 8),
                          const _LiveChip(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${record.game.board.name} · $roleLabel · '
                      '$playerCount player${playerCount == 1 ? '' : 's'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (balance != null)
                    Text(
                      formatMoney(
                        balance!,
                        record.game.board.currencySymbol,
                      ),
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    formatWhen(record.lastPlayedAt),
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveChip extends StatelessWidget {
  const _LiveChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.income.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.income,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'Live',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.income,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
