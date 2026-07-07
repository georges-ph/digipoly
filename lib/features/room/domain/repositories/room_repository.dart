import '../../../../core/errors/failures.dart';
import '../../../../core/models/app_event.dart';
import '../entities/discovered_room.dart';

abstract class RoomRepository {
  Future<(Failure? failure, (String roomName, Stream<RoomEvent> events)?)> createRoom();
  Future<(Failure? failure, bool closed)> closeRoom();
  Future<(Failure? failure, Stream<DiscoveredRoom>? roomsStream)> startDiscovery();
  Future<(Failure? failure, Stream<RoomEvent>?)> joinRoom(String address, int port);
  Future<(Failure? failure, bool stopped)> stopDiscovery();
  Future<(Failure? failure, bool left)> leaveRoom();
}
