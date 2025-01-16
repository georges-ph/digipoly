import 'dart:math';

import 'package:client_server_sockets/client_server_sockets.dart';
import 'package:flutter/material.dart';

import '../exceptions/app_exception.dart';
import '../models/player.dart';

class GameProvider extends ChangeNotifier {
  final _port = 42159;
  bool _gameStarted = false;
  String? _roomId;
  final List<Player> _players = [];

  bool get gameStarted => _gameStarted;
  String? get roomId => _roomId;
  List<Player> get players => _players;

  String _generateRoomId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();
  }

  void _resetGame() {
    _gameStarted = false;
    _roomId = null;
    _players.clear();
  }

  Future<String> openRoom() async {
    await Server.instance.start(
      port: _port,
      onServerError: (error) => throw AppException("Server error: $error"),
      onNewClient: (client) {
        _players.add(Player(port: client.remotePort));
        notifyListeners();
      },
      onClientData: (client, data) {},
      onClientError: (client, error) {
        _players.removeWhere((player) => player.port == client.remotePort);
        notifyListeners();
      },
      onClientLeft: (client) {
        _players.removeWhere((player) => player.port == client.remotePort);
        notifyListeners();
      },
    );

    _roomId = _generateRoomId();
    notifyListeners();
    return _roomId!;
  }

  void closeRoom() {
    Server.instance.stop();
    _resetGame();
    notifyListeners();
  }

  Future<bool> joinRoom(String roomId, String address) async {
    final connected = await Client.instance.connect(
      address,
      port: _port,
      onClientError: (error) => throw AppException("Client error: $error"),
      onServerData: (data) {},
      onServerError: (error) {
        Client.instance.disconnect();
        _resetGame();
        notifyListeners();
      },
      onServerStopped: () {
        Client.instance.disconnect();
        _resetGame();
        notifyListeners();
      },
    );

    _roomId = roomId;
    notifyListeners();
    return connected;
  }
}
