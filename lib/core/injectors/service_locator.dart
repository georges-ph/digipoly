import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../../providers/room_provider.dart';
import '../../repositories/room_repository.dart';
import '../../services/device_service.dart';
import '../../services/discovery_service.dart';
import '../../services/network_service.dart';
import '../../services/server_service.dart';
import '../../usecases/close_room_usecase.dart';
import '../../usecases/create_room_usecase.dart';

part 'service_locator.main.dart';
