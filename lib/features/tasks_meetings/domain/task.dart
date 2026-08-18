import 'package:flutter/foundation.dart';

/// Maps onto ClickUp task statuses. Kept as a closed enum so the UI can switch
/// exhaustively; the ClickUp repository will translate custom status names into
/// these buckets when it lands.
enum TaskStatus {
  todo('To Do'),
  inProgress('In Progress'),
  inReview('In Review'),
  done('Complete');

  const TaskStatus(this.label);
  final String label;

  bool get isDone => this == TaskStatus.done;
}

enum TaskPriority {
  urgent('Urgent'),
  high('High'),
  normal('Normal'),
  low('Low');

  const TaskPriority(this.label);
  final String label;
}

@immutable
class ChecklistItem {
  const ChecklistItem({required this.id, required this.label, this.done = false});

  final String id;
  final String label;
  final bool done;

  ChecklistItem copyWith({String? label, bool? done}) =>
      ChecklistItem(id: id, label: label ?? this.label, done: done ?? this.done);
}

@immutable
class TaskComment {
  const TaskComment({
    required this.id,
    required this.authorId,
    required this.body,
    required this.createdAt,
    this.authorName,
  });

  final String id;
  final String authorId;
  final String? authorName;
  final String body;
  final DateTime createdAt;
}

@immutable
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.assigneeId,
    required this.createdAt,
    this.description = '',
    this.status = TaskStatus.todo,
    this.priority = TaskPriority.normal,
    this.statusId = '',
    this.priorityId = '',
    this.dueDate,
    this.assigneeName,
    this.assigneeIds = const [],
    this.assigneeNames = const [],
    this.externalAssignees = const [],
    this.checklist = const [],
    this.comments = const [],
    this.tags = const [],
  });

  final String id;
  final String title;
  final String description;
  final TaskStatus status;
  final TaskPriority priority;
  final String statusId;
  final String priorityId;
  final DateTime? dueDate;

  /// Primary assignee (first in [allAssigneeIds]).
  final String assigneeId;
  final String? assigneeName;

  /// All assignees including primary. Empty means fall back to [assigneeId].
  final List<String> assigneeIds;
  final List<String> assigneeNames;

  /// Free-text people outside the organization.
  final List<String> externalAssignees;

  final List<ChecklistItem> checklist;
  final List<TaskComment> comments;
  final List<String> tags;
  final DateTime createdAt;

  List<String> get allAssigneeIds {
    if (assigneeIds.isNotEmpty) return assigneeIds;
    if (externalAssignees.isNotEmpty) return const [];
    return assigneeId.isEmpty ? const [] : [assigneeId];
  }

  /// Org assignee names plus external names for display / share.
  List<String> get allPeopleNames {
    final names = <String>[
      ...assigneeNames.where((n) => n.trim().isNotEmpty),
      ...externalAssignees.where((n) => n.trim().isNotEmpty),
    ];
    if (names.isNotEmpty) return names;
    if (assigneeName != null && assigneeName!.trim().isNotEmpty) {
      return [assigneeName!.trim()];
    }
    return const [];
  }

  bool isAssignedTo(String userId) => allAssigneeIds.contains(userId);

  bool get isDone => status.isDone;

  bool get isOverdue {
    final due = dueDate;
    if (due == null || isDone) return false;
    return due.isBefore(DateTime.now());
  }

  int get checklistDone => checklist.where((c) => c.done).length;

  double get checklistProgress =>
      checklist.isEmpty ? 0 : checklistDone / checklist.length;

  bool isDueOn(DateTime day) {
    final due = dueDate?.toLocal();
    if (due == null) return false;
    final localDay = day.toLocal();
    return due.year == localDay.year &&
        due.month == localDay.month &&
        due.day == localDay.day;
  }

  Task copyWith({
    String? title,
    String? description,
    TaskStatus? status,
    TaskPriority? priority,
    String? statusId,
    String? priorityId,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? assigneeId,
    String? assigneeName,
    List<String>? assigneeIds,
    List<String>? assigneeNames,
    List<String>? externalAssignees,
    List<ChecklistItem>? checklist,
    List<TaskComment>? comments,
    List<String>? tags,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      statusId: statusId ?? this.statusId,
      priorityId: priorityId ?? this.priorityId,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      assigneeId: assigneeId ?? this.assigneeId,
      assigneeName: assigneeName ?? this.assigneeName,
      assigneeIds: assigneeIds ?? this.assigneeIds,
      assigneeNames: assigneeNames ?? this.assigneeNames,
      externalAssignees: externalAssignees ?? this.externalAssignees,
      checklist: checklist ?? this.checklist,
      comments: comments ?? this.comments,
      tags: tags ?? this.tags,
      createdAt: createdAt,
    );
  }
}

/// What the create/edit form hands to the repository. Separate from [Task] so
/// the repository owns id generation — the real ClickUp API assigns ids too.
@immutable
class TaskDraft {
  const TaskDraft({
    required this.title,
    required this.assigneeId,
    this.assigneeIds = const [],
    this.description = '',
    this.status = TaskStatus.todo,
    this.priority = TaskPriority.normal,
    this.statusId,
    this.priorityId,
    this.dueDate,
    this.tags = const [],
    this.checklist = const [],
    this.externalAssignees = const [],
  });

  final String title;
  final String description;
  final TaskStatus status;
  final TaskPriority priority;
  final String? statusId;
  final String? priorityId;
  final DateTime? dueDate;
  final String assigneeId;
  final List<String> assigneeIds;
  final List<String> tags;
  final List<String> checklist;
  final List<String> externalAssignees;

  List<String> get allAssigneeIds => assigneeIds;
}
