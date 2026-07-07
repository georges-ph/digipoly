import '../../../../core/errors/failures.dart';
import '../../../../core/models/app_event.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/room_repository.dart';

class JoinRoomUsecase implements Usecase<Stream<RoomEvent>, JoinRoomParams> {
  final RoomRepository _roomRepository;
  const JoinRoomUsecase(this._roomRepository);

  @override
  Future<(Failure?, Stream<RoomEvent>?)> call(JoinRoomParams params) async {
    final result = await _roomRepository.joinRoom(params.address, params.port);
    if (result.$1 != null || result.$2 == null) return result;

    await _roomRepository.stopDiscovery();
    return result;
  }
}

class JoinRoomParams {
  final String address;
  final int port;

  const JoinRoomParams(this.address, this.port);
}
