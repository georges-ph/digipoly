part of 'app_event.dart';

sealed class RoomEvent extends AppEvent {
  const RoomEvent(super.type);
}

class JoinRoomEvent extends RoomEvent {
  final String playerName;
  const JoinRoomEvent({required this.playerName}) : super(.joinRoom);

  factory JoinRoomEvent.fromMap(Map<String, dynamic> map) {
    return JoinRoomEvent(playerName: map["player_name"] as String);
  }

  @override
  Map<String, dynamic> get _toMap => {"player_name": playerName};
}
