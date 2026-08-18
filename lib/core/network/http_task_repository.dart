import 'dart:async';

import '../../../features/tasks_meetings/data/task_repository.dart';
import '../../../features/tasks_meetings/domain/meeting.dart';
import '../../../features/tasks_meetings/domain/task.dart';
import '../config/org_config.dart';
import 'api_task_repository.dart';

/// HTTP implementation of [TaskRepository].
///
/// Mutations that users tap repeatedly (status / checklist) update the local
/// cache immediately, then sync with the API — so the UI never waits on Vercel
/// latency before looking "done".
class HttpTaskRepository implements TaskRepository {
  HttpTaskRepository(this._api, [this._orgConfigGetter]);

  final ApiTaskRepository _api;
  final OrgConfig Function()? _orgConfigGetter;

  final _tasksController = StreamController<List<Task>>.broadcast();
  final _meetingsController = StreamController<List<Meeting>>.broadcast();
  List<Task> _tasks = const [];
  List<Meeting> _meetings = const [];

  void _emitTasks() {
    if (!_tasksController.isClosed) _tasksController.add(List.unmodifiable(_tasks));
  }

  void _emitMeetings() {
    if (!_meetingsController.isClosed) {
      _meetingsController.add(List.unmodifiable(_meetings));
    }
  }

