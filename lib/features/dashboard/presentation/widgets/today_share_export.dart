import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../shared/utils/formatters.dart';
import '../../../tasks_meetings/domain/meeting.dart';
import '../../../tasks_meetings/domain/task.dart';
import '../../../tasks_meetings/presentation/providers/task_providers.dart';

/// Snapshot of Today used to build Excel / PNG exports.
class TodayShareData {
  const TodayShareData({
    required this.userName,
    required this.date,
    required this.meetings,
    required this.dueToday,
    required this.overdue,
    required this.timeline,
    required this.peopleNames,
    this.nextMeeting,
    this.showTags = true,
  });

  final String userName;
  final DateTime date;
  final List<Meeting> meetings;
  final List<Task> dueToday;
  final List<Task> overdue;
  final List<AgendaEntry> timeline;
  final Meeting? nextMeeting;
  final bool showTags;

  /// userId → display name for resolving attendees / assignees.
  final Map<String, String> peopleNames;

  String get fileStem {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return 'huddle-today-$y$m$d';
  }

  String get shareSubject =>
      '${Fmt.weekdayLong(date)} schedules and meetings';

  String personName(String id) => peopleNames[id] ?? id;

  String peopleList(Iterable<String> ids) {
    final names = ids.map(personName).where((n) => n.trim().isNotEmpty).toList();
    return names.isEmpty ? '—' : names.join(', ');
  }

  String taskAssignees(Task task) {
    final names = task.allPeopleNames;
    if (names.isNotEmpty) return names.join(', ');
    final fromIds = peopleList(task.allAssigneeIds);
    if (fromIds != '—') return fromIds;
    return 'Unassigned';
  }

  String taskTags(Task task) =>
      task.tags.isEmpty ? '—' : task.tags.join(', ');

  String meetingAttendees(Meeting meeting) {
    final names = meeting.isOnline
        ? meeting.attendeeIds.map(personName)
        : meeting.externalAttendees.map((e) => e.name.trim());
    final cleaned = names.where((n) => n.trim().isNotEmpty).toList();
    // De-dupe while preserving order.
    final seen = <String>{};
    final unique = <String>[];
    for (final n in cleaned) {
      final key = n.toLowerCase();
      if (seen.add(key)) unique.add(n);
    }
    return unique.isEmpty ? '—' : unique.join(', ');
  }
}

