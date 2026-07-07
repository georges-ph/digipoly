import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../../features/room/data/repositories/room_repository_impl.dart';
import '../../features/room/domain/repositories/room_repository.dart';
import '../../features/room/domain/usecases/close_room_usecase.dart';
import '../../features/room/domain/usecases/create_room_usecase.dart';
import '../../features/room/domain/usecases/join_room_usecase.dart';
import '../../features/room/domain/usecases/leave_room_usecase.dart';
import '../../features/room/domain/usecases/start_discovery_usecase.dart';
import '../../features/room/domain/usecases/stop_discovery_usecase.dart';
import '../../features/room/presentation/providers/room_provider.dart';
import '../services/client_service.dart';
import '../services/device_service.dart';
import '../services/discovery_service.dart';
import '../services/network_service.dart';
import '../services/server_service.dart';

part 'service_locator.main.dart';
