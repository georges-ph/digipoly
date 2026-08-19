import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/board.dart';
import '../models/property.dart';
import '../providers/boards_provider.dart';
import '../theme/app_theme.dart';
import '../utils/formatting.dart';
import '../utils/snack.dart';
import '../widgets/ring_board.dart';
import '../widgets/section_header.dart';

/// Create or edit a board template: money rules, properties, chance and
/// community chest cards.
class BoardEditorScreen extends StatefulWidget {
  const BoardEditorScreen({super.key, this.initial});

  final Board? initial;

  @override
  State<BoardEditorScreen> createState() => _BoardEditorScreenState();
}

class _BoardEditorScreenState extends State<BoardEditorScreen> {
  late final Board _base =
      widget.initial ??
      Board(
        id: const Uuid().v4(),
        name: '',
        currencySymbol: r'$',
        startingBalance: 1500,
        salary: 200,
      );

  late final _nameController = TextEditingController(text: _base.name);
  late final _currencyController = TextEditingController(
    text: _base.currencySymbol,
  );
  late final _startingController = TextEditingController(
    text: '${_base.startingBalance}',
  );
  late final _salaryController = TextEditingController(text: '${_base.salary}');
  late final _jailFineController = TextEditingController(
    text: '${_base.jailFine}',
  );

  late final List<Property> _properties = List.of(_base.properties);
  late final List<BoardCard> _chanceCards = List.of(_base.chanceCards);
  late final List<BoardCard> _communityCards = List.of(
    _base.communityChestCards,
  );

  bool _boardView = true;

  @override
  void dispose() {
    _nameController.dispose();
    _currencyController.dispose();
    _startingController.dispose();
    _salaryController.dispose();
    _jailFineController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Give the board a name first.');
      return;
    }

    final board = _base.copyWith(
      name: name,
      currencySymbol: _currencyController.text.trim().isEmpty
          ? r'$'
          : _currencyController.text.trim(),
      startingBalance: int.tryParse(_startingController.text.trim()) ?? 1500,
      salary: int.tryParse(_salaryController.text.trim()) ?? 200,
      jailFine: int.tryParse(_jailFineController.text.trim()) ?? 50,
      properties: _properties,
      chanceCards: _chanceCards,
      communityChestCards: _communityCards,
    );

    await context.read<BoardsProvider>().saveBoard(board);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _editProperty([Property? existing]) async {
    final result = await showModalBottomSheet<(Property?, bool)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PropertySheet(initial: existing),
    );
    if (result == null) return;

