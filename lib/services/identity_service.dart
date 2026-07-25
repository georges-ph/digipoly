import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Who this device is. A UUID is generated once on first launch and reused
/// forever — it is what identifies the player inside games, so closing the
/// app or losing the connection never loses your seat.
class IdentityService {
  static const _idKey = 'player_id';
  static const _nameKey = 'player_name';

  late final SharedPreferences _prefs;

  late String playerId;
  String displayName = '';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final existing = _prefs.getString(_idKey);
    if (existing == null) {
      playerId = const Uuid().v4();
      await _prefs.setString(_idKey, playerId);
    } else {
      playerId = existing;
    }
    displayName = _prefs.getString(_nameKey) ?? '';
  }

  bool get hasName => displayName.trim().isNotEmpty;

  Future<void> setDisplayName(String name) async {
    displayName = name.trim();
    await _prefs.setString(_nameKey, displayName);
  }
}
