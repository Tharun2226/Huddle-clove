import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/domain/app_user.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/app_feedback.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../../shared/widgets/agenda_date_picker.dart';
import '../../../../shared/widgets/huddle_card.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../domain/meeting.dart';
import '../../domain/task.dart';
import '../providers/task_providers.dart';
import '../widgets/create_meeting_sheet.dart';
import '../widgets/meeting_card.dart';
import '../widgets/meeting_sheet.dart';
import '../widgets/task_card.dart';
import '../widgets/task_filter_bar.dart';
import '../widgets/task_import_excel.dart';
import '../widgets/task_kanban.dart';

enum TasksTab { tasks, meetings }

enum TaskView { list, kanban }

class TasksTabController extends Notifier<TasksTab> {
  @override
  TasksTab build() => TasksTab.tasks;

  void set(TasksTab tab) => state = tab;
}

final tasksTabProvider = NotifierProvider<TasksTabController, TasksTab>(
  TasksTabController.new,
);

class TaskViewController extends Notifier<TaskView> {
  @override
  TaskView build() => TaskView.list;

  void set(TaskView view) => state = view;
}

final taskViewProvider = NotifierProvider<TaskViewController, TaskView>(
  TaskViewController.new,
);

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tasksTabProvider);
    final view = ref.watch(taskViewProvider);
    final tasksAsync = ref.watch(tasksProvider);
    final meetingsAsync = ref.watch(meetingsProvider);
    final tasks = ref.watch(filteredTasksProvider);
    final meetings = ref.watch(workDayMeetingsProvider);
    final agendaDate = ref.watch(workAgendaDateProvider);
    final filter = ref.watch(taskFilterProvider);
    final me = ref.watch(currentUserProvider);
    final canCreateMeeting = me.isManager;
    final loadingTasks = tasksAsync.isLoading && !tasksAsync.hasValue;
    final loadingMeetings = meetingsAsync.isLoading && !meetingsAsync.hasValue;
    final tasksError = tasksAsync.hasError && !tasksAsync.hasValue;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Work'),
        actions: [
          if (tab == TasksTab.tasks) ...[
            IconButton(
              tooltip: 'Import tasks',
              onPressed: () => showTaskImportSheet(context, ref),
              icon: const Icon(Icons.file_upload_outlined),
            ),
            Padding(
              padding: const EdgeInsets.only(right: Insets.screen),
              child: _IconToggle(
                selected: view,
                options: const [
                  (TaskView.list, Icons.view_list_rounded, 'List view'),
                  (TaskView.kanban, Icons.view_kanban_rounded, 'Kanban view'),
                ],
                onChanged: (v) => ref.read(taskViewProvider.notifier).set(v),
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: switch (tab) {
        TasksTab.tasks => canCreateMeeting
            ? FloatingActionButton.extended(
                onPressed: () async {
                  final choice = await showModalBottomSheet<String>(
                    context: context,
                    showDragHandle: true,
                    builder: (context) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.task_alt_rounded),
                            title: const Text('New task'),
                            onTap: () => Navigator.pop(context, 'task'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.event_available_rounded),
                            title: const Text('New meeting'),
                            subtitle: const Text('One-time or repeating'),
                            onTap: () => Navigator.pop(context, 'meeting'),
                          ),
                        ],
                      ),
                    ),
                  );
                  if (!context.mounted) return;
                  if (choice == 'task') {
                    context.push(Routes.newTask);
                  } else if (choice == 'meeting') {
                    ref.read(tasksTabProvider.notifier).set(TasksTab.meetings);
                    await showCreateMeetingSheet(context, ref);
                  }
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create'),
              )
            : FloatingActionButton.extended(
                onPressed: () => context.push(Routes.newTask),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New Task'),
              ),
        TasksTab.meetings => canCreateMeeting
            ? FloatingActionButton.extended(
                onPressed: () => showCreateMeetingSheet(context, ref),
                icon: const Icon(Icons.event_available_rounded),
                label: const Text('New meeting'),
              )
            : null,
      },
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.screen,
              Insets.sm,
              Insets.screen,
              Insets.md,
            ),
            child: _SegmentToggle<TasksTab>(
              selected: tab,
              options: const [
                (TasksTab.tasks, 'Tasks'),
                (TasksTab.meetings, 'Meetings'),
              ],
              onChanged: (value) =>
                  ref.read(tasksTabProvider.notifier).set(value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.screen,
              0,
              Insets.screen,
              Insets.sm,
            ),
            child: AgendaDateButton(
              date: agendaDate,
              allowAll: true,
              compact: true,
              onPick: () => pickAgendaDate(
                context: context,
                initialDate: agendaDate ?? DateTime.now(),
                onPicked: (d) =>
                    ref.read(workAgendaDateProvider.notifier).set(d),
              ),
              onToday: () =>
                  ref.read(workAgendaDateProvider.notifier).goToday(),
              onClear: () =>
                  ref.read(workAgendaDateProvider.notifier).clear(),
            ),
          ),
          if (tab == TasksTab.tasks) const TaskFilterBar(),
          Expanded(
            child: switch (tab) {
              TasksTab.tasks => tasksError
                  ? EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Couldn’t load tasks',
                      message: 'Check your connection and try again.',
                      action: FilledButton.icon(
                        onPressed: () => ref.invalidate(tasksProvider),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
                      ),
                    )
                  : loadingTasks
                  ? const Padding(
                      padding: EdgeInsets.all(Insets.screen),
                      child: SkeletonList(count: 5),
                    )
                  : tasks.isEmpty
                      ? _EmptyTasks(
                          filtered: filter.isActive ||
                              filter.query.isNotEmpty ||
                              agendaDate != null,
                          dateLabel: agendaDate == null
                              ? null
                              : isCalendarToday(agendaDate)
                                  ? 'today'
                                  : Fmt.friendlyDate(agendaDate),
                        )
                      : switch (view) {
                          TaskView.list => _TaskList(tasks: tasks),
                          TaskView.kanban => const TaskKanban(),
                        },
              TasksTab.meetings => meetingsAsync.hasError && !meetingsAsync.hasValue
                  ? EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Couldn’t load meetings',
                      message: 'Pull to refresh or try again in a moment.',
                      action: FilledButton.icon(
                        onPressed: () => ref.invalidate(meetingsProvider),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
                      ),
                    )
                  : loadingMeetings
                  ? const Padding(
                      padding: EdgeInsets.all(Insets.screen),
                      child: SkeletonList(count: 5),
                    )
                  : _MeetingsList(
                      meetings: meetings,
                      canManage: canCreateMeeting,
                      agendaDate: agendaDate,
                    ),
            },
          ),
        ],
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.tasks});

  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(
        Insets.screen,
        Insets.sm,
        Insets.screen,
        Insets.xxl * 3,
      ),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return TaskCard(
          task: task,
          onTap: () => context.push(Routes.taskDetail(task.id)),
        );
      },
    );
  }
}