    setState(() {
      final (property, deleted) = result;
      if (deleted && existing != null) {
        _properties.removeWhere((p) => p.id == existing.id);
      } else if (property != null) {
        final index = _properties.indexWhere((p) => p.id == property.id);
        if (index >= 0) {
          _properties[index] = property;
        } else {
          _properties.add(property);
        }
      }
    });
  }

  Future<void> _editCard(List<BoardCard> deck, [BoardCard? existing]) async {
    final result = await showModalBottomSheet<(BoardCard?, bool)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CardSheet(initial: existing, properties: _properties),
    );
    if (result == null) return;

    setState(() {
      final (card, deleted) = result;
      if (deleted && existing != null) {
        deck.removeWhere((c) => c.id == existing.id);
      } else if (card != null) {
        final index = deck.indexWhere((c) => c.id == card.id);
        if (index >= 0) {
          deck[index] = card;
        } else {
          deck.add(card);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final symbol = _currencyController.text.trim().isEmpty
        ? r'$'
        : _currencyController.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'New board' : 'Edit board'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(width: 8),
        ],
      ),
      // A CustomScrollView with the properties as a SliverReorderableList
      // (rather than a shrink-wrapped, non-scrolling ReorderableListView)
      // lets dragging near the top/bottom edge auto-scroll the real page —
      // otherwise reordering across a long list needs drag/scroll/drag/scroll.
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 32,
                  decoration: const InputDecoration(
                    labelText: 'Board name',
                    hintText: 'e.g. Monopoly Beirut Edition',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _currencyController,
                        maxLength: 4,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                          hintText: r'$',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _startingController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Starting balance',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _salaryController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'GO salary',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _jailFineController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Jail fine',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SectionHeader(
                  title: 'Properties (${_properties.length})',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_properties.isNotEmpty)
                        IconButton(
                          tooltip: _boardView
                              ? 'Switch to list view'
                              : 'Switch to board view',
                          onPressed: () =>
                              setState(() => _boardView = !_boardView),
                          icon: Icon(
                            _boardView
                                ? Icons.view_list_rounded
                                : Icons.grid_view_rounded,
                          ),
                        ),
                      TextButton.icon(
                        onPressed: () => _editProperty(),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                ),
                if (_properties.isNotEmpty)
                  Text(
                    _boardView
                        ? 'This is your board\'s physical layout — long-press '
                              'and drag a square to match the real board '
                              '(needed for the board view and auto jail/tax/GO).'
                        : 'This order is your board\'s layout — drag to '
                              'match the physical board (needed for the board '
                              'view and auto jail/tax/GO).',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (_properties.isEmpty)
                  Text(
                    'No properties yet.',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (_properties.isNotEmpty && _boardView) ...[
                  const SizedBox(height: 12),
                  _BoardRingEditor(
                    properties: _properties,
                    symbol: symbol,
                    onTapProperty: _editProperty,
                    onAdd: () => _editProperty(),
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        final moved = _properties.removeAt(oldIndex);
                        _properties.insert(newIndex, moved);
                      });
                    },
                  ),
                ],
              ]),
            ),
          ),
          if (_properties.isNotEmpty && !_boardView)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverReorderableList(
                itemCount: _properties.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final moved = _properties.removeAt(oldIndex);
                    _properties.insert(newIndex, moved);
                  });
                },
                // SliverReorderableList (unlike ReorderableListView) doesn't
                // wrap the dragged item in a Material by default, so a
                // ListTile mid-drag loses its Material ancestor.
                proxyDecorator: (child, index, animation) => Material(
                  elevation: 4,
                  color: Colors.transparent,
                  child: child,
                ),
                itemBuilder: (context, i) => ListTile(
                  key: ValueKey(_properties[i].id),
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _editProperty(_properties[i]),
                  leading: Container(
                    width: 14,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(_properties[i].colorValue),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  title: Text(
                    _properties[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${_kindLabel(_properties[i].kind)}'
                    '${_properties[i].kind.isOwnable ? ' · ${formatMoney(_properties[i].price, symbol)}' : ''}',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                SectionHeader(
                  title: 'Chance cards (${_chanceCards.length})',
                  trailing: TextButton.icon(
                    onPressed: () => _editCard(_chanceCards),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Add'),
                  ),
                ),
                _CardList(
                  cards: _chanceCards,
                  symbol: symbol,
                  properties: _properties,
                  onTap: (card) => _editCard(_chanceCards, card),
                ),
                const SizedBox(height: 16),
                SectionHeader(
                  title: 'Community chest (${_communityCards.length})',
                  trailing: TextButton.icon(
                    onPressed: () => _editCard(_communityCards),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Add'),
                  ),
                ),
                _CardList(
                  cards: _communityCards,
                  symbol: symbol,
                  properties: _properties,
                  onTap: (card) => _editCard(_communityCards, card),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Board ring editor — properties arranged as a physical ring around a
// square grid, matching the real board, instead of a linear list.
// ---------------------------------------------------------------------------

class _BoardRingEditor extends StatelessWidget {
  const _BoardRingEditor({
    required this.properties,
    required this.symbol,
    required this.onTapProperty,
    required this.onAdd,
    required this.onReorder,
  });

  final List<Property> properties;
  final String symbol;
  final void Function(Property property) onTapProperty;
  final VoidCallback onAdd;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    return RingBoard(
      squareCount: properties.length,
      cellBuilder: (context, i, cellSize) {
        if (i >= properties.length) {
          return _EmptyRingSlot(onTap: onAdd);
        }
        return _RingTile(
          property: properties[i],
          index: i,
          cellSize: cellSize,
          onTap: () => onTapProperty(properties[i]),
          onReorder: onReorder,
        );
      },
    );
  }
}

class _RingTile extends StatelessWidget {
  const _RingTile({
    required this.property,
    required this.index,
    required this.cellSize,
    required this.onTap,
    required this.onReorder,
  });

  final Property property;
  final int index;
  final Size cellSize;
  final VoidCallback onTap;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    final tile = _RingTileVisual(property: property, cellSize: cellSize);

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => onReorder(details.data, index),
      builder: (context, candidateData, rejectedData) {
        return LongPressDraggable<int>(
          data: index,
          feedback: Material(
            color: Colors.transparent,
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox.fromSize(size: cellSize, child: tile),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: tile),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: candidateData.isNotEmpty
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    child: tile,
                  )
                : tile,
          ),
        );
      },
    );
  }
}

class _RingTileVisual extends StatelessWidget {
  const _RingTileVisual({required this.property, required this.cellSize});

