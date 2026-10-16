import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../shared/utils/formatters.dart';
import '../../tasks_meetings/domain/meeting.dart';
import '../../tasks_meetings/domain/task.dart';
import 'native_alarm.dart';
import 'push_notification_service.dart';

enum ReminderKind { task, meeting }

/// How a reminder alerts the user.
enum ReminderStyle {
  /// Normal notification at the reminder time.
  notification('Notification'),

  /// Alarm sound + full-screen alert at the reminder time, rings for 15 s
  /// or until stopped.
  alarm('Alarm'),

  /// Notification at the reminder time, then an alarm when it starts / is due.
  both('Both');

  const ReminderStyle(this.label);
  final String label;

  static ReminderStyle fromName(String? raw) => ReminderStyle.values
      .firstWhere((s) => s.name == raw, orElse: () => ReminderStyle.notification);
}

/// "Remind me" choices, in minutes before the due / start time.
const reminderOptions = <int?, String>{
  null: 'No reminder',
  0: 'At the time',
  5: '5 minutes before',
  10: '10 minutes before',
  15: '15 minutes before',
  30: '30 minutes before',
  60: '1 hour before',
  1440: '1 day before',
};

/// One saved reminder choice.
typedef ReminderSetting = ({
  int minutes,
  ReminderStyle style,
  DateTime savedAt,
});

