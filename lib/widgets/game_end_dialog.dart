import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/game_provider.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import 'player_avatar.dart';

/// Final net-worth standings, shown once the host calls the game (see
/// [GameProvider.endGame]/[GameProvider.gameEndings]) — there's no
/// bankruptcy or win-condition tracking, so this is the deliberate,
/// house-rule "who's ahead when the table decides to stop" moment.
Future<void> showGameEndDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _GameEndDialog(),
  );
}

class _GameEndDialog extends StatelessWidget {
  const _GameEndDialog();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameProvider>();
    final board = session.game?.board;
    if (board == null) return const SizedBox.shrink();

    final standings = session.players.where((p) => !p.hasLeft).toList()
      ..sort(
        (a, b) => session.netWorthOf(b).compareTo(session.netWorthOf(a)),
      );

    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Game over'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Final standings, by net worth',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < standings.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: i == 0
                            ? const Icon(
                                Icons.emoji_events_rounded,
                                color: AppColors.income,
                                size: 20,
                              )
                            : Text(
                                '${i + 1}',
                                textAlign: TextAlign.center,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      PlayerAvatar(player: standings[i], size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          standings[i].id == session.myPlayerId
                              ? 'You'
                              : standings[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatMoney(
                          session.netWorthOf(standings[i]),
                          board.currencySymbol,
                        ),
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: i == 0 ? AppColors.income : null,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
