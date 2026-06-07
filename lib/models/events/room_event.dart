part of 'app_event.dart';

sealed class RoomEvent extends AppEvent {
  const RoomEvent(super.type);
}

class JoinRoomEvent extends RoomEvent {
  final Player player;
  const JoinRoomEvent({required this.player}) : super(.joinRoom);

  factory JoinRoomEvent.fromMap(Map<String, dynamic> map) {
    return JoinRoomEvent(player: Player.fromMap(map));
  }

  @override
  Map<String, dynamic> get _toMap => player.toMap();
}

class LeaveRoomEvent extends RoomEvent {
  final Player player;
  const LeaveRoomEvent({required this.player}) : super(.leaveRoom);

  factory LeaveRoomEvent.fromMap(Map<String, dynamic> map) {
    return LeaveRoomEvent(player: Player.fromMap(map));
  }

  @override
  Map<String, dynamic> get _toMap => player.toMap();
}

class CloseRoomEvent extends RoomEvent {
  const CloseRoomEvent() : super(.closeRoom);

  factory CloseRoomEvent.fromMap(Map<String, dynamic> map) {
    return const CloseRoomEvent();
  }

  @override
  Map<String, dynamic> get _toMap => {};
}
