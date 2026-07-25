import 'package:digipoly/models/board.dart';
import 'package:digipoly/models/game_transaction.dart';
import 'package:digipoly/models/player.dart';
import 'package:digipoly/models/property.dart';
import 'package:digipoly/models/property_ownership.dart';
import 'package:digipoly/models/result.dart';
import 'package:digipoly/services/game_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Player player(String id, int balance, {int seat = 0, bool hasLeft = false}) =>
    Player(id: id, name: id, balance: balance, seat: seat, hasLeft: hasLeft);

GameTransaction tx(String from, String to, int amount) => GameTransaction(
      id: 't1',
      gameId: 'g',
      fromId: from,
      toId: to,
      amount: amount,
      timestamp: DateTime(2026),
    );

Board board(List<Property> properties) => Board(
      id: 'b',
      name: 'Test',
      currencySymbol: r'$',
      startingBalance: 1500,
      salary: 200,
      properties: properties,
    );

Property street(String id, int color, List<int> rents,
        {int mortgageValue = 0}) =>
    Property(
      id: id,
      name: id,
      kind: PropertyKind.street,
      colorValue: color,
      price: 100,
      rentTiers: rents,
      housePrice: 50,
      mortgageValue: mortgageValue,
    );

void main() {
  group('applyPayment', () {
    test('moves money between players', () {
      final result = GameEngine.applyPayment(
        [player('a', 500), player('b', 100)],
        tx('a', 'b', 200),
      );
      expect(result.isOk, isTrue);
      final players = {for (final p in result.requireValue) p.id: p};
      expect(players['a']!.balance, 300);
      expect(players['b']!.balance, 300);
    });

    test('rejects overdrafts', () {
      final result = GameEngine.applyPayment(
        [player('a', 100), player('b', 0)],
        tx('a', 'b', 200),
      );
      expect(result.isOk, isFalse);
    });

    test('bank has infinite money', () {
      final result = GameEngine.applyPayment(
        [player('a', 0)],
        tx(Player.bankId, 'a', 1000000),
      );
      expect(result.isOk, isTrue);
      expect(result.requireValue.single.balance, 1000000);
    });

    test('rejects players who left', () {
      final result = GameEngine.applyPayment(
        [player('a', 500), player('b', 0, hasLeft: true)],
        tx('a', 'b', 100),
      );
      expect(result.isOk, isFalse);
    });

    test('rejects non-positive amounts and self payments', () {
      final players = [player('a', 500), player('b', 0)];
      expect(GameEngine.applyPayment(players, tx('a', 'b', 0)).isOk, isFalse);
      expect(GameEngine.applyPayment(players, tx('a', 'a', 10)).isOk, isFalse);
    });
  });

  group('computeRent', () {
    test('street rent uses the houses tier', () {
      final b = board([
        street('s1', 1, [10, 50, 150, 450, 625, 750]),
        street('s2', 1, [10, 50, 150, 450, 625, 750]),
      ]);
      final owned = {
        's1': const PropertyOwnership(
            propertyId: 's1', ownerId: 'a', houses: 3),
      };
      final rent = GameEngine.computeRent(
          board: b, ownerships: owned, propertyId: 's1');
      expect(rent.requireValue, 450);
    });

    test('base street rent doubles on a full color group', () {
      final b = board([
        street('s1', 1, [10, 50, 150, 450, 625, 750]),
        street('s2', 1, [10, 50, 150, 450, 625, 750]),
      ]);
      final owned = {
        's1': const PropertyOwnership(propertyId: 's1', ownerId: 'a'),
        's2': const PropertyOwnership(propertyId: 's2', ownerId: 'a'),
      };
      final rent = GameEngine.computeRent(
          board: b, ownerships: owned, propertyId: 's1');
      expect(rent.requireValue, 20);
    });

    test('railroad rent scales with railroads owned', () {
      Property railroad(String id) => Property(
            id: id,
            name: id,
            kind: PropertyKind.railroad,
            colorValue: 0,
            price: 200,
            rentTiers: const [25, 50, 100, 200],
          );
      final b = board([railroad('r1'), railroad('r2'), railroad('r3')]);
      final owned = {
        'r1': const PropertyOwnership(propertyId: 'r1', ownerId: 'a'),
        'r2': const PropertyOwnership(propertyId: 'r2', ownerId: 'a'),
      };
      final rent = GameEngine.computeRent(
          board: b, ownerships: owned, propertyId: 'r1');
      expect(rent.requireValue, 50);
    });

    test('utility rent multiplies the dice total', () {
      const utility = Property(
        id: 'u1',
        name: 'u1',
        kind: PropertyKind.utility,
        colorValue: 0,
        price: 150,
        rentTiers: [4, 10],
      );
      final b = board([utility]);
      final owned = {
        'u1': const PropertyOwnership(propertyId: 'u1', ownerId: 'a'),
      };
      expect(
        GameEngine.computeRent(
                board: b, ownerships: owned, propertyId: 'u1', diceTotal: 7)
            .requireValue,
        28,
      );
      expect(
        GameEngine.computeRent(board: b, ownerships: owned, propertyId: 'u1')
            .isOk,
        isFalse,
      );
    });
  });

  group('validateHouses', () {
    final b = board([
      street('s1', 1, [10, 50, 150, 450, 625, 750]),
    ]);
    final owned = {
      's1': const PropertyOwnership(propertyId: 's1', ownerId: 'a', houses: 2),
    };

    test('building charges full house price', () {
      final cost = GameEngine.validateHouses(
        board: b,
        ownerships: owned,
        propertyId: 's1',
        senderId: 'a',
        targetHouses: 4,
      );
      expect(cost.requireValue, 100);
    });

    test('selling refunds half', () {
      final cost = GameEngine.validateHouses(
        board: b,
        ownerships: owned,
        propertyId: 's1',
        senderId: 'a',
        targetHouses: 0,
      );
      expect(cost.requireValue, -50);
    });

    test('only the owner can build', () {
      final cost = GameEngine.validateHouses(
        board: b,
        ownerships: owned,
        propertyId: 's1',
        senderId: 'intruder',
        targetHouses: 3,
      );
      expect(cost.isOk, isFalse);
    });

    test('building requires owning the whole color group', () {
      final twoStreetBoard = board([
        street('s1', 1, [10, 50]),
        street('s2', 1, [10, 50]),
      ]);
      final partial = {
        's1': const PropertyOwnership(propertyId: 's1', ownerId: 'a'),
        's2': const PropertyOwnership(propertyId: 's2', ownerId: 'rival'),
      };
      expect(
        GameEngine.validateHouses(
          board: twoStreetBoard,
          ownerships: partial,
          propertyId: 's1',
          senderId: 'a',
          targetHouses: 1,
        ).isOk,
        isFalse,
      );

      final full = {
        's1': const PropertyOwnership(propertyId: 's1', ownerId: 'a'),
        's2': const PropertyOwnership(propertyId: 's2', ownerId: 'a'),
      };
      expect(
        GameEngine.validateHouses(
          board: twoStreetBoard,
          ownerships: full,
          propertyId: 's1',
          senderId: 'a',
          targetHouses: 1,
        ).isOk,
        isTrue,
      );
    });
  });

  group('validateHouses even-building rule', () {
    final b = board([
      street('s1', 1, [10, 50]),
      street('s2', 1, [10, 50]),
    ]);

    test('the next house must go on the least-built street', () {
      final owned = {
        's1': const PropertyOwnership(
            propertyId: 's1', ownerId: 'a', houses: 1),
        's2': const PropertyOwnership(propertyId: 's2', ownerId: 'a'),
      };
      expect(
        GameEngine.validateHouses(
          board: b,
          ownerships: owned,
          propertyId: 's1',
          senderId: 'a',
          targetHouses: 2,
        ).isOk,
        isFalse,
      );
      expect(
        GameEngine.validateHouses(
          board: b,
          ownerships: owned,
          propertyId: 's2',
          senderId: 'a',
          targetHouses: 1,
        ).isOk,
        isTrue,
      );
    });

    test('selling comes off the taller street first', () {
      final owned = {
        's1': const PropertyOwnership(
            propertyId: 's1', ownerId: 'a', houses: 2),
        's2': const PropertyOwnership(
            propertyId: 's2', ownerId: 'a', houses: 1),
      };
      expect(
        GameEngine.validateHouses(
          board: b,
          ownerships: owned,
          propertyId: 's2',
          senderId: 'a',
          targetHouses: 0,
        ).isOk,
        isFalse,
      );
      expect(
        GameEngine.validateHouses(
          board: b,
          ownerships: owned,
          propertyId: 's1',
          senderId: 'a',
          targetHouses: 1,
        ).isOk,
        isTrue,
      );
    });

    test('no building while a street of the group is mortgaged', () {
      final owned = {
        's1': const PropertyOwnership(propertyId: 's1', ownerId: 'a'),
        's2': const PropertyOwnership(
            propertyId: 's2', ownerId: 'a', mortgaged: true),
      };
      expect(
        GameEngine.validateHouses(
          board: b,
          ownerships: owned,
          propertyId: 's1',
          senderId: 'a',
          targetHouses: 1,
        ).isOk,
        isFalse,
      );
    });
  });

  group('validateMortgage', () {
    final b = board([
      street('s1', 1, [10, 50], mortgageValue: 50),
      street('s2', 1, [10, 50], mortgageValue: 50),
    ]);

    test('mortgaging pays the value, lifting costs value + 10%', () {
      final owned = {
        's1': const PropertyOwnership(propertyId: 's1', ownerId: 'a'),
      };
      expect(
        GameEngine.validateMortgage(
          board: b,
          ownerships: owned,
          propertyId: 's1',
          senderId: 'a',
          mortgage: true,
        ).requireValue,
        -50,
      );

      final mortgaged = {
        's1': const PropertyOwnership(
            propertyId: 's1', ownerId: 'a', mortgaged: true),
      };
      expect(
        GameEngine.validateMortgage(
          board: b,
          ownerships: mortgaged,
          propertyId: 's1',
          senderId: 'a',
          mortgage: false,
        ).requireValue,
        55,
      );
    });

    test('only the owner, and never with buildings on the group', () {
      final withHouses = {
        's1': const PropertyOwnership(propertyId: 's1', ownerId: 'a'),
        's2': const PropertyOwnership(
            propertyId: 's2', ownerId: 'a', houses: 1),
      };
      expect(
        GameEngine.validateMortgage(
          board: b,
          ownerships: withHouses,
          propertyId: 's1',
          senderId: 'a',
          mortgage: true,
        ).isOk,
        isFalse,
      );
      expect(
        GameEngine.validateMortgage(
          board: b,
          ownerships: {
            's1': const PropertyOwnership(propertyId: 's1', ownerId: 'a'),
          },
          propertyId: 's1',
          senderId: 'intruder',
          mortgage: true,
        ).isOk,
        isFalse,
      );
    });

    test('no rent is due on a mortgaged property', () {
      final owned = {
        's1': const PropertyOwnership(
            propertyId: 's1', ownerId: 'a', mortgaged: true),
      };
      expect(
        GameEngine.computeRent(board: b, ownerships: owned, propertyId: 's1')
            .isOk,
        isFalse,
      );
    });
  });

  group('validateTransfer', () {
    final b = board([street('s1', 1, [10, 50])]);

    test('owner hands the property to an active player', () {
      final owned = {
        's1': const PropertyOwnership(propertyId: 's1', ownerId: 'a'),
      };
      expect(
        GameEngine.validateTransfer(
          board: b,
          ownerships: owned,
          propertyId: 's1',
          senderId: 'a',
          target: player('b', 0),
        ).isOk,
        isTrue,
      );
      // Not mine, gone target, self — all rejected.
      expect(
        GameEngine.validateTransfer(
          board: b,
          ownerships: owned,
          propertyId: 's1',
          senderId: 'intruder',
          target: player('b', 0),
        ).isOk,
        isFalse,
      );
      expect(
        GameEngine.validateTransfer(
          board: b,
          ownerships: owned,
          propertyId: 's1',
          senderId: 'a',
          target: player('b', 0, hasLeft: true),
        ).isOk,
        isFalse,
      );
      expect(
        GameEngine.validateTransfer(
          board: b,
          ownerships: owned,
          propertyId: 's1',
          senderId: 'a',
          target: player('a', 0),
        ).isOk,
        isFalse,
      );
    });

    test('buildings must be sold before transferring', () {
      final built = {
        's1': const PropertyOwnership(
            propertyId: 's1', ownerId: 'a', houses: 2),
      };
      expect(
        GameEngine.validateTransfer(
          board: b,
          ownerships: built,
          propertyId: 's1',
          senderId: 'a',
          target: player('b', 0),
        ).isOk,
        isFalse,
      );
    });
  });

  group('nextTurn', () {
    test('rotates by seat order and skips players who left', () {
      final players = [
        player('a', 0, seat: 0),
        player('b', 0, seat: 1, hasLeft: true),
        player('c', 0, seat: 2),
      ];
      expect(GameEngine.nextTurn(players, 'a'), 'c');
      expect(GameEngine.nextTurn(players, 'c'), 'a');
    });

    test('handles an unknown current player', () {
      final players = [player('a', 0, seat: 0), player('b', 0, seat: 1)];
      expect(GameEngine.nextTurn(players, null), 'a');
    });
  });

  group('validatePurchase', () {
    test('rejects owned or unaffordable properties', () {
      final b = board([street('s1', 1, [10])]);
      expect(
        GameEngine.validatePurchase(
          board: b,
          ownerships: {
            's1': const PropertyOwnership(propertyId: 's1', ownerId: 'x'),
          },
          propertyId: 's1',
          buyer: player('a', 1000),
        ).isOk,
        isFalse,
      );
      expect(
        GameEngine.validatePurchase(
          board: b,
          ownerships: const {},
          propertyId: 's1',
          buyer: player('a', 50),
        ).isOk,
        isFalse,
      );
      expect(
        GameEngine.validatePurchase(
          board: b,
          ownerships: const {},
          propertyId: 's1',
          buyer: player('a', 1000),
        ).isOk,
        isTrue,
      );
    });

    test('an auction price replaces the list price', () {
      final b = board([street('s1', 1, [10])]);
      // Winning bid below list price: affordable even on a small balance.
      expect(
        GameEngine.validatePurchase(
          board: b,
          ownerships: const {},
          propertyId: 's1',
          buyer: player('a', 50),
          price: 40,
        ).isOk,
        isTrue,
      );
      // The bid, not the list price, is what must be affordable.
      expect(
        GameEngine.validatePurchase(
          board: b,
          ownerships: const {},
          propertyId: 's1',
          buyer: player('a', 1000),
          price: 2000,
        ).isOk,
        isFalse,
      );
      expect(
        GameEngine.validatePurchase(
          board: b,
          ownerships: const {},
          propertyId: 's1',
          buyer: player('a', 1000),
          price: 0,
        ).isOk,
        isFalse,
      );
    });
  });
}
