import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/board.dart';
import '../models/result.dart';
import '../providers/boards_provider.dart';
import '../providers/game_provider.dart';
import '../services/identity_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import '../utils/snack.dart';
import 'game_screen.dart';

/// Pick a board, name the room, start hosting.
class HostGameScreen extends StatefulWidget {
  const HostGameScreen({super.key});

  @override
  State<HostGameScreen> createState() => _HostGameScreenState();
}

class _HostGameScreenState extends State<HostGameScreen> {
  final _nameController = TextEditingController();

  /// null means the built-in Classic template.
  String? _selectedBoardId;
  bool _starting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    final session = context.read<GameProvider>();
    final identity = context.read<IdentityService>();
    final boards = context.read<BoardsProvider>();

    var gameName = _nameController.text.trim();
    if (gameName.isEmpty) gameName = "${identity.displayName}'s game";

    final Board board;
    if (_selectedBoardId == null) {
      board = Board.classic(const Uuid().v4());
    } else {
      final saved =
          boards.boards.where((b) => b.id == _selectedBoardId).toList();
      if (saved.isEmpty) return;
      board = saved.first;
    }

    setState(() => _starting = true);
    final result = await session.hostGame(board: board, gameName: gameName);
    if (!mounted) return;
    setState(() => _starting = false);

    if (result.isOk) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const GameScreen()),
      );
    } else {
      showSnack(context, result.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final boards = context.watch<BoardsProvider>();
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Host a game')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 32,
            decoration: const InputDecoration(
              labelText: 'Game name',
              hintText: 'Friday game night',
              counterText: '',
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Board',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'The board is embedded into the game — players who join get it '
            'automatically.',
            style:
                textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _BoardChoice(
            title: 'Classic',
            subtitle: '28 properties · \$ · built-in',
            symbol: r'$',
            color: AppColors.accent,
            selected: _selectedBoardId == null,
            badge: 'Built-in',
            onTap: () => setState(() => _selectedBoardId = null),
          ),
          for (final board in boards.boards) ...[
            const SizedBox(height: 10),
            _BoardChoice(
              title: board.name,
              subtitle: '${board.properties.length} properties · '
                  '${board.currencySymbol} · start '
                  '${formatMoney(board.startingBalance, board.currencySymbol)}',
              symbol: board.currencySymbol,
              color: AppColors.avatarColor(board.id),
              selected: _selectedBoardId == board.id,
              onTap: () => setState(() => _selectedBoardId = board.id),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton.icon(
            onPressed: _starting ? null : _start,
            icon: _starting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_starting ? 'Starting room…' : 'Start room'),
          ),
        ),
      ),
    );
  }
}

class _BoardChoice extends StatelessWidget {
  const _BoardChoice({
    required this.title,
    required this.subtitle,
    required this.symbol,
    required this.color,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final String symbol;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: selected ? AppColors.accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  symbol,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              badge!,
                              style: textTheme.labelSmall?.copyWith(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.accent : scheme.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
