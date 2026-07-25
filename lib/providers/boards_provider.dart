import 'package:flutter/foundation.dart';

import '../models/board.dart';
import '../services/database_service.dart';

/// The device's saved board templates. The built-in Classic template is not
/// stored — it is always offered alongside these.
class BoardsProvider extends ChangeNotifier {
  BoardsProvider(this._db);

  final DatabaseService _db;

  List<Board> _boards = [];
  bool _loaded = false;

  List<Board> get boards => _boards;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    _boards = await _db.getBoards();
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveBoard(Board board) async {
    await _db.upsertBoard(board);
    await load();
  }

  Future<void> deleteBoard(String id) async {
    await _db.deleteBoard(id);
    await load();
  }
}
