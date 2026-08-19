import 'dart:async';

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
import '../utils/game_reachability.dart';
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
  // "Live" for the game this device is actually connected to comes straight
  // off GameProvider. For every *other* saved game, the only way to know
  // whether its host is currently up is to ask — a quick, bounded reachability
  // probe per record (same idea discovery_service already uses for mDNS-found
  // rooms; see utils/game_reachability.dart for the platform split), so a
  // game hosted elsewhere shows as live without having to be opened first.
  // Keyed by game id.
  final Map<String, bool> _reachable = {};
  Timer? _probeTimer;

  @override
  void initState() {
    super.initState();
    // GamesProvider's initial load() (kicked off in main.dart) is async and
    // may still be empty on this first frame — probing once here would
    // silently probe nothing. Re-probing on every change (including that
    // first load landing) is cheap enough given the short per-probe timeout
    // and small list sizes, and doubles as picking up a host going down.
    context.read<GamesProvider>().addListener(_probeReachability);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _probeReachability();
    });
    // A one-shot probe only reflects reachability at the moment the app was
    // opened — a friend who starts hosting a few seconds later would show
    // as offline until something else (a pull-to-refresh) re-checks. Keep
    // re-probing while this tab is actually on screen so the Live badge
    // stays trustworthy without the player having to think about it —
    // this is exactly what decides which room in the list to tap into.
    _probeTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _probeReachability(),
    );
  }

  @override
  void dispose() {
    context.read<GamesProvider>().removeListener(_probeReachability);
    _probeTimer?.cancel();
    super.dispose();
  }

  Future<void> _probeReachability() async {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final records = context.read<GamesProvider>().records;
    // Every record gets probed, including whichever one this device is
    // currently connected to — GameClient has no ping/heartbeat of its own,
    // so if the host vanishes without a clean socket close (killed, network
    // drop) ClientStatus can stay stuck on "connected" for a long time. A
    // fresh check is the only way to catch that; see the override below.
    await Future.wait(
      records.map((record) async {
        final host = record.hostAddress;
        final port = record.hostPort;
        if (host == null || port == null) return;
        final reachable = await probeGameReachable(
          host,
          port,
          record.game.id,
        );
        if (mounted) setState(() => _reachable[record.game.id] = reachable);
      }),
    );
  }

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
    if (mounted) {
      context.read<GamesProvider>().load();
      // Back on this tab (its route is current again) — refresh reachability
      // right away instead of waiting out the periodic timer, so whichever
      // room is still active in the background shows correctly straight away.
      _probeReachability();
    }
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

  /// Watches a room's dashboard on a spare screen (a TV, a second window) —
  /// no seat, no name, nothing added to this device's games list. Session
  /// teardown happens in [DashboardScreen] itself when it's popped — not
  /// here, since `JoinGameScreen` reaches the dashboard via
  /// `pushReplacement`, which completes *this* push's future the moment
  /// the dashboard appears, not when the user actually leaves it.
  Future<void> _watch() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const JoinGameScreen(spectator: true)),
    );
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
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Ready to bankrupt your friends?',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
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
                  onRefresh: () => Future.wait(
                    [games.load(), _probeReachability()],
                  ),
                  child: ListView.separated(
                    // RefreshIndicator arms off an overscroll past the top —
                    // with few enough games that the list doesn't fill the
                    // viewport, the default physics never lets it overscroll
                    // at all, so pull-to-refresh silently does nothing.
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    itemCount: games.records.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final record = games.records[index];
                      // "Live" means actually connected right now, or (for
                      // every other saved game) its host answering a quick
                      // reachability probe. A fresh probe result of false
                      // wins even over "actually connected right now" — the
                      // socket has no heartbeat of its own, so ClientStatus
                      // can still read "connected" for a while after a host
                      // vanishes without a clean close (killed, network
                      // drop); the TCP probe is the freshest ground truth.
                      final probedReachable = _reachable[record.game.id];
                      final isConnectedHere =
                          session.hasActiveSession &&
                          session.record?.game.id == record.game.id &&
                          session.connection == ClientStatus.connected;
                      final isLive = probedReachable == false
                          ? false
                          : (isConnectedHere || probedReachable == true);
                      return _GameCard(
                        record: record,
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
            child: Column(
              children: [
                Row(
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
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _watch,
                  icon: const Icon(Icons.tv_rounded, size: 18),
                  label: const Text("Watch a room's dashboard"),
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
    required this.playerCount,
    required this.isLive,
    required this.onTap,
    required this.onLongPress,
  });

  final GameRecord record;
  final int playerCount;
  final bool isLive;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = AppColors.avatarColor(record.game.id);
    final roleLabel = record.role == GameRole.host ? 'Hosting' : 'Joined';

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
                    // Role and player count front-loaded, board name last —
                    // on a cramped width the ellipsis eats the board name
                    // first rather than hiding the player count, which is
                    // the thing actually worth glancing at in this list.
                    Text(
                      '$roleLabel · $playerCount '
                      'player${playerCount == 1 ? '' : 's'} · '
                      '${record.game.board.name}',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                formatWhen(record.lastPlayedAt),
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
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
