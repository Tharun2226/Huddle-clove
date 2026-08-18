import 'package:flutter/foundation.dart';

enum ActivityType {
  taskCreated,
  taskCompleted,
  taskMoved,
  taskCommented,
  expenseSubmitted,
  expenseApproved,
  expenseRejected,
  expenseReimbursed,
  meetingScheduled,
}

/// One line in the team activity feed: "Aisha completed task X",
/// "Rahul submitted ₹1,200 expense".
@immutable
class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.actorId,
    required this.type,
    required this.subject,
    required this.at,
    this.amount,
    this.targetId,
  });

  final String id;
  final String actorId;
  final ActivityType type;

  /// The thing acted upon — a task title or an expense merchant.
  final String subject;
  final DateTime at;
  final double? amount;
  final String? targetId;
}
