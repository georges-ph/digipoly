class Player {
  final String name;

  const Player({
    required this.name,
  });

  @override
  String toString() => 'Player(name: $name)';

  @override
  bool operator ==(covariant Player other) {
    if (identical(this, other)) return true;
    return other.name == name;
  }

  @override
  int get hashCode => name.hashCode;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
    };
  }

  factory Player.fromMap(Map<String, dynamic> map) {
    return Player(
      name: map['name'] as String,
    );
  }
}
