import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../exceptions/app_exception.dart';
import '../extensions/context_extensions.dart';
import '../providers/game_provider.dart';
import 'rooms_screen.dart';
import 'share_room.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("digipoly")),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () => _startRoom(context),
              child: const Text("Start room"),
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

  Future<void> _startRoom(BuildContext context) async {
    try {
      await context.read<GameProvider>().openRoom();
      if (context.mounted) context.to(const ShareRoom());
    } on AppException catch (e) {
      if (!context.mounted) return;
      context.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } catch (e) {
      if (!context.mounted) return;
      context.showSnackBar(SnackBar(content: Text("Error: $e")));
      return;
    }
  }

  Future<void> _joinRoom(BuildContext context) async {
    context.to(const RoomsScreen());
  }
}
