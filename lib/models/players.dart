import 'dart:convert';

import 'player.dart';

class Players {
  final List<Player> players;

  Players({
    required this.players,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'players': players.map((x) => x.toMap()).toList(),
    };
  }

  factory Players.fromMap(Map<String, dynamic> map) {
    return Players(
      players: List<Player>.from(
        (map['players'] as List<dynamic>).map<Player>(
          (x) => Player.fromMap(x as Map<String, dynamic>),
        ),
      ),
    );
  }

  String toJson() => json.encode(toMap());

  factory Players.fromJson(String source) => Players.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'Players(players: $players)';
}
