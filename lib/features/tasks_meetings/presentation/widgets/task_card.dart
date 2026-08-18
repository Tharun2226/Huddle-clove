import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/config/org_config.dart';
import '../../../../core/di/providers.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/huddle_card.dart';
import '../../../../shared/widgets/pill.dart';
import '../../domain/task.dart';
import 'task_visuals.dart';

/// The task row used on Today, Tasks and Team. Tapping the checkbox completes
/// the task in place; tapping the body opens the detail screen.
class TaskCard extends ConsumerWidget {
  const TaskCard({
    super.key,
    required this.task,
    this.onTap,
    this.showAssignee = true,
    this.dense = false,
  });

  final Task task;
  final VoidCallback? onTap;
  final bool showAssignee;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final directory = ref.watch(teamById);
    final me = ref.watch(currentUserProvider);
    final config = ref.watch(orgConfigProvider);
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
    final done = task.isDoneIn(config);

    return HuddleCard(
      onTap: onTap,
      padding: EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: dense ? Insets.md : Insets.lg - 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccentRail(color: priorityColor, height: dense ? 34 : 42),
          const SizedBox(width: Insets.md),
          _CompleteButton(task: task),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: palette.neutral,
                    color: done ? palette.neutral : null,
                  ),
                ),
                const SizedBox(height: Insets.sm),
                if (ref.watch(orgConfigProvider).showTags &&
                    task.tags.isNotEmpty) ...[
                  Wrap(
                    spacing: Insets.sm,
                    runSpacing: 4,
                    children: [
                      for (final tag in task.tags.take(3))
                        Pill(
                          label: tag,
                          color: palette.neutral,
                          dense: true,
                        ),
                      if (task.tags.length > 3)
                        Text(
                          '+${task.tags.length - 3}',
                          style: context.text.labelSmall?.copyWith(
                            color: palette.neutral,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Insets.sm),
                ],
                Row(
                  children: [
                    if (task.dueDate != null) ...[
                      Icon(
                        task.isOverdue
                            ? Icons.error_outline_rounded
                            : Icons.schedule_rounded,
                        size: 13,
                        color: task.isOverdue ? palette.danger : palette.neutral,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          Fmt.dueLabel(task.dueDate!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelMedium?.copyWith(
                            color: task.isOverdue ? palette.danger : palette.neutral,
                            fontWeight: task.isOverdue
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    if (task.checklist.isNotEmpty) ...[
                      _dotSeparator(context, task.dueDate != null),
                      Icon(
                        Icons.checklist_rounded,
                        size: 13,
                        color: palette.neutral,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${task.checklistDone}/${task.checklist.length}',
                        style: context.text.labelMedium?.copyWith(
                          color: palette.neutral,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (task.comments.isNotEmpty) ...[
                      _dotSeparator(
                        context,
                        task.dueDate != null || task.checklist.isNotEmpty,
                      ),
                      Icon(
                        Icons.mode_comment_outlined,
                        size: 12,
                        color: palette.neutral,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${task.comments.length}',
                        style: context.text.labelMedium?.copyWith(
                          color: palette.neutral,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (showAssignee)
                SizedBox(
                  width: 26.0 + (assignees.length > 1
                      ? (assignees.length - 1).clamp(0, 2) * 14.0
                      : 0),
                  height: 26,
                  child: Stack(
                    children: [
                      for (var i = 0;
                          i < assignees.take(3).length;
                          i++)
                        Positioned(
                          left: i * 14.0,
                          child: UserAvatar(
                            user: assignees[i],
                            size: 26,
                            showRing: assignees[i].id == me.id,
                          ),
                        ),
                    ],
                  ),
                )
              else
                Pill(
                  label: task.status.shortLabel,
                  color: task.status.color(palette),
                  dense: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dotSeparator(BuildContext context, bool show) {
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
      child: Dot(color: context.palette.neutral.withValues(alpha: 0.4), size: 3),
    );
  }
}

/// Optimistic completion toggle — local cache flips immediately; API syncs after.
class _CompleteButton extends ConsumerStatefulWidget {
  const _CompleteButton({required this.task});

  final Task task;

  @override
  ConsumerState<_CompleteButton> createState() => _CompleteButtonState();
}

class _CompleteButtonState extends ConsumerState<_CompleteButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.selectionClick();
    final me = ref.read(currentUserProvider);
    final config = ref.read(orgConfigProvider);
    final done = config.doneStatus;
    final fallback = config.defaultStatus;
    try {
      if (done != null && fallback != null) {
        final isDone = widget.task.isDoneIn(config);
        final next = isDone ? fallback : done;
        await ref.read(taskRepositoryProvider).setStatus(
              widget.task.id,
              taskStatusFromOrg(next),
              actorId: me.id,
              statusId: next.id,
            );
      } else {
        final next =
            widget.task.isDone ? TaskStatus.todo : TaskStatus.done;
        await ref
            .read(taskRepositoryProvider)
            .setStatus(widget.task.id, next, actorId: me.id);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final config = ref.watch(orgConfigProvider);
    final done = widget.task.isDoneIn(config);

    return Semantics(
      button: true,
      checked: done,
      label: done ? 'Mark ${widget.task.title} incomplete' : 'Complete ${widget.task.title}',
      child: InkResponse(
        onTap: _toggle,
        radius: 22,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standard,
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: done ? palette.success : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: done ? palette.success : palette.neutral.withValues(alpha: 0.45),
              width: 1.8,
            ),
          ),
          child: done
              ? Icon(Icons.check_rounded, size: 14, color: palette.card)
              : null,
        ),
      ),
    );
  }
}
