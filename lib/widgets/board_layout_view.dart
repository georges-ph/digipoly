import 'package:flutter/material.dart';

import '../models/board.dart';
import '../models/player.dart';
import '../models/property.dart';
import '../theme/app_theme.dart';

/// A read-only render of a board's curated layout — every square in board
/// order, including specials (GO, Jail, Tax, ...) — with each player's
/// token shown at their current square. A wrapping grid in reading order,
/// not a geometrically accurate ring; that polish (and animated movement)
/// is deferred.
class BoardLayoutView extends StatelessWidget {
  const BoardLayoutView({
    super.key,
    required this.board,
    required this.players,
    this.onTapProperty,
    this.shrinkWrap = false,
    this.physics,
  });

  final Board board;
  final List<Player> players;
  final void Function(Property property)? onTapProperty;

  /// Pass `true` (with [physics] set to
  /// [NeverScrollableScrollPhysics]) when embedding inside another
  /// scrollable, e.g. the dashboard.
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final activePlayers = players.where((p) => !p.hasLeft).toList();

    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: physics,
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      itemCount: board.properties.length,
      itemBuilder: (context, index) {
        final square = board.properties[index];
        final tokens = [
          for (final player in activePlayers)
            if (player.position == index) player,
        ];
        return _SquareTile(
          square: square,
          tokens: tokens,
          onTap: square.kind.isOwnable && onTapProperty != null
              ? () => onTapProperty!(square)
              : null,
        );
      },
    );
  }
}

class _SquareTile extends StatelessWidget {
  const _SquareTile({required this.square, required this.tokens, this.onTap});

  final Property square;
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: bandColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      square.name,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (tokens.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 3,
                        runSpacing: 3,
                        children: [
                          for (final player in tokens)
                            Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: AppColors.avatarColor(player.id),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: scheme.surface,
                                  width: 1.5,
                                ),
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