  void _replaceTask(Task task) {
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i < 0) {
      _tasks = [..._tasks, task];
    } else {
      _tasks = [..._tasks]..[i] = task;
    }
    _emitTasks();
  }

  Task? _taskOrNull(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> _refresh() async {
    try {
      final results = await Future.wait([
        _api.fetchTasks(),
        _api.fetchMeetings(),
      ]);
      _tasks = results[0] as List<Task>;
      _meetings = [...results[1] as List<Meeting>]
        ..sort((a, b) => a.start.compareTo(b.start));
      _emitTasks();
      _emitMeetings();
    } catch (e, st) {
      // First load with no snapshot → surface the error so UI isn't a fake empty.
      if (_tasks.isEmpty && !_tasksController.isClosed) {
        _tasksController.addError(e, st);
      }
      if (_meetings.isEmpty && !_meetingsController.isClosed) {
        _meetingsController.addError(e, st);
      }
    }
  }

  /// Background reconcile — don't block the tap that already updated UI.
  void _refreshInBackground() {
    unawaited(_refresh());
  }

  @override
  Stream<List<Task>> watchTasks() {
    unawaited(_refresh());
    return Stream.multi((listener) {
      listener.add(_tasks);
      final sub = _tasksController.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = sub.cancel;
    });
  }

  @override
  Stream<List<Meeting>> watchMeetings() {
    unawaited(_refresh());
    return Stream.multi((listener) {
      listener.add(_meetings);
      final sub = _meetingsController.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = sub.cancel;
    });
  }

  @override
  Future<Task> createTask(TaskDraft draft, {required String actorId}) async {
    final task = await _api.createTask(
      title: draft.title,
      assigneeId: draft.assigneeId,
      assigneeIds: draft.assigneeIds,
      description: draft.description,
      statusId: draft.statusId,
      priorityId: draft.priorityId,
      dueDate: draft.dueDate!,
      tags: draft.tags,
      checklist: draft.checklist,
      externalAssignees: draft.externalAssignees,
    );
    _replaceTask(task);
    _refreshInBackground();
    return task;
  }

  @override
  Future<Task> updateTask(Task task, {required String actorId}) async {
    final updated = await _api.updateTask(task);
    _replaceTask(updated);
    return updated;
  }

  @override
  Future<Task> setStatus(
    String taskId,
    TaskStatus status, {
    required String actorId,
    String? statusId,
  }) async {
    final resolvedId = statusId ?? _resolveStatusId(status);
    final previous = _taskOrNull(taskId);

    // Optimistic: flip the checkbox immediately.
    if (previous != null) {
      _replaceTask(
        previous.copyWith(
          status: status,
          statusId: resolvedId.isNotEmpty ? resolvedId : previous.statusId,
        ),
      );
    }

    try {
      final updated = await _api.setStatus(taskId, resolvedId);
      _replaceTask(updated);
      return updated;
    } catch (e) {
      if (previous != null) _replaceTask(previous);
      rethrow;
    }
  }

  String _resolveStatusId(TaskStatus status) {
    final slug = switch (status) {
      TaskStatus.todo => 'todo',
      TaskStatus.inProgress => 'in_progress',
      TaskStatus.inReview => 'in_review',
      TaskStatus.done => 'done',
    };
    final config = _orgConfigGetter?.call();
    if (config != null) {
      final match = config.taskStatuses.where((s) => s.slug == slug).firstOrNull;
      if (match != null) return match.id;
    }
    return '';
  }

  @override
  Future<Task> toggleChecklistItem(String taskId, String itemId) async {
    final previous = _taskOrNull(taskId);

    if (previous != null) {
      final nextChecklist = [
        for (final item in previous.checklist)
          if (item.id == itemId) item.copyWith(done: !item.done) else item,
      ];
      _replaceTask(previous.copyWith(checklist: nextChecklist));
    }

    try {
      final updated = await _api.toggleChecklist(taskId, itemId);
      _replaceTask(updated);
      return updated;
    } catch (e) {
      if (previous != null) _replaceTask(previous);
      rethrow;
    }
  }

  @override
  Future<Task> addChecklistItem(String taskId, String label) async {
    final updated = await _api.addChecklistItem(taskId, label);
    _replaceTask(updated);
    return updated;
  }

  @override
  Future<Task> addComment(
    String taskId,
    String body, {
    required String actorId,
  }) async {
    final updated = await _api.addComment(taskId, body);
    _replaceTask(updated);
    return updated;
  }

  @override
  Future<void> deleteTask(String taskId) async {
    final previous = _tasks;
    _tasks = _tasks.where((t) => t.id != taskId).toList(growable: false);
    _emitTasks();
    try {
      await _api.deleteTask(taskId);
    } catch (e) {
      _tasks = previous;
      _emitTasks();
      rethrow;
    }
  }

  @override
  Future<Meeting> createMeeting(
    MeetingDraft draft, {
    required String actorId,
  }) async {
    final meeting = await _api.createMeeting(
      title: draft.title,
      start: draft.start,
      end: draft.end,
      attendeeIds: draft.attendeeIds,
      location: draft.location,
      notes: draft.notes,
      link: draft.link,
      isOnline: draft.isOnline,
      externalAttendees: draft.externalAttendees,
      recurrence: draft.recurrence,
      weekdays: draft.weekdays,
      taskId: draft.taskId,
    );
    _meetings = [..._meetings, meeting]..sort((a, b) => a.start.compareTo(b.start));
    _emitMeetings();
    return meeting;
  }

  @override
  Future<Meeting> updateMeeting(
    String meetingId,
    MeetingDraft draft, {
    required String actorId,
  }) async {
    final meeting = await _api.updateMeeting(
      meetingId,
      title: draft.title,
      start: draft.start,
      end: draft.end,
      attendeeIds: draft.attendeeIds,
      location: draft.location,
      notes: draft.notes,
      link: draft.link,
      isOnline: draft.isOnline,
      externalAttendees: draft.externalAttendees,
      recurrence: draft.recurrence,
      weekdays: draft.weekdays,
      taskId: draft.taskId,
    );
    final i = _meetings.indexWhere((m) => m.id == meetingId);
    if (i >= 0) {
      _meetings = [..._meetings]..[i] = meeting;
    } else {
      _meetings = [..._meetings, meeting];
    }
    _meetings.sort((a, b) => a.start.compareTo(b.start));
    _emitMeetings();
    return meeting;
  }

  @override
  Future<void> deleteMeeting(String meetingId) async {
    final previous = _meetings;
    _meetings = _meetings.where((m) => m.id != meetingId).toList(growable: false);
    _emitMeetings();
    try {
      await _api.deleteMeeting(meetingId);
    } catch (e) {
      _meetings = previous;
      _emitMeetings();
      rethrow;
    }
  }

  void dispose() {
    _tasksController.close();
    _meetingsController.close();
  }
}
