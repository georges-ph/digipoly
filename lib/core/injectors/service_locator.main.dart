part of 'service_locator.dart';

class ServiceLocator {
  static late NetworkService _networkService;
  static late ServerService _serverService;
  static late DiscoveryService _discoveryService;
  static late DeviceService _deviceService;
  static late ClientService _clientService;

  static late RoomRepository _roomRepository;

  static RoomProvider? _roomProvider;

  static Future<void> init() async {
    _networkService = NetworkService(Connectivity(), NetworkInfo());
    _serverService = ServerService();
    _discoveryService = DiscoveryService();
    _deviceService = DeviceService(DeviceInfoPlugin());
    _clientService = ClientService();

    _roomRepository = RoomRepositoryImpl(
      networkService: _networkService,
      serverService: _serverService,
      discoveryService: _discoveryService,
      deviceService: _deviceService,
      clientService: _clientService,
    );
  }

  static RoomProvider get roomProvider {
    return _roomProvider ??= RoomProvider(
      createRoomUsecase: CreateRoomUsecase(_roomRepository),
      closeRoomUsecase: CloseRoomUsecase(_roomRepository),
      startDiscoveryUsecase: StartDiscoveryUsecase(_roomRepository),
      joinRoomUsecase: JoinRoomUsecase(_roomRepository),
      stopDiscoveryUsecase: StopDiscoveryUsecase(_roomRepository),
      leaveRoomUsecase: LeaveRoomUsecase(_roomRepository),
    );
  }
}