Future<File> _writeTempBytes(String name, List<int> bytes) async {
  // dart:io temp avoids path_provider MissingPluginException.
  final file = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}$name',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<void> shareTodayAsExcel(TodayShareData data) async {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet()!;
  excel.rename(defaultSheet, 'Meetings');

  String relatedTaskTitle(Meeting m) {
    final id = m.taskId;
    if (id == null || id.isEmpty) return '—';
    for (final t in [...data.dueToday, ...data.overdue]) {
      if (t.id == id) return t.title;
    }
    for (final entry in data.timeline) {
      if (entry case TaskEntry(:final task) when task.id == id) {
        return task.title;
      }
    }
    return id;
  }

  String meetingStatus(Meeting m) {
    if (m.isLive) return 'Live now';
    if (m.isPast) return 'Past';
    return 'Upcoming';
  }

  final meetings = excel['Meetings'];
  const meetingHeaders = [
    'Title',
    'Date',
    'Starts',
    'Ends',
    'Duration',
    'Status',
    'Location',
    'Meeting link',
    'Attendees',
    'Attendee count',
    'Repeats',
    'Notes',
    'Related task',
  ];
  final meetingsByTime = [...data.meetings]
    ..sort((a, b) => a.start.compareTo(b.start));
  _writeRows(meetings, [
    meetingHeaders,
    for (final m in meetingsByTime)
      [
        m.title,
        Fmt.dayMonthYear(m.start),
        Fmt.time(m.start),
        Fmt.time(m.end),
        Fmt.duration(m.duration),
        meetingStatus(m),
        m.location.isEmpty ? '—' : m.location,
        m.link.isEmpty ? '—' : m.link,
        data.meetingAttendees(m),
        '${m.isOnline ? m.attendeeIds.length : m.externalAttendees.length}',
        m.recurrenceSummary,
        m.notes.isEmpty ? '—' : m.notes,
        relatedTaskTitle(m),
      ],
  ], headerRows: {0});

  int byDueTime(Task a, Task b) {
    final ad = a.dueDate;
    final bd = b.dueDate;
    if (ad == null && bd == null) return a.title.compareTo(b.title);
    if (ad == null) return 1;
    if (bd == null) return -1;
    final cmp = ad.compareTo(bd);
    return cmp != 0 ? cmp : a.title.compareTo(b.title);
  }

  final dueTodaySorted = [...data.dueToday]..sort(byDueTime);
  final overdueSorted = [...data.overdue]..sort(byDueTime);

  List<String> taskRow(Task t, {required bool overdue}) => [
        t.title,
        t.description.trim().isEmpty ? '—' : t.description.trim(),
        t.status.label,
        t.priority.label,
        t.dueDate == null
            ? '—'
            : overdue
                ? Fmt.dayMonthYear(t.dueDate!)
                : '${Fmt.friendlyDate(t.dueDate!)} ${Fmt.time(t.dueDate!)}',
        data.taskAssignees(t),
        if (data.showTags) data.taskTags(t),
        t.checklist.isEmpty
            ? '—'
            : '${t.checklistDone}/${t.checklist.length} done',
        t.checklist.isEmpty
            ? '—'
            : t.checklist
                .map((c) => '${c.done ? '✓' : '○'} ${c.label}')
                .join(' | '),
        '${t.comments.length}',
      ];

  final taskHeaders = [
    'Title',
    'Description',
    'Status',
    'Priority',
    'Due',
    'Assignees',
    if (data.showTags) 'Tags',
    'Checklist',
    'Checklist items',
    'Comments',
  ];

  final due = excel['Due today'];
  _writeRows(due, [
    taskHeaders,
    for (final t in dueTodaySorted) taskRow(t, overdue: false),
  ], headerRows: {0});

  final overdue = excel['Overdue'];
  _writeRows(overdue, [
    taskHeaders,
    for (final t in overdueSorted) taskRow(t, overdue: true),
  ], headerRows: {0});

  // Drop any leftover default sheets besides the three we want.
  for (final name in excel.tables.keys.toList()) {
    if (name != 'Meetings' && name != 'Due today' && name != 'Overdue') {
      excel.delete(name);
    }
  }

  _autoWidth(meetings, meetingHeaders.length);
  _autoWidth(due, taskHeaders.length);
  _autoWidth(overdue, taskHeaders.length);

  final bytes = excel.save();
  if (bytes == null) {
    throw StateError('Could not build Excel file');
  }

  final file = await _writeTempBytes('${data.fileStem}.xlsx', bytes);
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile(
          file.path,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: '${data.fileStem}.xlsx',
        ),
      ],
      fileNameOverrides: ['${data.fileStem}.xlsx'],
      subject: data.shareSubject,
      text: data.shareSubject,
    ),
  );
}

void _writeRows(
  Sheet sheet,
  List<List<String>> rows, {
  Set<int> headerRows = const {},
}) {
  final headerStyle = CellStyle(bold: true);
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
      );
      cell.value = TextCellValue(rows[r][c]);
      if (headerRows.contains(r)) {
        cell.cellStyle = headerStyle;
      }
    }
  }
}

void _autoWidth(Sheet sheet, int columns) {
  for (var c = 0; c < columns; c++) {
    sheet.setColumnWidth(c, c == 0 ? 18 : (c == 1 ? 28 : 16));
  }
}

Future<void> shareTodayAsPng(
  BuildContext context,
  TodayShareData data,
) async {
  final bytes = await _captureTodayPng(context, data);
  final file = await _writeTempBytes('${data.fileStem}.png', bytes);
  if (!context.mounted) return;
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile(
          file.path,
          mimeType: 'image/png',
          name: '${data.fileStem}.png',
        ),
      ],
      fileNameOverrides: ['${data.fileStem}.png'],
      subject: data.shareSubject,
      text: data.shareSubject,
    ),
  );
}

