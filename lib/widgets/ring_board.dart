import 'package:flutter/material.dart';

import '../utils/board_ring.dart';

/// A static render of a board's ring layout, scaled to fit the available
/// width — no scroll, no zoom, no gesture handling of any kind, just a
/// plain `FittedBox`. Rectangular edge squares (tall/narrow on top &
/// bottom, wide/short on the sides) with big square corners — like a real
/// board — give tiles much more room for text than forcing every square to
/// the same small square.
class RingBoard extends StatelessWidget {
  const RingBoard({
    super.key,
    required this.squareCount,
    required this.cellBuilder,
    this.borderThickness = 130,
    this.innerLength = 62,
  });

  /// Number of real squares (the rest of the ring's capacity, if any, is
  /// still passed to [cellBuilder] so it can render empty filler slots).
  final int squareCount;

  final Widget Function(BuildContext context, int index, Size cellSize)
      cellBuilder;

  /// Depth of the ring (and side length of corner squares) — the "long"
  /// dimension of edge squares, since it's shared by only one square across
  /// the ring's width.
  final double borderThickness;

  /// Length of a non-corner square along its edge — the "short" dimension,
  /// since many squares share each edge's length.
  final double innerLength;

  @override
  Widget build(BuildContext context) {
    final side = ringSide(squareCount);
    final axisLengths = ringAxisLengths(
      side,
      borderThickness: borderThickness,
      innerLength: innerLength,
    );
    final rects = ringRects(side, axisLengths);
    final boardSize = axisLengths.fold(0.0, (sum, l) => sum + l);

    return AspectRatio(
      aspectRatio: 1,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: boardSize,
          height: boardSize,
          child: Stack(
            children: [
              for (var i = 0; i < rects.length; i++)
                Positioned(
                  left: rects[i].left,
                  top: rects[i].top,
                  width: rects[i].width,
                  height: rects[i].height,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: cellBuilder(
                      context,
                      i,
                      Size(rects[i].width, rects[i].height),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
