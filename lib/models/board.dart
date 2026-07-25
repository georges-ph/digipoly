import 'property.dart';

/// A Chance / Community Chest style card. [amount] is the money movement
/// relative to the bank: positive means the player receives, negative means
/// the player pays. Zero means the card has no direct money effect.
class BoardCard {
  const BoardCard({required this.id, required this.text, this.amount = 0});

  final String id;
  final String text;
  final int amount;

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'amount': amount};

  factory BoardCard.fromJson(Map<String, dynamic> json) => BoardCard(
        id: json['id'] as String,
        text: json['text'] as String? ?? '',
        amount: json['amount'] as int? ?? 0,
      );

  BoardCard copyWith({String? text, int? amount}) =>
      BoardCard(id: id, text: text ?? this.text, amount: amount ?? this.amount);
}

/// The full definition of a physical board: currency, money rules,
/// properties and card decks. Boards are plain serializable data so the same
/// JSON can be stored locally, sent to joining players inside the game
/// snapshot, written to an NFC card or shared in a community catalog.
class Board {
  const Board({
    required this.id,
    required this.name,
    required this.currencySymbol,
    required this.startingBalance,
    required this.salary,
    this.properties = const [],
    this.chanceCards = const [],
    this.communityChestCards = const [],
  });

  final String id;
  final String name;
  final String currencySymbol;

  /// Money each player starts the game with.
  final int startingBalance;

  /// Amount collected from the bank when passing GO.
  final int salary;

