import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../core/errors/exceptions.dart';

class NetworkService {
  final Connectivity _connectivity;
  final NetworkInfo _networkInfo;

  const NetworkService(this._connectivity, this._networkInfo);

  /// Checks if connected to Wi-Fi.
  ///
  /// Throws a [NetworkException] if not connected to Wi-Fi.
  Future<void> checkWifi() async {
    final result = await _connectivity.checkConnectivity();
    if (!result.contains(ConnectivityResult.wifi)) {
      throw const NetworkException("Not connected to Wi-Fi");
    }
  }

  /// Gets the Wi-Fi IP address of the device.
  ///
  /// Throws a [NetworkException] if the address is unavailable.
  Future<String> getIpAddress() async {
    final address = await _networkInfo.getWifiIP();
    if (address == null || address.trim().isEmpty) {
      throw const NetworkException("Unable to get IP address");
    }
    return address.trim();
  }
}
