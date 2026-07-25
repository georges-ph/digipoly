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
  late final Board _base = widget.initial ??
      Board(
        id: const Uuid().v4(),
        name: '',
        currencySymbol: r'$',
        startingBalance: 1500,
        salary: 200,
      );

  late final _nameController = TextEditingController(text: _base.name);
  late final _currencyController =
      TextEditingController(text: _base.currencySymbol);
  late final _startingController =
      TextEditingController(text: '${_base.startingBalance}');
  late final _salaryController = TextEditingController(text: '${_base.salary}');

  late final List<Property> _properties = List.of(_base.properties);
  late final List<BoardCard> _chanceCards = List.of(_base.chanceCards);
  late final List<BoardCard> _communityCards =
      List.of(_base.communityChestCards);

  @override
  void dispose() {
    _nameController.dispose();
    _currencyController.dispose();
    _startingController.dispose();
    _salaryController.dispose();
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
      startingBalance:
          int.tryParse(_startingController.text.trim()) ?? 1500,
      salary: int.tryParse(_salaryController.text.trim()) ?? 200,
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
      builder: (_) => _CardSheet(initial: existing),
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
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
              SizedBox(
                width: 110,
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
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Starting balance',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _salaryController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'GO salary',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SectionHeader(
            title: 'Properties (${_properties.length})',
            trailing: TextButton.icon(
              onPressed: () => _editProperty(),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add'),
            ),
          ),
          if (_properties.isEmpty)
            Text(
              'No properties yet.',
              style:
                  textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            for (final property in _properties)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => _editProperty(property),
                leading: Container(
                  width: 14,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(property.colorValue),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                title: Text(
                  property.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${property.kind.name} · ${formatMoney(property.price, symbol)}',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
          const SizedBox(height: 16),
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
            onTap: (card) => _editCard(_communityCards, card),
          ),
        ],
      ),
    );
  }
}

class _CardList extends StatelessWidget {
  const _CardList({
    required this.cards,
    required this.symbol,
    required this.onTap,
  });

  final List<BoardCard> cards;
  final String symbol;
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
  late final _nameController =
      TextEditingController(text: widget.initial?.name ?? '');
  late final _priceController =
      TextEditingController(text: _initialInt(widget.initial?.price));
  late final _houseController =
      TextEditingController(text: _initialInt(widget.initial?.housePrice));
  late final _mortgageController =
      TextEditingController(text: _initialInt(widget.initial?.mortgageValue));

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
                    style: textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (widget.initial != null)
                  IconButton(
                    onPressed: () =>
                        Navigator.of(context).pop((null, true)),
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
            SegmentedButton<PropertyKind>(
              segments: const [
                ButtonSegment(
                  value: PropertyKind.street,
                  label: Text('Street'),
                ),
                ButtonSegment(
                  value: PropertyKind.railroad,
                  label: Text('Railroad'),
                ),
                ButtonSegment(
                  value: PropertyKind.utility,
                  label: Text('Utility'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (selection) =>
                  setState(() => _kind = selection.first),
            ),
            const SizedBox(height: 16),
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Price'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _mortgageController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Mortgage'),
                  ),
                ),
                if (_kind == PropertyKind.street) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _houseController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration:
                          const InputDecoration(labelText: 'House cost'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _kind == PropertyKind.utility
                  ? 'Rent multipliers (rent = dice × multiplier)'
                  : 'Rents',
              style:
                  textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
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

class _CardSheet extends StatefulWidget {
  const _CardSheet({this.initial});

  final BoardCard? initial;

  @override
  State<_CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<_CardSheet> {
  late final _textController =
      TextEditingController(text: widget.initial?.text ?? '');
  late final _amountController = TextEditingController(
    text: widget.initial == null || widget.initial!.amount == 0
        ? ''
        : '${widget.initial!.amount.abs()}',
  );
  late bool _playerReceives = (widget.initial?.amount ?? 0) >= 0;

  @override
  void dispose() {
    _textController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _save() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

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

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
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
                  style: textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
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
          Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Receives')),
                    ButtonSegment(value: false, label: Text('Pays')),
                  ],
                  selected: {_playerReceives},
                  onSelectionChanged: (selection) =>
                      setState(() => _playerReceives = selection.first),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Save card')),
        ],
      ),
    );
  }
}
