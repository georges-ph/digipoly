import 'dart:convert';

import 'package:digipoly/models/player.dart';

class Players {
  final List<Player> players;

  Players({
    required this.players,
  });

  Map<String, dynamic> toMap() {
    return {
      'players': players.map((x) => x.toMap()).toList(),
    };
  }

  factory Players.fromMap(Map<String, dynamic> map) {
    return Players(
      players: List<Player>.from(map['players']?.map((x) => Player.fromMap(x))),
    );
  }

  String toJson() => json.encode(toMap());

  factory Players.fromJson(String source) =>
      Players.fromMap(json.decode(source));

  @override
  String toString() => 'Players(players: $players)';
}
