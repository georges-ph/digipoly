/// A participant in a game. Identity (the id) is a device-generated UUID that
/// survives disconnects: the socket can die and come back, the player stays.
class Player {
  const Player({
    required this.id,
    required this.name,
    required this.balance,
    this.seat = 0,
    this.isHost = false,
    this.isOnline = false,
    this.hasLeft = false,
    this.position = 0,
    this.inJail = false,
    this.jailTurns = 0,
    this.jailCards = 0,
  });

  /// Sentinel id for the bank. The bank has infinite money and is a valid
  /// sender/recipient in any transaction.
  static const String bankId = 'bank';
  static const String bankName = 'Bank';

  final String id;
  final String name;
  final int balance;

  /// Join order; defines the turn rotation.
  final int seat;

  final bool isHost;

  /// Whether this player's socket is currently connected.
  final bool isOnline;

  /// Whether the player explicitly left the game (as opposed to just
  /// disconnecting). Left players stay in history but can't transact.
  final bool hasLeft;

  /// Index into the board's `properties` list (its square order). Only
  /// meaningful for boards with a curated layout (`board.goIndex != -1`).
  final int position;

  /// Whether the player is currently locked in jail.
  final bool inJail;

  /// Failed jail-escape attempts so far this stay (0..3).
  final int jailTurns;

  /// Get Out of Jail Free cards currently held (drawn from Chance/Community
  /// Chest, kept until used — see [GameEngine]/GameServer's jail handling).
  final int jailCards;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'balance': balance,
        'seat': seat,
        'isHost': isHost,
        'isOnline': isOnline,
        'hasLeft': hasLeft,
        'position': position,
        'inJail': inJail,
        'jailTurns': jailTurns,
        'jailCards': jailCards,
      };

  factory Player.fromJson(Map<String, dynamic> json) => Player(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Player',
        balance: json['balance'] as int? ?? 0,
        seat: json['seat'] as int? ?? 0,
        isHost: json['isHost'] as bool? ?? false,
        isOnline: json['isOnline'] as bool? ?? false,
        hasLeft: json['hasLeft'] as bool? ?? false,
        position: json['position'] as int? ?? 0,
        inJail: json['inJail'] as bool? ?? false,
        jailTurns: json['jailTurns'] as int? ?? 0,
        jailCards: json['jailCards'] as int? ?? 0,
      );

  Player copyWith({
    String? name,
    int? balance,
    int? seat,
    bool? isHost,
    bool? isOnline,
    bool? hasLeft,
    int? position,
    bool? inJail,
    int? jailTurns,
    int? jailCards,
  }) =>
      Player(
        id: id,
        name: name ?? this.name,
        balance: balance ?? this.balance,
        seat: seat ?? this.seat,
        isHost: isHost ?? this.isHost,
        isOnline: isOnline ?? this.isOnline,
        hasLeft: hasLeft ?? this.hasLeft,
        position: position ?? this.position,
        inJail: inJail ?? this.inJail,
        jailTurns: jailTurns ?? this.jailTurns,
        jailCards: jailCards ?? this.jailCards,
      );
}
