import '../../../../core/errors/failures.dart';
import '../../../../core/models/app_event.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/room_repository.dart';

class CreateRoomUsecase implements Usecase<(String, Stream<RoomEvent>), NoParams> {
  final RoomRepository _roomRepository;
  const CreateRoomUsecase(this._roomRepository);

  @override
  Future<(Failure?, (String, Stream<RoomEvent>)?)> call(NoParams params) async {
    return await _roomRepository.createRoom();
  }
}
