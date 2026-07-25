/// What kind of money movement a transaction is, so the activity feed can
/// say "Rent · Boardwalk" instead of relying on hand-typed notes.
enum TransactionType {
  payment,
  rent,
  purchase,
  salary,
  house,
  request,

  /// A Chance / Community Chest card's money effect.
  card,

  /// Mortgaging a property (bank pays owner) or lifting the mortgage
  /// (owner pays value + interest).
  mortgage;

  static TransactionType fromName(String name) =>
      TransactionType.values.firstWhere(
        (type) => type.name == name,
        orElse: () => TransactionType.payment,
      );
}

/// A single money movement between two accounts (players or the bank).
class GameTransaction {
  const GameTransaction({
    required this.id,
    required this.gameId,
    required this.fromId,
    required this.toId,
    required this.amount,
    required this.timestamp,
    this.type = TransactionType.payment,
    this.propertyId,
    this.note = '',
  });

  final String id;
  final String gameId;

  /// Sender account id: a player id or [Player.bankId].
  final String fromId;

  /// Recipient account id: a player id or [Player.bankId].
  final String toId;

  /// Always positive; direction is expressed by from/to.
  final int amount;

  final TransactionType type;

  /// The property involved, for [TransactionType.rent], [purchase] and
  /// [house] transactions.
  final String? propertyId;

  final DateTime timestamp;
  final String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'gameId': gameId,
        'fromId': fromId,
        'toId': toId,
        'amount': amount,
        'type': type.name,
        if (propertyId != null) 'propertyId': propertyId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'note': note,
      };

  factory GameTransaction.fromJson(Map<String, dynamic> json) =>
      GameTransaction(
        id: json['id'] as String,
        gameId: json['gameId'] as String,
        fromId: json['fromId'] as String,
        toId: json['toId'] as String,
        amount: json['amount'] as int? ?? 0,
        type: TransactionType.fromName(json['type'] as String? ?? 'payment'),
        propertyId: json['propertyId'] as String?,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          json['timestamp'] as int? ?? 0,
        ),
        note: json['note'] as String? ?? '',
      );
}
