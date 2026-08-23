import 'package:flutter/material.dart';

import '../models/board.dart';
import '../models/player.dart';
import '../models/property.dart';
import '../models/property_ownership.dart';
import '../theme/app_theme.dart';
import '../utils/board_ring.dart';
import '../utils/formatting.dart';
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
/// zoom. Token movement itself is instant, not animated — every token
/// instead carries its own continuous, radar-style pulsing ring (staggered
/// per seat) so where everyone currently stands reads at a glance, not just
/// right after they move.
class BoardLayoutView extends StatelessWidget {
  const BoardLayoutView({
    super.key,
    required this.board,
    required this.players,
    this.ownerships = const {},
    this.onTapProperty,
    this.freeParkingPot = 0,
  });

  final Board board;
  final List<Player> players;
  final Map<String, PropertyOwnership> ownerships;
  final void Function(Property property)? onTapProperty;

  /// Shown as a badge on the Free Parking square itself when > 0 — the pot
  /// is otherwise invisible until it pays out, unlike a physical table
  /// where the cash literally piles up on the square.
  final int freeParkingPot;

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
          potText: square.kind == PropertyKind.freeParking && freeParkingPot > 0
              ? formatMoney(freeParkingPot, board.currencySymbol)
              : null,
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
    this.potText,
  });

  final Property square;
  final Size cellSize;
  final List<Player> tokens;
  final _Edge edge;
  final PropertyOwnership? ownership;
  final Player? owner;
  final VoidCallback? onTap;

  /// Free Parking's current pot, pre-formatted — null everywhere else.
  final String? potText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bandColor = square.kind.isOwnable
        ? Color(square.colorValue)
        : scheme.outline;
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
    // tileColor is semi-transparent for owned/mortgaged tiles, so it's no
    // good as a solid ring color on its own (it just reads as invisible) —
    // flatten it against the surface it's actually painted on so the ring
    // matches what's really rendered there instead.
    final opaqueTileColor = Color.alphaBlend(tileColor, scheme.surface);

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
        // Tokens are a Stack layer on top of the tile, not part of its
        // Column — the title/houses layout is identical whether or not
        // anyone's standing here, instead of having to make room for a
        // token row alongside it (which either squeezed the title down to
        // nothing on a short tile, or squeezed the avatar down to fit —
        // tried both, neither actually worked). A token overlapping the
        // title reads fine at a glance; a hidden title never did.
        child: Stack(
          children: [
            _banded(bandColor, _content(textTheme)),
            if (tokens.isNotEmpty)
              Positioned.fill(
                child: Align(
                  // Nudged toward the tile's own outer edge (away from the
                  // board's center, the opposite side from the color band)
                  // rather than sitting dead-center — reads more like a
                  // token resting on the square than a badge slapped over
                  // the middle of its name.
                  alignment: switch (edge) {
                    _Edge.top => const Alignment(0, -0.6),
                    _Edge.bottom => const Alignment(0, 0.6),
                    _Edge.left => const Alignment(-0.6, 0),
                    _Edge.right => const Alignment(0.6, 0),
                  },
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 3,
                    runSpacing: 3,
                    children: [
                      for (final player in tokens)
                        _TokenRadarPulse(
                          seat: player.seat,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: opaqueTileColor,
                                width: 1.5,
                              ),
                            ),
                            child: PlayerAvatar(
                              player: player,
                              size: 20,
                              showPresence: false,
                              showJailCard: false,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
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

  Widget _content(TextTheme textTheme) {
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
          if (potText != null) ...[
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                potText!,
                maxLines: 1,
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.income,
                ),
              ),
            ),
          ],
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
        ],
      ),
    );
  }
}

/// A continuous, sonar/GPS-style expanding-and-fading ring around every
/// token on the board — where each player currently stands should read at
/// a glance, radar-style, not just in the instant after they moved. Fixed
/// accent color rather than each player's own avatar color: the avatar
/// itself already carries identity (initials + color), so the ring's only
/// job is to stay noticeable, which a muted seat hue (brown, navy, ...)
/// can't reliably do against every possible tile background. Each token's
/// loop starts on a delay keyed off [seat] so tokens sharing a square (e.g.
/// everyone still on GO) don't all blip in lockstep.
class _TokenRadarPulse extends StatefulWidget {
  const _TokenRadarPulse({required this.seat, required this.child});

  final int seat;
  final Widget child;

  @override
  State<_TokenRadarPulse> createState() => _TokenRadarPulseState();
}

class _TokenRadarPulseState extends State<_TokenRadarPulse>
    with SingleTickerProviderStateMixin {
  static const _period = Duration(milliseconds: 1400);
  late final _controller = AnimationController(vsync: this, duration: _period);

  @override
  void initState() {
    super.initState();
    Future.delayed(_period * ((widget.seat % 6) / 6), () {
      if (mounted) _controller.repeat();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The ring is a Positioned child with an explicit size but no left/top/
    // right/bottom — Stack still centers it (via `alignment`) but, being
    // positioned, it's excluded from the Stack's own size computation, so it
    // can grow past the avatar without dragging the Wrap/Column that holds
    // this widget along with it. Without that split, reserving real layout
    // space for the ring's full diameter squeezed a short (wide/short
    // "horizontal") tile's title text down to nothing — and reserving too
    // little instead just clamped the avatar itself down to fit. Sizing the
    // Stack off `widget.child` (the avatar) alone avoids both: the ring can
    // be as big as it wants, the avatar always renders at its own size.
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            // Starts already bigger than the 20px avatar it surrounds —
            // starting at the same size hid the ring completely behind the
            // (opaque, on-top) avatar for the brightest part of the fade.
            final size = 26.0 + t * 22;
            return Positioned(
              width: size,
              height: size,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: (1 - t) * 0.95),
                    width: 2.5,
                  ),
                ),
              ),
            );
          },
        ),
        widget.child,
      ],
    );
  }
}
