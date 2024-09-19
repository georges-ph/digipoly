import 'dart:convert';

class Player {
  final String name;
  int balance;
  final int port;

  Player({
    required this.name,
    required this.balance,
    required this.port,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'balance': balance,
      'port': port,
    };
  }

  factory Player.fromMap(Map<String, dynamic> map) {
    return Player(
      name: map['name'] as String,
      balance: map['balance'] as int,
      port: map['port'] as int,
    );
  }

  String toJson() => json.encode(toMap());

  factory Player.fromJson(String source) => Player.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'Player(name: $name, balance: $balance, port: $port)';
}
