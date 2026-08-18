import 'package:flutter/material.dart';

import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/widgets/huddle_card.dart';

/// Compact metric tile for the Today header row. The number leads; the label
/// explains. Colour only carries urgency — a zero count stays neutral.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
    this.selected = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return HuddleCard(
      onTap: onTap,
      color: selected ? color.withValues(alpha: 0.1) : null,
      borderColor: selected ? color.withValues(alpha: 0.35) : null,
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(height: Insets.md),
          Text(
            value,
            style: context.text.headlineSmall?.copyWith(
              color: color,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelMedium?.copyWith(
              color: palette.neutral,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
