import 'package:flutter/foundation.dart';

/// How often a meeting repeats after its first [Meeting.start] day.
enum MeetingRecurrence {
  none('Does not repeat'),
  daily('Every day'),
  weekly('Selected weekdays');

  const MeetingRecurrence(this.label);
  final String label;

  static MeetingRecurrence fromApi(String? raw) => switch (raw) {
        'daily' => MeetingRecurrence.daily,
        'weekly' => MeetingRecurrence.weekly,
        _ => MeetingRecurrence.none,
      };

  String get apiValue => name;
}

/// Guest outside the organization.
@immutable
class ExternalAttendee {
  const ExternalAttendee({required this.name, this.email = ''});

  final String name;
  final String email;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (email.trim().isNotEmpty) 'email': email.trim(),
      };

  factory ExternalAttendee.fromJson(Map<String, dynamic> json) {
    return ExternalAttendee(
      name: (json['name'] as String?)?.trim() ?? '',
      email: (json['email'] as String?)?.trim() ?? '',
    );
  }
}

/// Calendar events shown alongside tasks. May be one-off or recurring.
@immutable
class Meeting {
  const Meeting({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.attendeeIds,
    this.location = '',
    this.notes = '',
    this.link = '',
    this.isOnline = true,
    this.externalAttendees = const [],
    this.recurrence = MeetingRecurrence.none,
    this.weekdays = const [],
    this.taskId,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final List<String> attendeeIds;
  final String location;
  final String notes;

  /// Join / redirect URL (Meet, Zoom, etc.) — for online meetings.
  final String link;

  /// Online uses [link]; in-person typically uses [location].
  final bool isOnline;

  /// People outside the org (name + optional email).
  final List<ExternalAttendee> externalAttendees;

  /// none | daily | weekly
  final MeetingRecurrence recurrence;

  /// Dart weekday numbers: 1=Mon … 7=Sun (used when [recurrence] is weekly).
  final List<int> weekdays;

  /// Optional related task.
  final String? taskId;

  Duration get duration => end.difference(start);

  bool get isLive {
    final now = DateTime.now();
    // Inclusive start, exclusive end — avoids a gap that labels as "In progress"
    // without counting as live or past.
    return !now.isBefore(start) && now.isBefore(end);
  }

  bool get isPast {
    final now = DateTime.now();
    return !now.isBefore(end);
  }

  /// True if this template fires on the calendar day of [day].
  bool occursOn(DateTime day) {
    final dayOnly = DateTime(day.year, day.month, day.day);
    final startDay = DateTime(start.year, start.month, start.day);
    if (dayOnly.isBefore(startDay)) return false;

    return switch (recurrence) {
      MeetingRecurrence.none =>
        start.year == day.year && start.month == day.month && start.day == day.day,
      MeetingRecurrence.daily => true,
      MeetingRecurrence.weekly => weekdays.contains(day.weekday),
    };
  }

  /// Legacy alias — prefer [occursOn] for recurrence-aware checks.
  bool isOn(DateTime day) => occursOn(day);

  /// Concrete instance for [day], shifting the template time-of-day onto that date.
  Meeting occurrenceOn(DateTime day) {
    if (recurrence == MeetingRecurrence.none) return this;
    final newStart = DateTime(
      day.year,
      day.month,
      day.day,
      start.hour,
      start.minute,
      start.second,
    );
    return Meeting(
      id: id,
      title: title,
      start: newStart,
      end: newStart.add(duration),
      attendeeIds: attendeeIds,
      location: location,
      notes: notes,
      link: link,
      isOnline: isOnline,
      externalAttendees: externalAttendees,
      recurrence: recurrence,
      weekdays: weekdays,
      taskId: taskId,
    );
  }

  /// Next occurrence that ends after [from], looking ahead up to [horizonDays].
  Meeting? nextAfter(DateTime from, {int horizonDays = 21}) {
    final fromDay = DateTime(from.year, from.month, from.day);
    for (var i = 0; i <= horizonDays; i++) {
      final day = fromDay.add(Duration(days: i));
      if (!occursOn(day)) continue;
      final occ = occurrenceOn(day);
      if (occ.end.isAfter(from)) return occ;
    }
    return null;
  }

  String get recurrenceSummary {
    switch (recurrence) {
      case MeetingRecurrence.none:
        return 'Does not repeat';
      case MeetingRecurrence.daily:
        return 'Every day';
      case MeetingRecurrence.weekly:
        if (weekdays.isEmpty) return 'Weekly';
        const names = {
          1: 'Mon',
          2: 'Tue',
          3: 'Wed',
          4: 'Thu',
          5: 'Fri',
          6: 'Sat',
          7: 'Sun',
        };
        final sorted = [...weekdays]..sort();
        return 'Every ${sorted.map((d) => names[d] ?? '$d').join(', ')}';
    }
  }
}

@immutable
class MeetingDraft {
  const MeetingDraft({
    required this.title,
    required this.start,
    required this.end,
    required this.attendeeIds,
    this.location = '',
    this.notes = '',
    this.link = '',
    this.isOnline = true,
    this.externalAttendees = const [],
    this.recurrence = MeetingRecurrence.none,
    this.weekdays = const [],
    this.taskId,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final List<String> attendeeIds;
  final String location;
  final String notes;
  final String link;
  final bool isOnline;
  final List<ExternalAttendee> externalAttendees;
  final MeetingRecurrence recurrence;
  final List<int> weekdays;
  final String? taskId;
}
