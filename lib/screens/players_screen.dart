// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'package:digipoly/enums/payload_type.dart';
import 'package:digipoly/enums/socket_type.dart';
import 'package:digipoly/globals.dart';
import 'package:digipoly/models/payload.dart';
import 'package:digipoly/models/payment.dart';
import 'package:digipoly/models/player.dart';
import 'package:digipoly/models/players.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class PlayersScreen extends StatefulWidget {
  const PlayersScreen({super.key});

  @override
  State<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends State<PlayersScreen> {
  num _balance = 0;
  Players _players = Players(players: []);

  @override
  void initState() {
    super.initState();
    _listeners();
  }

  @override
  void dispose() {
    if (socketType == SocketType.server) {
      players.players.clear();
      server.stopServer();
    } else if (socketType == SocketType.client) {
      client.disconnect();
    }
    socketType = SocketType.none;
    super.dispose();
  }

  void _listeners() {
    if (socketType == SocketType.server) {
      _balance = startingAmount;
      _players = players;

      server.onSocketDone = (port) {
        players.players.removeWhere((element) => element.port == port);
        _players = players;
        setState(() {});

        Payload playersPayload = Payload(
          type: Payloadtype.players,
          data: players,
        );

        server.broadcast(playersPayload.toJson());
      };

      server.stream.listen((event) {
        Payload payload = Payload.fromJson(event);

        if (payload.type == Payloadtype.player) {
          Player player = Player.fromJson(payload.data);

          final tempPlayer =
              players.players.where((element) => element.port == player.port);
          if (tempPlayer.isEmpty) {
            players.players.add(player);
            _players = players;
            setState(() {});
          }

          Payload playersPayload = Payload(
            type: Payloadtype.players,
            data: players,
          );

          Payload amountPayload = Payload(
            type: Payloadtype.payment,
            data: Payment(
              toPort: 0,
              amount: startingAmount,
            ),
          );

          server.broadcast(playersPayload.toJson());

          Future.delayed(
            Duration(seconds: 1),
            () => server.sendTo(player.port, amountPayload.toJson()),
          );
        } else if (payload.type == Payloadtype.payment) {
          Payment payment = Payment.fromJson(payload.data);
          if (payment.toPort != server.port) {
            server.sendTo(payment.toPort, payload.toJson());
          } else {
            _balance += payment.amount;
            setState(() {});
          }
        }
      });
    } else if (socketType == SocketType.client) {
      client.onSocketDone = () {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          Navigator.pop(context);
        });
      };

      client.stream.listen((event) {
        Payload payload = Payload.fromJson(event);

        if (payload.type == Payloadtype.players) {
          _players = Players.fromJson(payload.data);
          setState(() {});
        } else if (payload.type == Payloadtype.payment) {
          Payment payment = Payment.fromJson(payload.data);
          _balance += payment.amount;
          setState(() {});
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Players"),
        actions: [
          TextButton(
            onPressed: null,
            child: Text(
              "Balance: $_balance",
              style: TextStyle(
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: ListView.separated(
        padding: EdgeInsets.all(24),
        itemCount: socketType == SocketType.client
            ? _players.players.length
            : _players.players.length + 1,
        itemBuilder: (context, index) {
          if ((socketType == SocketType.server) && (index == 0)) {
            return Text(
              "Server running on ${server.address}",
              style: Theme.of(context).textTheme.titleMedium,
            );
          }

          if (socketType == SocketType.server) index = index - 1;

          Player player = _players.players.elementAt(index);
          TextEditingController controller = TextEditingController();

          return Card(
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              title: Text(player.name),
              subtitle: Text("port: ${player.port}"),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              childrenPadding: EdgeInsets.symmetric(
                horizontal: 16,
              ),
              children: ((socketType == SocketType.client &&
                          player.port == client.port) ||
                      (socketType == SocketType.server &&
                          player.port == server.port))
                  ? [Container()]
                  : [
                      TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: "Enter amount to pay",
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          _sendPayment(
                              player.port, num.parse(controller.text.trim()));
                        },
                        icon: Icon(Icons.send),
                        label: Text("Send"),
                      ),
                    ],
            ),
          );
        },
        separatorBuilder: (BuildContext context, int index) =>
            SizedBox(height: 16),
      ),
    );
  }

  void _sendPayment(int port, num amount) {
    _balance -= amount;
    setState(() {});

    Payload payload = Payload(
      type: Payloadtype.payment,
      data: Payment(
        toPort: port,
        amount: amount,
      ),
    );

    if (socketType == SocketType.client) {
      client.send(payload.toJson());
    } else if (socketType == SocketType.server) {
      server.sendTo(port, payload.toJson());
    }
  }
}
