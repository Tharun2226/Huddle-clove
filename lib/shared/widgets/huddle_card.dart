import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The one card in the app. Everything that sits on the canvas uses this, which
/// is most of why the screens feel like the same product.
class HuddleCard extends StatelessWidget {
  const HuddleCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(Insets.lg),
    this.color,
    this.borderColor,
    this.elevated = true,
    this.borderRadius = Radii.card,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final bool elevated;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? palette.card,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor ?? palette.hairline),
        boxShadow: elevated ? palette.shadow : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Section label above a group of cards — "Tasks due today", with an optional
/// count and trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.action,
    this.padding = const EdgeInsets.fromLTRB(Insets.xs, 0, 0, Insets.md),
  });

  final String title;
  final int? count;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: padding,
      child: Row(
        children: [
          Text(title, style: context.text.titleMedium),
          if (count != null) ...[
            const SizedBox(width: Insets.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: palette.neutralContainer,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                '$count',
                style: context.text.labelSmall?.copyWith(
                  color: palette.neutral,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
          const Spacer(),
          ?action,
        ],
      ),
    );
  }
}

/// Shown when a list is legitimately empty — distinct from a loading or error
/// state, and always says what to do next rather than just "nothing here".
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: Insets.xxl,
          vertical: compact ? Insets.xl : Insets.xxl * 2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 48 : 64,
              height: compact ? 48 : 64,
              decoration: BoxDecoration(
                color: palette.neutralContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: compact ? 24 : 30,
                color: palette.neutral,
              ),
            ),
            SizedBox(height: compact ? Insets.md : Insets.lg),
            Text(
              title,
              style: compact ? context.text.titleSmall : context.text.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.xs),
            Text(
              message,
              style: context.text.bodySmall?.copyWith(color: palette.neutral),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: Insets.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
