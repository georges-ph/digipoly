import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Big banking-style numeric keypad. The value is owned by the parent;
/// digits append, backspace trims, long-press backspace clears.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({
    super.key,
    required this.value,
    required this.onChanged,
    this.maxDigits = 9,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int maxDigits;

  /// Appends [digits] in one go — "00" must be applied atomically, since
  /// two separate calls would both read the same (stale) `value`.
  void _append(String digits) {
    final text = value == 0 ? digits : '$value$digits';
    if (text.length > maxDigits) return;
    HapticFeedback.selectionClick();
    onChanged(int.parse(text));
  }

  void _backspace() {
    final text = '$value';
    HapticFeedback.selectionClick();
    onChanged(text.length <= 1 ? 0 : int.parse(text.substring(0, text.length - 1)));
  }

  @override
  Widget build(BuildContext context) {
    Widget key({String? digit, Widget? child, VoidCallback? onTap, VoidCallback? onLongPress}) {
      return Expanded(
        child: InkWell(
          onTap: onTap ?? (digit == null ? null : () => _append(digit)),
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 62,
            child: Center(
              child: child ??
                  Text(
                    digit ?? '',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
            ),
          ),
        ),
      );
    }

    Widget row(List<Widget> keys) => Row(children: keys);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([key(digit: '1'), key(digit: '2'), key(digit: '3')]),
        row([key(digit: '4'), key(digit: '5'), key(digit: '6')]),
        row([key(digit: '7'), key(digit: '8'), key(digit: '9')]),
        row([
          key(
            child: Text(
              '00',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            onTap: value == 0 ? null : () => _append('00'),
          ),
          key(digit: '0'),
          key(
            child: const Icon(Icons.backspace_outlined, size: 26),
            onTap: _backspace,
            onLongPress: () => onChanged(0),
          ),
        ]),
      ],
    );
  }
}
