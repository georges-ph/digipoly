import 'package:web_socket/web_socket.dart';

import '../core/errors/exceptions.dart';

class ClientService {
  WebSocket? _socket;

  bool get isConnected => _socket != null;

  /// Connects to a socket using [address] and [port].
  ///
  /// Throws a [ClientException] if the client is already connected to a socket.
  Future<void> connect(String address, int port) async {
    if (isConnected) throw const ClientException("Client is already connected");

    final uri = Uri.parse("ws://$address:$port");
    _socket = await WebSocket.connect(uri);
  }

  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
  }
}
