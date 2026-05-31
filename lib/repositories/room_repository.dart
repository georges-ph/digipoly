import '../core/errors/exceptions.dart';
import '../core/errors/failures.dart';
import '../services/device_service.dart';
import '../services/discovery_service.dart';
import '../services/network_service.dart';
import '../services/server_service.dart';

abstract class RoomRepository {
  Future<(Failure? failure, String? roomName)> createRoom();
}

class RoomRepositoryImpl implements RoomRepository {
  final NetworkService _networkService;
  final ServerService _serverService;
  final DiscoveryService _discoveryService;
  final DeviceService _deviceService;

  RoomRepositoryImpl({
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
    bool serverStarted = false;
    bool broadcastStarted = false;

    try {
      await _networkService.checkWifi();
      final address = await _networkService.getIpAddress();

      final port = await _serverService.start(address);
      serverStarted = true;

      final deviceName = await _deviceService.getName();
      final roomName = "$deviceName's room";

      await _discoveryService.broadcast(roomName, port);
      broadcastStarted = true;

      return (null, roomName);
    } on AppException catch (e) {
      await _rollbackCreation(serverStarted, broadcastStarted);
      return (e.toFailure, null);
    } catch (e) {
      await _rollbackCreation(serverStarted, broadcastStarted);
      return (UnknownFailure(e.toString()), null);
    }
  }

  Future<void> _rollbackCreation(bool serverStarted, bool broadcastStarted) async {
    if (serverStarted) {
      try {
        await _serverService.stop();
      } catch (_) {
        // Ignore errors as it's not our primary logic
      }
    }

    if (broadcastStarted) {
      try {
        await _discoveryService.stopBroadcast();
      } catch (_) {
        // Ignore errors as it's not our primary logic
      }
    }
  }
}
