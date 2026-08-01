import 'property.dart';

/// A Chance / Community Chest style card. [amount] is the money movement
/// relative to the bank: positive means the player receives, negative means
/// the player pays. Zero means the card has no direct money effect.
///
/// [moveToPropertyId] is a forward "Advance to X" effect — the drawer's
/// token jumps straight to that square (paying GO salary if it's passed/
/// landed on along the way) and whatever's there is then resolved exactly
/// like landing on it normally would.
///
/// [moveBySpaces] is a relative move by a fixed number of squares — positive
/// forward, negative backward (the classic "Go Back 3 Spaces" card). Unlike
/// [moveToPropertyId] this never pays GO salary, even if it happens to land
/// exactly on GO, since backing up onto it isn't "passing" GO — matching the
/// physical rule that a Go Back card never collects.
///
/// [grantsJailCard] is the classic "Get Out of Jail Free" card: instead of
/// any immediate effect, the drawer holds onto it (`Player.jailCards`) until
/// they choose to use it to leave jail for free, skipping the fine and the
/// roll. Stays out of its deck's rotation while held, same as a physical
/// card being in someone's hand instead of the pile.
///
/// [perHouseCharge]/[perHotelCharge] are the classic "street repairs" cards:
/// "pay $X per house, $Y per hotel you own". The charge is computed from the
/// drawer's own buildings across every property they own (`GameEngine.
/// computeBuildingRepairs`) at draw time, not a fixed [amount] — always a
/// charge to the drawer, never a payout.
///
/// A card is exactly one of: a money card, a move-to card, a move-by card, a
/// jail card, or a repairs card — the board editor enforces that. Movement
/// effects are only meaningful on boards with a curated layout; elsewhere
/// there is no position to move, so the card is shown but has no effect.
class BoardCard {
  const BoardCard({
    required this.id,
    required this.text,
    this.amount = 0,
    this.moveToPropertyId,
    this.moveBySpaces,
    this.grantsJailCard = false,
    this.perHouseCharge,
    this.perHotelCharge,
  });

  final String id;
  final String text;
  final int amount;
  final String? moveToPropertyId;
  final int? moveBySpaces;
  final bool grantsJailCard;
  final int? perHouseCharge;
  final int? perHotelCharge;

  /// Whether this is a "pay per building" repairs card at all — true as
  /// soon as either rate is set, even if the author left the other at 0.
  bool get isBuildingRepairs => perHouseCharge != null || perHotelCharge != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'amount': amount,
        if (moveToPropertyId != null) 'moveToPropertyId': moveToPropertyId,
        if (moveBySpaces != null) 'moveBySpaces': moveBySpaces,
        if (grantsJailCard) 'grantsJailCard': grantsJailCard,
        if (perHouseCharge != null) 'perHouseCharge': perHouseCharge,
        if (perHotelCharge != null) 'perHotelCharge': perHotelCharge,
      };

  factory BoardCard.fromJson(Map<String, dynamic> json) => BoardCard(
        id: json['id'] as String,
        text: json['text'] as String? ?? '',
        amount: json['amount'] as int? ?? 0,
        moveToPropertyId: json['moveToPropertyId'] as String?,
        moveBySpaces: json['moveBySpaces'] as int?,
        grantsJailCard: json['grantsJailCard'] as bool? ?? false,
        perHouseCharge: json['perHouseCharge'] as int?,
        perHotelCharge: json['perHotelCharge'] as int?,
      );

  BoardCard copyWith({
    String? text,
    int? amount,
    String? moveToPropertyId,
    int? moveBySpaces,
    bool? grantsJailCard,
    int? perHouseCharge,
    int? perHotelCharge,
    bool clearMoveTarget = false,
  }) =>
      BoardCard(
        id: id,
        text: text ?? this.text,
        amount: amount ?? this.amount,
        moveToPropertyId: clearMoveTarget
            ? null
            : (moveToPropertyId ?? this.moveToPropertyId),
        moveBySpaces: clearMoveTarget
            ? null
            : (moveBySpaces ?? this.moveBySpaces),
        grantsJailCard: clearMoveTarget
            ? false
            : (grantsJailCard ?? this.grantsJailCard),
        perHouseCharge: clearMoveTarget
            ? null
            : (perHouseCharge ?? this.perHouseCharge),
        perHotelCharge: clearMoveTarget
            ? null
            : (perHotelCharge ?? this.perHotelCharge),
      );
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
