import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Shared camera view for every QR scan screen (room join, scan-to-pay):
/// a [MobileScanner] restricted to a centered square window
/// (`scanWindow` — ignores codes outside it, so a QR visible elsewhere in
/// frame doesn't get picked up by accident), dimmed everywhere else with a
/// bracketed viewfinder outline, plus a hint bar pinned to the bottom.
class QrScanView extends StatelessWidget {
  const QrScanView({
    super.key,
    required this.onDetect,
    required this.hintText,
  });

  final void Function(BarcodeCapture capture) onDetect;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final cutOutSize = size.shortestSide * 0.7;
            final scanWindow = Rect.fromCenter(
              center: size.center(Offset.zero),
              width: cutOutSize,
              height: cutOutSize,
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(scanWindow: scanWindow, onDetect: onDetect),
                IgnorePointer(
                  child: CustomPaint(
                    painter: _ViewfinderPainter(cutOutSize: cutOutSize),
                  ),
                ),
              ],
            );
          },
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              hintText,
              style: textTheme.bodyMedium?.copyWith(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({required this.cutOutSize});

  final double cutOutSize;

  @override
  void paint(Canvas canvas, Size size) {
    final cutOutRect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: cutOutSize,
      height: cutOutSize,
    );
    final cutOutRRect =
        RRect.fromRectAndRadius(cutOutRect, const Radius.circular(20));

    final scrimPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()..addRRect(cutOutRRect),
    );
    canvas.drawPath(
      scrimPath,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    canvas.drawRRect(
      cutOutRRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    const bracketLength = 26.0;
    const inset = 6.0;
    final bracketPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    void corner(Offset origin, Offset horizontal, Offset vertical) {
      canvas.drawLine(origin, origin + horizontal, bracketPaint);
      canvas.drawLine(origin, origin + vertical, bracketPaint);
    }

    final rect = cutOutRect.inflate(-inset);
    corner(rect.topLeft, const Offset(bracketLength, 0),
        const Offset(0, bracketLength));
    corner(rect.topRight, const Offset(-bracketLength, 0),
        const Offset(0, bracketLength));
    corner(rect.bottomLeft, const Offset(bracketLength, 0),
        const Offset(0, -bracketLength));
    corner(rect.bottomRight, const Offset(-bracketLength, 0),
        const Offset(0, -bracketLength));
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter oldDelegate) =>
      oldDelegate.cutOutSize != cutOutSize;
}
