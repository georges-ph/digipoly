import 'package:flutter/material.dart';

import '../models/board.dart';
import '../models/player.dart';
import '../models/property.dart';
import '../models/property_ownership.dart';
import '../theme/app_theme.dart';
import '../utils/board_ring.dart';
import 'player_avatar.dart';
import 'ring_board.dart';

/// Which side of the ring a square sits on — used to put its color band on
/// the side facing the board's center, like a real board (a top-row square
/// is banded along its bottom edge, a left-column one along its right).
enum _Edge { top, bottom, left, right }

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
    final playersById = {for (final p in players) p.id: p};
    final side = ringSide(board.properties.length);
    final cells = ringCells(side);

    return RingBoard(
      squareCount: board.properties.length,
      cellBuilder: (context, i, cellSize) {
        if (i >= board.properties.length) return const SizedBox.shrink();
        final square = board.properties[i];
        final ownership = ownerships[square.id];
        final cell = cells[i];
        // Classified purely by row/col so each corner lands on whichever
        // edge its row belongs to (top or bottom) — a real board has no
        // ambiguity here since corners aren't ownable and carry no band.
        final edge = cell.row == side - 1
            ? _Edge.bottom
            : cell.row == 0
                ? _Edge.top
                : cell.col == 0
                    ? _Edge.left
                    : _Edge.right;
        return _SquareTile(
          square: square,
          cellSize: cellSize,
          ownership: ownership,
          owner: ownership != null ? playersById[ownership.ownerId] : null,
          edge: edge,
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
    required this.edge,
    this.ownership,
    this.owner,
    this.onTap,
  });

  final Property square;
  final Size cellSize;
  final List<Player> tokens;
  final _Edge edge;
  final PropertyOwnership? ownership;
  final Player? owner;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bandColor =
        square.kind.isOwnable ? Color(square.colorValue) : scheme.outline;
    final ownership = this.ownership;
    final ownerColor = owner != null
        ? AppColors.avatarColorForSeat(owner!.seat)
        : ownership != null
            ? AppColors.avatarColor(ownership.ownerId)
            : null;
    // Owned squares are tinted in the owner's color across the whole tile
    // (not just a thin strip) so ownership reads at a glance from across
    // the room — mortgaged ones swap to a warning tone instead.
    final tileColor = ownership == null
        ? scheme.surfaceContainerLow
        : ownership.mortgaged
            ? AppColors.expense.withValues(alpha: 0.28)
            : ownerColor!.withValues(alpha: 0.35);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: tileColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: ownership != null && !ownership.mortgaged
                ? ownerColor!.withValues(alpha: 0.8)
                : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: _banded(bandColor, _content(textTheme, scheme)),
      ),
    );
  }

  /// The band always sits on the side facing the board's center — a real
  /// board's color strip runs along the inside of the ring, not always
  /// along one fixed side of the square.
  Widget _banded(Color bandColor, Widget content) {
    switch (edge) {
      case _Edge.bottom:
        return Column(
          children: [
            Container(height: 6, color: bandColor),
            Expanded(child: content),
          ],
        );
      case _Edge.top:
        return Column(
          children: [
            Expanded(child: content),
            Container(height: 6, color: bandColor),
          ],
        );
      case _Edge.left:
        return Row(
          children: [
            Expanded(child: content),
            Container(width: 6, color: bandColor),
          ],
        );
      case _Edge.right:
        return Row(
          children: [
            Container(width: 6, color: bandColor),
            Expanded(child: content),
          ],
        );
    }
  }

  Widget _content(TextTheme textTheme, ColorScheme scheme) {
    final ownership = this.ownership;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
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
                      border: Border.all(color: scheme.surface, width: 1.5),
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
    );
  }
}
