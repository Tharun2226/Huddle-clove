import '../../features/team/domain/activity_event.dart';
import '../../shared/utils/date_codec.dart';
import 'api_client.dart';

class ApiActivityRepository {
  ApiActivityRepository(this._client);

  final ApiClient _client;

  Future<List<ActivityEvent>> fetchActivity() async {
    final res = await _client.dio.get<List<dynamic>>('/activity');
    return [
      for (final row in res.data ?? const [])
        _map(row as Map<String, dynamic>),
    ];
  }

  ActivityEvent _map(Map<String, dynamic> json) {
    return ActivityEvent(
      id: json['id'] as String,
      actorId: json['actorId'] as String,
      type: _typeFrom(json['type'] as String),
      subject: json['subject'] as String,
      amount: json['amount'] != null ? (json['amount'] as num).toDouble() : null,
      targetId: json['targetId'] as String?,
      at: DateCodec.parseInstant(json['at'] as String?) ?? DateTime.now(),
    );
  }

  ActivityType _typeFrom(String v) => switch (v) {
    'taskCreated' => ActivityType.taskCreated,
    'taskCompleted' => ActivityType.taskCompleted,
    'taskMoved' => ActivityType.taskMoved,
    'taskCommented' => ActivityType.taskCommented,
    'expenseSubmitted' => ActivityType.expenseSubmitted,
    'expenseApproved' => ActivityType.expenseApproved,
    'expenseRejected' => ActivityType.expenseRejected,
    'expenseReimbursed' => ActivityType.expenseReimbursed,
    'meetingScheduled' => ActivityType.meetingScheduled,
    _ => ActivityType.taskMoved,
  };
}
