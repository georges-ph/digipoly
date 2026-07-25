/// A dice roll made by a player. Rolls are generated on the server so
/// nobody's phone can be "lucky" — the whole table sees the same result.
class DiceRoll {
  const DiceRoll({
    required this.playerId,
    required this.die1,
    required this.die2,
  });

  final String playerId;
  final int die1;
  final int die2;

  int get total => die1 + die2;
  bool get isDouble => die1 == die2;

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'die1': die1,
        'die2': die2,
      };

  factory DiceRoll.fromJson(Map<String, dynamic> json) => DiceRoll(
        playerId: json['playerId'] as String,
        die1: json['die1'] as int? ?? 1,
        die2: json['die2'] as int? ?? 1,
      );
}
