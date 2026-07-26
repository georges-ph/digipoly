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
    this.jailFine = 50,
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

  /// Cost to pay your way out of jail on your turn.
  final int jailFine;

  /// Every square on the board, in physical board order — ownable
  /// properties and special squares (GO, Jail, Tax, ...) alike. A board
  /// with no [PropertyKind.go] entry has no curated layout: token position
  /// tracking and its auto-effects stay off, and the game behaves exactly
  /// as a board without this feature always has.
  final List<Property> properties;
  final List<BoardCard> chanceCards;
  final List<BoardCard> communityChestCards;

  /// Index of the (first) GO square in [properties], or -1 if none.
  int get goIndex => properties.indexWhere((p) => p.kind == PropertyKind.go);

  /// Index of the (first) Jail square in [properties], or -1 if none.
  int get jailIndex =>
      properties.indexWhere((p) => p.kind == PropertyKind.jail);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'currencySymbol': currencySymbol,
        'startingBalance': startingBalance,
        'salary': salary,
        'jailFine': jailFine,
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
        jailFine: json['jailFine'] as int? ?? 50,
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
    int? jailFine,
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
        jailFine: jailFine ?? this.jailFine,
        properties: properties ?? this.properties,
        chanceCards: chanceCards ?? this.chanceCards,
        communityChestCards: communityChestCards ?? this.communityChestCards,
      );
}
