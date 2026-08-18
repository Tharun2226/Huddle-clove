import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/notifications/providers/notification_providers.dart';
import '../../shared/theme/app_tokens.dart';
import '../auth/session_controller.dart';

/// Bottom-nav host. The Team branch always exists in the router; whether its
/// destination is offered depends on role.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  var _pushBootstrapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_pushBootstrapped || !mounted) return;
      _pushBootstrapped = true;
      await bootstrapPushNotifications(ref);
      if (!mounted) return;
      ref.read(pushNotificationServiceProvider).flushPendingTap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isManager = ref.watch(isManagerProvider);
    final shell = widget.shell;

    final destinations = <_Destination>[
      const _Destination(branch: 0, label: 'Today', icon: Icons.today_outlined, selectedIcon: Icons.today_rounded),
      const _Destination(branch: 1, label: 'Work', icon: Icons.check_circle_outline_rounded, selectedIcon: Icons.check_circle_rounded),
      const _Destination(branch: 2, label: 'Expenses', icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long_rounded),
      if (isManager)
        const _Destination(
          branch: 3,
          label: 'Team',
          icon: Icons.groups_outlined,
          selectedIcon: Icons.groups_rounded,
        ),
    ];

    var selected = destinations.indexWhere((d) => d.branch == shell.currentIndex);
    if (selected < 0) selected = 0;

    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.hairline)),
        ),
        child: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (index) {
            final branch = destinations[index].branch;
            // Tapping the active tab pops it back to its root — the standard
            // bottom-nav affordance people expect.
            shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
          },
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.branch,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final int branch;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
