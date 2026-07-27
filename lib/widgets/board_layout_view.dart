import 'package:flutter/material.dart';

import '../models/board.dart';
import '../models/player.dart';
import '../models/property.dart';
import '../models/property_ownership.dart';
import '../theme/app_theme.dart';
import 'player_avatar.dart';
import 'ring_board.dart';

/// A read-only render of a board's curated layout — every square in board
/// order, including specials (GO, Jail, Tax, ...) — arranged as a physical
/// ring around a square grid (like a real board), with each player's token
/// shown at their current square, plus who owns each property and how
/// built-up it is. Static: scales to fit the available width, no scroll or
/// zoom. Animated movement is deferred.
class BoardLayoutView extends StatelessWidget {
  const BoardLayoutView({
    super.key,
    required this.board,
    required this.players,
    this.ownerships = const {},
    this.onTapProperty,
  });

  final Board board;
  final List<Player> players;
  final Map<String, PropertyOwnership> ownerships;
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
          ownership: ownerships[square.id],
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
    this.ownership,
    this.onTap,
  });

  final Property square;
  final Size cellSize;
  final List<Player> tokens;
  final PropertyOwnership? ownership;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bandColor =
        square.kind.isOwnable ? Color(square.colorValue) : scheme.outline;
    final ownership = this.ownership;

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
            // Ownership strip: the owner's avatar color, or a warning tone
            // once mortgaged — same color language as the players row.
            if (ownership != null)
              Container(
                height: 4,
                color: ownership.mortgaged
                    ? AppColors.expense.withValues(alpha: 0.6)
                    : AppColors.avatarColor(ownership.ownerId),
              ),
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
                    if (ownership != null && ownership.houses > 0) ...[
                      const SizedBox(height: 2),
                      if (ownership.houses >= PropertyOwnership.hotel)
                        const Icon(
                          Icons.apartment_rounded,
                          size: 12,
                          color: AppColors.expense,
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < ownership.houses; i++)
                              const Icon(
                                Icons.home_rounded,
                                size: 9,
                                color: AppColors.income,
                              ),
                          ],
                        ),
                    ],
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
