import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/join_address.dart';
import '../widgets/qr_scan_view.dart';

/// Scan a room's QR code instead of typing its address — mDNS discovery
/// doesn't reach every device/network, and a raw IP means nothing to most
/// players. Pops with the parsed (host, port) once a valid code is found.
class ScanJoinScreen extends StatefulWidget {
  const ScanJoinScreen({super.key});

  @override
  State<ScanJoinScreen> createState() => _ScanJoinScreenState();
}

class _ScanJoinScreenState extends State<ScanJoinScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final address = parseJoinAddress(raw);
      if (address == null) continue;

      _handled = true;
      Navigator.of(context).pop(address);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan room QR')),
      body: QrScanView(
        onDetect: _onDetect,
        hintText: "Point at the host's room QR code",
      ),
    );
  }
}
