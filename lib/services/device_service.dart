import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceService {
  final DeviceInfoPlugin _deviceInfo;

  DeviceService(this._deviceInfo);

  /// Gets the device name by platform. Returns unknown for unknown platforms.
  Future<String> getName() async {
    switch (defaultTargetPlatform) {
      case .android:
        return (await _deviceInfo.androidInfo).name;

      case .iOS:
        return (await _deviceInfo.iosInfo).name;

      case .linux:
        return (await _deviceInfo.linuxInfo).name;

      case .macOS:
        return (await _deviceInfo.macOsInfo).computerName;

      case .windows:
        return (await _deviceInfo.windowsInfo).computerName;

      default:
        return "Unknown device";
    }
  }
}
