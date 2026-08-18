import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/domain/app_user.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/config/org_config.dart';
import '../../../../core/di/providers.dart';
import '../../../../shared/widgets/agenda_date_picker.dart';
import '../../domain/meeting.dart';
import '../../domain/task.dart';
import '../widgets/task_visuals.dart';

final tasksProvider = StreamProvider<List<Task>>(
  (ref) => ref.watch(taskRepositoryProvider).watchTasks(),
);

final meetingsProvider = StreamProvider<List<Meeting>>(
  (ref) => ref.watch(taskRepositoryProvider).watchMeetings(),
);

/// API already scopes by role. Trust that list — only members need a
/// client-side self filter as a safety net.
final visibleTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider).value ?? const [];
  final me = ref.watch(sessionControllerProvider);
  if (me == null) return const [];
  if (me.isAdmin || me.role == UserRole.manager) return tasks;
  return tasks.where((t) => t.isAssignedTo(me.id)).toList();
});

final taskByIdProvider = Provider.family<Task?, String>((ref, id) {
  final tasks = ref.watch(tasksProvider).value ?? const [];
  for (final task in tasks) {
    if (task.id == id) return task;
  }
  return null;
});

@immutable
class TaskFilter {
  const TaskFilter({
    this.assigneeId,
    this.statusId,
    this.priorityId,
    this.status,
    this.priority,
    this.query = '',
    this.hideCompleted = false,
  });

  /// null means "everyone the current role is allowed to see".
  final String? assigneeId;
  final String? statusId;
  final String? priorityId;
  final TaskStatus? status;
  final TaskPriority? priority;
  final String query;
  final bool hideCompleted;

  bool get isActive =>
      assigneeId != null ||
      statusId != null ||
      priorityId != null ||
      status != null ||
      priority != null ||
      hideCompleted;

  int get activeCount => [
    assigneeId != null,
    statusId != null || status != null,
    priorityId != null || priority != null,
    hideCompleted,
  ].where((f) => f).length;

  TaskFilter copyWith({
    String? assigneeId,
    bool clearAssignee = false,
    String? statusId,
    bool clearStatusId = false,
    String? priorityId,
    bool clearPriorityId = false,
    TaskStatus? status,
    bool clearStatus = false,
    TaskPriority? priority,
    bool clearPriority = false,
    String? query,
    bool? hideCompleted,
  }) {
    return TaskFilter(
      assigneeId: clearAssignee ? null : (assigneeId ?? this.assigneeId),
      statusId: clearStatusId ? null : (statusId ?? this.statusId),
      priorityId: clearPriorityId ? null : (priorityId ?? this.priorityId),
      status: clearStatus ? null : (status ?? this.status),
      priority: clearPriority ? null : (priority ?? this.priority),
      query: query ?? this.query,
      hideCompleted: hideCompleted ?? this.hideCompleted,
    );
  }
}

class TaskFilterController extends Notifier<TaskFilter> {
  @override
  TaskFilter build() => const TaskFilter();

  void setAssignee(String? id) => state = id == null
      ? state.copyWith(clearAssignee: true)
      : state.copyWith(assigneeId: id);

  void setStatusId(String? id) => state = id == null
      ? state.copyWith(clearStatusId: true, clearStatus: true)
      : state.copyWith(statusId: id, clearStatus: true);

  void setPriorityId(String? id) => state = id == null
      ? state.copyWith(clearPriorityId: true, clearPriority: true)
      : state.copyWith(priorityId: id, clearPriority: true);

  void setStatus(TaskStatus? status) => state = status == null
      ? state.copyWith(clearStatus: true, clearStatusId: true)
      : state.copyWith(status: status, clearStatusId: true);

  void setPriority(TaskPriority? priority) => state = priority == null
      ? state.copyWith(clearPriority: true, clearPriorityId: true)
      : state.copyWith(priority: priority, clearPriorityId: true);

  void setQuery(String query) => state = state.copyWith(query: query);

  void toggleHideCompleted() =>
      state = state.copyWith(hideCompleted: !state.hideCompleted);

  void reset() => state = TaskFilter(query: state.query);
}

final taskFilterProvider = NotifierProvider<TaskFilterController, TaskFilter>(
  TaskFilterController.new,
);

final filteredTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(visibleTasksProvider);
  final filter = ref.watch(taskFilterProvider);
  final day = ref.watch(workAgendaDateProvider);
  final config = ref.watch(orgConfigProvider);
  final query = filter.query.trim().toLowerCase();

  final result =
      tasks.where((task) {
        if (day != null && !task.isDueOn(day)) return false;
        if (filter.assigneeId != null &&
            !task.isAssignedTo(filter.assigneeId!)) {
          return false;
        }
        if (filter.statusId != null) {
          final resolved = task.statusId.isNotEmpty
              ? task.statusId
              : task.orgStatus(config)?.id;
          if (resolved != filter.statusId) return false;
        } else if (filter.status != null && task.status != filter.status) {
          return false;
        }
        if (filter.priorityId != null) {
          final resolved = task.priorityId.isNotEmpty
              ? task.priorityId
              : task.orgPriority(config)?.id;
          if (resolved != filter.priorityId) return false;
        } else if (filter.priority != null && task.priority != filter.priority) {
          return false;
        }
        if (filter.hideCompleted && task.isDoneIn(config)) return false;
        if (query.isNotEmpty) {
          final haystack =
              '${task.title} ${task.description} ${task.tags.join(' ')}'.toLowerCase();
          if (!haystack.contains(query)) return false;
        }
        return true;
      }).toList()
      ..sort(_byUrgency);

  return result;
});

