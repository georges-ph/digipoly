import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/game_provider.dart';
import '../utils/network_utils.dart';

class ShareRoom extends StatelessWidget {
  const ShareRoom({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) context.read<GameProvider>().closeRoom();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text("Share room")),
        body: FutureBuilder<String?>(
          future: NetworkUtils.instance.getIpAddress(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done || snapshot.data == null || snapshot.data!.isEmpty || !snapshot.hasData) {
              return const SizedBox.shrink();
            }

            final shareMessage = "${context.read<GameProvider>().roomId}:${snapshot.data!}";
            Timer.periodic(const Duration(seconds: 5), (timer) {
              NetworkUtils.instance.broadcast(shareMessage);
            });

            return Center(
              child: Column(
                children: [
                  Text.rich(TextSpan(
                    style: Theme.of(context).textTheme.titleLarge,
                    children: [
                      const TextSpan(text: "Room ID: "),
                      TextSpan(
                        text: context.read<GameProvider>().roomId,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  )),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text("OR"),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const Text("Share using QR code"),
                  QrImageView(
                    data: shareMessage,
                    size: 150,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.person, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(context.watch<GameProvider>().players.length.toString()),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
