import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'huddle_logo.dart';

/// Brand splash shown while the API and session bootstrap.
/// After that, the app opens Today (or login) via the router.
class HuddleSplash extends StatefulWidget {
  const HuddleSplash({super.key});

  @override
  State<HuddleSplash> createState() => _HuddleSplashState();
}

class _HuddleSplashState extends State<HuddleSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  late final Animation<double> _scale = Tween<double>(begin: 0.92, end: 1).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = context.colors;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HuddleLogo(size: 132),
                  const SizedBox(height: Insets.lg),
                  Text(
                    'Huddle',
                    style: context.text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(
                    'Work, meetings & expenses',
                    style: context.text.bodyMedium?.copyWith(
                      color: palette.neutral,
                    ),
                  ),
                  const SizedBox(height: Insets.xxl),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: scheme.primary.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
