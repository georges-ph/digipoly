import 'dart:async';

import 'package:flutter/material.dart';

import '../core/errors/failures.dart';
import '../models/discovered_room.dart';
import '../usecases/close_room_usecase.dart';
import '../usecases/create_room_usecase.dart';
import '../usecases/join_room_usecase.dart';
import '../usecases/start_discovery_usecase.dart';
import '../usecases/stop_discovery_usecase.dart';
import '../usecases/usecase.dart';

class RoomProvider extends ChangeNotifier {
  final CreateRoomUsecase _createRoomUsecase;
  final CloseRoomUsecase _closeRoomUsecase;
  final StartDiscoveryUsecase _startDiscoveryUsecase;
  final JoinRoomUsecase _joinRoomUsecase;
  final StopDiscoveryUsecase _stopDiscoveryUsecase;

  RoomProvider({
    required CreateRoomUsecase createRoomUsecase,
    required CloseRoomUsecase closeRoomUsecase,
    required StartDiscoveryUsecase startDiscoveryUsecase,
    required JoinRoomUsecase joinRoomUsecase,
    required StopDiscoveryUsecase stopDiscoveryUsecase,
  }) : _createRoomUsecase = createRoomUsecase,
       _closeRoomUsecase = closeRoomUsecase,
       _startDiscoveryUsecase = startDiscoveryUsecase,
       _joinRoomUsecase = joinRoomUsecase,
       _stopDiscoveryUsecase = stopDiscoveryUsecase;

  Failure? _failure;
  Failure? get failure => _failure;

  String? _roomName;
  String? get roomName => _roomName;

  final List<DiscoveredRoom> _rooms = [];
  List<DiscoveredRoom> get rooms => List.unmodifiable(_rooms);
  StreamSubscription<DiscoveredRoom>? _roomsSubscription;

  Future<bool> createRoom() async {
    _failure = null;
    notifyListeners();

    final (failure, roomName) = await _createRoomUsecase.call(NoParams());

    if (failure != null) {
      _failure = failure;
    } else {
      _roomName = roomName;
    }

    notifyListeners();
    return _failure == null;
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

  Future<bool> joinRoom(String address, int port) async {
    _failure = null;
    notifyListeners();

    final (failure, joined) = await _joinRoomUsecase.call(JoinRoomParams(address, port));

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
}
