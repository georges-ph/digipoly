import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../models/game.dart';

/// A game room found on the local network.
class DiscoveredRoom {
  const DiscoveredRoom({
    required this.serviceName,
    required this.gameId,
    required this.gameName,
    required this.boardName,
    required this.host,
    required this.port,
  });

  final String serviceName;
  final String gameId;
  final String gameName;
  final String boardName;
  final String host;
  final int port;
}

/// mDNS advertising and browsing via Bonsoir, so players on the same wifi
/// find rooms without typing IP addresses. Manual `IP:port` joining remains
/// available as a fallback for networks that block multicast.
class DiscoveryService {
  static const serviceType = '_digipoly._tcp';

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySubscription;

  /// Keyed by game id, not service name: mDNS auto-renames a service
  /// ("Game (2)") when a stale registration with the same name lingers,
  /// which would list the same room twice.
  final Map<String, DiscoveredRoom> _rooms = {};
  final _roomsController =
      StreamController<List<DiscoveredRoom>>.broadcast();

  Stream<List<DiscoveredRoom>> get rooms => _roomsController.stream;
  List<DiscoveredRoom> get currentRooms => _rooms.values.toList();

  Future<void> advertise({required Game game, required int port}) async {
    if (kIsWeb) return;
    await stopAdvertising();

    final broadcast = BonsoirBroadcast(
      service: BonsoirService(
        // The game id, not its display name: names like "Game" repeat
        // across rooms and restarts, and mDNS resolves the collision by
        // renaming — leaving ghosts and duplicates in the room list.
        name: game.id,
        type: serviceType,
        port: port,
        attributes: {
          'gameId': game.id,
          'gameName': game.name,
          'board': game.board.name,
        },
      ),
    );
    _broadcast = broadcast;
    await broadcast.initialize();
    await broadcast.start();
  }

  Future<void> stopAdvertising() async {
    final broadcast = _broadcast;
    _broadcast = null;
    await broadcast?.stop();
  }

  Future<void> startDiscovery() async {
    if (kIsWeb) return;
    await stopDiscovery();

    final discovery = BonsoirDiscovery(type: serviceType);
    _discovery = discovery;
    await discovery.initialize();

    _discoverySubscription = discovery.eventStream?.listen((event) {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent(:final service):
          discovery.serviceResolver.resolveService(service);
        case BonsoirDiscoveryServiceResolvedEvent(:final service):
          final host = service.hostAddress;
          if (host == null) return;
          _addIfReachable(DiscoveredRoom(
            serviceName: service.name,
            gameId: service.attributes['gameId'] ?? '',
            gameName: service.attributes['gameName'] ?? service.name,
            boardName: service.attributes['board'] ?? '',
            host: host,
            port: service.port,
          ));
        case BonsoirDiscoveryServiceLostEvent(:final service):
          _rooms.removeWhere((_, room) => room.serviceName == service.name);
          _emit();
        default:
          break;
      }
    });
    await discovery.start();
  }

  Future<void> stopDiscovery() async {
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    final discovery = _discovery;
    _discovery = null;
    await discovery?.stop();
    _rooms.clear();
  }

  /// mDNS records outlive rooms — a force-closed host never unregisters,
  /// and OS caches keep answering until the TTL runs out. Only rooms that
  /// actually accept a TCP connection right now get listed.
  Future<void> _addIfReachable(DiscoveredRoom room) async {
    final key = room.gameId.isEmpty
        ? '${room.host}:${room.port}'
        : room.gameId;
    try {
      final socket = await Socket.connect(
        room.host,
        room.port,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
    } catch (_) {
      if (_rooms.remove(key) != null) _emit();
      return;
    }
    if (_discovery == null) return; // Discovery stopped while probing.
    _rooms[key] = room;
    _emit();
  }

  void _emit() {
    if (!_roomsController.isClosed) _roomsController.add(currentRooms);
  }

  void dispose() {
    stopAdvertising();
    stopDiscovery();
    _roomsController.close();
  }
}
