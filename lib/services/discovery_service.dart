import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import '../core/errors/exceptions.dart';
import '../models/discovered_room.dart';

class DiscoveryService {
  final _type = "_digipoly-mdns._tcp";
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;

  bool get isBroadcasting => _broadcast != null;
  bool get isDiscovering => _discovery != null;

  StreamController<DiscoveredRoom>? _roomsController;
  Stream<DiscoveredRoom>? get onRoomEvent => _roomsController?.stream;

  /// Broadcasts the [message] on [port].
  ///
  /// Throws a [DiscoveryException] if the broadcast is already running.
  Future<void> broadcast(String message, int port) async {
    if (isBroadcasting) {
      throw const DiscoveryException("Broadcast is already running");
    }

    final service = BonsoirService(name: message, type: _type, port: port);
    _broadcast = BonsoirBroadcast(service: service);

    await _broadcast!.initialize();
    await _broadcast!.start();
  }

  /// Disovers nearby services.
  ///
  /// Throws a [DiscoveryException] if the discovery is already running.
  Future<void> discover() async {
    if (isDiscovering) {
      throw const DiscoveryException("Discovery is already running");
    }

    _discovery = BonsoirDiscovery(type: _type);
    await _discovery!.initialize();

    _roomsController = StreamController.broadcast();

    _discovery!.eventStream!.listen((event) {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent(:final service):
          service.resolve(_discovery!.serviceResolver);

        case BonsoirDiscoveryServiceLostEvent(:final service):
          final room = DiscoveredRoom(
            name: service.name,
            address: service.hostname ?? "Unknown",
            port: service.port,
            event: .lost,
          );
          _roomsController!.add(room);

        case BonsoirDiscoveryServiceResolvedEvent(:final service):
          final room = DiscoveredRoom(
            name: service.name,
            address: service.hostname ?? "Unknown",
            port: service.port,
            event: .found,
          );
          _roomsController!.add(room);

        default:
      }
    });

    await _discovery!.start();
  }

  /// Stops the broadcast.
  Future<void> stopBroadcast() async {
    await _broadcast?.stop();
    _broadcast = null;
  }

  /// Stops the discovery.
  Future<void> stopDiscovery() async {
    await _discovery?.stop();
    _discovery = null;
    await _roomsController?.close();
    _roomsController = null;
  }
}
