import 'dart:async';
import 'dart:io';

class Server {
  late ServerSocket _serverSocket;
  final List<Socket> _socketsList = [];
  late final StreamController<dynamic> _streamController;
  Function(int)? onSocketDone;

  String get address => _serverSocket.address.address;
  int get port => _serverSocket.port;
  Stream<dynamic> get stream => _streamController.stream;

  Future<bool> startServer(String address) async {
    _streamController = StreamController<dynamic>.broadcast();

    try {
      _serverSocket = await ServerSocket.bind(
        address,
        8080,
        shared: true,
      );
    } catch (e) {
      _streamController.sink.addError(e);
      return false;
    }

    print(
        "Server running on ${_serverSocket.address.address}:${_serverSocket.port}");
    _serverSocket.listen(_listenForSockets);

    return true;
  }

  Future<bool> stopServer() async {
    for (var socket in _socketsList) {
      await socket.close();
    }
    _socketsList.clear();
    await _serverSocket.close();
    await _streamController.close();
    return true;
  }

  void _listenForSockets(Socket socket) {
    print(
        "Connection from ${socket.remoteAddress.address}:${socket.remotePort}");
    socket.listen(
      (data) {
        final response = String.fromCharCodes(data);
        _streamController.sink.add(response);

        if (!_socketsList.contains(socket)) {
          _socketsList.add(socket);
        }
      },
      onError: (error) {
        print(
            "Client ${socket.remoteAddress.address}:${socket.remotePort} got an error");
        _streamController.sink.addError(error);
        socket.close();
        _socketsList.remove(socket);
      },
      onDone: () {
        print(
            "Client ${socket.remoteAddress.address}:${socket.remotePort} is done");
        onSocketDone!(socket.remotePort);
        socket.close();
        _socketsList.remove(socket);
      },
    );
  }

  void broadcast(String message) {
    for (var socket in _socketsList) {
      socket.write(message);
    }
  }

  void sendTo(int port, String message) {
    Socket socket = _socketsList.firstWhere(
      (element) => element.remotePort == port,
    );
    socket.write(message);
  }
}
