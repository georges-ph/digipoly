import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/errors/exceptions.dart';
import '../models/events/app_event.dart';

class ServerService {
  HttpServer? _server;
  final _sockets = <WebSocketChannel>[];

  bool get isRunning => _server != null;

  StreamController<AppEvent>? _eventsController;
  Stream<AppEvent>? get events => _eventsController?.stream;

  /// Starts the server on the specified [address] and returns the port that has started on.
  ///
  /// Throws a [ServerException] if the server is already running.
  Future<int> start(String address) async {
    if (isRunning) throw const ServerException("Server is already running");

    _eventsController = StreamController.broadcast();

    final handler = webSocketHandler((webSocket, _) {
      _sockets.add(webSocket);

      webSocket.stream.listen(
        (data) => _eventsController!.add(AppEvent.fromJson(data)),
        onDone: () => _sockets.remove(webSocket),
        onError: (_) => _sockets.remove(webSocket),
        cancelOnError: true,
      );
    });

    _server = await shelf_io.serve(handler, address, 0);
    return _server!.port;
  }

  /// Stops the server if running.
  Future<void> stop() async {
    while (_sockets.isNotEmpty) {
      final socket = _sockets.removeLast();
      await socket.sink.close();
    }
    _sockets.clear();
    await _server?.close();
    _server = null;
    await _eventsController?.close();
    _eventsController = null;
  }

  /// Broadcasts a [message] to all connected clients.
  void broadcast(String message) {
    for (final socket in _sockets) {
      socket.sink.add(message);
    }
  }
}
