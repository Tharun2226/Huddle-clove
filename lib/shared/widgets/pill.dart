import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Generic tinted label. Feature code maps its own enums to a colour and hands
/// the result here, so every status/priority badge in the app shares one shape.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.color,
    this.background,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Color color;
  final Color? background;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: (dense ? context.text.labelSmall : context.text.labelMedium)
                ?.copyWith(color: color, height: 1.2),
          ),
        ],
      ),
    );
  }
}

/// Small colour dot for priority — cheaper visually than a full pill when it
/// sits next to a title that already carries the meaning.
class Dot extends StatelessWidget {
  const Dot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// The 3px accent rail down the left edge of a card, used to carry priority or
/// status colour without adding another badge.
class AccentRail extends StatelessWidget {
  const AccentRail({super.key, required this.color, this.height, this.width = 3.5});

  final Color color;
  final double? height;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
    );
  }
}
