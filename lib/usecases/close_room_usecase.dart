import '../core/errors/failures.dart';
import '../repositories/room_repository.dart';
import 'usecase.dart';

class CloseRoomUsecase implements Usecase<bool, NoParams> {
  final RoomRepository _roomRepository;
  const CloseRoomUsecase(this._roomRepository);

  @override
  Future<(Failure?, bool)> call(NoParams params) async {
    return await _roomRepository.closeRoom();
  }
}