class _MeetingsList extends ConsumerWidget {
  const _MeetingsList({
    required this.meetings,
    required this.canManage,
    required this.agendaDate,
  });

  final List<Meeting> meetings;
  final bool canManage;
  final DateTime? agendaDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (meetings.isEmpty) {
      final day = agendaDate;
      return EmptyState(
        icon: Icons.event_available_rounded,
        title: day == null
            ? 'No meetings yet'
            : isCalendarToday(day)
                ? 'No meetings today'
                : 'No meetings on ${Fmt.friendlyDate(day)}',
        message: canManage
            ? (day == null
                ? 'Use + to schedule a meeting for your team.'
                : 'Pick another date, or schedule a meeting.')
            : 'Meetings you’re invited to will show up here.',
      );
    }

    // Day-scoped: flat chronological list for that day.
    if (agendaDate != null) {
      return ListView.separated(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(
          Insets.screen,
          Insets.sm,
          Insets.screen,
          Insets.xxl * 3,
        ),
        itemCount: meetings.length,
        separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
        itemBuilder: (context, index) => _MeetingListTile(
          meeting: meetings[index],
          canManage: canManage,
        ),
      );
    }

    final now = DateTime.now();
    final upcoming = <Meeting>[];
    final past = <Meeting>[];
    for (final m in meetings) {
      final next = m.nextAfter(now);
      if (next != null) {
        upcoming.add(next);
      } else {
        past.add(m);
      }
    }
    upcoming.sort((a, b) => a.start.compareTo(b.start));
    past.sort((a, b) => b.start.compareTo(a.start));

