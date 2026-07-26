enum PropertyKind {
  street,
  railroad,
  utility,

  /// Passing/landing here pays the board's salary (doubled if landed on
  /// exactly). Not ownable.
  go,

  /// Not ownable. A player only stops moving here when sent by a
  /// [goToJail] square or failing to escape; otherwise it's just visited.
  jail,

  /// Not ownable. Pays out the accumulated pot, if any (house rule).
  freeParking,

  /// Not ownable. Sends the landing player straight to the board's jail
  /// square.
  goToJail,

  /// Not ownable. [Property.price] is reused as the fixed tax amount,
  /// auto-charged to the bank and added to the Free Parking pot.
  tax,

  /// Not ownable. Draws from the board's Chance deck.
  chance,

  /// Not ownable. Draws from the board's Community Chest deck.
  communityChest;

  /// Whether a square of this kind can be bought/owned/mortgaged/built on.
  bool get isOwnable =>
      this == street || this == railroad || this == utility;

  static PropertyKind fromName(String name) => PropertyKind.values.firstWhere(
        (kind) => kind.name == name,
        orElse: () => PropertyKind.street,
      );
}

/// A single purchasable tile on a board.
///
/// This is reference data: the app shows it to players so nobody has to dig
/// through the rulebook card, it does not compute rents by itself.
class Property {
  const Property({
    required this.id,
    required this.name,
    required this.kind,
    required this.colorValue,
    required this.price,
    required this.rentTiers,
    this.housePrice = 0,
    this.mortgageValue = 0,
  });

  final String id;
  final String name;
  final PropertyKind kind;

  /// ARGB color of the property group, e.g. `0xFF8B4513` for brown.
  final int colorValue;

  final int price;

  /// For streets: rent with 0 houses, 1..4 houses, hotel (6 entries).
  /// For railroads: rent owning 1..4 of them.
  /// For utilities: dice multipliers owning 1..2 of them.
  final List<int> rentTiers;

  final int housePrice;
  final int mortgageValue;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'color': colorValue,
        'price': price,
        'rentTiers': rentTiers,
        'housePrice': housePrice,
        'mortgageValue': mortgageValue,
      };

  factory Property.fromJson(Map<String, dynamic> json) => Property(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: PropertyKind.fromName(json['kind'] as String? ?? 'street'),
        colorValue: json['color'] as int? ?? 0xFF9E9E9E,
        price: json['price'] as int? ?? 0,
        rentTiers: (json['rentTiers'] as List<dynamic>? ?? const [])
            .map((e) => e as int)
            .toList(),
        housePrice: json['housePrice'] as int? ?? 0,
        mortgageValue: json['mortgageValue'] as int? ?? 0,
      );

  Property copyWith({
    String? name,
    PropertyKind? kind,
    int? colorValue,
    int? price,
    List<int>? rentTiers,
    int? housePrice,
    int? mortgageValue,
  }) =>
      Property(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        colorValue: colorValue ?? this.colorValue,
        price: price ?? this.price,
        rentTiers: rentTiers ?? this.rentTiers,
        housePrice: housePrice ?? this.housePrice,
        mortgageValue: mortgageValue ?? this.mortgageValue,
      );
}
