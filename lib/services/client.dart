import 'dart:async';
import 'dart:io';

class Client {
  late Socket _socket;
  late final StreamController<dynamic> _streamController;
  Function()? onSocketDone;

  int get port => _socket.port;
  Stream<dynamic> get stream => _streamController.stream;

  Future<bool> connect(String address) async {
    _streamController = StreamController<dynamic>.broadcast();

    try {
      _socket = await Socket.connect(
        address,
        8080,
      );
    } catch (e) {
      _streamController.sink.addError(e);
      return false;
    }

    print(
        "Connected to ${_socket.remoteAddress.address}:${_socket.remotePort} from ${_socket.address.address}:${_socket.port}");

    _socket.listen(
      (data) {
        final response = String.fromCharCodes(data);
        _streamController.sink.add(response);
      },
      onError: (error) {
        print(
            "Server ${_socket.remoteAddress.address}:${_socket.remotePort} got an error");
        _streamController.sink.addError(error);
        _socket.destroy();
      },
      onDone: () {
        print(
            // "Server ${_socket.remoteAddress.address}:${_socket.remotePort} is done";
            "Server is done");
        onSocketDone!();
        _socket.destroy();
      },
    );

    return true;
  }

  Future<void> disconnect() async {
    _socket.destroy();
    await _streamController.close();
  }

  void send(String message) {
    _socket.write(message);
  }
}
