import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../features/tasks_meetings/domain/meeting.dart';
import '../../features/tasks_meetings/domain/task.dart';
import '../../shared/utils/date_codec.dart';
import 'api_client.dart';

class TaskImportFailure {
  const TaskImportFailure({
    required this.row,
    required this.title,
    required this.error,
  });

  final int row;
  final String title;
  final String error;

  factory TaskImportFailure.fromJson(Map<String, dynamic> json) =>
      TaskImportFailure(
        row: (json['row'] as num?)?.toInt() ?? 0,
        title: (json['title'] as String?) ?? '',
        error: (json['error'] as String?) ?? 'Unknown error',
      );
}

class TaskImportResult {
  const TaskImportResult({
    required this.createdCount,
    required this.failedCount,
    required this.failed,
  });

  final int createdCount;
  final int failedCount;
  final List<TaskImportFailure> failed;

  factory TaskImportResult.fromJson(Map<String, dynamic> json) =>
      TaskImportResult(
        createdCount: (json['createdCount'] as num?)?.toInt() ?? 0,
        failedCount: (json['failedCount'] as num?)?.toInt() ?? 0,
        failed: [
          for (final row in (json['failed'] as List<dynamic>? ?? const []))
            if (row is Map<String, dynamic>) TaskImportFailure.fromJson(row),
        ],
      );
}

class TaskMappers {
  static TaskStatus statusFrom(String slug) => switch (slug) {
    'in_progress' || 'inProgress' || 'IN_PROGRESS' => TaskStatus.inProgress,
    'in_review' || 'inReview' || 'IN_REVIEW' => TaskStatus.inReview,
    'done' || 'DONE' => TaskStatus.done,
    _ => TaskStatus.todo,
  };

  static TaskPriority priorityFrom(String slug) => switch (slug.toLowerCase()) {
    'urgent' => TaskPriority.urgent,
    'high' => TaskPriority.high,
    'low' => TaskPriority.low,
    _ => TaskPriority.normal,
  };

  static Task taskFromJson(Map<String, dynamic> json) {
    final statusSlug = (json['statusSlug'] as String?) ?? (json['status'] as String?) ?? 'todo';
    final prioritySlug = (json['prioritySlug'] as String?) ?? (json['priority'] as String?) ?? 'normal';
    final primaryId = json['assigneeId'] as String;
    final assigneeIds = [
      for (final id in (json['assigneeIds'] as List<dynamic>? ?? const []))
        id as String,
    ];
    final externalAssignees = [
      for (final n in (json['externalAssignees'] as List<dynamic>? ?? const []))
        if (n is String)
          n
        else if (n is Map && n['name'] != null)
          '${n['name']}',
    ].map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    // Keep empty when only external people — don't treat DB owner as assignee.
    final resolvedIds = assigneeIds.isNotEmpty
        ? assigneeIds
        : externalAssignees.isNotEmpty
            ? const <String>[]
            : [primaryId];
    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      description: (json['description'] as String?) ?? '',
      status: statusFrom(statusSlug),
      priority: priorityFrom(prioritySlug),
      statusId: (json['statusId'] as String?) ?? '',
      priorityId: (json['priorityId'] as String?) ?? '',
      dueDate: DateCodec.parseInstant(json['dueDate'] as String?),
      assigneeId: primaryId,
      assigneeName: json['assigneeName'] as String?,
      assigneeIds: resolvedIds,
      assigneeNames: [
        for (final n in (json['assigneeNames'] as List<dynamic>? ?? const []))
          n as String,
      ],
      externalAssignees: externalAssignees,
      tags: [
        for (final t in (json['tags'] as List<dynamic>? ?? const []))
          t as String,
      ],
      createdAt: DateCodec.parseInstant(json['createdAt'] as String?) ??
          DateTime.now(),
      checklist: [
        for (final c in (json['checklist'] as List<dynamic>? ?? const []))
          ChecklistItem(
            id: (c as Map<String, dynamic>)['id'] as String,
            label: c['label'] as String,
            done: c['done'] as bool? ?? false,
          ),
      ],
      comments: [
        for (final c in (json['comments'] as List<dynamic>? ?? const []))
          TaskComment(
            id: (c as Map<String, dynamic>)['id'] as String,
            authorId: c['authorId'] as String,
            authorName: c['authorName'] as String?,
            body: c['body'] as String,
            createdAt: DateCodec.parseInstant(c['createdAt'] as String?) ??
                DateTime.now(),
          ),
      ],
    );
  }

  static Meeting meetingFromJson(Map<String, dynamic> json) {
    final guestsRaw = json['externalAttendees'];
    return Meeting(
      id: json['id'] as String,
      title: json['title'] as String,
      // Keep wall-clock times in local so “today” / recurrence match the UI.
      start: DateCodec.parseInstant(json['start'] as String?) ?? DateTime.now(),
      end: DateCodec.parseInstant(json['end'] as String?) ?? DateTime.now(),
      attendeeIds: [
        for (final id in (json['attendeeIds'] as List<dynamic>? ?? const []))
          id as String,
      ],
      location: (json['location'] as String?) ?? '',
      notes: (json['notes'] as String?) ?? '',
      link: (json['link'] as String?) ?? '',
      isOnline: json['isOnline'] as bool? ?? true,
      externalAttendees: [
        if (guestsRaw is List)
          for (final row in guestsRaw)
            if (row is Map<String, dynamic>)
              ExternalAttendee.fromJson(row),
      ],
      recurrence: MeetingRecurrence.fromApi(json['recurrence'] as String?),
      weekdays: [
        for (final d in (json['weekdays'] as List<dynamic>? ?? const []))
          (d as num).toInt(),
      ],
      taskId: json['taskId'] as String?,
    );
  }
}

