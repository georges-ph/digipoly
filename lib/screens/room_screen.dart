import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/extensions/context_extensions.dart';
import '../models/discovered_room.dart';
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
    return Center(
      child: Text(context.read<RoomProvider>().roomName!),
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
