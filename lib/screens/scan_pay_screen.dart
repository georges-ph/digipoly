import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../providers/game_provider.dart';
import '../utils/pay_code.dart';
import '../utils/snack.dart';
import '../widgets/qr_scan_view.dart';
import 'send_money_screen.dart';

/// Whether this platform can scan QR codes (mobile_scanner has no Windows
/// or Linux implementation).
bool get canScanQr =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Scan another player's payment QR and land in the send flow with the
/// recipient (and amount, if they fixed one) already filled in.
class ScanPayScreen extends StatefulWidget {
  const ScanPayScreen({super.key});

  @override
  State<ScanPayScreen> createState() => _ScanPayScreenState();
}

class _ScanPayScreenState extends State<ScanPayScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final code = PayCode.parse(raw);
      if (code == null) continue;

      final session = context.read<GameProvider>();
      final game = session.game;
      String? problem;
      if (game == null || code.gameId != game.id) {
        problem = 'That code belongs to a different game.';
      } else if (code.playerId == session.myPlayerId) {
        problem = 'That is your own code.';
      } else {
        final player = session.playerById(code.playerId);
        if (player == null || player.hasLeft) {
          problem = 'That player is not in this game.';
        }
      }
      if (problem != null) {
        _handled = true;
        Navigator.of(context).pop();
        showSnack(context, problem);
        return;
      }

      _handled = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SendMoneyScreen(
            initialRecipientId: code.playerId,
            initialAmount: code.amount,
            fromScannedCode: true,
          ),
        ),
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan to pay')),
      body: QrScanView(
        onDetect: _onDetect,
        hintText: "Point at another player's payment code",
      ),
    );
  }
}
