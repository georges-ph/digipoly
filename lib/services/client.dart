import 'dart:async';
import 'dart:io';

class Client {
  static final Client _instance = Client._internal();

  late Socket _socket;
  String _errorMessage = "", _infoMessage = "";
  final _streamController = StreamController<dynamic>.broadcast();
  final _infoStreamController = StreamController<String>.broadcast();
  final _errorStreamController = StreamController<String>.broadcast();

  Client._internal();

  factory Client() {
    return _instance;
  }

  int get port => _socket.port;
  String get infoMessage => _infoMessage;
  String get errorMessage => _errorMessage;
  Stream<dynamic> get stream => _streamController.stream;
  Stream<String> get infoStream => _infoStreamController.stream;
  Stream<String> get errorStream => _errorStreamController.stream;

  Future<bool> connect(String address, {int? port}) async {
    try {
      _socket = await Socket.connect(
        address,
        port ?? 8080,
      );
      _infoMessage =
          "Connected to ${_socket.remoteAddress.address}:${_socket.remotePort} from ${_socket.address.address}:${_socket.port}";
      _infoStreamController.sink.add(_infoMessage);
    } catch (e) {
      _errorMessage = e.toString();
      _errorStreamController.sink.add(_errorMessage);
      _streamController.sink.addError(_errorMessage);
      return false;
    }

    _socket.listen(
      (data) {
        final response = String.fromCharCodes(data);
        _streamController.sink.add(response);
      },
      onError: (error) {
        _infoMessage =
            "Server ${_socket.remoteAddress.address}:${_socket.remotePort} got an error";
        _errorMessage = error;
        _streamController.sink.addError(error);
        _infoStreamController.sink.add(_infoMessage);
        _errorStreamController.sink.add(_errorMessage);
        _socket.destroy();
      },
      onDone: () {
        _infoMessage =
            // "Server ${_socket.remoteAddress.address}:${_socket.remotePort} is done";
            "Server is done";
        _infoStreamController.sink.add(_infoMessage);
        _socket.destroy();
      },
    );

    return true;
  }

  Future<void> disconnect() async {
    _socket.destroy();
    // await _streamController.close();
  }

  void send(String message) {
    _socket.write(message);
  }
}