class ApiTaskRepository {
  ApiTaskRepository(this._client);

  final ApiClient _client;

  Future<List<Task>> fetchTasks() async {
    final res = await _client.dio.get<List<dynamic>>('/tasks');
    return [
      for (final row in res.data ?? const [])
        TaskMappers.taskFromJson(row as Map<String, dynamic>),
    ];
  }

  Future<List<Meeting>> fetchMeetings() async {
    final res = await _client.dio.get<List<dynamic>>('/meetings');
    return [
      for (final row in res.data ?? const [])
        TaskMappers.meetingFromJson(row as Map<String, dynamic>),
    ];
  }

  Future<Task> createTask({
    required String title,
    required String assigneeId,
    List<String> assigneeIds = const [],
    String description = '',
    String? statusId,
    String? priorityId,
    required DateTime dueDate,
    List<String> tags = const [],
    List<String> checklist = const [],
    List<String> externalAssignees = const [],
  }) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/tasks',
      data: {
        'title': title,
        'description': description,
        'assigneeId': assigneeIds.isNotEmpty ? assigneeIds.first : assigneeId,
        'assigneeIds': assigneeIds,
        if (statusId != null) 'statusId': statusId,
        if (priorityId != null) 'priorityId': priorityId,
        'dueDate': DateCodec.encodeInstant(dueDate),
        'tags': tags,
        if (checklist.isNotEmpty) 'checklist': checklist,
        'externalAssignees': externalAssignees,
      },
    );
    return TaskMappers.taskFromJson(res.data!);
  }

  Future<TaskImportResult> importTasks(List<Map<String, dynamic>> rows) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/tasks/import',
      data: {'rows': rows},
    );
    final data = res.data ?? const <String, dynamic>{};
    return TaskImportResult.fromJson(data);
  }

  Future<({Uint8List bytes, String fileName})> downloadImportTemplate() async {
    final res = await _client.dio.get<List<int>>(
      '/tasks/import/template',
      options: Options(responseType: ResponseType.bytes),
    );
    final raw = res.data ?? const <int>[];
    final bytes = Uint8List.fromList(raw);
    final disposition = res.headers.value('content-disposition') ?? '';
    final match = RegExp(r'filename="?([^"]+)"?').firstMatch(disposition);
    final fileName = match?.group(1) ?? 'tasks import sheet.xlsx';
    return (bytes: bytes, fileName: fileName);
  }

  Future<Task> updateTask(Task task) async {
    final ids = task.allAssigneeIds;
    final res = await _client.dio.patch<Map<String, dynamic>>(
      '/tasks/${task.id}',
      data: {
        'title': task.title,
        'description': task.description,
        'assigneeId': ids.isNotEmpty ? ids.first : task.assigneeId,
        'assigneeIds': ids,
        if (task.statusId.isNotEmpty) 'statusId': task.statusId,
        if (task.priorityId.isNotEmpty) 'priorityId': task.priorityId,
        'dueDate': task.dueDate == null
            ? null
            : DateCodec.encodeInstant(task.dueDate!),
        'tags': task.tags,
        'externalAssignees': task.externalAssignees,
      },
    );
    return TaskMappers.taskFromJson(res.data!);
  }

  Future<Task> setStatus(String taskId, String statusId) async {
    final res = await _client.dio.patch<Map<String, dynamic>>(
      '/tasks/$taskId',
      data: {'statusId': statusId},
    );
    return TaskMappers.taskFromJson(res.data!);
  }

  Future<Task> toggleChecklist(String taskId, String itemId) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/tasks/$taskId/checklist/$itemId/toggle',
    );
    return TaskMappers.taskFromJson(res.data!);
  }

  Future<Task> addChecklistItem(String taskId, String label) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/tasks/$taskId/checklist',
      data: {'label': label},
    );
    return TaskMappers.taskFromJson(res.data!);
  }

  Future<Task> addComment(String taskId, String body) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/tasks/$taskId/comments',
      data: {'body': body},
    );
    return TaskMappers.taskFromJson(res.data!);
  }

  Future<void> deleteTask(String taskId) async {
    await _client.dio.delete('/tasks/$taskId');
  }

  Future<Meeting> createMeeting({
    required String title,
    required DateTime start,
    required DateTime end,
    required List<String> attendeeIds,
    String location = '',
    String notes = '',
    String link = '',
    bool isOnline = true,
    List<ExternalAttendee> externalAttendees = const [],
    MeetingRecurrence recurrence = MeetingRecurrence.none,
    List<int> weekdays = const [],
    String? taskId,
  }) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/meetings',
      data: {
        'title': title,
        'start': DateCodec.encodeInstant(start),
        'end': DateCodec.encodeInstant(end),
        'attendeeIds': attendeeIds,
        'location': location,
        'notes': notes,
        'link': isOnline ? link : '',
        'isOnline': isOnline,
        'externalAttendees': [
          for (final g in externalAttendees) g.toJson(),
        ],
        'recurrence': recurrence.apiValue,
        if (recurrence == MeetingRecurrence.weekly) 'weekdays': weekdays,
        if (taskId != null) 'taskId': taskId,
      },
    );
    return TaskMappers.meetingFromJson(res.data!);
  }

  Future<Meeting> updateMeeting(
    String meetingId, {
    required String title,
    required DateTime start,
    required DateTime end,
    required List<String> attendeeIds,
    String location = '',
    String notes = '',
    String link = '',
    bool isOnline = true,
    List<ExternalAttendee> externalAttendees = const [],
    MeetingRecurrence recurrence = MeetingRecurrence.none,
    List<int> weekdays = const [],
    String? taskId,
  }) async {
    final res = await _client.dio.patch<Map<String, dynamic>>(
      '/meetings/$meetingId',
      data: {
        'title': title,
        'start': DateCodec.encodeInstant(start),
        'end': DateCodec.encodeInstant(end),
        'attendeeIds': attendeeIds,
        'location': location,
        'notes': notes,
        'link': isOnline ? link : '',
        'isOnline': isOnline,
        'externalAttendees': [
          for (final g in externalAttendees) g.toJson(),
        ],
        'recurrence': recurrence.apiValue,
        if (recurrence == MeetingRecurrence.weekly) 'weekdays': weekdays,
        if (taskId != null) 'taskId': taskId,
      },
    );
    return TaskMappers.meetingFromJson(res.data!);
  }

  Future<void> deleteMeeting(String meetingId) async {
    await _client.dio.delete('/meetings/$meetingId');
  }
}
