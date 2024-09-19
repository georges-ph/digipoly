// ignore_for_file: public_member_api_docs, sort_constructors_first, prefer_const_constructors, prefer_const_literals_to_create_immutables, avoid_print, unused_field, use_super_parameters, unused_local_variable
import 'package:client_server_sockets/client_server_sockets.dart' hide Payload;
import 'package:flutter/material.dart';

import '../enums/payload_type.dart';
import '../models/payload.dart';
import '../models/player.dart';
import '../models/players.dart';
import '../widgets/players_list.dart';

class ClientScreen extends StatefulWidget {
  const ClientScreen({
    Key? key,
    required this.playerName,
    required this.serverAddress,
  }) : super(key: key);

  final String playerName;
  final String serverAddress;

  @override
  State<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<ClientScreen> {
  final _client = Client.instance;
  Players _players = Players(players: []);
  int _balance = 0;

  @override
  void initState() {
    super.initState();
    _initClient();
  }

  Future<void> _initClient() async {
    final connected = await _client.connect(
      widget.serverAddress,
      onClientError: (error) {
        print("Client error: $error");
        if (error.contains("SocketException")) {
          Navigator.pop(context);
        }
      },
      onServerData: (data) {
        print("Message from sever: $data");
        Payload payload = Payload.fromJson(data);
        if (payload.type == PayloadType.players) {
          setState(() {
            _players = Players.fromJson(payload.data);
            _balance = _players.players.singleWhere((player) => player.port == _client.port).balance;
          });
        }
      },
      onServerError: (error) {
        print("Error from server: $error");
        _client.disconnect();
        Navigator.pop(context);
      },
      onServerStopped: () {
        print("Server stopped");
        _client.disconnect();
        Navigator.pop(context);
      },
    );

    if (!connected) return;

    _client.send(Payload(
      type: PayloadType.name,
      data: widget.playerName,
    ).toJson());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Game"),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text("Balance: $_balance"),
          ),
        ],
      ),
      body: PlayersList(
        players: _players,
        onBankPay: (amount) {
          setState(() => _balance -= amount);

          _client.send(Payload(
            type: PayloadType.payment,
            data: _balance,
          ).toJson());
        },
        onBankCollect: (amount) {
          setState(() => _balance += amount);

          _client.send(Payload(
            type: PayloadType.payment,
            data: _balance,
          ).toJson());
        },
        onPlayerSend: (amount, player) {
          setState(() => _balance -= amount);

          _client.send(Payload(
            type: PayloadType.payment,
            data: amount,
            port: player.port,
          ).toJson());
        },
      ),
    );
  }
}
