import '../core/errors/failures.dart';
import '../repositories/room_repository.dart';
import 'usecase.dart';

class CreateRoomUsecase implements Usecase<String, NoParams> {
  final RoomRepository _roomRepository;
  const CreateRoomUsecase(this._roomRepository);

  @override
  Future<(Failure?, String?)> call(NoParams params) async {
    return await _roomRepository.createRoom();
  }
}
