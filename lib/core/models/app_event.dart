import 'dart:convert';

import '../../features/room/domain/entities/player.dart';

part '../../features/room/domain/entities/room_event.dart';

enum AppEventType { unknown, joinRoom, leaveRoom, closeRoom }

sealed class AppEvent {
  final AppEventType type;
  const AppEvent(this.type);

  Map<String, dynamic> get _toMap;

  String get toJson => jsonEncode({
    "type": type.name,
    "data": _toMap,
  });

  factory AppEvent.fromJson(String json) => AppEvent._fromMap(jsonDecode(json));

  factory AppEvent._fromMap(Map<String, dynamic> map) {
    try {
      final type = map["type"] as String;
      final data = map["data"] as Map<String, dynamic>;

      return switch (AppEventType.values.byName(type)) {
        .joinRoom => JoinRoomEvent.fromMap(data),
        .leaveRoom => LeaveRoomEvent.fromMap(data),
        .closeRoom => CloseRoomEvent.fromMap(data),
        _ => const UnknownEvent(),
      };
    } catch (e) {
      return const UnknownEvent();
    }
  }
}

class UnknownEvent extends AppEvent {
  const UnknownEvent() : super(.unknown);

  @override
  Map<String, dynamic> get _toMap => {};
}
