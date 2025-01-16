import 'dart:async';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

class NetworkUtils {
  static final NetworkUtils instance = NetworkUtils._internal();

  NetworkUtils._internal();

  /// Get current device's IP
  Future<String?> getIpAddress() async {
    final networkInfo = NetworkInfo();
    return await networkInfo.getWifiIP();
  }

  /// Broadcasts a message to the network
  Future<void> broadcast(String message) async {
    const broadcastPort = 3000;
    final broadcastSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, broadcastPort);
    broadcastSocket
      ..broadcastEnabled = true
      ..send(message.codeUnits, InternetAddress("255.255.255.255"), broadcastPort)
      ..close();
  }

  /// Listens to a broadcasting socket
  Stream<String> listenBroadcast() async* {
    final controller = StreamController<String>();
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 3000);

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      controller.add(String.fromCharCodes(datagram.data));
    });

    controller.onCancel = () {
      socket.close();
      controller.close();
    };

    yield* controller.stream;
  }
}
