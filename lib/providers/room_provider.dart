import 'package:flutter/material.dart';

import '../core/errors/failures.dart';
import '../usecases/close_room_usecase.dart';
import '../usecases/create_room_usecase.dart';
import '../usecases/usecase.dart';

class RoomProvider extends ChangeNotifier {
  final CreateRoomUsecase _createRoomUsecase;
  final CloseRoomUsecase _closeRoomUsecase;

  RoomProvider({
    required CreateRoomUsecase createRoomUsecase,
    required CloseRoomUsecase closeRoomUsecase,
  }) : _createRoomUsecase = createRoomUsecase,
       _closeRoomUsecase = closeRoomUsecase;

  Failure? _failure;
  Failure? get failure => _failure;

  String? _roomName;
  String? get roomName => _roomName;

  Future<bool> createRoom() async {
    if (_roomName != null) {
      _failure = const ServerFailure("A room is already active");
      notifyListeners();
      return false;
    }

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
}
