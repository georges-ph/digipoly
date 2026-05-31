import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/extensions/context_extensions.dart';
import '../providers/room_provider.dart';
import 'room_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => _createRoom(context),
          child: const Text("Create room"),
        ),
      ),
    );
  }

  Future<void> _createRoom(BuildContext context) async {
    final provider = context.read<RoomProvider>();
    final started = await provider.createRoom();

    if (!context.mounted) return;

    if (provider.failure != null) {
      context.showSnackBar(SnackBar(content: Text(provider.failure!.message)));
      return;
    }

    if (started) context.push(const RoomScreen());
  }
}
