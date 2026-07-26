import '../models/board.dart';
import '../models/game_transaction.dart';
import '../models/player.dart';
import '../models/property.dart';
import '../models/property_ownership.dart';
import '../models/result.dart';

/// Outcome of one dice roll attempted while in jail.
enum JailRollOutcome {
  /// Doubles: free, and the roll also moves the player.
  escaped,

  /// Not doubles, and attempts remain — stays in jail, no movement.
  stillStuck,

  /// Not doubles on the 3rd attempt — the fine is forced, and the roll
  /// still moves the player (same as escaping, just paid for).
  mustPayNow,
}

/// The money rules, and nothing else. Pure functions over game state — no
/// sockets, no database — so the server can validate intents in one place
/// and the logic stays trivially testable.
abstract final class GameEngine {
  /// Validates [tx] against [players] and, if valid, returns the player list
  /// with updated balances. The bank ([Player.bankId]) has infinite money.
  static Result<List<Player>> applyPayment(
    List<Player> players,
    GameTransaction tx,
  ) {
    if (tx.amount <= 0) {
      return err('Amount must be greater than zero.');
    }
    if (tx.fromId == tx.toId) {
      return err('Sender and recipient must be different.');
    }

    Player? find(String id) {
      for (final player in players) {
        if (player.id == id) return player;
      }
      return null;
    }

    Player? from;
    if (tx.fromId != Player.bankId) {
      from = find(tx.fromId);
      if (from == null) return err('Unknown sender.');
      if (from.hasLeft) return err('${from.name} has left the game.');
      if (from.balance < tx.amount) {
        return err('${from.name} does not have enough money.');
      }
    }

    Player? to;
    if (tx.toId != Player.bankId) {
      to = find(tx.toId);
      if (to == null) return err('Unknown recipient.');
      if (to.hasLeft) return err('${to.name} has left the game.');
    }

    final updated = players.map((player) {
      if (player.id == tx.fromId) {
        return player.copyWith(balance: player.balance - tx.amount);
      }
      if (player.id == tx.toId) {
        return player.copyWith(balance: player.balance + tx.amount);
      }
      return player;
    }).toList();

    return ok(updated);
  }

  /// Whether [senderId] is allowed to initiate a transaction moving money
  /// out of [fromId]. Players move their own money; anyone may trigger a
  /// payout from the bank (collecting salary, card rewards) — the physical
  /// game trusts the banker the same way.
  static bool canInitiate({required String senderId, required String fromId}) =>
      fromId == senderId || fromId == Player.bankId;

  /// Validates buying [propertyId]. [price] overrides the list price —
  /// that's how a table-held auction settles: the winner buys at their
  /// bid instead (the physical game trusts the table on the amount).
  static Result<Property> validatePurchase({
    required Board board,
    required Map<String, PropertyOwnership> ownerships,
    required String propertyId,
    required Player buyer,
    int? price,
  }) {
    final property = _find(board, propertyId);
    if (property == null) return err('Unknown property.');
    if (!property.kind.isOwnable) {
      return err("This square can't be owned.");
    }
    if (ownerships.containsKey(propertyId)) {
      return err('${property.name} is already owned.');
    }
    final cost = price ?? property.price;
    if (cost <= 0) return err('The price must be greater than zero.');
    if (buyer.balance < cost) {
      return err('Not enough money to buy ${property.name}.');
    }
    return ok(property);
  }

