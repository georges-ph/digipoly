import 'package:flutter/material.dart';

import '../models/board.dart';
import '../models/player.dart';
import '../models/property.dart';
import 'player_avatar.dart';
import 'ring_board.dart';

/// A read-only render of a board's curated layout — every square in board
/// order, including specials (GO, Jail, Tax, ...) — arranged as a physical
/// ring around a square grid (like a real board), with each player's token
/// shown at their current square. Static: scales to fit the available
/// width, no scroll or zoom. Animated movement is deferred.
class BoardLayoutView extends StatelessWidget {
  const BoardLayoutView({
    super.key,
    required this.board,
    required this.players,
    this.onTapProperty,
  });

  final Board board;
  final List<Player> players;
  final void Function(Property property)? onTapProperty;

  @override
  Widget build(BuildContext context) {
    final activePlayers = players.where((p) => !p.hasLeft).toList();

    return RingBoard(
      squareCount: board.properties.length,
      cellBuilder: (context, i, cellSize) {
        if (i >= board.properties.length) return const SizedBox.shrink();
        final square = board.properties[i];
        return _SquareTile(
          square: square,
          cellSize: cellSize,
          tokens: [
            for (final player in activePlayers)
              if (player.position == i) player,
          ],
          onTap: square.kind.isOwnable && onTapProperty != null
              ? () => onTapProperty!(square)
              : null,
        );
      },
    );
  }
}

class _SquareTile extends StatelessWidget {
  const _SquareTile({
    required this.square,
    required this.cellSize,
    required this.tokens,
    this.onTap,
  });

  final Property square;
  final Size cellSize;
  final List<Player> tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bandColor =
        square.kind.isOwnable ? Color(square.colorValue) : scheme.outline;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 6, color: bandColor),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: cellSize.width - 10,
                          child: Text(
                            square.name,
                            textAlign: TextAlign.center,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (tokens.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 3,
                        runSpacing: 3,
                        children: [
                          for (final player in tokens)
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: scheme.surface,
                                  width: 1.5,
                                ),
                              ),
                              child: PlayerAvatar(
                                player: player,
                                size: 20,
                                showPresence: false,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
