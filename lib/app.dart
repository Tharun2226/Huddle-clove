import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/session_controller.dart';
import 'core/di/providers.dart';
import 'core/network/api_config.dart';
import 'core/network/api_health.dart';
import 'core/router/app_router.dart';
import 'shared/theme/app_theme.dart';
import 'shared/theme/app_tokens.dart';
import 'shared/widgets/huddle_logo.dart';
import 'shared/widgets/huddle_splash.dart';

class HuddleApp extends ConsumerStatefulWidget {
  const HuddleApp({super.key});

  @override
  ConsumerState<HuddleApp> createState() => _HuddleAppState();
}

class _HuddleAppState extends ConsumerState<HuddleApp> {
  late Future<bool> _boot;

  /// Keep the logo splash visible briefly so open never feels like a spinner flash.
  static const _minSplash = Duration(milliseconds: 1100);

  @override
  void initState() {
    super.initState();
    _boot = _startBoot();
  }

  Future<bool> _startBoot() async {
    final ready = ApiHealth.isReachable();
    await Future.wait<void>([
      ready.then((_) {}),
      Future<void>.delayed(_minSplash),
    ]);
    return ready;
  }

  void _retry() {
    setState(() {
      _boot = _startBoot();
    });
  }

  Widget _brandedShell({
    required ThemeMode themeMode,
    required Widget home,
  }) {
    return MaterialApp(
      title: 'Huddle',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: home,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return FutureBuilder<bool>(
      future: _boot,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _brandedShell(
            themeMode: themeMode,
            home: const HuddleSplash(),
          );
        }

        if (snapshot.data != true) {
          return _brandedShell(
            themeMode: themeMode,
            home: _ApiDownScreen(onRetry: _retry),
          );
        }

        final router = ref.watch(routerProvider);
        final sessionReady = ref.watch(sessionBootstrapProvider);

        if (sessionReady.isLoading) {
          return _brandedShell(
            themeMode: themeMode,
            home: const HuddleSplash(),
          );
        }

        return MaterialApp.router(
          title: 'Huddle',
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: media.textScaler.clamp(
                  minScaleFactor: 0.9,
                  maxScaleFactor: 1.3,
                ),
              ),
              child: child!,
            );
          },
        );
      },
    );
  }
}

class _ApiDownScreen extends StatelessWidget {
  const _ApiDownScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Insets.xxl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HuddleLogo(size: 96),
                  const SizedBox(height: Insets.xl),
                  Text(
                    'Can’t reach Huddle',
                    style: context.text.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Insets.sm),
                  Text(
                    'The server is offline or unreachable. Check your connection and try again.',
                    style: context.text.bodyMedium?.copyWith(
                      color: palette.neutral,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Insets.md),
                  Text(
                    ApiConfig.baseUrl,
                    style: context.text.bodySmall?.copyWith(
                      color: palette.neutral,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Insets.xl),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try again'),
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
