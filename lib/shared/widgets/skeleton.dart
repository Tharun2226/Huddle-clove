import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Shimmering placeholder block. Drives a single controller per instance and
/// paints with a moving gradient, so a screenful stays cheap.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = Radii.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final base = palette.neutralContainer;
    final highlight = Color.alphaBlend(
      palette.card.withValues(alpha: 0.55),
      base,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.1, 0.5, 0.9],
              begin: Alignment(-1.6 + _controller.value * 3.2, 0),
              end: Alignment(-0.6 + _controller.value * 3.2, 0),
            ),
          ),
        );
      },
    );
  }
}

/// Card-shaped placeholder matching the real rows, so the layout does not jump
/// when data lands.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 76});

  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      height: height,
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: Radii.card,
        border: Border.all(color: palette.hairline),
      ),
      child: Row(
        children: [
          const Skeleton(width: 42, height: 42, radius: Radii.sm),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Skeleton(width: MediaQuery.sizeOf(context).width * 0.42),
                const SizedBox(height: Insets.sm),
                const Skeleton(width: 96, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 3, this.height = 76});

  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: Insets.md),
          SkeletonCard(height: height),
        ],
      ],
    );
  }
}