Future<Uint8List> _captureTodayPng(
  BuildContext context,
  TodayShareData data,
) async {
  final key = GlobalKey();
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) {
      return Positioned(
        left: -8000,
        top: 0,
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: 980,
            child: RepaintBoundary(
              key: key,
              child: _TodaySharePoster(data: data),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);
  // Give fonts / layout time to settle so the capture is sharp.
  await Future<void>.delayed(const Duration(milliseconds: 80));
  await WidgetsBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(milliseconds: 120));
  await WidgetsBinding.instance.endOfFrame;

  try {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('Could not render Today image');
    }
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Could not encode PNG');
    }
    return byteData.buffer.asUint8List();
  } finally {
    entry.remove();
  }
}

/// Formal schedule-table poster for the PNG share.
/// Meetings on top, tasks below — inspired by a day agenda grid.
class _TodaySharePoster extends StatelessWidget {
  const _TodaySharePoster({required this.data});

  final TodayShareData data;

  // Formal schedule palette — navy + soft priority tints, dark readable text.
  static const _ink = Color(0xFF0F172A);
  static const _border = Color(0xFFCBD5E1);
  static const _headerBg = Color(0xFFE8EEF6);
  static const _headerInk = Color(0xFF1E3A5F);
  static const _title = Color(0xFF1E3A5F);
  static const _sectionBg = Color(0xFFF8FAFC);
  static const _sideBg = Color(0xFFF1F5F9);
  static const _liveBg = Color(0xFFECFDF5);
  static const _liveAccent = Color(0xFF059669);
  static const _pastBg = Color(0xFFF8FAFC);
  static const _pastAccent = Color(0xFF94A3B8);
  static const _meetingAccent = Color(0xFF3B82F6);
  static const _overdueBg = Color(0xFFFEF2F2);
  static const _overdueAccent = Color(0xFFDC2626);
  static const _urgentBg = Color(0xFFFEF2F2);
  static const _urgentAccent = Color(0xFFE11D48);
  static const _highBg = Color(0xFFFFF7ED);
  static const _highAccent = Color(0xFFEA580C);
  static const _normalBg = Color(0xFFFFFFFF);
  static const _normalAccent = Color(0xFF3B82F6);
  static const _lowBg = Color(0xFFF8FAFC);
  static const _lowAccent = Color(0xFF94A3B8);

  Color _priorityBackground(TaskPriority priority, {required bool overdue}) {
    if (overdue) return _overdueBg;
    return switch (priority) {
      TaskPriority.urgent => _urgentBg,
      TaskPriority.high => _highBg,
      TaskPriority.normal => _normalBg,
      TaskPriority.low => _lowBg,
    };
  }

  Color _priorityAccent(TaskPriority priority, {required bool overdue}) {
    if (overdue) return _overdueAccent;
    return switch (priority) {
      TaskPriority.urgent => _urgentAccent,
      TaskPriority.high => _highAccent,
      TaskPriority.normal => _normalAccent,
      TaskPriority.low => _lowAccent,
    };
  }

  List<Meeting> get _meetingsByTime {
    final list = [...data.meetings];
    list.sort((a, b) {
      int rank(Meeting m) {
        if (m.isLive) return 0;
        if (!m.isPast) return 1;
        return 2;
      }

      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return a.start.compareTo(b.start);
    });
    return list;
  }

  List<Task> get _tasksByTime {
    int byDue(Task a, Task b) {
      final ad = a.dueDate;
      final bd = b.dueDate;
      if (ad == null && bd == null) return a.title.compareTo(b.title);
      if (ad == null) return 1;
      if (bd == null) return -1;
      final cmp = ad.compareTo(bd);
      return cmp != 0 ? cmp : a.title.compareTo(b.title);
    }

    // Due today first, then overdue at the bottom of the tasks table.
    return [
      ...[...data.dueToday]..sort(byDue),
      ...[...data.overdue]..sort(byDue),
    ];
  }

  String _dateStamp(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final weekday = DateFormat('EEEE').format(dt);
    return '$d.$m.${dt.year}\n($weekday)';
  }

  String _clock(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final ampm = hour >= 12 ? 'PM' : 'AM';
    return '${h12.toString().padLeft(2, '0')}.$minute $ampm';
  }

