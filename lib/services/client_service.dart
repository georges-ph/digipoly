import 'dart:async';

import 'package:web_socket/web_socket.dart';

import '../core/errors/exceptions.dart';
import '../models/events/app_event.dart';

class ClientService {
  WebSocket? _socket;

  bool get isConnected => _socket != null;

  StreamController<AppEvent>? _eventsController;
  Stream<AppEvent>? get events => _eventsController?.stream;

  /// Connects to a socket using [address] and [port].
  ///
  /// Throws a [ClientException] if the client is already connected to a socket.
  Future<void> connect(String address, int port) async {
    if (isConnected) throw const ClientException("Client is already connected");

    final uri = Uri.parse("ws://$address:$port");
    _socket = await WebSocket.connect(uri);

    _eventsController = StreamController.broadcast();

    _socket!.events.listen(
      _handleSocketEvents,
      onDone: () async {
        _socket = null;
        await _eventsController?.close();
        _eventsController = null;
      },
      onError: (_) async {
        _socket = null;
        await _eventsController?.close();
        _eventsController = null;
      },
    );
  }

  void _handleSocketEvents(WebSocketEvent event) {
    switch (event) {
      case TextDataReceived(:final text):
        _eventsController!.add(AppEvent.fromJson(text));

      default:
    }
  }

  /// Disconnects the socket if previously connected.
  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
    await _eventsController?.close();
    _eventsController = null;
  }

  /// Sends a [message] to the server if connected.
  void send(String message) {
    _socket?.sendText(message);
  }
}
