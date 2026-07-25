/// The payload inside a payment QR code:
/// `digipoly:pay:<gameId>:<playerId>:<amount>`.
///
/// The receiver shows the code; the payer scans it. Amount 0 means the
/// receiver left it open and the payer types it.
class PayCode {
  const PayCode({
    required this.gameId,
    required this.playerId,
    this.amount = 0,
  });

  final String gameId;

  /// Who gets paid.
  final String playerId;

  /// 0 = payer chooses.
  final int amount;

  String encode() => 'digipoly:pay:$gameId:$playerId:$amount';

  static PayCode? parse(String text) {
    final parts = text.trim().split(':');
    if (parts.length != 5 || parts[0] != 'digipoly' || parts[1] != 'pay') {
      return null;
    }
    final amount = int.tryParse(parts[4]);
    if (amount == null || amount < 0) return null;
    return PayCode(gameId: parts[2], playerId: parts[3], amount: amount);
  }
}
