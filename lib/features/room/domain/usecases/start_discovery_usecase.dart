import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/discovered_room.dart';
import '../repositories/room_repository.dart';

class StartDiscoveryUsecase implements Usecase<Stream<DiscoveredRoom>, NoParams> {
  final RoomRepository _roomRepository;
  const StartDiscoveryUsecase(this._roomRepository);

  @override
  Future<(Failure?, Stream<DiscoveredRoom>?)> call(NoParams params) async {
    return await _roomRepository.startDiscovery();
  }
}
