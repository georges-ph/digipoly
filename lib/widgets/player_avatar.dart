import 'package:flutter/material.dart';

import '../models/player.dart';
import '../theme/app_theme.dart';

/// Initials avatar with a color derived from the player id, so every device
/// shows the same color for the same player. Shows an online dot and fades
/// players who left.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.player,
    this.size = 48,
    this.showPresence = true,
    this.highlight = false,
  });

  final Player player;
  final double size;
  final bool showPresence;

  /// Draws an accent ring — used to mark whose turn it is.
  final bool highlight;

  static String initialsOf(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.avatarColor(player.id);
    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: highlight
            ? Border.all(color: AppColors.accent, width: 2.5)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        initialsOf(player.name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
        ),
      ),
    );

    Widget child = avatar;
    if (showPresence && !player.hasLeft) {
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: player.isOnline
                    ? AppColors.income
                    : Theme.of(context).colorScheme.outlineVariant,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Opacity(opacity: player.hasLeft ? 0.4 : 1, child: child);
  }
}
