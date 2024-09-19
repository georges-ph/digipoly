import 'package:client_server_sockets/client_server_sockets.dart';
import 'package:flutter/material.dart';

import '../models/player.dart';
import '../models/players.dart';

class PlayersList extends StatelessWidget {
  const PlayersList({
    super.key,
    required this.players,
    required this.onBankPay,
    required this.onBankCollect,
    required this.onPlayerSend,
  });

  final Players players;
  final void Function(int amount) onBankPay;
  final void Function(int amount) onBankCollect;
  final void Function(int amount, Player player) onPlayerSend;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: players.players.length,
      itemBuilder: (context, index) {
        final controller = TextEditingController();
        final player = players.players.elementAt(index);
        final isBank = player.name == "Bank";

        if (player.port == Client.instance.port || player.port == Server.instance.port) {
          return const SizedBox.shrink();
        }

        return Card(
          child: ExpansionTile(
            title: Text(isBank ? player.name : "${player.name} - ${player.port}"),
            subtitle: isBank ? null : Text("Balance: ${player.balance}"),
            children: player.port == Client.instance.port || player.port == Server.instance.port
                ? []
                : [
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: "Enter amount",
                      ),
                    ),
                    !isBank
                        ? SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                if (controller.text.isEmpty) return;
                                final amount = int.tryParse(controller.text);
                                if (amount == null) return;
                                onPlayerSend(amount, player);
                              },
                              icon: const Icon(Icons.send),
                              label: const Text("Send"),
                            ),
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    if (controller.text.isEmpty) return;
                                    final amount = int.tryParse(controller.text);
                                    if (amount == null) return;
                                    onBankPay(amount);
                                  },
                                  icon: const Icon(Icons.file_upload),
                                  label: const Text("Pay"),
                                ),
                              ),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    if (controller.text.isEmpty) return;
                                    final amount = int.tryParse(controller.text);
                                    if (amount == null) return;
                                    onBankCollect(amount);
                                  },
                                  icon: const Icon(Icons.file_download),
                                  label: const Text("Collect"),
                                ),
                              ),
                            ],
                          ),
                  ],
          ),
        );
      },
    );
  }
}
