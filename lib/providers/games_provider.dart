import 'package:flutter/foundation.dart';

import '../models/game.dart';
import '../services/database_service.dart';

/// The games this device belongs to, for the home screen: each record plus
/// my locally cached balance so the list is meaningful even offline.
class GamesProvider extends ChangeNotifier {
  GamesProvider(this._db);

  final DatabaseService _db;

  List<GameRecord> _records = [];
  final Map<String, int> _myBalances = {};
  final Map<String, int> _playerCounts = {};
  bool _loaded = false;

  List<GameRecord> get records => _records;
  bool get isLoaded => _loaded;

  int? myBalanceIn(GameRecord record) => _myBalances[record.game.id];

  int playerCountIn(GameRecord record) => _playerCounts[record.game.id] ?? 0;

  Future<void> load() async {
    _records = await _db.getGameRecords();
    _myBalances.clear();
    _playerCounts.clear();
    for (final record in _records) {
      final players = await _db.getPlayers(record.game.id);
      _playerCounts[record.game.id] =
          players.where((p) => !p.hasLeft).length;
      for (final player in players) {
        if (player.id == record.myPlayerId) {
          _myBalances[record.game.id] = player.balance;
        }
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> deleteGame(String gameId) async {
    await _db.deleteGame(gameId);
    await load();
  }
}
