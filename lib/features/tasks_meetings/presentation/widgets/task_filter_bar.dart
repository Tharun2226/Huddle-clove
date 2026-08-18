import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/config/catalog_icons.dart';
import '../../../../core/config/org_config.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/widgets/pill.dart';
import '../../domain/task.dart';
import '../providers/task_providers.dart';
import 'task_visuals.dart';

/// Search + filter chips. The assignee filter only appears for managers —
/// a member's list is already scoped to them, so the control would be a no-op.
class TaskFilterBar extends ConsumerStatefulWidget {
  const TaskFilterBar({super.key});

  @override
  ConsumerState<TaskFilterBar> createState() => _TaskFilterBarState();
}

class _TaskFilterBarState extends ConsumerState<TaskFilterBar> {
  late final TextEditingController _search = TextEditingController(
    text: ref.read(taskFilterProvider).query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final filter = ref.watch(taskFilterProvider);
    final controller = ref.read(taskFilterProvider.notifier);
    final isManager = ref.watch(isManagerProvider);
    final team = ref.watch(teamProvider);
    final me = ref.watch(currentUserProvider);
    final config = ref.watch(orgConfigProvider);
    final orgStatuses = config.taskStatuses;
    final orgPriorities = config.taskPriorities;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.screen,
            Insets.sm,
            Insets.screen,
            Insets.md,
          ),
          child: TextField(
            controller: _search,
            onChanged: controller.setQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search tasks',
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: palette.neutral,
              ),
              suffixIcon: filter.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _search.clear();
                        controller.setQuery('');
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: Insets.md),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Insets.screen),
            children: [
              if (filter.isActive) ...[
                _ClearChip(onTap: controller.reset, count: filter.activeCount),
                const SizedBox(width: Insets.sm),
              ],
              if (isManager) ...[
                _DropdownChip<String>(
                  label: 'Assignee',
                  value: filter.assigneeId,
                  valueLabel: filter.assigneeId == null
                      ? null
                      : (filter.assigneeId == me.id
                            ? 'Me'
                            : team
                                  .firstWhere((u) => u.id == filter.assigneeId)
                                  .firstName),
                  options: [
                    for (final user in team)
                      (user.id, user.id == me.id ? 'Me' : user.firstName),
                  ],
                  onSelected: controller.setAssignee,
                ),
                const SizedBox(width: Insets.sm),
              ],
              if (orgStatuses.isNotEmpty)
                _DropdownChip<String>(
                  label: 'Status',
                  value: filter.statusId,
                  valueLabel: filter.statusId == null
                      ? null
                      : orgStatuses
                          .where((s) => s.id == filter.statusId)
                          .firstOrNull
                          ?.name,
                  options: [
                    for (final status in orgStatuses) (status.id, status.name),
                  ],
                  onSelected: controller.setStatusId,
                )
              else
                _DropdownChip<TaskStatus>(
                  label: 'Status',
                  value: filter.status,
                  valueLabel: filter.status?.label,
                  options: [
                    for (final status in TaskStatus.values)
                      (status, status.label),
                  ],
                  onSelected: controller.setStatus,
                ),
              const SizedBox(width: Insets.sm),
              if (orgPriorities.isNotEmpty)
                _DropdownChip<String>(
                  label: 'Priority',
                  value: filter.priorityId,
                  valueLabel: filter.priorityId == null
                      ? null
                      : orgPriorities
                          .where((p) => p.id == filter.priorityId)
                          .firstOrNull
                          ?.name,
                  colorFor: (id) {
                    final p =
                        orgPriorities.where((x) => x.id == id).firstOrNull;
                    return parseOrgColor(p?.color ?? '#6B7280');
                  },
                  options: [
                    for (final p in orgPriorities) (p.id, p.name),
                  ],
                  onSelected: controller.setPriorityId,
                )
              else
                _DropdownChip<TaskPriority>(
                  label: 'Priority',
                  value: filter.priority,
                  valueLabel: filter.priority?.label,
                  colorFor: (p) => p.color(palette),
                  options: [
                    for (final p in TaskPriority.values) (p, p.label),
                  ],
                  onSelected: controller.setPriority,
                ),
              const SizedBox(width: Insets.sm),
              _ToggleChip(
                label: 'Hide done',
                selected: filter.hideCompleted,
                onTap: controller.toggleHideCompleted,
              ),
            ],
          ),
        ),
        const SizedBox(height: Insets.md),
      ],
    );
  }
}

/// Chip that opens a menu. Selecting the active value again clears it, which
/// saves a separate "All" row in every menu.
class _DropdownChip<T> extends StatelessWidget {
  const _DropdownChip({
    required this.label,
    required this.value,
    required this.valueLabel,
    required this.options,
    required this.onSelected,
    this.colorFor,
  });

  final String label;
  final T? value;
  final String? valueLabel;
  final List<(T, String)> options;
  final ValueChanged<T?> onSelected;
  final Color Function(T)? colorFor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = context.colors;
    final active = value != null;

    return PopupMenuButton<T>(
      onSelected: (selected) => onSelected(selected == value ? null : selected),
      position: PopupMenuPosition.under,
      color: palette.card,
      shape: const RoundedRectangleBorder(borderRadius: Radii.field),
      itemBuilder: (context) => [
        for (final (optionValue, optionLabel) in options)
          PopupMenuItem<T>(
            value: optionValue,
            height: 44,
            child: Row(
              children: [
                if (colorFor != null) ...[
                  Dot(color: colorFor!(optionValue)),
                  const SizedBox(width: Insets.md),
                ],
                Text(optionLabel),
                const Spacer(),
                if (optionValue == value)
                  Icon(Icons.check_rounded, size: 16, color: scheme.primary),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? scheme.primary.withValues(alpha: 0.12)
              : palette.neutralContainer,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(
            color: active ? scheme.primary.withValues(alpha: 0.3) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              active ? valueLabel! : label,
              style: context.text.labelMedium?.copyWith(
                color: active ? scheme.primary : palette.neutral,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.expand_more_rounded,
              size: 15,
              color: active ? scheme.primary : palette.neutral,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = context.colors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : palette.neutralContainer,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(
            color: selected ? scheme.primary.withValues(alpha: 0.3) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 14, color: scheme.primary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: context.text.labelMedium?.copyWith(
                color: selected ? scheme.primary : palette.neutral,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClearChip extends StatelessWidget {
  const _ClearChip({required this.onTap, required this.count});

  final VoidCallback onTap;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 7),
        decoration: BoxDecoration(
          color: palette.dangerContainer,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.close_rounded, size: 14, color: palette.danger),
            const SizedBox(width: 4),
            Text(
              'Clear $count',
              style: context.text.labelMedium?.copyWith(color: palette.danger),
            ),
          ],
        ),
      ),
    );
  }
}