  String _meetingDetails(Meeting m, {required bool compact}) {
    final noteLimit = compact ? 120 : 280;
    final lines = <String>[m.title.trim()];

    final place = m.location.trim();
    if (place.isNotEmpty) {
      lines.add('Location: $place');
    } else if (m.isOnline) {
      lines.add('Location: Online');
    }

    if (m.isOnline && m.link.trim().isNotEmpty) {
      lines.add('Link: ${_clip(m.link.trim(), compact ? 90 : 160)}');
    }

    final notes = m.notes.trim();
    if (notes.isNotEmpty) {
      lines.add('Notes: ${_clip(notes, noteLimit)}');
    }

    if (m.recurrence != MeetingRecurrence.none) {
      lines.add('Repeats: ${m.recurrenceSummary}');
    }

    return lines.join('\n');
  }

  String _taskDetails(Task t, {required bool overdue, required bool compact}) {
    final descLimit = compact ? 120 : 280;
    final lines = <String>[t.title.trim()];

    final meta = <String>[
      if (overdue) 'Overdue',
      t.status.label,
      t.priority.label,
    ];
    lines.add(meta.join(' · '));

    final description = t.description.trim();
    if (description.isNotEmpty) {
      lines.add('Description: ${_clip(description, descLimit)}');
    }

    if (t.tags.isNotEmpty && data.showTags) {
      lines.add('Tags: ${data.taskTags(t)}');
    }

    return lines.join('\n');
  }