  final Property property;
  final Size cellSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bandColor = property.kind.isOwnable
        ? Color(property.colorValue)
        : scheme.outline;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 6, color: bandColor),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: cellSize.width - 10,
                  child: Text(
                    property.name,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRingSlot extends StatelessWidget {
  const _EmptyRingSlot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Icon(
          Icons.add_rounded,
          size: 16,
          color: scheme.outlineVariant,
        ),
      ),
    );
  }
}

class _CardList extends StatelessWidget {
  const _CardList({
    required this.cards,
    required this.symbol,
    required this.properties,
    required this.onTap,
  });

  final List<BoardCard> cards;
  final String symbol;
  final List<Property> properties;
  final void Function(BoardCard card) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (cards.isEmpty) {
      return Text(
        'No cards yet.',
        style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      );
    }

    String? moveTargetName(BoardCard card) {
      final targetId = card.moveToPropertyId;
      if (targetId == null) return null;
      for (final property in properties) {
        if (property.id == targetId) return property.name;
      }
      return 'a removed square';
    }

    String? moveBySubtitle(BoardCard card) {
      final spaces = card.moveBySpaces;
      if (spaces == null) return null;
      return spaces < 0 ? 'Back ${-spaces} spaces' : 'Forward $spaces spaces';
    }

    String? subtitleFor(BoardCard card) {
      if (card.grantsJailCard) return 'Get out of jail free';
      if (card.isBuildingRepairs) {
        return '${card.perHouseCharge ?? 0}/house, '
            '${card.perHotelCharge ?? 0}/hotel';
      }
      final target = moveTargetName(card);
      if (target != null) return 'Moves to $target';
      return moveBySubtitle(card);
    }

