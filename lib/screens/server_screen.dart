// ignore_for_file: public_member_api_docs, sort_constructors_first, prefer_const_constructors, prefer_const_literals_to_create_immutables, avoid_print, unused_field, use_super_parameters, unused_local_variable, prefer_final_fields
import 'package:client_server_sockets/client_server_sockets.dart' show Server;
import 'package:flutter/material.dart';

import '../enums/payload_type.dart';
import '../models/payload.dart';
import '../models/player.dart';
import '../models/players.dart';
import '../widgets/players_list.dart';

class ServerScreen extends StatefulWidget {
  const ServerScreen({
    Key? key,
    required this.playerName,
    required this.amount,
  }) : super(key: key);

  final String playerName;
  final int amount;

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final _server = Server.instance;
  Players _players = Players(players: []);
  int _balance = 0;

  @override
  void initState() {
    super.initState();
    _initServer();
    _balance = widget.amount;
    _players.players.insert(0, Player(name: "Bank", balance: 0, port: 0));
  }

  @override
  void dispose() {
    _server.stop();
    super.dispose();
  }

  Future<void> _initServer() async {
    final started = await _server.start(
      onServerError: (error) {
        print("Server error: $error");
        _server.stop();
        setState(() {
          _players.players
            ..skip(1)
            ..clear();
        });
      },
      onNewClient: (client) {
        print("New client: ${client.remotePort}");
      },
      onClientData: (client, data) {
        Payload payload = Payload.fromJson(data);
        print("Message from client ${client.remotePort}: $payload");
        // _server.sendTo(payload.port, payload.data);

        if (payload.type == PayloadType.name) {
          setState(() {
            _players.players.add(Player(
              name: payload.data as String,
              balance: widget.amount,
              port: client.remotePort,
            ));
          });

          _server.broadcast(Payload(
            type: PayloadType.players,
            data: _players.toJson(),
          ).toJson());
        } else if (payload.type == PayloadType.payment) {
          final player = _players.players.singleWhere((e) => e.port == client.remotePort);
          setState(() {
            player.balance = payload.data as int;
            if (payload.port != null) {
              final receiver = _players.players.singleWhere((e) => e.port == payload.port);
              receiver.balance += payload.data as int;
            }
          });

          _server.broadcast(Payload(
            type: PayloadType.players,
            data: _players.toJson(),
          ).toJson());
        }
      },
      onClientError: (client, error) {
        print("Error from client ${client.remotePort}: $error");
        setState(() => _players.players.removeWhere((player) => player.port == client.remotePort));
      },
      onClientLeft: (client) {
        print("Client ${client.remotePort} left");
        setState(() => _players.players.removeWhere((player) => player.port == client.remotePort));
      },
    );

    if (!started) return;

    setState(() {
      _players.players.insert(
          1,
          Player(
            name: widget.playerName,
            balance: widget.amount,
            port: _server.port!,
          ));
    });
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
          _players.players[1].balance = _balance;
          _server.broadcast(Payload(
            type: PayloadType.players,
            data: _players,
          ).toJson());
        },
        onBankCollect: (amount) {
          setState(() => _balance += amount);
          _players.players[1].balance = _balance;
          _server.broadcast(Payload(
            type: PayloadType.players,
            data: _players,
          ).toJson());
        },
        onPlayerSend: (amount, player) {
          setState(() => _balance -= amount);
          _players.players[1].balance = _balance;

          final receiver = _players.players.singleWhere((e) => e.port == player.port);
          receiver.balance += amount;

          _server.broadcast(Payload(
            type: PayloadType.players,
            data: _players,
          ).toJson());
        },
      ),
    );
  }
}