/// Open work first, ordered by how soon it bites; completed work sinks.
int _byUrgency(Task a, Task b) {
  if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
  final aDue = a.dueDate;
  final bDue = b.dueDate;
  if (aDue != null && bDue != null && aDue != bDue) return aDue.compareTo(bDue);
  if (aDue == null && bDue != null) return 1;
  if (aDue != null && bDue == null) return -1;
  final byPriority = a.priority.index.compareTo(b.priority.index);
  if (byPriority != 0) return byPriority;
  return b.createdAt.compareTo(a.createdAt);
}

final tasksDueTodayProvider = Provider<List<Task>>((ref) {
  final day = ref.watch(todayAgendaDateProvider);
  final tasks =
      ref.watch(visibleTasksProvider).where((t) => t.isDueOn(day)).toList()
        ..sort(_byUrgency);
  return tasks;
});

final overdueTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(visibleTasksProvider).where((t) => t.isOverdue).toList()
    ..sort(_byUrgency);
  return tasks;
});

/// Meetings visible to the signed-in user.
/// Managers/admins see the API-scoped list; members only their invites.
final myMeetingsProvider = Provider<List<Meeting>>((ref) {
  final meetings = ref.watch(meetingsProvider).value ?? const [];
  final me = ref.watch(sessionControllerProvider);
  if (me == null) return const [];
  if (me.isManager) return meetings;
  return meetings.where((m) => m.attendeeIds.contains(me.id)).toList();
});

/// Meetings linked to a task (created from that task).
final meetingsForTaskProvider =
    Provider.family<List<Meeting>, String>((ref, taskId) {
  final meetings = ref.watch(meetingsProvider).value ?? const [];
  return [
    for (final m in meetings)
      if (m.taskId == taskId) m,
  ]..sort((a, b) => a.start.compareTo(b.start));
});

int _todayMeetingOrder(Meeting a, Meeting b) {
  int rank(Meeting m) {
    if (m.isLive) return 0;
    if (!m.isPast) return 1;
    return 2;
  }

  final byRank = rank(a).compareTo(rank(b));
  if (byRank != 0) return byRank;
  // Upcoming / live: soonest first. Past: most recently ended last in the
  // past group (earlier past first so newest completed sits at the very end).
  if (a.isPast && b.isPast) return a.end.compareTo(b.end);
  return a.start.compareTo(b.start);
}

final todayMeetingsProvider = Provider<List<Meeting>>((ref) {
  final day = ref.watch(todayAgendaDateProvider);
  final list = [
    for (final m in ref.watch(myMeetingsProvider))
      if (m.occursOn(day)) m.occurrenceOn(day),
  ]..sort(_todayMeetingOrder);
  return list;
});

final nextMeetingProvider = Provider<Meeting?>((ref) {
  final now = DateTime.now();
  Meeting? soonest;
  for (final meeting in ref.watch(myMeetingsProvider)) {
    final next = meeting.nextAfter(now);
    if (next == null) continue;
    if (soonest == null || next.start.isBefore(soonest.start)) {
      soonest = next;
    }
  }
  return soonest;
});

/// The guide's "one timeline" — meetings and due tasks merged, sorted by time.
sealed class AgendaEntry {
  const AgendaEntry(this.at);
  final DateTime at;
}

class MeetingEntry extends AgendaEntry {
  MeetingEntry(this.meeting) : super(meeting.start);
  final Meeting meeting;
}

class TaskEntry extends AgendaEntry {
  TaskEntry(this.task) : super(task.dueDate!);
  final Task task;
}

final todayTimelineProvider = Provider<List<AgendaEntry>>((ref) {
  int rank(AgendaEntry e) {
    if (e is MeetingEntry) {
      if (e.meeting.isLive) return 0;
      if (e.meeting.isPast) return 2;
    }
    return 1;
  }

  final entries = <AgendaEntry>[
    ...ref.watch(todayMeetingsProvider).map(MeetingEntry.new),
    ...ref
        .watch(tasksDueTodayProvider)
        .where((t) => t.dueDate != null)
        .map(TaskEntry.new),
  ]..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      if (a is MeetingEntry &&
          b is MeetingEntry &&
          a.meeting.isPast &&
          b.meeting.isPast) {
        return a.meeting.end.compareTo(b.meeting.end);
      }
      return a.at.compareTo(b.at);
    });
  return entries;
});

/// Work tab meetings for the selected agenda day (or all when date is cleared).
final workDayMeetingsProvider = Provider<List<Meeting>>((ref) {
  final day = ref.watch(workAgendaDateProvider);
  final meetings = ref.watch(myMeetingsProvider);
  if (day == null) return meetings;
  final list = [
    for (final m in meetings)
      if (m.occursOn(day)) m.occurrenceOn(day),
  ]..sort((a, b) => a.start.compareTo(b.start));
  return list;
});

/// Kanban columns for the Tasks board and the manager team board.
final tasksByStatusProvider = Provider<Map<TaskStatus, List<Task>>>((ref) {
  final tasks = ref.watch(filteredTasksProvider);
  return {
    for (final status in TaskStatus.values)
      status: tasks.where((t) => t.status == status).toList(),
  };
});

/// Org-catalog kanban columns (preferred when statuses are configured).
final tasksByOrgStatusProvider = Provider<Map<String, List<Task>>>((ref) {
  final tasks = ref.watch(filteredTasksProvider);
  final config = ref.watch(orgConfigProvider);
  return {
    for (final status in config.taskStatuses)
      status.id: [
        for (final task in tasks)
          if ((task.statusId.isNotEmpty
                  ? task.statusId
                  : task.orgStatus(config)?.id) ==
              status.id)
            task,
      ],
  };
});
