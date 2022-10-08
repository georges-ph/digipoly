import 'dart:async';
import 'dart:io';

class Server {
  static final Server _instance = Server._internal();

  late ServerSocket _serverSocket;
  String _errorMessage = "", _infoMessage = "";
  List<Socket> _socketsList = [];
  final _streamController = StreamController<dynamic>.broadcast();
  final _infoStreamController = StreamController<String>.broadcast();
  final _errorStreamController = StreamController<String>.broadcast();
  Function(int)? socketLeft;

  Server._internal();

  factory Server() {
    return _instance;
  }

  String get address => _serverSocket.address.address;
  int get port => _serverSocket.port;
  String get errorMessage => _errorMessage;
  String get infoMessage => _infoMessage;
  Stream<dynamic> get stream => _streamController.stream;
  Stream<String> get infoStream => _infoStreamController.stream;
  Stream<String> get errorStream => _errorStreamController.stream;

  Future<bool> startServer(String address, {int? port}) async {
    try {
      _serverSocket = await ServerSocket.bind(
        address,
        port ?? 8080,
        shared: true,
      );
      _infoMessage =
          "Server running on ${_serverSocket.address.address}:${_serverSocket.port}";
      _infoStreamController.sink.add(_infoMessage);
    } catch (e) {
      _errorMessage = e.toString();
      _errorStreamController.sink.add(_errorMessage);
      _streamController.sink.addError(_errorMessage);
      return false;
    }

    _serverSocket.listen(_listenForSockets);

    return true;
  }

  Future<bool> stopServer() async {
    for (var socket in _socketsList) {
      await socket.close();
    }
    _socketsList.clear();
    await _serverSocket.close();
    // await _streamController.close();
    return true;
  }

  void _listenForSockets(Socket socket) {
    _infoMessage =
        "Connection from ${socket.remoteAddress.address}:${socket.remotePort}";
    _infoStreamController.sink.add(_infoMessage);
    socket.listen(
      (data) {
        final response = String.fromCharCodes(data);
        _streamController.sink.add(response);

        if (!_socketsList.contains(socket)) {
          _socketsList.add(socket);
        }
      },
      onError: (error) {
        _infoMessage =
            "Client ${socket.remoteAddress.address}:${socket.remotePort} got an error";
        _errorMessage = error;
        _infoStreamController.sink.add(_infoMessage);
        _errorStreamController.sink.add(_errorMessage);
        _streamController.sink.addError(error);
        socket.close();
        _socketsList.remove(socket);
      },
      onDone: () {
        _infoMessage =
            "Client ${socket.remoteAddress.address}:${socket.remotePort} is done";
        _infoStreamController.sink.add(_infoMessage);
        socketLeft!(socket.remotePort);
        socket.close();
        _socketsList.remove(socket);
      },
    );
  }

  void broadcast(String message) {
    print(_socketsList);
    for (var socket in _socketsList) {
      socket.write(message);
    }
  }

  void sendTo(int port, String message) {
    Socket socket = _socketsList.firstWhere(
      (element) =>
          // element.remoteAddress.address == address &&
          element.remotePort == port,
    );
    socket.write(message);
  }
}
