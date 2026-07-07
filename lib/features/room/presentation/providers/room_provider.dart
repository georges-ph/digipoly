import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/models/app_event.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/entities/discovered_room.dart';
import '../../domain/entities/player.dart';
import '../../domain/usecases/close_room_usecase.dart';
import '../../domain/usecases/create_room_usecase.dart';
import '../../domain/usecases/join_room_usecase.dart';
import '../../domain/usecases/leave_room_usecase.dart';
import '../../domain/usecases/start_discovery_usecase.dart';
import '../../domain/usecases/stop_discovery_usecase.dart';

class RoomProvider extends ChangeNotifier {
  final CreateRoomUsecase _createRoomUsecase;
  final CloseRoomUsecase _closeRoomUsecase;
  final StartDiscoveryUsecase _startDiscoveryUsecase;
  final JoinRoomUsecase _joinRoomUsecase;
  final StopDiscoveryUsecase _stopDiscoveryUsecase;
  final LeaveRoomUsecase _leaveRoomUsecase;

  RoomProvider({
    required CreateRoomUsecase createRoomUsecase,
    required CloseRoomUsecase closeRoomUsecase,
    required StartDiscoveryUsecase startDiscoveryUsecase,
    required JoinRoomUsecase joinRoomUsecase,
    required StopDiscoveryUsecase stopDiscoveryUsecase,
    required LeaveRoomUsecase leaveRoomUsecase,
  }) : _createRoomUsecase = createRoomUsecase,
       _closeRoomUsecase = closeRoomUsecase,
       _startDiscoveryUsecase = startDiscoveryUsecase,
       _joinRoomUsecase = joinRoomUsecase,
       _stopDiscoveryUsecase = stopDiscoveryUsecase,
       _leaveRoomUsecase = leaveRoomUsecase;

  Failure? _failure;
  Failure? get failure => _failure;

  String? _roomName;
  String? get roomName => _roomName;

  StreamSubscription<RoomEvent>? _roomEventsSubscription;

  final List<Player> _players = [];
  List<Player> get players => List.unmodifiable(_players);

  final List<DiscoveredRoom> _rooms = [];
  List<DiscoveredRoom> get rooms => List.unmodifiable(_rooms);
  StreamSubscription<DiscoveredRoom>? _roomsSubscription;

  VoidCallback? onConnectionLost;

  Future<bool> createRoom() async {
    _failure = null;
    notifyListeners();

    final (failure, room) = await _createRoomUsecase.call(NoParams());

    if (failure != null) {
      _failure = failure;
    } else {
      _roomName = room?.$1;
      _roomEventsSubscription = room?.$2.listen(_handleRoomEvents);
    }

    notifyListeners();
    return _failure == null;
  }

  Future<void> _handleRoomEvents(RoomEvent event) async {
    switch (event) {
      // Server specific event - A player joined the room
      case JoinRoomEvent(:final player):
        _players.add(player);
        notifyListeners();

      // Server specific event - A player left the room
      case LeaveRoomEvent(:final player):
        _players.remove(player);
        notifyListeners();

      // Client specific event - The server closed the room
      case CloseRoomEvent():
        await leaveRoom();
    }
  }

  Future<bool> closeRoom() async {
    _failure = null;
    notifyListeners();

    final (failure, closed) = await _closeRoomUsecase.call(NoParams());

    if (failure != null) {
      _failure = failure;
    } else {
      _roomName = null;
    }

    await _roomEventsSubscription?.cancel();
    _roomEventsSubscription = null;
    _players.clear();

    notifyListeners();
    return _failure == null;
  }

  Future<bool> discoverRooms() async {
    _failure = null;
    _rooms.clear();
    await _roomsSubscription?.cancel();
    notifyListeners();

    final (failure, roomsStream) = await _startDiscoveryUsecase.call(NoParams());

    if (failure != null) {
      _failure = failure;
      notifyListeners();
      return false;
    }

    _roomsSubscription = roomsStream?.listen((room) {
      room.event == .found ? _rooms.add(room) : _rooms.remove(room);
      notifyListeners();
    });

    return true;
  }

  Future<bool> joinRoom(String name, String address, int port) async {
    _failure = null;
    notifyListeners();

    final (failure, roomEvents) = await _joinRoomUsecase.call(JoinRoomParams(address, port));

    if (failure != null) {
      _failure = failure;
      notifyListeners();
      return false;
    }

    _roomName = name;

    _roomEventsSubscription = roomEvents?.listen(
      _handleRoomEvents,
      onDone: () async => await leaveRoom(),
    );

    await _roomsSubscription?.cancel();
    _roomsSubscription = null;
    _rooms.clear();

    notifyListeners();
    return true;
  }

  Future<bool> stopDiscovery() async {
    _failure = null;
    notifyListeners();

    final (failure, stopped) = await _stopDiscoveryUsecase.call(NoParams());

    if (failure != null) {
      _failure = failure;
      notifyListeners();
      return false;
    }

    await _roomsSubscription?.cancel();
    _roomsSubscription = null;
    _rooms.clear();

    notifyListeners();
    return true;
  }

  Future<bool> leaveRoom() async {
    final connectionLostCallback = onConnectionLost;
    onConnectionLost = null;
    _failure = null;
    notifyListeners();

    final (failure, left) = await _leaveRoomUsecase.call(NoParams());

    if (failure != null) {
      _failure = failure;
      notifyListeners();
      return false;
    }

    await _roomEventsSubscription?.cancel();
    _roomEventsSubscription = null;
    _roomName = null;
    connectionLostCallback?.call();

    notifyListeners();
    return true;
  }
}
