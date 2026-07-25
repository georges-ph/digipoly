import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/game_transaction.dart';
import '../models/player.dart';
import '../providers/game_provider.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import 'player_avatar.dart';

/// Everything about one transaction: parties, type, property, note, exact
/// time and the balance it left me with.
class TransactionDetailsSheet extends StatelessWidget {
  const TransactionDetailsSheet({
    super.key,
    required this.transaction,
    required this.session,
    this.balanceAfter,
  });

  final GameTransaction transaction;
  final GameProvider session;
  final int? balanceAfter;

  String get _typeLabel => switch (transaction.type) {
        TransactionType.payment => 'Payment',
        TransactionType.rent => 'Rent',
        TransactionType.purchase => 'Property purchase',
        TransactionType.salary => 'Salary (passed GO)',
        TransactionType.house => 'Buildings',
        TransactionType.request => 'Requested payment',
        TransactionType.card => 'Card',
        TransactionType.mortgage => 'Mortgage',
      };

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

    final propertyName = transaction.propertyId == null
        ? null
        : session.propertyNameOf(transaction.propertyId!);

    Widget partyRow(String label, String accountId) {
      final player =
          accountId == Player.bankId ? null : session.playerById(accountId);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                label,
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            if (player != null)
              PlayerAvatar(player: player, size: 30, showPresence: false)
            else
              Container(
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
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                accountId == session.myPlayerId
                    ? 'You'
                    : session.accountName(accountId),
                style: textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    Widget factRow(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  label,
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
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
              (incoming ? '+' : (outgoing ? '−' : '')) +
                  formatMoney(transaction.amount, currency),
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
            if (transaction.note.isNotEmpty) factRow('Note', transaction.note),
            factRow(
              'When',
              DateFormat('EEEE d MMM y · HH:mm:ss')
                  .format(transaction.timestamp),
            ),
            if (balanceAfter != null)
              factRow(
                'Balance after',
                formatMoney(balanceAfter!, currency),
              ),
            factRow('Reference', transaction.id.split('-').first),
          ],
        ),
      ),
    );
  }
}
