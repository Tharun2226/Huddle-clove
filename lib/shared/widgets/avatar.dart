import 'package:flutter/material.dart';

import '../../core/auth/domain/app_user.dart';
import '../theme/app_tokens.dart';

/// Initials avatar with a stable per-person colour. No network images — the
/// team is small enough that initials read faster than photos anyway.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.size = 40,
    this.showRing = false,
    this.ringColor,
    this.ringWidth = 2,
  });

  final AppUser user;
  final double size;

  /// Ring marks "this is you" in lists of other people.
  final bool showRing;

  /// Optional ring for stacked avatars (drawn inside [size], not outside).
  final Color? ringColor;
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = palette.avatarFor(user.id);
    final border = showRing
        ? Border.all(color: color, width: ringWidth)
        : ringColor != null
            ? Border.all(color: ringColor!, width: ringWidth)
            : null;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: border,
      ),
      alignment: Alignment.center,
      child: Text(
        user.initials,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
          letterSpacing: 0,
          height: 1,
        ),
      ),
    );
  }
}

/// Overlapping avatars for meeting attendees, with a "+N" overflow bubble.
class AvatarStack extends StatelessWidget {
  const AvatarStack({
    super.key,
    required this.users,
    this.size = 28,
    this.max = 3,
    this.borderColor,
  });

  final List<AppUser> users;
  final double size;
  final int max;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ring = borderColor ?? palette.card;
    final shown = users.take(max).toList();
    final overflow = users.length - shown.length;
    final overlap = size * 0.32;

    return SizedBox(
      height: size,
      width: shown.isEmpty
          ? 0
          : size + (shown.length - 1 + (overflow > 0 ? 1 : 0)) * (size - overlap),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: UserAvatar(
                user: shown[i],
                size: size,
                ringColor: ring,
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: shown.length * (size - overlap),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.neutralContainer,
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 2),
                ),
                child: Text(
                  '+$overflow',
                  style: TextStyle(
                    fontSize: size * 0.3,
                    fontWeight: FontWeight.w700,
                    color: palette.neutral,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
