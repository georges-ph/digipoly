import 'package:flutter/foundation.dart';

import '../models/game.dart';
import '../services/database_service.dart';

/// The games this device belongs to, for the home screen: each record plus
/// its player count, read locally so the list is meaningful even offline.
class GamesProvider extends ChangeNotifier {
  GamesProvider(this._db);

  final DatabaseService _db;

  List<GameRecord> _records = [];
  final Map<String, int> _playerCounts = {};
  bool _loaded = false;

  List<GameRecord> get records => _records;
  bool get isLoaded => _loaded;

  int playerCountIn(GameRecord record) => _playerCounts[record.game.id] ?? 0;

  Future<void> load() async {
    _records = await _db.getGameRecords();
    _playerCounts.clear();
    for (final record in _records) {
      final players = await _db.getPlayers(record.game.id);
      _playerCounts[record.game.id] =
          players.where((p) => !p.hasLeft).length;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> deleteGame(String gameId) async {
    await _db.deleteGame(gameId);
    await load();
  }
}
