import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/huddle_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final me = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeModeProvider);
    final roleLabel = me.roleNames.isNotEmpty
        ? me.roleNames.join(', ')
        : me.role.label;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(
          Insets.screen,
          Insets.sm,
          Insets.screen,
          Insets.xxl,
        ),
        children: [
          HuddleCard(
            padding: const EdgeInsets.all(Insets.lg),
            child: Row(
              children: [
                UserAvatar(user: me, size: 52),
                const SizedBox(width: Insets.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(me.name, style: context.text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        me.email,
                        style: context.text.bodySmall?.copyWith(
                          color: palette.neutral,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.xl),

          const SectionHeader(title: 'Role'),
          HuddleCard(
            child: _InfoRow(label: 'Current role', value: roleLabel),
          ),
          const SizedBox(height: Insets.xl),

          if (me.isAdmin) ...[
            const SectionHeader(title: 'Organization'),
            HuddleCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Insets.lg,
                  vertical: Insets.sm,
                ),
                leading: Icon(
                  Icons.apartment_rounded,
                  color: context.colors.primary,
                ),
                title: const Text('Organization settings'),
                subtitle: Text(
                  'Roles, permissions, statuses',
                  style: context.text.bodySmall?.copyWith(
                    color: palette.neutral,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.orgSettings),
              ),
            ),
            const SizedBox(height: Insets.xl),
          ],

          const SectionHeader(title: 'Appearance'),
          HuddleCard(
            padding: const EdgeInsets.all(Insets.md),
            child: Column(
              children: [
                for (final mode in ThemeMode.values)
                  _OptionRow(
                    label: switch (mode) {
                      ThemeMode.system => 'Match system',
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                    },
                    icon: switch (mode) {
                      ThemeMode.system => Icons.brightness_auto_rounded,
                      ThemeMode.light => Icons.light_mode_rounded,
                      ThemeMode.dark => Icons.dark_mode_rounded,
                    },
                    selected: themeMode == mode,
                    onTap: () => ref.read(themeModeProvider.notifier).set(mode),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Insets.xl),

          const SectionHeader(title: 'About'),
          HuddleCard(
            child: Column(
              children: [
                _InfoRow(
                  label: 'Backend',
                  value: 'NestJS API',
                ),
                Divider(height: Insets.xl, color: palette.hairline),
                _InfoRow(label: 'Version', value: '1.0.0'),
                Divider(height: Insets.xl, color: palette.hairline),
                _InfoRow(
                  label: 'Tasks & expenses',
                  value: 'Huddle API',
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.xxl),

          OutlinedButton.icon(
            onPressed: () {
              ref.read(sessionControllerProvider.notifier).signOut();
              context.go('/login');
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.danger,
              side: BorderSide(color: palette.danger.withValues(alpha: 0.35)),
            ),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = context.colors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.md,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 19,
              color: selected ? scheme.primary : palette.neutral,
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Text(
                label,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        Text(
          label,
          style: context.text.bodyMedium?.copyWith(color: palette.neutral),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
