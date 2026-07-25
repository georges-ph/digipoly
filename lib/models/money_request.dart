/// One player asking another for money (rent they forgot, a trade, ...).
/// The target approves or declines on their own device; approval turns into
/// a normal validated payment.
class MoneyRequest {
  const MoneyRequest({
    required this.id,
    required this.gameId,
    required this.requesterId,
    required this.targetId,
    required this.amount,
    required this.createdAt,
    this.note = '',
  });

  final String id;
  final String gameId;

  /// Who wants to receive the money.
  final String requesterId;

  /// Who is being asked to pay.
  final String targetId;

  final int amount;
  final String note;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'gameId': gameId,
        'requesterId': requesterId,
        'targetId': targetId,
        'amount': amount,
        'note': note,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory MoneyRequest.fromJson(Map<String, dynamic> json) => MoneyRequest(
        id: json['id'] as String,
        gameId: json['gameId'] as String? ?? '',
        requesterId: json['requesterId'] as String,
        targetId: json['targetId'] as String,
        amount: json['amount'] as int? ?? 0,
        note: json['note'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          json['createdAt'] as int? ?? 0,
        ),
      );
}
