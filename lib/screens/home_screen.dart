// ignore_for_file: use_build_context_synchronously, avoid_print

import 'package:client_server_sockets/client_server_sockets.dart';
import 'package:digipoly/enums/payload_type.dart';
import 'package:digipoly/enums/socket_type.dart';
import 'package:digipoly/globals.dart';
import 'package:digipoly/models/payload.dart';
import 'package:digipoly/models/player.dart';
import 'package:digipoly/screens/players_screen.dart';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _createVisibility = false;
  bool _joinVisibility = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Digipoly"),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Visibility(
                visible: _createVisibility,
                child: TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: "Enter your name",
                    hintText: "John",
                  ),
                ),
              ),
              Visibility(
                visible: _createVisibility,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                  ),
                  child: TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Enter starting amount",
                      hintText: "100",
                    ),
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: _createRoom,
                child: const Text("Create room"),
              ),
              Visibility(
                visible: _joinVisibility,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                  ),
                  child: TextField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: "Enter your name",
                      hintText: "John",
                    ),
                  ),
                ),
              ),
              Visibility(
                visible: _joinVisibility,
                child: Padding(
                  padding: const EdgeInsets.only(
                    bottom: 16,
                  ),
                  child: TextField(
                    controller: _addressController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Enter server address",
                      hintText: "192.168.1.1",
                    ),
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: _joinRoom,
                child: const Text("Join room"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createRoom() async {
    if (_nameController.text.isEmpty || _amountController.text.isEmpty) {
      setState(() {
        _createVisibility = true;
      });
      SnackBar snackBar = const SnackBar(content: Text("Fill out both fields"));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
      return;
    }

    String? address = await wifiIp();
    if (address == null) {
      SnackBar snackBar = const SnackBar(
          content: Text("Could not get IP address. Check your WiFi"));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
      return;
    }

    socketType = SocketType.server;
    server = Server();

    final started = await server.startServer(address);
    if (!started) return;
    server.stream.listen(
      print,
      onError: (error) {
        SnackBar snackBar = SnackBar(content: Text(error.toString()));
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      },
    );

    players.players.add(
      Player(
        name: _nameController.text.trim(),
        port: server.port,
      ),
    );

    startingAmount = num.parse(_amountController.text.trim());

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PlayersScreen(),
      ),
    );
  }

  Future<void> _joinRoom() async {
    if (_nameController.text.isEmpty || _addressController.text.isEmpty) {
      setState(() {
        _joinVisibility = true;
      });
      SnackBar snackBar = const SnackBar(content: Text("Fill out both field"));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
      return;
    }

    socketType = SocketType.client;
    client = Client();

    final connected = await client.connect(_addressController.text.trim());
    if (!connected) return;
    client.stream.listen(
      print,
      onError: (error) {
        SnackBar snackBar = SnackBar(content: Text(error.toString()));
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      },
    );

    Payload payload = Payload(
      type: Payloadtype.player,
      data: Player(
        name: _nameController.text.trim(),
        port: client.port,
      ),
    );

    client.send(payload.toJson());

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PlayersScreen(),
      ),
    );
  }

  Future<String?> wifiIp() async {
    final networkInfo = NetworkInfo();
    final wifiIp = await networkInfo.getWifiIP();

    if (wifiIp == null) {
      return null;
    }

    return wifiIp;
  }
}
