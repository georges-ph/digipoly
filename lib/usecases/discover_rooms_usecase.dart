import '../core/errors/failures.dart';
import '../models/discovered_room.dart';
import '../repositories/room_repository.dart';
import 'usecase.dart';

class DiscoverRoomsUsecase implements Usecase<Stream<DiscoveredRoom>, NoParams> {
  final RoomRepository _roomRepository;
  const DiscoverRoomsUsecase(this._roomRepository);

  @override
  Future<(Failure?, Stream<DiscoveredRoom>?)> call(NoParams params) async {
    return await _roomRepository.discoverRooms();
  }
}
