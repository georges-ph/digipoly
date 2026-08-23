import 'player.dart';

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
  mortgage,

  /// Landing on a Tax square, or paying the jail fine — both feed the
  /// Free Parking pot.
  tax,

  /// Landing on Free Parking pays out the accumulated pot.
  freeParking,

  /// A property handed to another player directly (no money moves — any
  /// cash for the deal is a separate, normal [payment]). Logged at $0
  /// purely so the trade shows up in the activity feed.
  transfer,

  /// A held Get Out of Jail Free card handed to another player directly —
  /// same idea as [transfer], just for a card instead of a property. No
  /// [GameTransaction.propertyId]; logged at $0 for the same reason.
  jailCardTransfer,

  /// Borrowing from the bank (bank pays player) or repaying it (player
  /// pays bank) — either direction uses this same type, told apart by
  /// fromId/toId like every other transaction.
  loan,

  /// Interest accrued on an outstanding loan balance (see
  /// `Board.loanInterestRate`) — no cash actually moves, this is a record
  /// of the loan balance growing, not a real payment. fromId is the
  /// borrower, toId the bank, same direction as [loan] repayment.
  loanInterest;

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

  /// Whoever actually triggered this transaction — the payer, except a
  /// bank collection has no controlling player on the paying side, so it
  /// falls to the collector instead. Used to gate note edits to the one
  /// player who wrote it, not just anyone it happened to involve.
  String get makerId => fromId == Player.bankId ? toId : fromId;

  GameTransaction copyWith({String? note}) => GameTransaction(
        id: id,
        gameId: gameId,
        fromId: fromId,
        toId: toId,
        amount: amount,
        timestamp: timestamp,
        type: type,
        propertyId: propertyId,
        note: note ?? this.note,
      );

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
