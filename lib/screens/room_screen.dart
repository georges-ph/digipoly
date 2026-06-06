import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/extensions/context_extensions.dart';
import '../models/discovered_room.dart';
import '../models/player.dart';
import '../providers/room_provider.dart';

class RoomScreen extends StatelessWidget {
  const RoomScreen({
    super.key,
    this.isHost = false,
  });

  final bool isHost;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<RoomProvider>();

    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) return;

        if (isHost) {
          await provider.closeRoom();
        } else {
          await provider.stopDiscovery();
          await provider.leaveRoom();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text("Room Details")),
        body: isHost ? const _RoomDetails() : const _RoomsList(),
      ),
    );
  }
}

class _RoomDetails extends StatelessWidget {
  const _RoomDetails();

  @override
  Widget build(BuildContext context) {
    final players = context.select<RoomProvider, List<Player>>((value) => value.players);

    return Column(
      children: [
        Text.rich(
          TextSpan(
            style: Theme.of(context).textTheme.titleLarge,
            children: [
              const TextSpan(text: "Room ID: "),
              TextSpan(
                text: context.read<RoomProvider>().roomName,
                style: const TextStyle(fontWeight: .bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          title: Text(
            "Players joined",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          trailing: Text.rich(
            TextSpan(
              children: [
                const WidgetSpan(child: Icon(Icons.people), alignment: .middle),
                const WidgetSpan(child: SizedBox(width: 4)),
                TextSpan(text: players.length.toString()),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const .fromLTRB(16, 0, 16, 24),
            itemCount: players.length,
            itemBuilder: (context, index) {
              final player = players.elementAt(index);
              return Card(child: ListTile(title: Text(player.name)));
            },
          ),
        ),
      ],
    );
  }
}

class _RoomsList extends StatelessWidget {
  const _RoomsList();

  @override
  Widget build(BuildContext context) {
    final rooms = context.select<RoomProvider, List<DiscoveredRoom>>((value) => value.rooms);

    if (rooms.isEmpty) {
      return const Center(child: Text("No rooms nearby"));
    }

    return ListView.builder(
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final room = rooms.elementAt(index);

        return ListTile(
          onTap: () => _joinRoom(context, room),
          title: Text(room.name),
          subtitle: Text(room.address),
        );
      },
    );
  }

  Future<void> _joinRoom(BuildContext context, DiscoveredRoom room) async {
    final provider = context.read<RoomProvider>();
    final joined = await provider.joinRoom(room.address, room.port);

    if (!context.mounted) return;

    if (provider.failure != null) {
      context.showSnackBar(SnackBar(content: Text(provider.failure!.message)));
      return;
    }

    if (joined) context.showSnackBar(const SnackBar(content: Text("Joined room")));
  }
}
