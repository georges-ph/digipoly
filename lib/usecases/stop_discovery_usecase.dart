import '../core/errors/failures.dart';
import '../repositories/room_repository.dart';
import 'usecase.dart';

class StopDiscoveryUsecase implements Usecase<bool, NoParams> {
  final RoomRepository _roomRepository;
  const StopDiscoveryUsecase(this._roomRepository);

  @override
  Future<(Failure?, bool?)> call(NoParams params) async {
    return await _roomRepository.stopDiscovery();
  }
}
