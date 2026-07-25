import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player.dart';
import '../models/result.dart';
import '../providers/game_provider.dart';
import '../services/nfc_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import '../utils/snack.dart';

/// A player's payment card, styled like the debit card it pretends to be.
/// From here a physical NFC tag is registered ("written") for the player:
/// once registered, anyone can type an amount in Send and tap the card to
/// pay them — same card in every game, since it carries the player id.
class PlayerCardSheet extends StatefulWidget {
  const PlayerCardSheet({super.key, required this.player});

  final Player player;

  @override
  State<PlayerCardSheet> createState() => _PlayerCardSheetState();
}

class _PlayerCardSheetState extends State<PlayerCardSheet> {
  final _nfc = NfcService.instance;
  bool _nfcAvailable = false;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    _nfc.isAvailable().then((available) {
      if (mounted) setState(() => _nfcAvailable = available);
    });
  }

  @override
  void dispose() {
    _nfc.cancel();
    super.dispose();
  }

  Future<void> _register() async {
    if (_writing) return;
    setState(() => _writing = true);
    final result = await _nfc.writeText(
      NfcService.playerPayload(playerId: widget.player.id),
    );
    if (!mounted) return;
    setState(() => _writing = false);
    if (result.error == NfcService.cancelled) return;
    showSnack(
      context,
      result.isOk
          ? 'Card registered to ${widget.player.name}. Tap it in Send '
              'to pay them.'
          : result.error!,
    );
    if (result.isOk) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameProvider>();
    final board = session.game?.board;
    final player = session.playerById(widget.player.id) ?? widget.player;
    final isMe = player.id == session.myPlayerId;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    // A stable fake card number derived from the player id.
    final digits = player.id.replaceAll(RegExp(r'[^0-9]'), '').padRight(4, '0');
    final last4 = digits.substring(digits.length - 4);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1.62,
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'DIGIPOLY',
                          style: textTheme.labelLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.contactless_rounded,
                            color: Colors.white, size: 26),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '••••  ••••  ••••  $last4',
                      style: textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CARD HOLDER',
                                style: textTheme.labelSmall?.copyWith(
                                  color: Colors.white
                                      .withValues(alpha: 0.6),
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Text(
                                player.name.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (board != null)
                          Text(
                            formatMoney(
                                player.balance, board.currencySymbol),
                            style: textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (_nfcAvailable)
              FilledButton.icon(
                onPressed: _writing ? null : _register,
                icon: _writing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.nfc_rounded),
                label: Text(
                  _writing
                      ? 'Hold a card near the device…'
                      : 'Register a physical card',
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'This device has no NFC. Register the card from a phone '
                  'that does — it works for any player.',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            if (_writing)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: TextButton(
                  onPressed: () {
                    _nfc.cancel();
                    setState(() => _writing = false);
                  },
                  child: const Text('Cancel'),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              isMe
                  ? 'Once registered, anyone types an amount in Send and '
                      'taps your card to pay you — like tap-to-pay. The '
                      'same card works in every game you join.'
                  : 'Register a blank NFC tag as ${player.name}\'s card. '
                      'Typing an amount in Send and tapping it pays them.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
