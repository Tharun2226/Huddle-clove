import '../../../../shared/utils/date_codec.dart';

class TaskImportRowPayload {
  const TaskImportRowPayload({
    required this.title,
    required this.dueDate,
    this.description = '',
    this.assignees = '',
    this.priority = '',
    this.status = '',
  });

  final String title;
  final String description;
  final DateTime dueDate;
  final String assignees;
  final String priority;
  final String status;

  TaskImportRowPayload copyWith({
    String? priority,
    String? status,
  }) {
    return TaskImportRowPayload(
      title: title,
      description: description,
      dueDate: dueDate,
      assignees: assignees,
      priority: priority ?? this.priority,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'dueDate': DateCodec.encodeInstant(dueDate),
        if (assignees.trim().isNotEmpty) 'assignees': assignees.trim(),
        if (priority.trim().isNotEmpty) 'priority': priority.trim(),
        if (status.trim().isNotEmpty) 'status': status.trim(),
      };
}