  String _clip(String value, int max) {
    final oneLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= max) return oneLine;
    return '${oneLine.substring(0, max - 1)}…';
  }

  String _people(String value, {required bool compact}) {
    if (!compact) return value;
    return _clip(value, 72);
  }

  @override
  Widget build(BuildContext context) {
    final meetings = _meetingsByTime;
    final tasks = _tasksByTime;
    final overdueIds = {for (final t in data.overdue) t.id};
    final dateLabel = _dateStamp(data.date);
    final hasMeetings = meetings.isNotEmpty;
    final hasTasks = tasks.isNotEmpty;
    final totalRows = meetings.length + tasks.length;
    // 10+10 (or similar) → denser rows so the PNG stays readable and tall.
    final compact = totalRows >= 8;

    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(28, 28, 28, compact ? 24 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Schedule of ${data.userName}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _title,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 22),

            if (!hasMeetings && !hasTasks)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 36,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: _border, width: 1),
                  color: _sectionBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'No meetings or tasks scheduled for today.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              )
            else ...[
              if (hasMeetings)
                _ScheduleTable(
                  dateLabel: dateLabel,
                  compact: compact,
                  headers: const [
                    'Day & Date',
                    'Time',
                    'Details',
                    'Participants Details',
                  ],
                  rows: [
                    for (var i = 0; i < meetings.length; i++)
                      _ScheduleRowData(
                        time:
                            '${_clock(meetings[i].start)} – ${_clock(meetings[i].end)}',
                        details: _meetingDetails(
                          meetings[i],
                          compact: compact,
                        ),
                        participants: _people(
                          data.meetingAttendees(meetings[i]),
                          compact: compact,
                        ),
                        background: meetings[i].isLive
                            ? _liveBg
                            : meetings[i].isPast
                                ? _pastBg
                                : Colors.white,
                        accent: meetings[i].isLive
                            ? _liveAccent
                            : meetings[i].isPast
                                ? _pastAccent
                                : _meetingAccent,
                      ),
                  ],
                ),
              if (hasMeetings && hasTasks) const SizedBox(height: 16),
              if (hasTasks)
                _ScheduleTable(
                  dateLabel: dateLabel,
                  compact: compact,
                  headers: const [
                    'Day & Date',
                    'Time',
                    'Details',
                    'Participants Details',
                  ],
                  rows: [
                    for (var i = 0; i < tasks.length; i++)
                      _ScheduleRowData(
                        time: tasks[i].dueDate == null
                            ? '—'
                            : _clock(tasks[i].dueDate!),
                        details: _taskDetails(
                          tasks[i],
                          overdue: overdueIds.contains(tasks[i].id),
                          compact: compact,
                        ),
                        participants: _people(
                          data.taskAssignees(tasks[i]),
                          compact: compact,
                        ),
                        background: _priorityBackground(
                          tasks[i].priority,
                          overdue: overdueIds.contains(tasks[i].id),
                        ),
                        accent: _priorityAccent(
                          tasks[i].priority,
                          overdue: overdueIds.contains(tasks[i].id),
                        ),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScheduleRowData {
  const _ScheduleRowData({
    required this.time,
    required this.details,
    required this.participants,
    this.background = Colors.white,
    this.accent,
  });

  final String time;
  final String details;
  final String participants;
  final Color background;
  final Color? accent;
}

class _ScheduleTable extends StatelessWidget {
  const _ScheduleTable({
    required this.dateLabel,
    required this.headers,
    required this.rows,
    this.compact = false,
  });

  final String dateLabel;
  final List<String> headers;
  final List<_ScheduleRowData> rows;
  final bool compact;

  static const _borderSide = BorderSide(
    color: _TodaySharePoster._border,
    width: 1,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _TodaySharePoster._border, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _HeaderRow(headers: headers, compact: compact),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SideCell(
                  width: compact ? 102 : 118,
                  compact: compact,
                  child: Text(
                    dateLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _TodaySharePoster._headerInk,
                      fontSize: compact ? 11 : 12,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++)
                        _DataRow(
                          row: rows[i],
                          compact: compact,
                          showBottomBorder: i < rows.length - 1,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.headers, this.compact = false});

  final List<String> headers;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _TodaySharePoster._headerBg,
        border: Border(bottom: _ScheduleTable._borderSide),
      ),
      child: Row(
        children: [
          _HeaderCell(
            text: headers[0],
            width: compact ? 102 : 118,
            compact: compact,
          ),
          Expanded(
            flex: 18,
            child: _HeaderCell(text: headers[1], compact: compact),
          ),
          Expanded(
            flex: 42,
            child: _HeaderCell(text: headers[2], compact: compact),
          ),
          Expanded(
            flex: 34,
            child: _HeaderCell(
              text: headers[3],
              last: true,
              compact: compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.text,
    this.width,
    this.last = false,
    this.compact = false,
  });

  final String text;
  final double? width;
  final bool last;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: width,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 7 : 10,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(right: _ScheduleTable._borderSide),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _TodaySharePoster._headerInk,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    return width == null ? child : child;
  }
}

class _SideCell extends StatelessWidget {
  const _SideCell({
    required this.width,
    required this.child,
    this.compact = false,
  });

  final double width;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(
        horizontal: 6,
        vertical: compact ? 7 : 10,
      ),
      decoration: const BoxDecoration(
        color: _TodaySharePoster._sideBg,
        border: Border(right: _ScheduleTable._borderSide),
      ),
      child: child,
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.row,
    required this.showBottomBorder,
    this.compact = false,
  });

  final _ScheduleRowData row;
  final bool showBottomBorder;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = row.accent ?? _TodaySharePoster._normalAccent;
    return Container(
      decoration: BoxDecoration(
        color: row.background,
        border: showBottomBorder
            ? const Border(bottom: _ScheduleTable._borderSide)
            : null,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Expanded(
              flex: 18,
              child: _BodyCell(
                text: row.time,
                align: TextAlign.center,
                bold: true,
                compact: compact,
              ),
            ),
            Expanded(
              flex: 42,
              child: _BodyCell(
                text: row.details,
                compact: compact,
                multiline: true,
              ),
            ),
            Expanded(
              flex: 34,
              child: _BodyCell(
                text: row.participants,
                last: true,
                compact: compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell({
    required this.text,
    this.align = TextAlign.left,
    this.bold = false,
    this.last = false,
    this.compact = false,
    this.multiline = false,
  });

  final String text;
  final TextAlign align;
  final bool bold;
  final bool last;
  final bool compact;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 7 : 10,
      ),
      alignment: align == TextAlign.center
          ? Alignment.center
          : Alignment.centerLeft,
      decoration: BoxDecoration(
        border: last ? null : const Border(right: _ScheduleTable._borderSide),
      ),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          color: _TodaySharePoster._ink,
          fontSize: compact ? 11.5 : 12.5,
          height: multiline ? 1.4 : 1.35,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