    return Column(
      children: [
        for (final card in cards)
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () => onTap(card),
            leading: Icon(
              Icons.style_rounded,
              color: scheme.onSurfaceVariant,
            ),
            title: Text(
              card.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium,
            ),
            subtitle: subtitleFor(card) == null
                ? null
                : Text(
                    subtitleFor(card)!,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
            trailing: card.amount == 0
                ? null
                : Text(
                    formatSignedMoney(
                      card.amount,
                      symbol,
                      incoming: card.amount > 0,
                    ),
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: card.amount > 0
                          ? AppColors.income
                          : AppColors.expense,
                    ),
                  ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Property editing sheet
// ---------------------------------------------------------------------------

String _kindLabel(PropertyKind kind) => switch (kind) {
  PropertyKind.street => 'Street',
  PropertyKind.railroad => 'Railroad',
  PropertyKind.utility => 'Utility',
  PropertyKind.go => 'GO',
  PropertyKind.jail => 'Jail',
  PropertyKind.freeParking => 'Free Parking',
  PropertyKind.goToJail => 'Go To Jail',
  PropertyKind.tax => 'Tax',
  PropertyKind.chance => 'Chance',
  PropertyKind.communityChest => 'Community Chest',
};

const _groupColors = [
  0xFF8B4513, // brown
  0xFF87CEEB, // light blue
  0xFFD81E75, // pink
  0xFFF57C00, // orange
  0xFFD32F2F, // red
  0xFFFBC02D, // yellow
  0xFF2E7D32, // green
  0xFF1A47B8, // dark blue
  0xFF37474F, // slate (railroads)
  0xFF78909C, // gray (utilities)
  0xFF00897B, // teal
  0xFF6D4CBF, // purple
];

class _PropertySheet extends StatefulWidget {
  const _PropertySheet({this.initial});

  final Property? initial;

  @override
  State<_PropertySheet> createState() => _PropertySheetState();
}

class _PropertySheetState extends State<_PropertySheet> {
  late final _nameController = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final _priceController = TextEditingController(
    text: _initialInt(widget.initial?.price),
  );
  late final _houseController = TextEditingController(
    text: _initialInt(widget.initial?.housePrice),
  );
  late final _mortgageController = TextEditingController(
    text: _initialInt(widget.initial?.mortgageValue),
  );

  late PropertyKind _kind = widget.initial?.kind ?? PropertyKind.street;
  late int _color = widget.initial?.colorValue ?? _groupColors.first;

  /// Six controllers; how many are shown depends on the kind.
  late final List<TextEditingController> _rentControllers = List.generate(
    6,
    (i) => TextEditingController(
      text: _initialInt(
        (widget.initial?.rentTiers.length ?? 0) > i
            ? widget.initial!.rentTiers[i]
            : null,
      ),
    ),
  );

  static String _initialInt(int? value) =>
      value == null || value == 0 ? '' : '$value';

  List<String> get _rentLabels => switch (_kind) {
    PropertyKind.street => const [
      'Rent',
      '1 house',
      '2 houses',
      '3 houses',
      '4 houses',
      'Hotel',
    ],
    PropertyKind.railroad => const [
      'Own 1',
      'Own 2',
      'Own 3',
      'Own 4',
    ],
    PropertyKind.utility => const ['×1 owned', '×2 owned'],
    PropertyKind.go ||
    PropertyKind.jail ||
    PropertyKind.freeParking ||
    PropertyKind.goToJail ||
    PropertyKind.tax ||
    PropertyKind.chance ||
    PropertyKind.communityChest => const [],
  };

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _houseController.dispose();
    _mortgageController.dispose();
    for (final controller in _rentControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final labels = _rentLabels;
    final property = Property(
      id: widget.initial?.id ?? const Uuid().v4(),
      name: name,
      kind: _kind,
      colorValue: _color,
      price: int.tryParse(_priceController.text.trim()) ?? 0,
      rentTiers: [
        for (var i = 0; i < labels.length; i++)
          int.tryParse(_rentControllers[i].text.trim()) ?? 0,
      ],
      housePrice: _kind == PropertyKind.street
          ? int.tryParse(_houseController.text.trim()) ?? 0
          : 0,
      mortgageValue: int.tryParse(_mortgageController.text.trim()) ?? 0,
    );
    Navigator.of(context).pop((property, false));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final labels = _rentLabels;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.initial == null ? 'New property' : 'Edit property',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (widget.initial != null)
                  IconButton(
                    onPressed: () => Navigator.of(context).pop((null, true)),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.expense,
                    ),
                    tooltip: 'Delete',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PropertyKind>(
              initialValue: _kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Kind'),
              items: [
                for (final kind in PropertyKind.values)
                  DropdownMenuItem(value: kind, child: Text(_kindLabel(kind))),
              ],
              onChanged: (kind) {
                if (kind != null) setState(() => _kind = kind);
              },
            ),
            const SizedBox(height: 16),
            if (_kind.isOwnable) ...[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final color in _groupColors)
                    GestureDetector(
                      onTap: () => setState(() => _color = color),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Color(color),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == color
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: _color == color
                            ? const Icon(
                                Icons.check,
                                size: 18,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // A Wrap (not a fixed Row) so these reflow onto their own line
              // instead of squeezing to nothing on a narrow window — the
              // same approach already used for the rent fields below.
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(labelText: 'Price'),
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _mortgageController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(labelText: 'Mortgage'),
                    ),
                  ),
                  if (_kind == PropertyKind.street)
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: _houseController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'House cost',
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _kind == PropertyKind.utility
                    ? 'Rent multipliers (rent = dice × multiplier)'
                    : 'Rents',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < labels.length; i++)
                    SizedBox(
                      width: 104,
                      child: TextField(
                        controller: _rentControllers[i],
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(labelText: labels[i]),
                      ),
                    ),
                ],
              ),
            ] else if (_kind == PropertyKind.tax)
              TextField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Tax amount'),
              ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Save property')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card editing sheet
// ---------------------------------------------------------------------------

enum _CardEffect { money, move, moveBy, jailCard, buildingRepairs }

String _cardEffectLabel(_CardEffect effect) => switch (effect) {
  _CardEffect.money => 'Money',
  _CardEffect.move => 'Move to property',
  _CardEffect.moveBy => 'Move by spaces',
  _CardEffect.jailCard => 'Get out of jail free',
  _CardEffect.buildingRepairs => 'Building repairs',
};

class _CardSheet extends StatefulWidget {
  const _CardSheet({this.initial, required this.properties});

  final BoardCard? initial;

  /// Board squares a "move to" card can target.
  final List<Property> properties;

  @override
  State<_CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<_CardSheet> {
  late final _textController = TextEditingController(
    text: widget.initial?.text ?? '',
  );
  late final _amountController = TextEditingController(
    text: widget.initial == null || widget.initial!.amount == 0
        ? ''
        : '${widget.initial!.amount.abs()}',
  );
  late final _spacesController = TextEditingController(
    text: widget.initial?.moveBySpaces == null
        ? ''
        : '${widget.initial!.moveBySpaces!.abs()}',
  );
  late final _perHouseController = TextEditingController(
    text: '${widget.initial?.perHouseCharge ?? 0}',
  );
  late final _perHotelController = TextEditingController(
    text: '${widget.initial?.perHotelCharge ?? 0}',
  );
  late bool _playerReceives = (widget.initial?.amount ?? 0) >= 0;
  late bool _movesForward = (widget.initial?.moveBySpaces ?? -1) >= 0;
  late _CardEffect _effect = widget.initial?.moveToPropertyId != null
      ? _CardEffect.move
      : widget.initial?.moveBySpaces != null
      ? _CardEffect.moveBy
      : widget.initial?.grantsJailCard == true
      ? _CardEffect.jailCard
      : widget.initial?.isBuildingRepairs == true
      ? _CardEffect.buildingRepairs
      : _CardEffect.money;
  late String? _moveTargetId = widget.initial?.moveToPropertyId;

  @override
  void dispose() {
    _textController.dispose();
    _amountController.dispose();
    _spacesController.dispose();
    _perHouseController.dispose();
    _perHotelController.dispose();
    super.dispose();
  }

  void _save() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (_effect == _CardEffect.move) {
      final targetId = _moveTargetId;
      if (targetId == null) return;
      Navigator.of(context).pop((
        BoardCard(
          id: widget.initial?.id ?? const Uuid().v4(),
          text: text,
          moveToPropertyId: targetId,
        ),
        false,
      ));
      return;
    }

    if (_effect == _CardEffect.moveBy) {
      final spaces = int.tryParse(_spacesController.text.trim()) ?? 0;
      if (spaces == 0) return;
      Navigator.of(context).pop((
        BoardCard(
          id: widget.initial?.id ?? const Uuid().v4(),
          text: text,
          moveBySpaces: _movesForward ? spaces : -spaces,
        ),
        false,
      ));
      return;
    }

    if (_effect == _CardEffect.jailCard) {
      Navigator.of(context).pop((
        BoardCard(
          id: widget.initial?.id ?? const Uuid().v4(),
          text: text,
          grantsJailCard: true,
        ),
        false,
      ));
      return;
    }

    if (_effect == _CardEffect.buildingRepairs) {
      Navigator.of(context).pop((
        BoardCard(
          id: widget.initial?.id ?? const Uuid().v4(),
          text: text,
          perHouseCharge: int.tryParse(_perHouseController.text.trim()) ?? 0,
          perHotelCharge: int.tryParse(_perHotelController.text.trim()) ?? 0,
        ),
        false,
      ));
      return;
    }

    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    final card = BoardCard(
      id: widget.initial?.id ?? const Uuid().v4(),
      text: text,
      amount: _playerReceives ? amount : -amount,
    );
    Navigator.of(context).pop((card, false));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // A short window (resized small, or split-screen) can't always fit this
    // whole sheet — SafeArea + a scroll view let it shrink and scroll
    // instead of overflowing vertically off the bottom.
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.initial == null ? 'New card' : 'Edit card',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (widget.initial != null)
                  IconButton(
                    onPressed: () => Navigator.of(context).pop((null, true)),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.expense,
                    ),
                    tooltip: 'Delete',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Card text',
                hintText: 'Bank error in your favor',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final effect in _CardEffect.values)
                  ChoiceChip(
                    label: Text(_cardEffectLabel(effect)),
                    selected: _effect == effect,
                    onSelected: (_) => setState(() => _effect = effect),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_effect == _CardEffect.money)
              // Stacked, not a Row: on a narrow window there isn't enough
              // width left for both segments' text once a fixed-width amount
              // field sits next to it — this always has the full sheet width
              // to itself instead.
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Receives')),
                      ButtonSegment(value: false, label: Text('Pays')),
                    ],
                    selected: {_playerReceives},
                    onSelectionChanged: (selection) =>
                        setState(() => _playerReceives = selection.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                ],
              )
            else if (_effect == _CardEffect.move)
              if (widget.properties.isEmpty)
                Text(
                  'Add some properties to the board first.',
                  style: textTheme.bodySmall,
                )
              else
                DropdownButtonFormField<String>(
                  initialValue:
                      widget.properties.any((p) => p.id == _moveTargetId)
                      ? _moveTargetId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Destination'),
                  items: [
                    for (final property in widget.properties)
                      DropdownMenuItem(
                        value: property.id,
                        child: Text(property.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _moveTargetId = value),
                )
            else if (_effect == _CardEffect.moveBy)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Back')),
                      ButtonSegment(value: true, label: Text('Forward')),
                    ],
                    selected: {_movesForward},
                    onSelectionChanged: (selection) =>
                        setState(() => _movesForward = selection.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _spacesController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Spaces'),
                  ),
                ],
              )
            else if (_effect == _CardEffect.jailCard)
              Text(
                'The drawer keeps this card until they use it to leave jail '
                'for free — no fine, no roll.',
                style: textTheme.bodySmall,
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _perHouseController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Per house'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _perHotelController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Per hotel'),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Save card')),
          ],
        ),
      ),
    );
  }
}
