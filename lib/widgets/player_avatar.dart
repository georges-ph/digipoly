import 'package:flutter/material.dart';

import '../models/player.dart';
import '../theme/app_theme.dart';

/// Initials avatar with a color derived from the player's seat, so every
/// device shows the same color for the same player and no two players at
/// the table share a color. Shows an online dot and fades players who left.
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
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.avatarColorForSeat(player.seat);
    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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

    // The presence dot is positioned against the plain avatar circle, not
    // the ring — it must sit on the avatar's own edge regardless of
    // whether the ring is drawn this frame.
    if (showPresence && !player.hasLeft) {
      avatar = Stack(
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

    // Always reserved, never just added/removed: whichever player's turn
    // it is would otherwise render a few pixels larger than everyone else
    // (the ring's own padding + border), pushing its avatar — and whatever
    // sits below it in a Column, like the name/balance in the players row —
    // out of line with the rest of the table. Toggling the border's color
    // instead of its presence keeps every avatar the same footprint.
    // A gap between the avatar and the ring (rather than flush against its
    // edge) keeps the ring visible even when a player's seat color happens
    // to match the accent color (seat 0's palette color *is*
    // AppColors.accent) — same color on same color has no visible edge.
    avatar = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: highlight ? AppColors.accent : Colors.transparent,
          width: 3,
        ),
      ),
      child: avatar,
    );

    return Opacity(opacity: player.hasLeft ? 0.4 : 1, child: avatar);
  }
}