  /// The rent due on [propertyId] right now.
  ///
  /// Streets: the rent tier for the built houses; base rent doubles when the
  /// owner holds the whole color group with no houses (standard rule).
  /// Railroads: tier by how many the owner holds. Utilities: multiplier by
  /// how many the owner holds × [diceTotal].
  static Result<int> computeRent({
    required Board board,
    required Map<String, PropertyOwnership> ownerships,
    required String propertyId,
    int? diceTotal,
  }) {
    final property = _find(board, propertyId);
    if (property == null) return err('Unknown property.');
    final ownership = ownerships[propertyId];
    if (ownership == null) return err('${property.name} has no owner.');
    if (ownership.mortgaged) {
      return err('${property.name} is mortgaged — no rent is due.');
    }
    final tiers = property.rentTiers;
    if (tiers.isEmpty) return err('${property.name} has no rents defined.');

    int ownedOfKind(PropertyKind kind) => board.properties
        .where((p) =>
            p.kind == kind &&
            ownerships[p.id]?.ownerId == ownership.ownerId)
        .length;

    switch (property.kind) {
      case PropertyKind.street:
        final tier = ownership.houses.clamp(0, tiers.length - 1);
        var rent = tiers[tier];
        if (tier == 0 && _ownsWholeGroup(board, ownerships, property)) {
          rent *= 2;
        }
        return ok(rent);
      case PropertyKind.railroad:
        final count = ownedOfKind(PropertyKind.railroad);
        return ok(tiers[(count - 1).clamp(0, tiers.length - 1)]);
      case PropertyKind.utility:
        if (diceTotal == null || diceTotal <= 0) {
          return err('Utility rent needs the dice total.');
        }
        final count = ownedOfKind(PropertyKind.utility);
        final multiplier = tiers[(count - 1).clamp(0, tiers.length - 1)];
        return ok(multiplier * diceTotal);
      case PropertyKind.go:
      case PropertyKind.jail:
      case PropertyKind.freeParking:
      case PropertyKind.goToJail:
      case PropertyKind.tax:
      case PropertyKind.chance:
      case PropertyKind.communityChest:
        // Unreachable: these kinds are never ownable, so no ownership row
        // (and thus no rent) can exist for one — see [validatePurchase].
        return err("This square can't be owned.");
    }
  }

  /// Validates changing the buildings on a street and returns the money
  /// movement: positive = owner pays the bank (building), negative = the
  /// bank pays the owner (selling back at half price, standard rule).
  static Result<int> validateHouses({
    required Board board,
    required Map<String, PropertyOwnership> ownerships,
    required String propertyId,
    required String senderId,
    required int targetHouses,
  }) {
    final property = _find(board, propertyId);
    if (property == null) return err('Unknown property.');
    final ownership = ownerships[propertyId];
    if (ownership == null || ownership.ownerId != senderId) {
      return err('You do not own ${property.name}.');
    }
    if (property.kind != PropertyKind.street) {
      return err('Only streets can have houses.');
    }
    // Standard rule: building requires a monopoly on the color group.
    if (!_ownsWholeGroup(board, ownerships, property)) {
      return err('You need to own the whole color group to build.');
    }
    if (targetHouses < 0 || targetHouses > PropertyOwnership.hotel) {
      return err('Houses must be between 0 and ${PropertyOwnership.hotel}.');
    }
    final delta = targetHouses - ownership.houses;
    if (delta == 0) return err('Nothing to change.');
    if (property.housePrice <= 0) {
      return err('${property.name} has no house price defined.');
    }
    // Standard rule: no building while any street of the group is
    // mortgaged (selling back is always allowed).
    if (delta > 0 &&
        board.properties.any((p) =>
            p.kind == PropertyKind.street &&
            p.colorValue == property.colorValue &&
            (ownerships[p.id]?.mortgaged ?? false))) {
      return err('Lift the mortgage on the color group before building.');
    }
    // Even-building rule: after the change no street of the group may be
    // more than one house apart from another — building spreads across
    // the group, selling comes off the tallest first (hotel counts as 5).
    for (final p in board.properties) {
      if (p.kind != PropertyKind.street ||
          p.colorValue != property.colorValue ||
          p.id == propertyId) {
        continue;
      }
      final other = ownerships[p.id]?.houses ?? 0;
      if ((targetHouses - other).abs() > 1) {
        return err(delta > 0
            ? 'Build evenly — put the next house on ${p.name} first.'
            : 'Sell evenly — take a house off ${p.name} first.');
      }
    }
    return ok(delta > 0
        ? delta * property.housePrice
        : delta * property.housePrice ~/ 2);
  }

  /// Lifting a mortgage costs its value plus 10% interest, rounded up.
  static int mortgageLiftCost(Property property) =>
      property.mortgageValue + (property.mortgageValue + 9) ~/ 10;

