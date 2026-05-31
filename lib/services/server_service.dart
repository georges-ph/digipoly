import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';

import '../core/errors/exceptions.dart';

class ServerService {
  HttpServer? _server;

  /// Starts the server on the specified [address] and returns the port that has started on.
  ///
  /// Throws a [ServerException] if the server is already running.
  Future<int> start(String address) async {
    if (_server != null) throw const ServerException("Server is already running");

    final handler = webSocketHandler((webSocket, _) {});
    _server = await shelf_io.serve(handler, address, 0);
    return _server!.port;
  }

  /// Stops the server if running.
  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }
}
