import 'package:intl/intl.dart';

final NumberFormat _money = NumberFormat('#,##0');

/// `1500` with symbol `$` -> `$1,500`. `-1500` -> `-$1,500` (balances are
/// allowed to go negative — debt owed rather than a blocked payment).
String formatMoney(int amount, String symbol) =>
    '${amount < 0 ? '-' : ''}$symbol${_money.format(amount.abs())}';

/// Signed variant for transaction feeds: `+$200` / `-$60`.
String formatSignedMoney(int amount, String symbol, {required bool incoming}) =>
    '${incoming ? '+' : '-'}${formatMoney(amount.abs(), symbol)}';

/// Section label for grouping an activity feed by day.
String formatDay(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('EEEE, d MMM').format(time);
}

/// Short relative timestamp for activity feeds.
String formatWhen(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24 && now.day == time.day) {
    return DateFormat.Hm().format(time);
  }
  if (diff.inDays < 7) return DateFormat('E, HH:mm').format(time);
  return DateFormat('d MMM').format(time);
}
