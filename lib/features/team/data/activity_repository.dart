import '../domain/activity_event.dart';

/// Write side of the feed. Task/expense repositories depend on this narrow
/// interface rather than the whole repository so they can only append.
abstract interface class ActivityRecorder {
  void record({
    required String actorId,
    required ActivityType type,
    required String subject,
    double? amount,
    String? targetId,
  });
}

abstract interface class ActivityRepository {
  Stream<List<ActivityEvent>> watchActivity();
}