/// On-device reminders for tasks and meetings.
///
/// Choices live only on this phone (secure storage). Every time the task /
/// meeting lists change, [sync] cancels what it scheduled before and
/// re-schedules from the latest due / start times, so edits, completions
/// and deletions are picked up automatically.
class ReminderService {
  ReminderService(this._push, {FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final PushNotificationService _push;
  final FlutterSecureStorage _storage;

  static const _settingsKey = 'huddle_reminders_v1';
  static const _scheduledKey = 'huddle_reminders_scheduled_v1';

  /// Keep a missing item's reminder this long — a just-created task may not
  /// be in the list yet.
  static const _pruneGrace = Duration(days: 1);

  /// Upcoming occurrences scheduled per recurring meeting.
  static const _maxOccurrences = 10;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Map<String, ReminderSetting>? _settings;
  List<Task> _tasks = const [];
  List<Meeting> _meetings = const [];
  bool _haveLists = false;
  bool _askedExact = false;
  Future<void> _queue = Future.value();

  static String _key(ReminderKind kind, String id) => '${kind.name}:$id';

  Future<ReminderSetting?> settingFor(ReminderKind kind, String id) async {
    if (!isSupported) return null;
    final settings = await _load();
    return settings[_key(kind, id)];
  }

  /// Sets (or clears, when [minutesBefore] is null) one reminder.
  /// Pass [task] / [meeting] right after saving so it is scheduled even
  /// before the list refreshes.
  Future<void> setReminder(
    ReminderKind kind,
    String id,
    int? minutesBefore, {
    ReminderStyle style = ReminderStyle.notification,
    Task? task,
    Meeting? meeting,
  }) async {
    if (task != null) {
      _tasks = [for (final t in _tasks) if (t.id != task.id) t, task];
    }
    if (meeting != null) {
      _meetings = [
        for (final m in _meetings) if (m.id != meeting.id) m,
        meeting,
      ];
    }
    await setEach(kind, {id: (minutes: minutesBefore, style: style)});
  }

  /// Same reminder for every id in [ids].
  Future<void> setReminders(
    ReminderKind kind,
    Iterable<String> ids,
    int? minutesBefore, {
    ReminderStyle style = ReminderStyle.notification,
  }) =>
      setEach(kind, {
        for (final id in ids) id: (minutes: minutesBefore, style: style),
      });

  /// A different reminder per id (null minutes clears it), saved and
  /// scheduled in one pass.
  Future<void> setEach(
    ReminderKind kind,
    Map<String, ({int? minutes, ReminderStyle style})> choices,
  ) async {
    if (!isSupported || choices.isEmpty) return;
    // Never let a reminder problem fail the task / meeting save.
    try {
      final settings = await _load();
      final now = DateTime.now();
      for (final e in choices.entries) {
        final key = _key(kind, e.key);
        final minutes = e.value.minutes;
        if (minutes == null) {
          settings.remove(key);
        } else {
          settings[key] = (minutes: minutes, style: e.value.style, savedAt: now);
        }
      }
      await _save(settings);
      if (choices.values.any((c) => c.minutes != null)) {
        await _requestPermissions();
      }
    } catch (e) {
      debugPrint('Could not save reminder: $e');
      return;
    }
    if (_haveLists) await _enqueue(_reschedule);
  }

  /// Called whenever the task / meeting lists change.
  Future<void> sync({
    required List<Task> tasks,
    required List<Meeting> meetings,
  }) {
    if (!isSupported) return Future.value();
    _tasks = tasks;
    _meetings = meetings;
    _haveLists = true;
    return _enqueue(_reschedule);
  }

  Future<void> _enqueue(Future<void> Function() job) {
    final next = _queue.then((_) => job()).catchError((Object e) {
      debugPrint('Reminder sync failed: $e');
    });
    _queue = next;
    return next;
  }

  Future<void> _reschedule() async {
    await _push.ensureLocalInitialized();
    final local = _push.local;
    final settings = await _load();

    for (final id in await _loadScheduled()) {
      await local.cancel(id: id);
    }
    await NativeAlarm.cancelAll();

    final android = local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final exact = await android?.canScheduleExactNotifications() ?? false;
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    final now = DateTime.now();
    final tasksById = {for (final t in _tasks) t.id: t};
    final meetingsById = {for (final m in _meetings) m.id: m};
    final scheduled = <int>[];
    final stale = <String>[];

    Future<void> schedule({
      required String key,
      required DateTime fireAt,
      required bool alarm,
      required String title,
      required String body,
      required ReminderKind kind,
      required String id,
    }) async {
      if (!fireAt.isAfter(now)) return;
      final notificationId = _stableId(
        '$key|${fireAt.millisecondsSinceEpoch}|${alarm ? 'a' : 'n'}',
      );
      final payload = jsonEncode({
        'type': 'REMINDER',
        'referenceId': id,
        'referenceKind': kind.name,
      });
      if (alarm) {
        // Real alarm (alarm stream, full-screen, power / volume to stop) —
        // a notification sound gets downgraded while the phone is in use.
        await NativeAlarm.schedule(
          id: notificationId,
          at: fireAt,
          title: title,
          body: body,
          payload: payload,
        );
        return;
      }
      await local.zonedSchedule(
        id: notificationId,
        scheduledDate: tz.TZDateTime.from(fireAt.toUtc(), tz.UTC),
        notificationDetails: const NotificationDetails(
          android: _notificationDetails,
        ),
        androidScheduleMode: mode,
        title: title,
        body: body,
        payload: payload,
      );
      scheduled.add(notificationId);
    }

    /// Schedules [setting] against one due / start time.
    Future<void> scheduleFor({
      required String key,
      required ReminderSetting setting,
      required DateTime at,
      required String title,
      required String verb,
      required ReminderKind kind,
      required String id,
    }) async {
      final offset = Duration(minutes: setting.minutes);
      final remindAt = at.subtract(offset);
      switch (setting.style) {
        case ReminderStyle.notification:
        case ReminderStyle.alarm:
          await schedule(
            key: key,
            fireAt: remindAt,
            alarm: setting.style == ReminderStyle.alarm,
            title: title,
            body: _whenText(verb, at, offset),
            kind: kind,
            id: id,
          );
        case ReminderStyle.both:
          // Heads-up first, alarm when it actually starts. With "At the
          // time" both would land together, so only the alarm rings.
          if (offset > Duration.zero) {
            await schedule(
              key: key,
              fireAt: remindAt,
              alarm: false,
              title: title,
              body: _whenText(verb, at, offset),
              kind: kind,
              id: id,
            );
          }
          await schedule(
            key: key,
            fireAt: at,
            alarm: true,
            title: title,
            body: _whenText(verb, at, Duration.zero),
            kind: kind,
            id: id,
          );
      }
    }

    for (final entry in settings.entries) {
      final sep = entry.key.indexOf(':');
      if (sep < 0) continue;
      final kindName = entry.key.substring(0, sep);
      final id = entry.key.substring(sep + 1);
      final setting = entry.value;
      final missingTooLong = now.difference(setting.savedAt) > _pruneGrace;

      if (kindName == ReminderKind.task.name) {
        final task = tasksById[id];
        if (task == null) {
          if (missingTooLong) stale.add(entry.key);
          continue;
        }
        final due = task.dueDate?.toLocal();
        if (due == null || task.isDone) continue;
        await scheduleFor(
          key: entry.key,
          setting: setting,
          at: due,
          title: 'Task: ${task.title}',
          verb: 'Due',
          kind: ReminderKind.task,
          id: id,
        );
      } else if (kindName == ReminderKind.meeting.name) {
        final meeting = meetingsById[id];
        if (meeting == null) {
          if (missingTooLong) stale.add(entry.key);
          continue;
        }
        // Earliest alert is `minutes` before start, so look from now + that.
        final from = now.add(Duration(minutes: setting.minutes));
        final starts = setting.style == ReminderStyle.both
            ? _upcomingStarts(meeting, now)
            : _upcomingStarts(meeting, from);
        for (final start in starts) {
          await scheduleFor(
            key: entry.key,
            setting: setting,
            at: start,
            title: 'Meeting: ${meeting.title}',
            verb: 'Starts',
            kind: ReminderKind.meeting,
            id: id,
          );
        }
      }
    }

    if (stale.isNotEmpty) {
      for (final key in stale) {
        settings.remove(key);
      }
      await _save(settings);
    }
    await _storage.write(key: _scheduledKey, value: jsonEncode(scheduled));
  }

  static const _notificationDetails = AndroidNotificationDetails(
    PushNotificationService.reminderChannelId,
    PushNotificationService.reminderChannelName,
    channelDescription: 'Task and meeting reminders you set on this phone',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    icon: '@mipmap/ic_launcher',
  );

  /// Start times after [after], covering repeats for the next two weeks.
  List<DateTime> _upcomingStarts(Meeting meeting, DateTime after) {
    final start = meeting.start.toLocal();
    if (meeting.recurrence == MeetingRecurrence.none) {
      return start.isAfter(after) ? [start] : const [];
    }
    final out = <DateTime>[];
    final firstDay = DateTime(after.year, after.month, after.day);
    for (var i = 0; i <= 14 && out.length < _maxOccurrences; i++) {
      final day = firstDay.add(Duration(days: i));
      if (!meeting.occursOn(day)) continue;
      final occ = meeting.occurrenceOn(day).start.toLocal();
      if (occ.isAfter(after)) out.add(occ);
    }
    return out;
  }

  String _whenText(String verb, DateTime at, Duration offset) {
    final time = Fmt.time(at);
    if (offset == Duration.zero) return '$verb now ($time)';
    final mins = offset.inMinutes;
    final lead = mins >= 1440 && mins % 1440 == 0
        ? '${mins ~/ 1440} day${mins == 1440 ? '' : 's'}'
        : mins >= 60 && mins % 60 == 0
            ? '${mins ~/ 60} hour${mins == 60 ? '' : 's'}'
            : '$mins min';
    return '$verb in $lead · ${Fmt.friendlyDate(at)}, $time';
  }

  Future<void> _requestPermissions() async {
    await _push.ensureLocalInitialized();
    final android = _push.local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.requestNotificationsPermission();
    // Exact timing needs "Alarms & reminders" on Android 12+. Without it the
    // reminder still fires, just possibly a few minutes late.
    if (_askedExact) return;
    _askedExact = true;
    final exact = await android.canScheduleExactNotifications() ?? true;
    if (!exact) await android.requestExactAlarmsPermission();
  }

  Future<Map<String, ReminderSetting>> _load() async {
    final cached = _settings;
    if (cached != null) return cached;
    final out = <String, ReminderSetting>{};
    try {
      final raw = await _storage.read(key: _settingsKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in map.entries) {
          final v = e.value as Map<String, dynamic>;
          out[e.key] = (
            minutes: (v['m'] as num).toInt(),
            style: ReminderStyle.fromName(v['s'] as String?),
            savedAt: DateTime.fromMillisecondsSinceEpoch(
              (v['t'] as num).toInt(),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Could not read reminders: $e');
    }
    return _settings = out;
  }

  Future<void> _save(Map<String, ReminderSetting> settings) async {
    _settings = settings;
    await _storage.write(
      key: _settingsKey,
      value: jsonEncode({
        for (final e in settings.entries)
          e.key: {
            'm': e.value.minutes,
            's': e.value.style.name,
            't': e.value.savedAt.millisecondsSinceEpoch,
          },
      }),
    );
  }

  Future<List<int>> _loadScheduled() async {
    try {
      final raw = await _storage.read(key: _scheduledKey);
      if (raw == null || raw.isEmpty) return const [];
      return [for (final v in jsonDecode(raw) as List<dynamic>) (v as num).toInt()];
    } catch (_) {
      return const [];
    }
  }

  /// FNV-1a, masked to a positive 31-bit notification id. Stable across runs
  /// (unlike [String.hashCode]).
  static int _stableId(String s) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(s)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }
}
