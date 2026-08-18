/// In-app notification model (mirrors Nest `AppNotification`).
enum NotificationType {
  expenseApproved,
  expenseRejected,
  expenseSubmitted,
  expenseComment,
  reminder,
  announcement,
  systemAlert,
  unknown;

  static NotificationType fromApi(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'EXPENSE_APPROVED':
        return NotificationType.expenseApproved;
      case 'EXPENSE_REJECTED':
        return NotificationType.expenseRejected;
      case 'EXPENSE_SUBMITTED':
        return NotificationType.expenseSubmitted;
      case 'EXPENSE_COMMENT':
        return NotificationType.expenseComment;
      case 'REMINDER':
        return NotificationType.reminder;
      case 'ANNOUNCEMENT':
        return NotificationType.announcement;
      case 'SYSTEM_ALERT':
        return NotificationType.systemAlert;
      default:
        return NotificationType.unknown;
    }
  }

  String get apiValue => switch (this) {
        NotificationType.expenseApproved => 'EXPENSE_APPROVED',
        NotificationType.expenseRejected => 'EXPENSE_REJECTED',
        NotificationType.expenseSubmitted => 'EXPENSE_SUBMITTED',
        NotificationType.expenseComment => 'EXPENSE_COMMENT',
        NotificationType.reminder => 'REMINDER',
        NotificationType.announcement => 'ANNOUNCEMENT',
        NotificationType.systemAlert => 'SYSTEM_ALERT',
        NotificationType.unknown => 'SYSTEM_ALERT',
      };
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.referenceId,
    this.referenceKind,
  });

  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final String? referenceId;
  final String? referenceKind;
  final bool isRead;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      type: NotificationType.fromApi(json['type'] as String?),
      referenceId: json['referenceId'] as String?,
      referenceKind: json['referenceKind'] as String?,
      isRead: json['isRead'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class NotificationListResult {
  const NotificationListResult({
    required this.unreadCount,
    required this.items,
  });

  final int unreadCount;
  final List<AppNotification> items;

  factory NotificationListResult.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List<dynamic>? ?? const [];
    return NotificationListResult(
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      items: [
        for (final row in raw)
          if (row is Map<String, dynamic>) AppNotification.fromJson(row),
      ],
    );
  }
}
