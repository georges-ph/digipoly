import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/game_provider.dart';
import '../utils/network_utils.dart';

class RoomsScreen extends StatelessWidget {
  const RoomsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Set<({String id, String address})> rooms = {};

    return Scaffold(
      appBar: AppBar(title: const Text("Rooms nearby")),
      body: StreamBuilder(
        stream: NetworkUtils.instance.listenBroadcast(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data == null || snapshot.data!.isEmpty) {
            return const Center(child: Text("No rooms nearby"));
          }

          final message = snapshot.data!.split(":");
          final (roomId, roomAddress) = (message[0], message[1]);
          rooms.add((id: roomId, address: roomAddress));

          if (context.read<GameProvider>().roomId != null) {
            return const _RoomJoined();
          }

          return _RoomsList(rooms: rooms);
        },
      ),
    );
  }
}

class _RoomJoined extends StatelessWidget {
  const _RoomJoined();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(TextSpan(children: [
            const TextSpan(text: "Joined room "),
            TextSpan(
              text: "#${context.read<GameProvider>().roomId}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ])),
          const Text("Waiting to start the game"),
        ],
      ),
    );
  }
}

class _RoomsList extends StatelessWidget {
  const _RoomsList({
    required this.rooms,
  });

  final Set<({String id, String address})> rooms;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final room = rooms.elementAt(index);

        return ListTile(
          onTap: () => context.read<GameProvider>().joinRoom(room.id, room.address),
          title: Text(room.id),
        );
      },
    );
  }
}
