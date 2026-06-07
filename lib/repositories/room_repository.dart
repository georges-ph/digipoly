import '../core/errors/exceptions.dart';
import '../core/errors/failures.dart';
import '../models/discovered_room.dart';
import '../models/events/app_event.dart';
import '../models/player.dart';
import '../services/client_service.dart';
import '../services/device_service.dart';
import '../services/discovery_service.dart';
import '../services/network_service.dart';
import '../services/server_service.dart';

abstract class RoomRepository {
  Future<(Failure? failure, (String roomName, Stream<RoomEvent> events)?)> createRoom();
  Future<(Failure? failure, bool closed)> closeRoom();
  Future<(Failure? failure, Stream<DiscoveredRoom>? roomsStream)> startDiscovery();
  Future<(Failure? failure, Stream<RoomEvent>?)> joinRoom(String address, int port);
  Future<(Failure? failure, bool stopped)> stopDiscovery();
  Future<(Failure? failure, bool left)> leaveRoom();
}

class RoomRepositoryImpl implements RoomRepository {
  final NetworkService _networkService;
  final ServerService _serverService;
  final DiscoveryService _discoveryService;
  final DeviceService _deviceService;
  final ClientService _clientService;

  const RoomRepositoryImpl({
    required NetworkService networkService,
    required ServerService serverService,
    required DiscoveryService discoveryService,
    required DeviceService deviceService,
    required ClientService clientService,
  }) : _networkService = networkService,
       _serverService = serverService,
       _discoveryService = discoveryService,
       _deviceService = deviceService,
       _clientService = clientService;

  @override
  Future<(Failure?, (String, Stream<RoomEvent>)?)> createRoom() async {
    if (_serverService.isRunning) {
      return (const ServerFailure("A room is already active"), null);
    }

    try {
      await _networkService.checkWifi();
      final address = await _networkService.getIpAddress();
      final port = await _serverService.start(address);
      final roomEvents = _serverService.events!.where((e) => e is RoomEvent).cast<RoomEvent>();

      final deviceName = await _deviceService.getName();
      final roomName = "$deviceName's room";

      await _discoveryService.broadcast(roomName, port);
      return (null, (roomName, roomEvents));
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
        _serverService.broadcast(const CloseRoomEvent().toJson);
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
  Future<(Failure?, Stream<DiscoveredRoom>?)> startDiscovery() async {
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

  @override
  Future<(Failure?, Stream<RoomEvent>?)> joinRoom(String address, int port) async {
    if (_clientService.isConnected) {
      return (const ClientFailure("Already connected to a room"), null);
    }

    try {
      await _networkService.checkWifi();
      await _clientService.connect(address, port);
      final deviceName = await _deviceService.getName();
      _clientService.send(JoinRoomEvent(player: Player(name: deviceName)).toJson);

      final roomEvents = _clientService.events!.where((e) => e is RoomEvent).cast<RoomEvent>();
      return (null, roomEvents);
    } on AppException catch (e) {
      try {
        await _clientService.disconnect();
      } catch (_) {}
      return (e.toFailure, null);
    } catch (e) {
      try {
        await _clientService.disconnect();
      } catch (_) {}

      return (UnknownFailure(e.toString()), null);
    }
  }

  @override
  Future<(Failure?, bool)> stopDiscovery() async {
    if (!_discoveryService.isDiscovering) {
      return (null, true);
    }

    try {
      await _discoveryService.stopDiscovery();
      return (null, true);
    } on AppException catch (e) {
      return (e.toFailure, false);
    } catch (e) {
      return (UnknownFailure(e.toString()), false);
    }
  }

  @override
  Future<(Failure?, bool)> leaveRoom() async {
    if (!_clientService.isConnected) {
      return (null, true);
    }

    try {
      final deviceName = await _deviceService.getName();
      _clientService.send(LeaveRoomEvent(player: Player(name: deviceName)).toJson);
      await _clientService.disconnect();
      return (null, true);
    } on AppException catch (e) {
      return (e.toFailure, false);
    } catch (e) {
      return (UnknownFailure(e.toString()), false);
    }
  }
}
