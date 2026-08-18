import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/config/catalog_icons.dart';
import '../../../../core/config/org_config.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/huddle_card.dart';
import '../../../../shared/widgets/pill.dart';
import '../../domain/task.dart';
import '../providers/task_providers.dart';
import 'task_visuals.dart';

/// Kanban board. Columns scroll horizontally; cards drag between them to change
/// status, which is the whole reason the board view exists.
class TaskKanban extends ConsumerWidget {
  const TaskKanban({super.key, this.assigneeId});

  /// When set, the board shows only one person's tasks — used by the team board.
  final String? assigneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(orgConfigProvider);
    final width = MediaQuery.sizeOf(context).width;
    final columnWidth = (width * 0.76).clamp(240.0, 320.0);
    final orgStatuses = config.taskStatuses;

    if (orgStatuses.isNotEmpty) {
      final columns = ref.watch(tasksByOrgStatusProvider);
      return ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          Insets.screen,
          Insets.xs,
          Insets.screen,
          Insets.xl,
        ),
        children: [
          for (var i = 0; i < orgStatuses.length; i++) ...[
            SizedBox(
              width: columnWidth,
              child: _OrgColumn(
                status: orgStatuses[i],
                tasks: [
                  for (final task in columns[orgStatuses[i].id] ?? const <Task>[])
                    if (assigneeId == null || task.isAssignedTo(assigneeId!))
                      task,
                ],
              ),
            ),
            if (i != orgStatuses.length - 1) const SizedBox(width: Insets.md),
          ],
        ],
      );
    }

    final columns = ref.watch(tasksByStatusProvider);
    return ListView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Insets.screen,
        Insets.xs,
        Insets.screen,
        Insets.xl,
      ),
      children: [
        for (final status in TaskStatus.values) ...[
          SizedBox(
            width: columnWidth,
            child: _Column(
              status: status,
              tasks: assigneeId == null
                  ? columns[status]!
                  : columns[status]!
                      .where((t) => t.isAssignedTo(assigneeId!))
                      .toList(),
            ),
          ),
          if (status != TaskStatus.values.last) const SizedBox(width: Insets.md),
        ],
      ],
    );
  }
}

class _OrgColumn extends ConsumerStatefulWidget {
  const _OrgColumn({required this.status, required this.tasks});

  final OrgTaskStatus status;
  final List<Task> tasks;

  @override
  ConsumerState<_OrgColumn> createState() => _OrgColumnState();
}

class _OrgColumnState extends ConsumerState<_OrgColumn> {
  bool _hovering = false;

