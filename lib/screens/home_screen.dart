// ignore_for_file: prefer_const_constructors, unused_import

import 'package:flutter/material.dart';

import '../enums/socket_type.dart';
import '../utils/sizes.dart';
import 'client_screen.dart';
import '../widgets/balance.dart';
import 'server_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Digipoly")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => _createRoom(context),
              child: const Text("Create room"),
            ),
            ElevatedButton(
              onPressed: () => _joinRoom(context),
              child: const Text("Join room"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createRoom(BuildContext context) async {
    TextEditingController nameController = TextEditingController(text: "Windows");
    TextEditingController amountController = TextEditingController(text: "100");

    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        contentPadding: const EdgeInsets.all(24),
        title: const Text("Create room"),
        children: [
          TextField(
            controller: nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: "John",
              labelText: "Enter your name",
            ),
          ),
          verticalSpace(16),
          TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: "100",
              labelText: "Enter starting amount",
            ),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty || amountController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fill out both fields")));
                return;
              }

              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => ServerScreen(
                  playerName: nameController.text.trim(),
                  amount: int.tryParse(amountController.text.trim()) ?? 0,
                ),
              ));
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  Future<void> _joinRoom(BuildContext context) async {
    TextEditingController nameController = TextEditingController(text: "Android");
    TextEditingController addressController = TextEditingController(text: "192.168.1.11");

    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        contentPadding: const EdgeInsets.all(24),
        title: const Text("Join room"),
        children: [
          TextField(
            controller: nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: "John",
              labelText: "Enter your name",
            ),
          ),
          verticalSpace(16),
          TextField(
            controller: addressController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: "192.168.1.10",
              labelText: "Enter server address",
            ),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty || addressController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fill out both fields")));
                return;
              }

              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => ClientScreen(
                  playerName: nameController.text.trim(),
                  serverAddress: addressController.text.trim(),
                ),
              ));
            },
            child: const Text("Join"),
          ),
        ],
      ),
    );
  }
}
