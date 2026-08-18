import 'dart:async';

import '../../../features/team/data/activity_repository.dart';
import '../../../features/team/domain/activity_event.dart';
import 'api_activity_repository.dart';

class HttpActivityRepository implements ActivityRepository, ActivityRecorder {
  HttpActivityRepository(this._api);

  final ApiActivityRepository _api;
  final _controller = StreamController<List<ActivityEvent>>.broadcast();
  List<ActivityEvent> _events = const [];

  Future<void> _refresh() async {
    try {
      final list = await _api.fetchActivity();
      _events = [...list]..sort((a, b) => b.at.compareTo(a.at));
      _controller.add(_events);
    } catch (_) {}
  }

  @override
  Stream<List<ActivityEvent>> watchActivity() {
    unawaited(_refresh());
    return Stream.multi((listener) {
      listener.add(_events);
      final sub = _controller.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = sub.cancel;
    });
  }

  @override
  void record({
    required String actorId,
    required ActivityType type,
    required String subject,
    double? amount,
    String? targetId,
  }) {
    // Server records activity on mutations; local append is best-effort.
    _events = [
      ActivityEvent(
        id: 'local_${DateTime.now().microsecondsSinceEpoch}',
        actorId: actorId,
        type: type,
        subject: subject,
        amount: amount,
        targetId: targetId,
        at: DateTime.now(),
      ),
      ..._events,
    ];
    _controller.add(_events);
  }

  void dispose() {
    _controller.close();
  }
}