  Future<void> _accept(Task task) async {
    setState(() => _hovering = false);
    final currentId = task.statusId.isNotEmpty
        ? task.statusId
        : task.orgStatus(ref.read(orgConfigProvider))?.id;
    if (currentId == widget.status.id) return;
    HapticFeedback.selectionClick();
    final me = ref.read(currentUserProvider);
    await ref.read(taskRepositoryProvider).setStatus(
          task.id,
          taskStatusFromOrg(widget.status),
          actorId: me.id,
          statusId: widget.status.id,
        );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = parseOrgColor(widget.status.color);

    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) {
        final currentId = details.data.statusId.isNotEmpty
            ? details.data.statusId
            : details.data.orgStatus(ref.read(orgConfigProvider))?.id;
        final accepts = currentId != widget.status.id;
        if (accepts && !_hovering) setState(() => _hovering = true);
        return accepts;
      },
      onLeave: (_) => setState(() => _hovering = false),
      onAcceptWithDetails: (details) => _accept(details.data),
      builder: (context, candidates, rejects) {
        return AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.all(Insets.md),
          decoration: BoxDecoration(
            color: _hovering
                ? color.withValues(alpha: 0.07)
                : palette.neutralContainer.withValues(alpha: 0.45),
            borderRadius: Radii.card,
            border: Border.all(
              color: _hovering ? color.withValues(alpha: 0.5) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.xs,
                  Insets.xs,
                  Insets.xs,
                  Insets.md,
                ),
                child: Row(
                  children: [
                    Icon(
                      CatalogIcons.resolve(widget.status.icon),
                      size: 16,
                      color: color,
                    ),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: Text(
                        widget.status.name,
                        style: context.text.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${widget.tasks.length}',
                      style: context.text.labelMedium?.copyWith(
                        color: palette.neutral,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: widget.tasks.isEmpty
                    ? _EmptyColumn(hovering: _hovering, color: color)
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: Insets.xxl * 2),
                        itemCount: widget.tasks.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: Insets.sm),
                        itemBuilder: (context, index) =>
                            _DraggableCard(task: widget.tasks[index]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Column extends ConsumerStatefulWidget {
  const _Column({required this.status, required this.tasks});

  final TaskStatus status;
  final List<Task> tasks;

  @override
  ConsumerState<_Column> createState() => _ColumnState();
}

class _ColumnState extends ConsumerState<_Column> {
  bool _hovering = false;

  Future<void> _accept(Task task) async {
    setState(() => _hovering = false);
    if (task.status == widget.status) return;
    HapticFeedback.selectionClick();
    final me = ref.read(currentUserProvider);
    await ref
        .read(taskRepositoryProvider)
        .setStatus(task.id, widget.status, actorId: me.id);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = widget.status.color(palette);

    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) {
        final accepts = details.data.status != widget.status;
        if (accepts && !_hovering) setState(() => _hovering = true);
        return accepts;
      },
      onLeave: (_) => setState(() => _hovering = false),
      onAcceptWithDetails: (details) => _accept(details.data),
      builder: (context, candidates, rejects) {
        return AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.all(Insets.md),
          decoration: BoxDecoration(
            color: _hovering
                ? color.withValues(alpha: 0.07)
                : palette.neutralContainer.withValues(alpha: 0.45),
            borderRadius: Radii.card,
            border: Border.all(
              color: _hovering ? color.withValues(alpha: 0.5) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.xs,
                  Insets.xs,
                  Insets.xs,
                  Insets.md,
                ),
                child: Row(
                  children: [
                    Dot(color: color),
                    const SizedBox(width: Insets.sm),
                    Text(widget.status.shortLabel, style: context.text.titleSmall),
                    const SizedBox(width: Insets.sm),
                    Text(
                      '${widget.tasks.length}',
                      style: context.text.labelMedium?.copyWith(
                        color: palette.neutral,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: widget.tasks.isEmpty
                    ? _EmptyColumn(hovering: _hovering, color: color)
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: Insets.xxl * 2),
                        itemCount: widget.tasks.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: Insets.sm),
                        itemBuilder: (context, index) =>
                            _DraggableCard(task: widget.tasks[index]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyColumn extends StatelessWidget {
  const _EmptyColumn({required this.hovering, required this.color});

  final bool hovering;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Center(
      child: AnimatedOpacity(
        duration: Motion.fast,
        opacity: hovering ? 1 : 0.6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hovering ? Icons.download_rounded : Icons.inbox_rounded,
              size: 22,
              color: hovering ? color : palette.neutral,
            ),
            const SizedBox(height: Insets.sm),
            Text(
              hovering ? 'Drop here' : 'Empty',
              style: context.text.labelMedium?.copyWith(
                color: hovering ? color : palette.neutral,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraggableCard extends ConsumerWidget {
  const _DraggableCard({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final config = ref.watch(orgConfigProvider);
    final directory = ref.watch(teamById);
    final assignees = [
      for (var i = 0; i < task.allAssigneeIds.length; i++)
        directory.resolve(
          task.allAssigneeIds[i],
          fallbackName: i < task.assigneeNames.length
              ? task.assigneeNames[i]
              : (task.allAssigneeIds[i] == task.assigneeId
                  ? task.assigneeName
                  : null),
        ),
    ];
    final priorityColor = task.priorityColor(config, palette);

    return LongPressDraggable<Task>(
      data: task,
      feedback: Material(
        elevation: 6,
        borderRadius: Radii.card,
        child: SizedBox(
          width: 260,
          child: Opacity(
            opacity: 0.92,
            child: _KanbanCardBody(
              task: task,
              assignees: assignees,
              priorityColor: priorityColor,
              priorityLabel: task.priorityLabel(config),
              priorityIcon: task.priorityIcon(config),
              showTags: config.showTags,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _KanbanCardBody(
          task: task,
          assignees: assignees,
          priorityColor: priorityColor,
          priorityLabel: task.priorityLabel(config),
          priorityIcon: task.priorityIcon(config),
          showTags: config.showTags,
        ),
      ),
      child: _KanbanCardBody(
        task: task,
        assignees: assignees,
        priorityColor: priorityColor,
        priorityLabel: task.priorityLabel(config),
        priorityIcon: task.priorityIcon(config),
        showTags: config.showTags,
        onTap: () => context.push(Routes.taskDetail(task.id)),
      ),
    );
  }
}

class _KanbanCardBody extends StatelessWidget {
  const _KanbanCardBody({
    required this.task,
    required this.assignees,
    required this.priorityColor,
    required this.priorityLabel,
    required this.priorityIcon,
    required this.showTags,
    this.onTap,
  });

  final Task task;
  final List<dynamic> assignees;
  final Color priorityColor;
  final String priorityLabel;
  final IconData priorityIcon;
  final bool showTags;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return HuddleCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(priorityIcon, size: 14, color: priorityColor),
              const SizedBox(width: 4),
              Text(
                priorityLabel,
                style: context.text.labelSmall?.copyWith(
                  color: priorityColor,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 22.0 +
                    (assignees.length > 1
                        ? (assignees.length - 1).clamp(0, 2) * 12.0
                        : 0),
                height: 22,
                child: Stack(
                  children: [
                    for (var i = 0; i < assignees.take(3).length; i++)
                      Positioned(
                        left: i * 12.0,
                        child: UserAvatar(user: assignees[i], size: 22),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (showTags && task.tags.isNotEmpty) ...[
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final tag in task.tags.take(2))
                  Pill(label: tag, color: palette.neutral, dense: true),
              ],
            ),
          ],
          const SizedBox(height: Insets.sm),
          Text(
            task.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (task.dueDate != null) ...[
            const SizedBox(height: Insets.sm),
            Text(
              Fmt.dueLabel(task.dueDate!),
              style: context.text.labelSmall?.copyWith(
                color: task.isOverdue ? palette.danger : palette.neutral,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
