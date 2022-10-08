import 'dart:convert';

class Player {
  final String name;
  final int port;

  Player({
    required this.name,
    required this.port,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'port': port,
    };
  }

  factory Player.fromMap(Map<String, dynamic> map) {
    return Player(
      name: map['name'] ?? '',
      port: map['port']?.toInt() ?? 0,
    );
  }

  String toJson() => json.encode(toMap());

  factory Player.fromJson(String source) => Player.fromMap(json.decode(source));

  @override
  String toString() => 'Player(name: $name, port: $port)';
}
