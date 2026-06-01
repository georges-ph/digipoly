import '../core/errors/exceptions.dart';
import '../core/errors/failures.dart';
import '../models/discovered_room.dart';
import '../services/device_service.dart';
import '../services/discovery_service.dart';
import '../services/network_service.dart';
import '../services/server_service.dart';

abstract class RoomRepository {
  Future<(Failure? failure, String? roomName)> createRoom();
  Future<(Failure? failure, bool closed)> closeRoom();
  Future<(Failure? failure, Stream<DiscoveredRoom>?)> discoverRooms();
}

class RoomRepositoryImpl implements RoomRepository {
  final NetworkService _networkService;
  final ServerService _serverService;
  final DiscoveryService _discoveryService;
  final DeviceService _deviceService;

  const RoomRepositoryImpl({
    required NetworkService networkService,
    required ServerService serverService,
    required DiscoveryService discoveryService,
    required DeviceService deviceService,
  }) : _networkService = networkService,
       _serverService = serverService,
       _discoveryService = discoveryService,
       _deviceService = deviceService;

  @override
  Future<(Failure?, String?)> createRoom() async {
    if (_serverService.isRunning) {
      return (const ServerFailure("A room is already active"), null);
    }

    try {
      await _networkService.checkWifi();
      final address = await _networkService.getIpAddress();
      final port = await _serverService.start(address);

      final deviceName = await _deviceService.getName();
      final roomName = "$deviceName's room";

      await _discoveryService.broadcast(roomName, port);

      return (null, roomName);
    } on AppException catch (e) {
      await closeRoom();
      return (e.toFailure, null);
    } catch (e) {
      await closeRoom();
      return (UnknownFailure(e.toString()), null);
    }
  }

  @override
  Future<(Failure?, bool)> closeRoom() async {
    AppException? exception;

    if (_serverService.isRunning) {
      try {
        await _serverService.stop();
      } on AppException catch (e) {
        exception ??= e;
      } catch (e) {
        exception ??= UnknownException(e.toString());
      }
    }

    if (_discoveryService.isBroadcasting) {
      try {
        await _discoveryService.stopBroadcast();
      } on AppException catch (e) {
        exception ??= e;
      } catch (e) {
        exception ??= UnknownException(e.toString());
      }
    }

    return exception == null ? (null, true) : (exception.toFailure, false);
  }

  @override
  Future<(Failure?, Stream<DiscoveredRoom>?)> discoverRooms() async {
    if (_discoveryService.isDiscovering) {
      return (null, _discoveryService.onRoomEvent);
    }

    try {
      await _networkService.checkWifi();
      await _discoveryService.discover();
      return (null, _discoveryService.onRoomEvent);
    } on AppException catch (e) {
      try {
        await _discoveryService.stopDiscovery();
      } catch (_) {}

      return (e.toFailure, null);
    } catch (e) {
      try {
        await _discoveryService.stopDiscovery();
      } catch (_) {}

      return (UnknownFailure(e.toString()), null);
    }
  }
}
