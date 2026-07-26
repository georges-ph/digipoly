import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/game_provider.dart';
import '../widgets/board_layout_view.dart';
import 'properties_screen.dart';

/// Live view of the board's layout and every player's token — for times
/// the physical board isn't on the table. Only reachable once the board
/// has a curated layout (a GO square defined in the editor).
class BoardViewScreen extends StatelessWidget {
  const BoardViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameProvider>();
    final board = session.game?.board;

    return Scaffold(
      appBar: AppBar(title: const Text('Board')),
      body: board == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.all(16),
              child: BoardLayoutView(
                board: board,
                players: session.players,
                onTapProperty: (property) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PropertiesScreen(openPropertyId: property.id),
                  ),
                ),
              ),
            ),
    );
  }
}
