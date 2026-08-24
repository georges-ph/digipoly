import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/game_transaction.dart';
import '../models/player.dart';
import '../models/result.dart';
import '../providers/game_provider.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import '../utils/snack.dart';
import 'player_avatar.dart';

/// Everything about one transaction: parties, type, property, note, exact
/// time and the balance it left me with.
class TransactionDetailsSheet extends StatelessWidget {
  const TransactionDetailsSheet({
    super.key,
    required this.transaction,
    required this.session,
    this.balanceAfter,
    this.balanceAfterOwnerId,
  });

  final GameTransaction transaction;
  final GameProvider session;
  final int? balanceAfter;
  final String? balanceAfterOwnerId;

  /// Notes only make sense on free-form money moves — a rent/purchase/
  /// mortgage/tax/etc. transaction's "note" is really just its label, not
  /// something either party wrote, so editing it there would be confusing.
  /// Even on an editable type, only whoever actually made the transaction
  /// (`GameTransaction.makerId`) may edit its note — not just any party to
  /// it (e.g. the other side of a payment didn't write the note).
  bool get _noteIsEditable =>
      (transaction.type == TransactionType.payment ||
          transaction.type == TransactionType.request) &&
      transaction.makerId == session.myPlayerId;

  String get _typeLabel => switch (transaction.type) {
    TransactionType.payment => 'Payment',
    TransactionType.rent => 'Rent',
    TransactionType.purchase => 'Property purchase',
    TransactionType.salary => 'Salary (passed GO)',
    TransactionType.house => 'Buildings',
    TransactionType.request => 'Requested payment',
    TransactionType.card => 'Card',
    TransactionType.mortgage => 'Mortgage',
    TransactionType.tax => 'Tax',
    TransactionType.freeParking => 'Free Parking',
    TransactionType.transfer => 'Property transfer',
    TransactionType.jailCardTransfer => 'Get Out of Jail Free card transfer',
    TransactionType.loan => 'Bank loan',
    TransactionType.loanInterest => 'Loan interest',
  };

  Future<void> _editNote(BuildContext context) async {
    final controller = TextEditingController(text: transaction.note);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Add a note',
            counterText: '',
          ),
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || !context.mounted) return;

    final res = await session.editTransactionNote(transaction.id, result);
    if (!context.mounted) return;
    if (res.isOk) {
      Navigator.of(context).pop();
    } else {
      showSnack(context, res.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final currency = session.game?.board.currencySymbol ?? r'$';

    final incoming = transaction.toId == session.myPlayerId;
    final outgoing = transaction.fromId == session.myPlayerId;
    final color = incoming
        ? AppColors.income
        : (outgoing ? AppColors.expense : scheme.onSurface);

    // Not my transaction, but still show a direction: money leaving the
    // bank reads as a collection (+), everything else — including one
    // player paying another — reads from the payer's side (−), matching
    // the tile's convention. A $0 transfer has no direction.
    final String sign;
    if (incoming) {
      sign = '+';
    } else if (outgoing) {
      sign = '−';
    } else if (transaction.amount == 0) {
      sign = '';
    } else {
      sign = transaction.fromId == Player.bankId ? '+' : '−';
    }

    final propertyName = transaction.propertyId == null
        ? null
        : session.propertyNameOf(transaction.propertyId!);

    Widget partyRow(String label, String accountId) {
      final player = accountId == Player.bankId
          ? null
          : session.playerById(accountId);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                label,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (player != null)
              PlayerAvatar(player: player, size: 30, showPresence: false)
            else
              // Padding+border mirror PlayerAvatar's own always-reserved
              // ring so the bank's icon takes up the exact same footprint
              // as a player avatar — otherwise this row renders shorter
              // and its icon sits visibly left of the row below it.
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(
                    BorderSide(color: Colors.transparent, width: 3),
                  ),
                ),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.account_balance_rounded,
                    size: 16,
                    color: AppColors.accent,
                  ),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                accountId == session.myPlayerId
                    ? 'You'
                    : session.accountName(accountId),
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget factRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _typeLabel,
              textAlign: TextAlign.center,
              style: textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              sign + formatMoney(transaction.amount, currency),
              textAlign: TextAlign.center,
              style: textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                color: color,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  partyRow('From', transaction.fromId),
                  const Divider(height: 1),
                  partyRow('To', transaction.toId),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (propertyName != null) factRow('Property', propertyName),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Note',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      transaction.note.isEmpty ? 'No note' : transaction.note,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: transaction.note.isEmpty
                            ? scheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ),
                  if (!session.isSpectating && _noteIsEditable)
                    InkWell(
                      onTap: () => _editNote(context),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            factRow(
              'When',
              DateFormat(
                'EEEE d MMM y · h:mm:ss a',
              ).format(transaction.timestamp),
            ),
            if (balanceAfter != null)
              factRow(
                balanceAfterOwnerId == null ||
                        balanceAfterOwnerId == session.myPlayerId
                    ? 'Balance after'
                    : "${session.accountName(balanceAfterOwnerId!)}'s "
                          'balance after',
                formatMoney(balanceAfter!, currency),
              ),
            factRow('Reference', transaction.id.split('-').first),
          ],
        ),
      ),
    );
  }
}
