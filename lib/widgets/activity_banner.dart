import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum BannerTone { income, expense, neutral }

class ActivityBannerData {
  const ActivityBannerData({
    required this.icon,
    required this.tone,
    required this.title,
    this.meta,
    this.amountText,
  });

  final IconData icon;
  final BannerTone tone;
  final String title;
  final String? meta;
  final String? amountText;
}

/// Shows a rich, self-dismissing notification card catching a player up on
/// something that just happened at the table (a bank collection, rent
/// landing in their account) — reuses [ActivityFeed]/`TransactionTile`'s own
/// visual language (icon, title, meta, colored amount) rather than a plain
/// icon-and-text strip. Inserted into the root [Overlay] so it stays visible
/// no matter what else is open (a sheet, a dialog) — unlike [showSnack],
/// which anchors to the page's own Scaffold. Multiple banners stack, each
/// dismissing on its own timer or on tap.
void showActivityBanner(BuildContext context, ActivityBannerData data) {
  final overlay = Navigator.of(context, rootNavigator: true).overlay;
  if (overlay == null) return;
  _ActivityBannerHost.add(overlay, data);
}

/// One overlay entry, reused for the app's whole lifetime, hosting every
/// banner shown from anywhere in the app.
abstract final class _ActivityBannerHost {
  static OverlayEntry? _entry;
  static final _key = GlobalKey<_ActivityBannerLayerState>();

  static void add(OverlayState overlay, ActivityBannerData data) {
    if (_entry == null) {
      final entry = OverlayEntry(
        builder: (_) => _ActivityBannerLayer(key: _key),
      );
      _entry = entry;
      overlay.insert(entry);
      // The layer isn't attached until the entry's first build — defer the
      // first banner by a frame so `_key.currentState` isn't still null.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _key.currentState?.add(data),
      );
    } else {
      _key.currentState?.add(data);
    }
  }
}

class _Entry {
  _Entry(this.id, this.data);
  final int id;
  final ActivityBannerData data;
}

class _ActivityBannerLayer extends StatefulWidget {
  const _ActivityBannerLayer({super.key});

  @override
  State<_ActivityBannerLayer> createState() => _ActivityBannerLayerState();
}

class _ActivityBannerLayerState extends State<_ActivityBannerLayer> {
  final List<_Entry> _entries = [];
  int _nextId = 0;

  void add(ActivityBannerData data) {
    if (!mounted) return;
    setState(() {
      _entries.insert(0, _Entry(_nextId++, data));
      // A burst of events (several transactions in quick succession) stays
      // readable by capping how many stack at once rather than piling up.
      while (_entries.length > 3) {
        _entries.removeLast();
      }
    });
  }

  void _remove(int id) {
    if (!mounted) return;
    setState(() => _entries.removeWhere((e) => e.id == id));
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: _entries.isEmpty,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in _entries)
                  Padding(
                    key: ValueKey(entry.id),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ActivityBannerCard(
                      data: entry.data,
                      onDismissed: () => _remove(entry.id),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityBannerCard extends StatefulWidget {
  const _ActivityBannerCard({
    required this.data,
    required this.onDismissed,
  });

  final ActivityBannerData data;
  final VoidCallback onDismissed;

  @override
  State<_ActivityBannerCard> createState() => _ActivityBannerCardState();
}

class _ActivityBannerCardState extends State<_ActivityBannerCard>
    with TickerProviderStateMixin {
  static const _displayDuration = Duration(seconds: 7);

  late final _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();
  late final _rail = AnimationController(
    vsync: this,
    duration: _displayDuration,
  )..forward();
  Timer? _timer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_displayDuration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    _timer?.cancel();
    await _enter.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _enter.dispose();
    _rail.dispose();
    super.dispose();
  }

  Color _color() => switch (widget.data.tone) {
    BannerTone.income => AppColors.income,
    BannerTone.expense => AppColors.expense,
    BannerTone.neutral => AppColors.accent,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final data = widget.data;
    final color = _color();

    // Whatever's directly underneath (the balance card's own gradient,
    // most often) can otherwise read as a broken continuation of this card
    // rather than something separate sitting temporarily on top of it — a
    // frosted backdrop blur plus a much stronger drop shadow and a hairline
    // border make the "floating card above the page" relationship obvious
    // at a glance instead of relying on elevation alone.
    return FadeTransition(
      opacity: _enter,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.2),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radius - 4),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Material(
              color: scheme.surface.withValues(alpha: 0.92),
              elevation: 20,
              shadowColor: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppTheme.radius - 4),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radius - 4),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: InkWell(
                  onTap: _dismiss,
                  borderRadius: BorderRadius.circular(AppTheme.radius - 4),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          // A single-line title (no meta) is shorter than
                          // the fixed-height leading icon, so top-aligning
                          // them (right for the two-line case) leaves the
                          // icon visibly sitting below the title's center —
                          // center them instead whenever there's no second
                          // line pulling the text block down to match.
                          crossAxisAlignment: data.meta != null
                              ? CrossAxisAlignment.start
                              : CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(data.icon, color: color, size: 19),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    data.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (data.meta != null)
                                    Text(
                                      data.meta!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (data.amountText != null) ...[
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 96),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    data.amountText!,
                                    maxLines: 1,
                                    style: textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        AnimatedBuilder(
                          animation: _rail,
                          builder: (context, _) => ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: 1 - _rail.value,
                              minHeight: 3,
                              backgroundColor: scheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation(
                                color.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
