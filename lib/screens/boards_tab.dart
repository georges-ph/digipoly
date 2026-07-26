import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/board.dart';
import '../providers/boards_provider.dart';
import '../theme/app_theme.dart';
import '../utils/snack.dart';
import '../widgets/empty_state.dart';
import 'board_editor_screen.dart';

/// Home tab with the device's board templates: create, edit, duplicate.
/// Boards are what get embedded into games (and, later, NFC cards and a
/// community catalog).
class BoardsTab extends StatelessWidget {
  const BoardsTab({super.key});

  Future<void> _openEditor(BuildContext context, {Board? board}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BoardEditorScreen(initial: board)),
    );
  }

  Future<void> _newBoard(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Start from scratch'),
              subtitle: const Text('Empty board, add your own properties'),
              onTap: () => Navigator.pop(sheetContext, 'blank'),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_rounded),
              title: const Text('Paste from clipboard'),
              subtitle: const Text('Import a board someone shared as text'),
              onTap: () => Navigator.pop(sheetContext, 'paste'),
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('Import from file'),
              subtitle: const Text(
                'A .json board file received on WhatsApp, email…',
              ),
              onTap: () => Navigator.pop(sheetContext, 'file'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    Board? board;
    if (choice == 'paste') {
      board = await _boardFromClipboard(context);
      if (board == null) return;
    } else if (choice == 'file') {
      board = await _boardFromFile(context);
      if (board == null) return;
    }
    if (!context.mounted) return;
    await _openEditor(context, board: board);
  }

  /// Imports a board from a JSON file (shared over WhatsApp, email, USB…),
  /// giving it a fresh id so it never collides with the sharer's copy.
  Future<Board?> _boardFromFile(BuildContext context) async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Digipoly board', extensions: ['json']),
        ],
      );
      if (file == null) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      json['id'] = const Uuid().v4();
      return Board.fromJson(json);
    } catch (_) {
      if (context.mounted) {
        showSnack(context, 'That file is not a Digipoly board.');
      }
      return null;
    }
  }

  /// Parses a board JSON from the clipboard, giving it a fresh id so it
  /// never collides with the sharer's copy.
  Future<Board?> _boardFromClipboard(BuildContext context) async {
    void fail() {
      if (context.mounted) {
        showSnack(context, 'The clipboard does not contain a board.');
      }
    }

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) {
        fail();
        return null;
      }
      final json = jsonDecode(text) as Map<String, dynamic>;
      json['id'] = const Uuid().v4();
      return Board.fromJson(json);
    } catch (_) {
      fail();
      return null;
    }
  }

  Future<void> _boardMenu(BuildContext context, Board board) async {
    final boards = context.read<BoardsProvider>();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Duplicate'),
              onTap: () => Navigator.pop(sheetContext, 'duplicate'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('Copy as text'),
              subtitle:
                  const Text('Share it anywhere; others paste it to import'),
              onTap: () => Navigator.pop(sheetContext, 'share'),
            ),
            // Save dialogs only exist on desktop; mobile shares via copy.
            if (!kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.windows ||
                    defaultTargetPlatform == TargetPlatform.linux ||
                    defaultTargetPlatform == TargetPlatform.macOS))
              ListTile(
                leading: const Icon(Icons.save_alt_rounded),
                title: const Text('Save as file'),
                subtitle: const Text('A .json file to send to anyone'),
                onTap: () => Navigator.pop(sheetContext, 'exportFile'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.expense),
              title: const Text(
                'Delete',
                style: TextStyle(color: AppColors.expense),
              ),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted) return;

    switch (action) {
      case 'duplicate':
        final copy = Board.fromJson(board.toJson()..['id'] = const Uuid().v4())
            .copyWith(name: '${board.name} (copy)');
        await boards.saveBoard(copy);
      case 'share':
        await Clipboard.setData(
          ClipboardData(text: jsonEncode(board.toJson())),
        );
        if (context.mounted) {
          showSnack(context, 'Board copied — paste it to a friend');
        }
      case 'exportFile':
        final safeName =
            board.name.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
        final location = await getSaveLocation(
          suggestedName:
              '${safeName.isEmpty ? 'board' : safeName}.digipoly.json',
          acceptedTypeGroups: const [
            XTypeGroup(label: 'Digipoly board', extensions: ['json']),
          ],
        );
        if (location == null) return;
        await File(location.path)
            .writeAsString(jsonEncode(board.toJson()));
        if (context.mounted) {
          showSnack(context, 'Board saved — send the file to anyone');
        }
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Delete "${board.name}"?'),
            content: const Text(
              'Games already created with this board keep working — the '
              'board travels inside the game.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.expense,
                  minimumSize: const Size(0, 44),
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true) await boards.deleteBoard(board.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final boards = context.watch<BoardsProvider>();

    return Column(
      children: [
        Expanded(
          child: boards.boards.isEmpty
              ? EmptyState(
                  icon: Icons.grid_view_rounded,
                  title: 'No boards yet',
                  message:
                      'Describe the physical board in your hands once — '
                      'currency, properties, cards — and reuse it in every '
                      'game.',
                  action: FilledButton.icon(
                    onPressed: () => _newBoard(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create a board'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  itemCount: boards.boards.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final board = boards.boards[index];
                    return _BoardCard(
                      board: board,
                      onTap: () => _openEditor(context, board: board),
                      onLongPress: () => _boardMenu(context, board),
                    );
                  },
                ),
        ),
        if (boards.boards.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton.icon(
                onPressed: () => _newBoard(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New board'),
              ),
            ),
          ),
      ],
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.board,
    required this.onTap,
    required this.onLongPress,
  });

  final Board board;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = AppColors.avatarColor(board.id);
    final cardCount =
        board.chanceCards.length + board.communityChestCards.length;

    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  board.currencySymbol,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      board.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${board.properties.length} properties'
                      '${cardCount > 0 ? ' · $cardCount cards' : ''}',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