  final List<Property> properties;
  final List<BoardCard> chanceCards;
  final List<BoardCard> communityChestCards;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'currencySymbol': currencySymbol,
        'startingBalance': startingBalance,
        'salary': salary,
        'properties': properties.map((p) => p.toJson()).toList(),
        'chanceCards': chanceCards.map((c) => c.toJson()).toList(),
        'communityChestCards':
            communityChestCards.map((c) => c.toJson()).toList(),
      };

  factory Board.fromJson(Map<String, dynamic> json) => Board(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Untitled board',
        currencySymbol: json['currencySymbol'] as String? ?? r'$',
        startingBalance: json['startingBalance'] as int? ?? 1500,
        salary: json['salary'] as int? ?? 200,
        properties: (json['properties'] as List<dynamic>? ?? const [])
            .map((e) => Property.fromJson(e as Map<String, dynamic>))
            .toList(),
        chanceCards: (json['chanceCards'] as List<dynamic>? ?? const [])
            .map((e) => BoardCard.fromJson(e as Map<String, dynamic>))
            .toList(),
        communityChestCards:
            (json['communityChestCards'] as List<dynamic>? ?? const [])
                .map((e) => BoardCard.fromJson(e as Map<String, dynamic>))
                .toList(),
      );

  Board copyWith({
    String? name,
    String? currencySymbol,
    int? startingBalance,
    int? salary,
    List<Property>? properties,
    List<BoardCard>? chanceCards,
    List<BoardCard>? communityChestCards,
  }) =>
      Board(
        id: id,
        name: name ?? this.name,
        currencySymbol: currencySymbol ?? this.currencySymbol,
        startingBalance: startingBalance ?? this.startingBalance,
        salary: salary ?? this.salary,
        properties: properties ?? this.properties,
        chanceCards: chanceCards ?? this.chanceCards,
        communityChestCards: communityChestCards ?? this.communityChestCards,
      );

  /// The classic US edition as a ready-to-play template.
  factory Board.classic(String id) {
    Property street(
      String id,
      String name,
      int color,
      int price,
      List<int> rents,
      int housePrice,
    ) =>
        Property(
          id: id,
          name: name,
          kind: PropertyKind.street,
          colorValue: color,
          price: price,
          rentTiers: rents,
          housePrice: housePrice,
          mortgageValue: price ~/ 2,
        );

    const brown = 0xFF8B4513;
    const lightBlue = 0xFF87CEEB;
    const pink = 0xFFD81E75;
    const orange = 0xFFF57C00;
    const red = 0xFFD32F2F;
    const yellow = 0xFFFBC02D;
    const green = 0xFF2E7D32;
    const darkBlue = 0xFF1A47B8;
    const railroad = 0xFF37474F;
    const utility = 0xFF78909C;

    return Board(
      id: id,
      name: 'Classic',
      currencySymbol: r'$',
      startingBalance: 1500,
      salary: 200,
      properties: [
        street('med', 'Mediterranean Avenue', brown, 60, [2, 10, 30, 90, 160, 250], 50),
        street('bal', 'Baltic Avenue', brown, 60, [4, 20, 60, 180, 320, 450], 50),
        street('ori', 'Oriental Avenue', lightBlue, 100, [6, 30, 90, 270, 400, 550], 50),
        street('ver', 'Vermont Avenue', lightBlue, 100, [6, 30, 90, 270, 400, 550], 50),
        street('con', 'Connecticut Avenue', lightBlue, 120, [8, 40, 100, 300, 450, 600], 50),
        street('stc', 'St. Charles Place', pink, 140, [10, 50, 150, 450, 625, 750], 100),
        street('sta', 'States Avenue', pink, 140, [10, 50, 150, 450, 625, 750], 100),
        street('vir', 'Virginia Avenue', pink, 160, [12, 60, 180, 500, 700, 900], 100),
        street('stj', 'St. James Place', orange, 180, [14, 70, 200, 550, 750, 950], 100),
        street('ten', 'Tennessee Avenue', orange, 180, [14, 70, 200, 550, 750, 950], 100),
        street('nyk', 'New York Avenue', orange, 200, [16, 80, 220, 600, 800, 1000], 100),
        street('ken', 'Kentucky Avenue', red, 220, [18, 90, 250, 700, 875, 1050], 150),
        street('ind', 'Indiana Avenue', red, 220, [18, 90, 250, 700, 875, 1050], 150),
        street('ill', 'Illinois Avenue', red, 240, [20, 100, 300, 750, 925, 1100], 150),
        street('atl', 'Atlantic Avenue', yellow, 260, [22, 110, 330, 800, 975, 1150], 150),
        street('ven', 'Ventnor Avenue', yellow, 260, [22, 110, 330, 800, 975, 1150], 150),
        street('mar', 'Marvin Gardens', yellow, 280, [24, 120, 360, 850, 1025, 1200], 150),
        street('pac', 'Pacific Avenue', green, 300, [26, 130, 390, 900, 1100, 1275], 200),
        street('ncr', 'North Carolina Avenue', green, 300, [26, 130, 390, 900, 1100, 1275], 200),
        street('pen', 'Pennsylvania Avenue', green, 320, [28, 150, 450, 1000, 1200, 1400], 200),
        street('prk', 'Park Place', darkBlue, 350, [35, 175, 500, 1100, 1300, 1500], 200),
        street('bdw', 'Boardwalk', darkBlue, 400, [50, 200, 600, 1400, 1700, 2000], 200),
        const Property(id: 'rr1', name: 'Reading Railroad', kind: PropertyKind.railroad, colorValue: railroad, price: 200, rentTiers: [25, 50, 100, 200], mortgageValue: 100),
        const Property(id: 'rr2', name: 'Pennsylvania Railroad', kind: PropertyKind.railroad, colorValue: railroad, price: 200, rentTiers: [25, 50, 100, 200], mortgageValue: 100),
        const Property(id: 'rr3', name: 'B. & O. Railroad', kind: PropertyKind.railroad, colorValue: railroad, price: 200, rentTiers: [25, 50, 100, 200], mortgageValue: 100),
        const Property(id: 'rr4', name: 'Short Line', kind: PropertyKind.railroad, colorValue: railroad, price: 200, rentTiers: [25, 50, 100, 200], mortgageValue: 100),
        const Property(id: 'ele', name: 'Electric Company', kind: PropertyKind.utility, colorValue: utility, price: 150, rentTiers: [4, 10], mortgageValue: 75),
        const Property(id: 'wat', name: 'Water Works', kind: PropertyKind.utility, colorValue: utility, price: 150, rentTiers: [4, 10], mortgageValue: 75),
      ],
    );
  }
}
