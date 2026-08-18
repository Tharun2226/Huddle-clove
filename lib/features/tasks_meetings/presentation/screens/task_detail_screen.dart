import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/domain/app_user.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/config/catalog_icons.dart';
import '../../../../core/config/org_config.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/app_feedback.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/huddle_card.dart';
import '../../../../shared/widgets/pill.dart';
import '../../domain/meeting.dart';
import '../../domain/task.dart';
import '../providers/task_providers.dart';
import '../widgets/create_meeting_sheet.dart';
import '../widgets/meeting_card.dart';
import '../widgets/meeting_sheet.dart';
import '../widgets/task_visuals.dart';

class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(taskByIdProvider(taskId));

    if (task == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Task not found',
          message: 'It may have been deleted.',
        ),
      );
    }

    final palette = context.palette;
    final me = ref.watch(currentUserProvider);
    final directory = ref.watch(teamById);
    // Members can work their own tasks; only a manager edits someone else's.
    final canEdit = me.isManager || task.isAssignedTo(me.id);
    final canCreateMeeting = me.isManager;
    final linkedMeetings = ref.watch(meetingsForTaskProvider(task.id));
    final config = ref.watch(orgConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task'),
        actions: [
          if (canEdit || canCreateMeeting)
            PopupMenuButton<String>(
              position: PopupMenuPosition.under,
              color: palette.card,
              shape: const RoundedRectangleBorder(borderRadius: Radii.field),
              onSelected: (value) async {
                if (value == 'edit') {
                  context.push(Routes.editTask(task.id));
                } else if (value == 'meeting') {
                  await showCreateMeetingSheet(context, ref, task: task);
                } else if (value == 'delete') {
                  await _confirmDelete(context, ref, task);
                }
              },
              itemBuilder: (context) => [
                if (canEdit)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: Insets.md),
                        Text('Edit task'),
                      ],
                    ),
                  ),
                if (canCreateMeeting)
                  const PopupMenuItem(
                    value: 'meeting',
                    child: Row(
                      children: [
                        Icon(Icons.event_available_outlined, size: 18),
                        SizedBox(width: Insets.md),
                        Text('Create meeting'),
                      ],
                    ),
                  ),
                if (canEdit)
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 18, color: palette.danger),
                        const SizedBox(width: Insets.md),
                        Text('Delete', style: TextStyle(color: palette.danger)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      floatingActionButton: canCreateMeeting
          ? FloatingActionButton.extended(
              onPressed: () => showCreateMeetingSheet(context, ref, task: task),
              icon: const Icon(Icons.event_available_rounded),
              label: const Text('Meeting'),
            )
          : null,
      body: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(
          Insets.screen,
          Insets.sm,
          Insets.screen,
          Insets.xxl * 3,
        ),
        children: [
          Row(
            children: [
              Pill(
                label: task.priorityLabel(config),
                color: task.priorityColor(config, palette),
                icon: task.priorityIcon(config),
              ),
              const SizedBox(width: Insets.sm),
              Pill(
                label: task.statusLabel(config),
                color: task.statusColor(config, palette),
                icon: task.statusIcon(config),
              ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          Text(task.title, style: context.text.headlineSmall),
          const SizedBox(height: Insets.xl),

          _StatusPicker(task: task, enabled: canEdit),
          const SizedBox(height: Insets.xl),

          HuddleCard(
            child: Column(
              children: [
                _MetaRow(
                  icon: Icons.person_outline_rounded,
                  label: task.allAssigneeIds.length > 1 ||
                          task.externalAssignees.isNotEmpty
                      ? 'Assignees'
                      : 'Assignee',
                  child: Wrap(
                    spacing: Insets.sm,
                    runSpacing: Insets.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (var i = 0; i < task.allAssigneeIds.length; i++) ...[
                        Builder(
                          builder: (context) {
                            final id = task.allAssigneeIds[i];
                            final name = i < task.assigneeNames.length
                                ? task.assigneeNames[i]
                                : null;
                            final person = directory.resolve(
                              id,
                              fallbackName: name ??
                                  (id == task.assigneeId
                                      ? task.assigneeName
                                      : null),
                            );
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                UserAvatar(user: person, size: 24),
                                const SizedBox(width: Insets.sm),
                                Text(
                                  person.id == me.id ? 'You' : person.name,
                                  style: context.text.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                      for (final name in task.externalAssignees)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: CircleAvatar(
                            backgroundColor:
                                context.colors.primary.withValues(alpha: 0.12),
                            child: Text(
                              name.isEmpty ? '?' : name[0].toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: context.colors.primary,
                              ),
                            ),
                          ),
                          label: Text(name),
                        ),
                    ],
                  ),
                ),
                Divider(height: Insets.xl, color: palette.hairline),
                _MetaRow(
                  icon: Icons.event_rounded,
                  label: 'Due',
                  child: Text(
                    task.dueDate == null
                        ? 'No due date'
                        : '${Fmt.friendlyDate(task.dueDate!)}, ${Fmt.time(task.dueDate!)}',
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: task.isOverdue ? palette.danger : null,
                    ),
                  ),
                ),
                if (config.showTags && task.tags.isNotEmpty) ...[
                  Divider(height: Insets.xl, color: palette.hairline),
                  _MetaRow(
                    icon: Icons.sell_outlined,
                    label: 'Tags',
                    child: Wrap(
                      spacing: Insets.sm,
                      runSpacing: Insets.sm,
                      children: [
                        for (final tag in task.tags)
                          Pill(label: tag, color: palette.neutral, dense: true),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (task.description.isNotEmpty) ...[
            const SizedBox(height: Insets.xl),
            const SectionHeader(title: 'Description'),
            HuddleCard(
              child: Text(
                task.description,
                style: context.text.bodyMedium?.copyWith(height: 1.55),
              ),
            ),
          ],

          if (canEdit || task.checklist.isNotEmpty) ...[
            const SizedBox(height: Insets.xl),
            _Checklist(task: task, enabled: canEdit),
          ],

          const SizedBox(height: Insets.xl),
          SectionHeader(
            title: 'Meetings',
            count: linkedMeetings.isEmpty ? null : linkedMeetings.length,
            action: canCreateMeeting
                ? TextButton(
                    onPressed: () =>
                        showCreateMeetingSheet(context, ref, task: task),
                    child: const Text('Add'),
                  )
                : null,
          ),
          if (linkedMeetings.isEmpty)
            HuddleCard(
              child: Text(
                canCreateMeeting
                    ? 'No meetings linked yet. Create one from this task.'
                    : 'No meetings linked to this task.',
                style: context.text.bodyMedium?.copyWith(color: palette.neutral),
              ),
            )
          else
            for (final meeting in linkedMeetings) ...[
              _TaskMeetingTile(
                meeting: meeting,
                task: task,
                canManage: canCreateMeeting,
              ),
              const SizedBox(height: Insets.md),
            ],

          const SizedBox(height: Insets.xl),
          _Comments(task: task),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Task task) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this task?'),
        content: Text(
          '"${task.title}" will be removed for everyone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(taskRepositoryProvider).deleteTask(task.id);
      if (!context.mounted) return;
      AppFeedback.successAndPop(
        context,
        message: 'Task deleted',
      );
    } catch (e) {
      if (!context.mounted) return;
      AppFeedback.error(
        AppFeedback.messengerOf(context),
        AppFeedback.apiMessage(e, 'Could not delete task'),
      );
    }
  }
}

class _TaskMeetingTile extends ConsumerWidget {
  const _TaskMeetingTile({
    required this.meeting,
    required this.task,
    required this.canManage,
  });

  final Meeting meeting;
  final Task task;
  final bool canManage;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this meeting?'),
        content: Text(
          '“${meeting.title}” will be removed for everyone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(taskRepositoryProvider).deleteMeeting(meeting.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted “${meeting.title}”')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    return MeetingRow(
      meeting: meeting,
      onTap: () => showMeetingSheet(
        context,
        ref,
        meeting,
        task: task,
        canManage: canManage,
      ),
      trailing: canManage
          ? PopupMenuButton<String>(
              tooltip: 'Meeting actions',
              padding: EdgeInsets.zero,
              splashRadius: 18,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(
                Icons.more_vert_rounded,
                color: palette.neutral,
                size: 20,
              ),
              onSelected: (value) async {
                if (value == 'edit') {
                  await showCreateMeetingSheet(
                    context,
                    ref,
                    task: task,
                    meeting: meeting,
                  );
                } else if (value == 'delete') {
                  await _delete(context, ref);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  height: 40,
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Edit'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  height: 40,
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: palette.danger,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Delete',
                        style: TextStyle(color: palette.danger),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

/// Status is the thing people change most on this screen, so it gets a
/// first-class control rather than living behind the edit form.
class _StatusPicker extends ConsumerStatefulWidget {
  const _StatusPicker({required this.task, required this.enabled});

  final Task task;
  final bool enabled;

  @override
  ConsumerState<_StatusPicker> createState() => _StatusPickerState();
}

class _StatusPickerState extends ConsumerState<_StatusPicker> {
  bool _busy = false;

  Future<void> _setOrg(OrgTaskStatus status) async {
    final currentId = widget.task.statusId.isNotEmpty
        ? widget.task.statusId
        : widget.task.orgStatus(ref.read(orgConfigProvider))?.id;
    if (_busy || currentId == status.id) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      final me = ref.read(currentUserProvider);
      await ref.read(taskRepositoryProvider).setStatus(
            widget.task.id,
            taskStatusFromOrg(status),
            actorId: me.id,
            statusId: status.id,
          );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _set(TaskStatus status) async {
    if (_busy || status == widget.task.status) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      final me = ref.read(currentUserProvider);
      await ref
          .read(taskRepositoryProvider)
          .setStatus(widget.task.id, status, actorId: me.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final config = ref.watch(orgConfigProvider);
    final orgStatuses = config.taskStatuses;
    final selectedId = widget.task.statusId.isNotEmpty
        ? widget.task.statusId
        : widget.task.orgStatus(config)?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Status'),
        if (orgStatuses.isNotEmpty)
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final status in orgStatuses)
                _OrgStatusButton(
                  label: status.name,
                  icon: CatalogIcons.resolve(status.icon),
                  color: parseOrgColor(status.color),
                  selected: selectedId == status.id,
                  enabled: widget.enabled && !_busy,
                  onTap: () => _setOrg(status),
                ),
            ],
          )
        else
          Row(
            children: [
              for (final status in TaskStatus.values) ...[
                Expanded(
                  child: _StatusButton(
                    status: status,
                    selected: widget.task.status == status,
                    enabled: widget.enabled && !_busy,
                    onTap: () => _set(status),
                  ),
                ),
                if (status != TaskStatus.values.last)
                  const SizedBox(width: Insets.sm),
              ],
            ],
          ),
        if (!widget.enabled) ...[
          const SizedBox(height: Insets.sm),
          Text(
            'Only ${_ownerLabel()} or a manager can change this.',
            style: context.text.bodySmall?.copyWith(color: palette.neutral),
          ),
        ],
      ],
    );
  }

  String _ownerLabel() {
    final directory = ref.read(teamById);
    return directory
        .resolve(widget.task.assigneeId, fallbackName: widget.task.assigneeName)
        .firstName;
  }
}

class _OrgStatusButton extends StatelessWidget {
  const _OrgStatusButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: Insets.md,
          ),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.14) : palette.card,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.5) : palette.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: selected ? color : palette.neutral),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.text.labelSmall?.copyWith(
                  letterSpacing: 0,
                  color: selected ? color : palette.neutral,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.status,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final TaskStatus status;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = status.color(palette);

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standard,
          padding: const EdgeInsets.symmetric(vertical: Insets.md),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.14) : palette.card,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.5) : palette.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                status.icon,
                size: 17,
                color: selected ? color : palette.neutral,
              ),
              const SizedBox(height: 5),
              Text(
                status.shortLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(
                  letterSpacing: 0,
                  color: selected ? color : palette.neutral,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.label, required this.child});

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: palette.neutral),
        const SizedBox(width: Insets.md),
        Text(
          label,
          style: context.text.bodyMedium?.copyWith(color: palette.neutral),
        ),
        const Spacer(),
        Flexible(child: Align(alignment: Alignment.centerRight, child: child)),
      ],
    );
  }
}

class _Checklist extends ConsumerStatefulWidget {
  const _Checklist({required this.task, required this.enabled});

  final Task task;
  final bool enabled;

  @override
  ConsumerState<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends ConsumerState<_Checklist> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  var _adding = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final label = _controller.text.trim();
    if (label.isEmpty || _adding || !widget.enabled) return;
    setState(() => _adding = true);
    try {
      await ref
          .read(taskRepositoryProvider)
          .addChecklistItem(widget.task.id, label);
      _controller.clear();
      _focus.requestFocus();
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final task = widget.task;
    final enabled = widget.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Checklist',
          action: Text(
            task.checklist.isEmpty
                ? 'None yet'
                : '${task.checklistDone} of ${task.checklist.length}',
            style: context.text.labelMedium?.copyWith(color: palette.neutral),
          ),
        ),
        HuddleCard(
          padding: const EdgeInsets.symmetric(vertical: Insets.sm),
          child: Column(
            children: [
              if (task.checklist.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.lg,
                    Insets.sm,
                    Insets.lg,
                    Insets.md,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: task.checklistProgress),
                      duration: Motion.normal,
                      curve: Motion.emphasized,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 5,
                        backgroundColor: palette.neutralContainer,
                        valueColor: AlwaysStoppedAnimation(palette.success),
                      ),
                    ),
                  ),
                ),
              for (final item in task.checklist)
                InkWell(
                  onTap: enabled
                      ? () {
                          HapticFeedback.selectionClick();
                          ref
                              .read(taskRepositoryProvider)
                              .toggleChecklistItem(task.id, item.id);
                        }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Insets.lg,
                      vertical: Insets.md,
                    ),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: Motion.fast,
                          width: 19,
                          height: 19,
                          decoration: BoxDecoration(
                            color:
                                item.done ? palette.success : Colors.transparent,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: item.done
                                  ? palette.success
                                  : palette.neutral.withValues(alpha: 0.45),
                              width: 1.6,
                            ),
                          ),
                          child: item.done
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 13,
                                  color: palette.card,
                                )
                              : null,
                        ),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: Text(
                            item.label,
                            style: context.text.bodyMedium?.copyWith(
                              decoration: item.done
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: palette.neutral,
                              color: item.done ? palette.neutral : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (enabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.md,
                    Insets.xs,
                    Insets.md,
                    Insets.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _add(),
                          decoration: InputDecoration(
                            hintText: 'Add a checklist item',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Radii.md),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: Insets.md,
                              vertical: Insets.sm,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: Insets.sm),
                      IconButton.filled(
                        onPressed: _adding ? null : _add,
                        tooltip: 'Add item',
                        icon: _adding
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Comments extends ConsumerStatefulWidget {
  const _Comments({required this.task});

  final Task task;

  @override
  ConsumerState<_Comments> createState() => _CommentsState();
}

class _CommentsState extends ConsumerState<_Comments> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final me = ref.read(currentUserProvider);
      await ref
          .read(taskRepositoryProvider)
          .addComment(widget.task.id, body, actorId: me.id);
      _controller.clear();
      _focus.unfocus();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = context.colors;
    final directory = ref.watch(teamById);
    final me = ref.watch(currentUserProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Comments',
          count: widget.task.comments.isEmpty ? null : widget.task.comments.length,
        ),
        for (final comment in widget.task.comments) ...[
          _CommentTile(
            author: directory.resolve(
              comment.authorId,
              fallbackName: comment.authorName,
            ),
            comment: comment,
            isMe: comment.authorId == me.id,
          ),
          const SizedBox(height: Insets.md),
        ],
        if (widget.task.comments.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.md, left: Insets.xs),
            child: Text(
              'No comments yet.',
              style: context.text.bodySmall?.copyWith(color: palette.neutral),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            UserAvatar(user: me, size: 32),
            const SizedBox(width: Insets.md),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Add a comment',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Insets.lg,
                    vertical: Insets.md,
                  ),
                  suffixIcon: IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          )
                        : Icon(Icons.send_rounded, size: 18, color: scheme.primary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.author,
    required this.comment,
    required this.isMe,
  });

  final AppUser author;
  final TaskComment comment;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UserAvatar(user: author, size: 32),
        const SizedBox(width: Insets.md),
        Expanded(
          child: HuddleCard(
            elevated: false,
            padding: const EdgeInsets.all(Insets.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      isMe ? 'You' : author.name,
                      style: context.text.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    Text(
                      Fmt.relative(comment.createdAt),
                      style: context.text.labelSmall?.copyWith(
                        color: palette.neutral,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(comment.body, style: context.text.bodyMedium),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
