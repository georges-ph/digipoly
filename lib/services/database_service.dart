import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import '../models/board.dart';
import '../models/dice_roll.dart';
import '../models/game.dart';
import '../models/game_transaction.dart';
import '../models/player.dart';
import '../models/property_ownership.dart';

/// Every device keeps its own local copy of the games it belongs to.
/// On the host this is the authoritative record; on clients it is a cache
/// that gets replaced by server snapshots, so the home screen can still show
/// games and balances while offline.
class DatabaseService {
  static const _dbName = 'digipoly.db';

  late final Database _db;

  Future<void> init() async {
    // dart:io's Platform throws on web, so the web branch must come first.
    final String path;
    if (kIsWeb) {
      // IndexedDB-backed sqlite via a wasm worker; there is no filesystem.
      databaseFactory = databaseFactoryFfiWeb;
      path = _dbName;
    } else if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      path = p.join(
        (await getApplicationSupportDirectory()).path,
        _dbName,
      );
    } else if (Platform.isMacOS) {
      path = p.join(
        (await getApplicationSupportDirectory()).path,
        _dbName,
      );
    } else {
      path = p.join(await getDatabasesPath(), _dbName);
    }

    _db = await openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE boards('
          'id TEXT PRIMARY KEY, json TEXT NOT NULL, updated_at INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE games('
          'id TEXT PRIMARY KEY, json TEXT NOT NULL, role TEXT NOT NULL, '
          'my_player_id TEXT NOT NULL, host_address TEXT, host_port INTEGER, '
          'last_played_at INTEGER NOT NULL, current_turn_id TEXT, '
          'last_roll TEXT, turn_rolled INTEGER NOT NULL DEFAULT 0, '
          'free_parking_pot INTEGER NOT NULL DEFAULT 0, '
          'game_ended INTEGER NOT NULL DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE players('
          'game_id TEXT NOT NULL, id TEXT NOT NULL, json TEXT NOT NULL, '
          'PRIMARY KEY(game_id, id))',
        );
        await db.execute(
          'CREATE TABLE game_transactions('
          'id TEXT PRIMARY KEY, game_id TEXT NOT NULL, ts INTEGER NOT NULL, '
          'json TEXT NOT NULL)',
        );
        await db.execute(_createOwnershipsSql);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE games ADD COLUMN current_turn_id TEXT',
          );
          await db.execute(_createOwnershipsSql);
        }
        if (oldVersion < 3) {
          // Roll state survives a host restart: without it, reopening the
          // host app mid-turn handed the current player a fresh roll.
          await db.execute('ALTER TABLE games ADD COLUMN last_roll TEXT');
          await db.execute(
            'ALTER TABLE games ADD COLUMN '
            'turn_rolled INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE games ADD COLUMN '
            'free_parking_pot INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE games ADD COLUMN '
            'game_ended INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
    );
  }

  static const _createOwnershipsSql = 'CREATE TABLE game_properties('
      'game_id TEXT NOT NULL, property_id TEXT NOT NULL, json TEXT NOT NULL, '
      'PRIMARY KEY(game_id, property_id))';

  // ---------------------------------------------------------------- Boards

  Future<void> upsertBoard(Board board) => _db.insert(
        'boards',
        {
          'id': board.id,
          'json': jsonEncode(board.toJson()),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<Board>> getBoards() async {
    final rows = await _db.query('boards', orderBy: 'updated_at DESC');
    return rows
        .map((row) =>
            Board.fromJson(jsonDecode(row['json'] as String) as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteBoard(String id) =>
      _db.delete('boards', where: 'id = ?', whereArgs: [id]);

  // ---------------------------------------------------------- Game records

  // A plain `INSERT OR REPLACE` deletes the existing row on conflict, so any
  // column not listed here — current_turn_id/last_roll/turn_rolled/
  // free_parking_pot/game_ended, all written separately via setTurnState —
  // would get
  // silently reset to its default. This game hasn't just started a fresh
  // turn just because its GameRecord (role/address/last-played, etc.)
  // changed, which happens far more often (every reconnect re-applies a
  // snapshot) than an actual new turn — an UPSERT that only touches these
  // columns leaves whatever turn state is already there alone.
  Future<void> upsertGameRecord(GameRecord record) => _db.rawInsert(
        'INSERT INTO games '
        '(id, json, role, my_player_id, host_address, host_port, last_played_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET '
        'json = excluded.json, role = excluded.role, '
        'my_player_id = excluded.my_player_id, '
        'host_address = excluded.host_address, '
        'host_port = excluded.host_port, '
        'last_played_at = excluded.last_played_at',
        [
          record.game.id,
          jsonEncode(record.game.toJson()),
          record.role.name,
          record.myPlayerId,
          record.hostAddress,
          record.hostPort,
          record.lastPlayedAt.millisecondsSinceEpoch,
        ],
      );

  Future<List<GameRecord>> getGameRecords() async {
    final rows = await _db.query('games', orderBy: 'last_played_at DESC');
    return rows.map(_recordFromRow).toList();
  }

  GameRecord _recordFromRow(Map<String, Object?> row) => GameRecord(
        game: Game.fromJson(
          jsonDecode(row['json'] as String) as Map<String, dynamic>,
        ),
        role: GameRole.fromName(row['role'] as String),
        myPlayerId: row['my_player_id'] as String,
        hostAddress: row['host_address'] as String?,
        hostPort: row['host_port'] as int?,
        lastPlayedAt: DateTime.fromMillisecondsSinceEpoch(
          row['last_played_at'] as int,
        ),
      );

  /// Removes the game and everything that belongs to it.
  Future<void> deleteGame(String gameId) => _db.transaction((txn) async {
        await txn.delete('games', where: 'id = ?', whereArgs: [gameId]);
        await txn
            .delete('players', where: 'game_id = ?', whereArgs: [gameId]);
        await txn.delete(
          'game_transactions',
          where: 'game_id = ?',
          whereArgs: [gameId],
        );
        await txn.delete(
          'game_properties',
          where: 'game_id = ?',
          whereArgs: [gameId],
        );
      });

  // --------------------------------------------------------------- Players

  Future<void> upsertPlayers(String gameId, List<Player> players) async {
    final batch = _db.batch();
    for (final player in players) {
      batch.insert(
        'players',
        {
          'game_id': gameId,
          'id': player.id,
          'json': jsonEncode(player.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Player>> getPlayers(String gameId) async {
    final rows = await _db.query(
      'players',
      where: 'game_id = ?',
      whereArgs: [gameId],
    );
    return rows
        .map((row) => Player.fromJson(
            jsonDecode(row['json'] as String) as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------- Transactions

  Future<void> insertTransactions(
    String gameId,
    List<GameTransaction> transactions,
  ) async {
    final batch = _db.batch();
    for (final tx in transactions) {
      batch.insert(
        'game_transactions',
        {
          'id': tx.id,
          'game_id': gameId,
          'ts': tx.timestamp.millisecondsSinceEpoch,
          'json': jsonEncode(tx.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Chronological order (oldest first).
  Future<List<GameTransaction>> getTransactions(String gameId) async {
    final rows = await _db.query(
      'game_transactions',
      where: 'game_id = ?',
      whereArgs: [gameId],
      orderBy: 'ts ASC',
    );
    return rows
        .map((row) => GameTransaction.fromJson(
            jsonDecode(row['json'] as String) as Map<String, dynamic>))
        .toList();
  }

  // ------------------------------------------------------------ Ownerships

  Future<void> upsertOwnerships(
    String gameId,
    List<PropertyOwnership> ownerships,
  ) async {
    final batch = _db.batch();
    for (final ownership in ownerships) {
      batch.insert(
        'game_properties',
        {
          'game_id': gameId,
          'property_id': ownership.propertyId,
          'json': jsonEncode(ownership.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<PropertyOwnership>> getOwnerships(String gameId) async {
    final rows = await _db.query(
      'game_properties',
      where: 'game_id = ?',
      whereArgs: [gameId],
    );
    return rows
        .map((row) => PropertyOwnership.fromJson(
            jsonDecode(row['json'] as String) as Map<String, dynamic>))
        .toList();
  }

  // ------------------------------------------------------------------ Turn

  Future<void> setTurnState(
    String gameId, {
    String? currentTurnId,
    DiceRoll? lastRoll,
    bool turnRolled = false,
    int freeParkingPot = 0,
    bool gameEnded = false,
  }) =>
      _db.update(
        'games',
        {
          'current_turn_id': currentTurnId,
          'last_roll':
              lastRoll == null ? null : jsonEncode(lastRoll.toJson()),
          'turn_rolled': turnRolled ? 1 : 0,
          'free_parking_pot': freeParkingPot,
          'game_ended': gameEnded ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [gameId],
      );

  Future<({
    String? currentTurnId,
    DiceRoll? lastRoll,
    bool turnRolled,
    int freeParkingPot,
    bool gameEnded,
  })> getTurnState(String gameId) async {
    final rows = await _db.query(
      'games',
      columns: [
        'current_turn_id',
        'last_roll',
        'turn_rolled',
        'free_parking_pot',
        'game_ended',
      ],
      where: 'id = ?',
      whereArgs: [gameId],
    );
    if (rows.isEmpty) {
      return (
        currentTurnId: null,
        lastRoll: null,
        turnRolled: false,
        freeParkingPot: 0,
        gameEnded: false,
      );
    }
    final row = rows.first;
    final rollJson = row['last_roll'] as String?;
    return (
      currentTurnId: row['current_turn_id'] as String?,
      lastRoll: rollJson == null
          ? null
          : DiceRoll.fromJson(jsonDecode(rollJson) as Map<String, dynamic>),
      turnRolled: (row['turn_rolled'] as int? ?? 0) != 0,
      freeParkingPot: row['free_parking_pot'] as int? ?? 0,
      gameEnded: (row['game_ended'] as int? ?? 0) != 0,
    );
  }

  /// Replaces the whole local copy of a game with an authoritative server
  /// snapshot.
  Future<void> saveSnapshot(GameRecord record, GameSnapshot snapshot) async {
    final gameId = snapshot.game.id;
    await _db.transaction((txn) async {
      await txn
          .delete('players', where: 'game_id = ?', whereArgs: [gameId]);
      await txn.delete(
        'game_transactions',
        where: 'game_id = ?',
        whereArgs: [gameId],
      );
      await txn.delete(
        'game_properties',
        where: 'game_id = ?',
        whereArgs: [gameId],
      );
    });
    await upsertGameRecord(record);
    await upsertPlayers(gameId, snapshot.players);
    await insertTransactions(gameId, snapshot.transactions);
    await upsertOwnerships(gameId, snapshot.ownerships);
    await setTurnState(
      gameId,
      currentTurnId: snapshot.currentTurnId,
      lastRoll: snapshot.lastRoll,
      turnRolled: snapshot.turnRolled,
      freeParkingPot: snapshot.freeParkingPot,
      gameEnded: snapshot.gameEnded,
    );
  }
}