    return ListView(
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
        if (upcoming.isNotEmpty) ...[
          const SectionHeader(title: 'Upcoming'),
          for (final meeting in upcoming) ...[
            _MeetingListTile(meeting: meeting, canManage: canManage),
            const SizedBox(height: Insets.md),
          ],
        ],
        if (past.isNotEmpty) ...[
          if (upcoming.isNotEmpty) const SizedBox(height: Insets.sm),
          const SectionHeader(title: 'Past'),
          for (final meeting in past) ...[
            _MeetingListTile(meeting: meeting, canManage: canManage),
            const SizedBox(height: Insets.md),
          ],
        ],
      ],
    );
  }
}

class _MeetingListTile extends ConsumerWidget {
  const _MeetingListTile({
    required this.meeting,
    required this.canManage,
  });

  final Meeting meeting;
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
    try {
      await ref.read(taskRepositoryProvider).deleteMeeting(meeting.id);
      if (!context.mounted) return;
      AppFeedback.success(
        AppFeedback.messengerOf(context),
        'Deleted “${meeting.title}”',
      );
    } catch (e) {
      if (!context.mounted) return;
      AppFeedback.error(
        AppFeedback.messengerOf(context),
        AppFeedback.apiMessage(e, 'Could not delete meeting'),
      );
    }
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

class _EmptyTasks extends ConsumerWidget {
  const _EmptyTasks({required this.filtered, this.dateLabel});

  final bool filtered;
  final String? dateLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (filtered) {
      return EmptyState(
        icon: Icons.filter_alt_off_rounded,
        title: dateLabel != null
            ? 'No tasks due $dateLabel'
            : 'No tasks match',
        message: dateLabel != null
            ? 'Pick another date, tap All, or clear filters.'
            : 'Try loosening the filters or search.',
        action: OutlinedButton.icon(
          onPressed: () {
            ref.read(taskFilterProvider.notifier).reset();
            ref.read(workAgendaDateProvider.notifier).clear();
          },
          icon: const Icon(Icons.clear_rounded, size: 18),
          label: const Text('Clear filters'),
        ),
      );
    }

    final me = ref.watch(currentUserProvider);
    final teamSize = ref.watch(teamProvider).length;
    return EmptyState(
      icon: Icons.task_alt_rounded,
      title: 'No tasks yet',
      message: me.role == UserRole.manager && teamSize <= 1
          ? 'Your team is just you for now. Create a task for yourself, or add members and assign them to you.'
          : me.isManager
              ? 'Use + to create a task and assign it to your team.'
              : 'Tasks assigned to you will show up here.',
    );
  }
}

class _SegmentToggle<T> extends StatelessWidget {
  const _SegmentToggle({
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  final T selected;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.neutralContainer,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        children: [
          for (final (value, label) in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: selected == value,
                label: label,
                child: InkWell(
                  onTap: () => onChanged(value),
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    curve: Motion.standard,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color:
                          selected == value ? palette.card : Colors.transparent,
                      borderRadius: BorderRadius.circular(Radii.pill),
                      boxShadow: selected == value
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: context.text.labelLarge?.copyWith(
                        color: selected == value
                            ? scheme.primary
                            : palette.neutral,
                        fontWeight:
                            selected == value ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IconToggle<T> extends StatelessWidget {
  const _IconToggle({
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  final T selected;
  final List<(T, IconData, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = context.colors;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.neutralContainer,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, icon, label) in options)
            Semantics(
              button: true,
              selected: selected == value,
              label: label,
              child: InkWell(
                onTap: () => onChanged(value),
                borderRadius: BorderRadius.circular(Radii.pill),
                child: AnimatedContainer(
                  duration: Motion.fast,
                  curve: Motion.standard,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.md,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        selected == value ? palette.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(Radii.pill),
                    boxShadow: selected == value
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: selected == value ? scheme.primary : palette.neutral,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
