import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/room_repository.dart';

class LeaveRoomUsecase implements Usecase<bool, NoParams> {
  final RoomRepository _roomRepository;
  const LeaveRoomUsecase(this._roomRepository);

  @override
  Future<(Failure?, bool?)> call(NoParams params) async {
    return await _roomRepository.leaveRoom();
  }
}
