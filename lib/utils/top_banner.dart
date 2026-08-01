import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A brief, self-dismissing banner pinned to the top of the screen.
///
/// Unlike [showSnack] (which anchors to the page's own Scaffold and ends up
/// hidden behind anything pushed on top of it — a modal sheet, a dialog),
/// this is inserted straight into the root [Overlay], so it stays visible
/// no matter what else is open. Meant for ambient, low-friction notices
/// (someone else did something at the table) rather than direct feedback
/// on an action the viewer themselves just took — that's still [showSnack].
void showTopBanner(
  BuildContext context,
  String message, {
  IconData icon = Icons.info_outline_rounded,
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Navigator.of(context, rootNavigator: true).overlay;
  if (overlay == null) return;

  final entry = _TopBannerEntry();
  Timer? timer;

  void dismiss() {
    timer?.cancel();
    entry.dismiss();
  }

  entry.overlayEntry = OverlayEntry(
    builder: (context) => _TopBanner(
      message: message,
      icon: icon,
      onDismissed: entry.remove,
      onTap: dismiss,
    ),
  );

  overlay.insert(entry.overlayEntry);
  timer = Timer(duration, dismiss);
}

/// Bundles the [OverlayEntry] with a [GlobalKey] onto its animated state so
/// a tap (or the timer) can trigger the same out-animation before removal,
/// instead of yanking the banner off screen instantly either way.
class _TopBannerEntry {
  late final OverlayEntry overlayEntry;
  final _key = GlobalKey<_TopBannerState>();

  void dismiss() => _key.currentState?.dismiss();

  void remove() {
    if (overlayEntry.mounted) overlayEntry.remove();
  }
}

class _TopBanner extends StatefulWidget {
  const _TopBanner({
    required this.message,
    required this.icon,
    required this.onDismissed,
    required this.onTap,
  });

  final String message;
  final IconData icon;
  final VoidCallback onDismissed;
  final VoidCallback onTap;

  @override
  State<_TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<_TopBanner>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final _offset = Tween<Offset>(
    begin: const Offset(0, -1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  Future<void> dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: SlideTransition(
          position: _offset,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              color: scheme.inverseSurface,
              elevation: 6,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              child: InkWell(
                onTap: () {
                  widget.onTap();
                },
                borderRadius: BorderRadius.circular(AppTheme.radius),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(widget.icon, color: scheme.onInverseSurface, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onInverseSurface,
                            fontWeight: FontWeight.w600,
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
    );
  }
}