  /// Validates mortgaging (or lifting the mortgage on) [propertyId] and
  /// returns the money movement: negative = the bank pays the owner the
  /// mortgage value, positive = the owner pays the bank value + interest.
  static Result<int> validateMortgage({
    required Board board,
    required Map<String, PropertyOwnership> ownerships,
    required String propertyId,
    required String senderId,
    required bool mortgage,
  }) {
    final property = _find(board, propertyId);
    if (property == null) return err('Unknown property.');
    final ownership = ownerships[propertyId];
    if (ownership == null || ownership.ownerId != senderId) {
      return err('You do not own ${property.name}.');
    }
    if (property.mortgageValue <= 0) {
      return err('${property.name} has no mortgage value defined.');
    }
    if (mortgage) {
      if (ownership.mortgaged) {
        return err('${property.name} is already mortgaged.');
      }
      // Standard rule: buildings on the whole color group must be sold
      // before any of its streets can be mortgaged.
      if (property.kind == PropertyKind.street &&
          board.properties.any((p) =>
              p.kind == PropertyKind.street &&
              p.colorValue == property.colorValue &&
              (ownerships[p.id]?.houses ?? 0) > 0)) {
        return err('Sell the buildings on this color group first.');
      }
      return ok(-property.mortgageValue);
    }
    if (!ownership.mortgaged) {
      return err('${property.name} is not mortgaged.');
    }
    return ok(mortgageLiftCost(property));
  }

  /// Validates handing [propertyId] over to [target] — the property side
  /// of a trade; any cash for the deal moves as a normal Send. Buildings
  /// must be sold first; a mortgage travels with the property.
  static Result<Player> validateTransfer({
    required Board board,
    required Map<String, PropertyOwnership> ownerships,
    required String propertyId,
    required String senderId,
    required Player? target,
  }) {
    final property = _find(board, propertyId);
    if (property == null) return err('Unknown property.');
    final ownership = ownerships[propertyId];
    if (ownership == null || ownership.ownerId != senderId) {
      return err('You do not own ${property.name}.');
    }
    if (target == null || target.hasLeft) {
      return err('That player is not in this game.');
    }
    if (target.id == senderId) {
      return err('You already own ${property.name}.');
    }
    if (ownership.houses > 0) {
      return err('Sell the buildings on ${property.name} first.');
    }
    return ok(target);
  }

  /// Moves a token [total] squares forward around a board of [squareCount]
  /// squares. [goIndex] is `board.goIndex` (-1 if the board has no curated
  /// layout, in which case nothing ever "crosses GO"). `crossedGo` is true
  /// whenever the move passes through or lands on GO — pay salary once for
  /// that, doubled when [landedOnGo] is also true (landed on it exactly).
  static ({int position, bool crossedGo, bool landedOnGo}) advancePosition({
    required int squareCount,
    required int currentPosition,
    required int total,
    required int goIndex,
  }) {
    final position = (currentPosition + total) % squareCount;
    if (goIndex < 0) {
      return (position: position, crossedGo: false, landedOnGo: false);
    }
    // Steps forward needed to first reach goIndex, not counting a start
    // already sitting on it (so passing/landing pays out once, not on
    // every roll for a player who happens to start their turn there).
    final stepsToGo = (goIndex - currentPosition - 1) % squareCount + 1;
    return (
      position: position,
      crossedGo: total >= stepsToGo,
      landedOnGo: position == goIndex,
    );
  }

  /// Resolves one roll attempted while in jail: doubles always escape (and
  /// move by the roll); otherwise the 3rd failed attempt (`jailTurns == 2`
  /// going in) forces paying the fine so the roll still moves the player.
  static JailRollOutcome resolveJailRoll({
    required int jailTurns,
    required bool isDouble,
  }) {
    if (isDouble) return JailRollOutcome.escaped;
    if (jailTurns >= 2) return JailRollOutcome.mustPayNow;
    return JailRollOutcome.stillStuck;
  }

  /// The next player in seat order who is still in the game.
  static String? nextTurn(List<Player> players, String? currentId) {
    final active = players.where((p) => !p.hasLeft).toList()
      ..sort((a, b) => a.seat.compareTo(b.seat));
    if (active.isEmpty) return null;

    final index = active.indexWhere((p) => p.id == currentId);
    return active[(index + 1) % active.length].id;
  }

  static Property? _find(Board board, String propertyId) {
    for (final property in board.properties) {
      if (property.id == propertyId) return property;
    }
    return null;
  }

  static bool _ownsWholeGroup(
    Board board,
    Map<String, PropertyOwnership> ownerships,
    Property property,
  ) {
    final ownerId = ownerships[property.id]?.ownerId;
    if (ownerId == null) return false;
    return board.properties
        .where((p) =>
            p.kind == PropertyKind.street &&
            p.colorValue == property.colorValue)
        .every((p) => ownerships[p.id]?.ownerId == ownerId);
  }
}
