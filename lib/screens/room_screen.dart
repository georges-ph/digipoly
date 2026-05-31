import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/room_provider.dart';

class RoomScreen extends StatelessWidget {
  const RoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Room Details")),
      body: Center(
        child: Text(context.read<RoomProvider>().roomName ?? "Room name"),
      ),
    );
  }
}
