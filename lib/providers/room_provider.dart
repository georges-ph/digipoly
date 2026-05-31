import 'package:flutter/material.dart';

import '../core/errors/failures.dart';
import '../usecases/create_room_usecase.dart';
import '../usecases/usecase.dart';

class RoomProvider extends ChangeNotifier {
  final CreateRoomUsecase _createRoomUsecase;

  RoomProvider({
    required CreateRoomUsecase createRoomUsecase,
  }) : _createRoomUsecase = createRoomUsecase;

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
}
