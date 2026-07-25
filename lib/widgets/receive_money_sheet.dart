import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/game_provider.dart';
import '../utils/formatting.dart';
import '../utils/pay_code.dart';

/// "Receive money": shows my payment QR. Leave the amount empty and the
/// payer types it, or set an amount and the payer just confirms.
class ReceiveMoneySheet extends StatefulWidget {
  const ReceiveMoneySheet({super.key});

  @override
  State<ReceiveMoneySheet> createState() => _ReceiveMoneySheetState();
}

class _ReceiveMoneySheetState extends State<ReceiveMoneySheet> {
  int _amount = 0;
  String? _newestTxId;

  @override
  void initState() {
    super.initState();
    final transactions = context.read<GameProvider>().transactions;
    _newestTxId = transactions.isEmpty ? null : transactions.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameProvider>();
    final game = session.game;
    if (game == null) return const SizedBox(height: 200);

    // Getting paid while showing the code closes it — payment complete.
    final transactions = session.transactions;
    final newest = transactions.isEmpty ? null : transactions.first;
    if (newest != null &&
        newest.id != _newestTxId &&
        newest.toId == session.myPlayerId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }

    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final code = PayCode(
      gameId: game.id,
      playerId: session.myPlayerId,
      amount: _amount,
    );

    return SafeArea(
      child: SingleChildScrollView(
        // The keyboard inset keeps the amount field visible while typing.
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Receive money',
              textAlign: TextAlign.center,
              style:
                  textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _amount > 0
                  ? 'They scan and confirm '
                      '${formatMoney(_amount, game.board.currencySymbol)}'
                  : 'They scan and choose the amount',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: QrImageView(
                  data: code.encode(),
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: 'Amount (optional)',
                prefixText: '${game.board.currencySymbol} ',
              ),
              onChanged: (value) => setState(
                () => _amount = int.tryParse(value.trim()) ?? 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
