// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, use_build_context_synchronously

import 'package:digipoly/enums/payload_type.dart';
import 'package:digipoly/enums/socket_type.dart';
import 'package:digipoly/globals.dart';
import 'package:digipoly/models/payload.dart';
import 'package:digipoly/models/player.dart';
import 'package:digipoly/screens/players_screen.dart';
import 'package:digipoly/services/client.dart';
import 'package:digipoly/services/server.dart';
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

  TextEditingController _nameController = TextEditingController();
  TextEditingController _amountController = TextEditingController();
  TextEditingController _addressController = TextEditingController();

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
        title: Text("Digipoly"),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              Visibility(
                visible: _createVisibility,
                child: TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: "Enter your name",
                    hintText: "John",
                  ),
                ),
              ),
              Visibility(
                visible: _createVisibility,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 16,
                  ),
                  child: TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: "Enter starting amount",
                      hintText: "100",
                    ),
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: _createRoom,
                child: Text("Create room"),
              ),
              Visibility(
                visible: _joinVisibility,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 16,
                  ),
                  child: TextField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: "Enter your name",
                      hintText: "John",
                    ),
                  ),
                ),
              ),
              Visibility(
                visible: _joinVisibility,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: 16,
                  ),
                  child: TextField(
                    controller: _addressController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: "Enter server address",
                      hintText: "192.168.1.1",
                    ),
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: _joinRoom,
                child: Text("Join room"),
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
      SnackBar snackBar = SnackBar(content: Text("Fill out both fields"));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
      return;
    }

    String? address = await wifiIp();
    if (address == null) {
      // TODO: handle this
      return;
    }

    socketType = SocketType.server;
    server = Server();

    // must listen to stream before sending events
    server.stream.listen(print);
    server.infoStream.map((event) => "Info: $event").listen(print);
    server.errorStream.map((event) => "Error: $event").listen(print);

    final started = await server.startServer(address);
    if (!started) return;

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
        builder: (context) => PlayersScreen(),
      ),
    );
  }

  Future<void> _joinRoom() async {
    if (_nameController.text.isEmpty || _addressController.text.isEmpty) {
      setState(() {
        _joinVisibility = true;
      });
      SnackBar snackBar = SnackBar(content: Text("Fill out both field"));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
      return;
    }

    String? address = await wifiIp();
    if (address == null) {
      // TODO: handle this
      return;
    }

    socketType = SocketType.client;
    client = Client();

    client.stream.listen(print);
    client.infoStream.map((event) => "Info: $event").listen(print);
    client.errorStream.map((event) => "Error: $event").listen(print);

    final connected = await client.connect(_addressController.text.trim());
    if (!connected) return;

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
        builder: (context) => PlayersScreen(),
      ),
    );
  }

  Future<String?> wifiIp() async {
    final networkInfo = NetworkInfo();
    final wifiIp = await networkInfo.getWifiIP();

    if (wifiIp == null) {
      // TODO: handle this
      // maybe retry and if not working either use any ip or provide a way to manually enter one
      return null;
    }

    return wifiIp;
  }
}
