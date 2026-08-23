import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/result.dart';
import '../providers/game_provider.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import 'amount_keypad.dart';

/// Borrow from the bank or repay an outstanding loan. Interest accrues
/// automatically each lap of GO (`Board.loanInterestRate`) — shown here so
/// borrowing doesn't read as free money.
class LoanSheet extends StatefulWidget {
  const LoanSheet({super.key});

  @override
  State<LoanSheet> createState() => _LoanSheetState();
}

class _LoanSheetState extends State<LoanSheet> {
  int _amount = 0;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<Result<void>> Function() action) async {
    if (_busy || _amount <= 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isOk) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = result.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameProvider>();
    final board = session.game?.board;
    if (board == null) return const SizedBox(height: 200);

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final currency = board.currencySymbol;
    final owed = session.me?.loanBalance ?? 0;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bank loan',
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              owed > 0
                  ? 'You owe ${formatMoney(owed, currency)} · '
                        '${board.loanInterestRate}% interest each lap of GO'
                  : '${board.loanInterestRate}% interest each lap of GO, '
                        'added to what you owe',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                formatMoney(_amount, currency),
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            AmountKeypad(
              value: _amount,
              onChanged: (value) => setState(() => _amount = value),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: _busy || _amount <= 0 || owed <= 0
                        ? null
                        : () => _run(
                            () => session.repayLoan(
                              _amount > owed ? owed : _amount,
                            ),
                          ),
                    child: const Text('Repay'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: _busy || _amount <= 0
                        ? null
                        : () => _run(() => session.takeLoan(_amount)),
                    child: const Text('Borrow'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Center(
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.expense,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
