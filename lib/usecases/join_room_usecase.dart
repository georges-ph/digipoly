import '../core/errors/failures.dart';
import '../repositories/room_repository.dart';
import 'usecase.dart';

class JoinRoomUsecase implements Usecase<bool, JoinRoomParams> {
  final RoomRepository _roomRepository;
  const JoinRoomUsecase(this._roomRepository);

  @override
  Future<(Failure?, bool?)> call(JoinRoomParams params) async {
    final result = await _roomRepository.joinRoom(params.address, params.port);
    if (result.$1 != null || !result.$2) return result;

    await _roomRepository.stopDiscovery();
    return (null, true);
  }
}

class JoinRoomParams {
  final String address;
  final int port;

  const JoinRoomParams(this.address, this.port);
}
