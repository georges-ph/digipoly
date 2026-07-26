/// Geometry for rendering a board's squares as a physical ring around the
/// edge of a square grid (like a real board), instead of a plain
/// reading-order list/grid. Board-agnostic: works for any square count, not
/// just a classic 40-square board.
library;

/// A cell position in the NxN grid a ring is drawn on.
class RingCell {
  const RingCell(this.row, this.col);

  final int row;
  final int col;
}

/// Smallest grid side (cells per edge) whose perimeter fits [count]
/// squares. A classic 40-square board needs an 11x11 grid (perimeter 40).
int ringSide(int count) {
  var side = 2;
  while (4 * (side - 1) < count) {
    side++;
  }
  return side;
}

/// Perimeter cells of a [side]x[side] grid, in board traversal order:
/// starting at the bottom-right corner (GO, by convention) and moving
/// counter-clockwise — along the bottom edge, up the left edge, across the
/// top edge, then down the right edge back to the start.
List<RingCell> ringCells(int side) {
  final cells = <RingCell>[];
  for (var c = side - 1; c >= 0; c--) {
    cells.add(RingCell(side - 1, c));
  }
  for (var r = side - 2; r >= 0; r--) {
    cells.add(RingCell(r, 0));
  }
  for (var c = 1; c < side; c++) {
    cells.add(RingCell(0, c));
  }
  for (var r = 1; r < side - 1; r++) {
    cells.add(RingCell(r, side - 1));
  }
  return cells;
}

/// A cell's pixel box within the board.
class RingRect {
  const RingRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;
}

/// Pixel length of each of the [side] rows/columns of the grid: the two
/// border rows/columns (index 0 and `side - 1`) get [borderThickness],
/// every interior row/column gets [innerLength]. Real boards use this so
/// corner squares are big and square while edge squares are rectangular —
/// long along the edge is wrong; they're actually *short* along the edge
/// ([innerLength], since many share that length) and *long* across it
/// ([borderThickness], one ring-deep) — much more room for text than
/// forcing every square to the same small square.
List<double> ringAxisLengths(
  int side, {
  required double borderThickness,
  required double innerLength,
}) =>
    [
      for (var i = 0; i < side; i++)
        (i == 0 || i == side - 1) ? borderThickness : innerLength,
    ];

/// Pixel rects for each ring cell (see [ringCells]), given [axisLengths]
/// from [ringAxisLengths] (the same lengths apply to rows and columns,
/// since the grid is square).
List<RingRect> ringRects(int side, List<double> axisLengths) {
  final offsets = [0.0];
  for (final length in axisLengths) {
    offsets.add(offsets.last + length);
  }
  return [
    for (final cell in ringCells(side))
      RingRect(
        offsets[cell.col],
        offsets[cell.row],
        axisLengths[cell.col],
        axisLengths[cell.row],
      ),
  ];
}
