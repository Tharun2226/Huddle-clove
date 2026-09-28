import 'dart:convert';
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

  /// userId â†’ display name for resolving attendees / assignees.
  final Map<String, String> peopleNames;

  String get fileStem {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return 'huddle-today-$y$m$d';
  }

  String get shareSubject {
    final name = userName.trim();
    if (name.isEmpty) {
      return '${Fmt.weekdayLong(date)} schedules and meetings';
    }
    return 'Daily schedule — Time & Meeting Details of $name';
  }

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
  // Precache logos so off-screen capture doesn't miss APGOV / Amaravati.
  await Future.wait([
    precacheImage(const AssetImage(_TodaySharePoster._logoLeft), context),
    precacheImage(const AssetImage(_TodaySharePoster._logoRight), context),
  ]);
  if (!context.mounted) {
    throw StateError('Could not render Today image');
  }

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
            width: _a4WidthPx,
            height: _a4HeightPx,
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
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await WidgetsBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(milliseconds: 160));
  await WidgetsBinding.instance.endOfFrame;

  try {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('Could not render Today image');
    }
    final image = await boundary.toImage(pixelRatio: _a4PixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Could not encode PNG');
    }
    return _pngWithPrintDpi(
      byteData.buffer.asUint8List(),
      dpi: _a4Dpi,
    );
  } finally {
    entry.remove();
  }
}

/// A4 portrait at 300 DPI: 2480×3508 px (210×297 mm).
/// Logical size is half of that; capture uses [_a4PixelRatio].
const _a4Dpi = 300;
const _a4PixelRatio = 2.0;
const _a4WidthPx = 1240.0;
const _a4HeightPx = 1754.0;
const _a4MarginPx = 36.0;

/// Stamp PNG pHYs so printers treat the pixels as [_a4Dpi] dots per inch.
Uint8List _pngWithPrintDpi(Uint8List png, {required int dpi}) {
  if (png.length < 33) return png;
  final ppm = (dpi / 0.0254).round();
  final data = ByteData(9)
    ..setUint32(0, ppm, Endian.big)
    ..setUint32(4, ppm, Endian.big)
    ..setUint8(8, 1);
  final type = ascii.encode('pHYs');
  final crcInput = Uint8List(4 + 9)
    ..setRange(0, 4, type)
    ..setRange(4, 13, data.buffer.asUint8List());
  final crc = _pngCrc32(crcInput);
  final chunk = BytesBuilder()
    ..add((ByteData(4)..setUint32(0, 9, Endian.big)).buffer.asUint8List())
    ..add(type)
    ..add(data.buffer.asUint8List())
    ..add((ByteData(4)..setUint32(0, crc, Endian.big)).buffer.asUint8List());

  final view = ByteData.sublistView(png);
  final ihdrLen = view.getUint32(8, Endian.big);
  final insertAt = 12 + 4 + ihdrLen + 4;
  if (insertAt >= png.length) return png;
  return Uint8List.fromList([
    ...png.sublist(0, insertAt),
    ...chunk.toBytes(),
    ...png.sublist(insertAt),
  ]);
}

int _pngCrc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      final bit = crc & 1;
      crc >>= 1;
      if (bit != 0) crc ^= 0xEDB88320;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Official daily-schedule poster (APCRDA style) — logos + Time / Meeting Details.
/// Fixed A4 page, no calendars.
class _TodaySharePoster extends StatelessWidget {
  const _TodaySharePoster({required this.data});

  final TodayShareData data;

  static const _ink = Color(0xFF111111);
  static const _titleRed = Color(0xFFC41E3A);
  static const _roleBlue = Color(0xFF1E40AF);
  static const _morning = Color(0xFF0F766E);
  static const _afternoon = Color(0xFFC2410C);
  static const _evening = Color(0xFF7E22CE);
  static const _border = Color(0xFF1A1A1A);
  static const _headerBg = Color(0xFFD9D9D9);
  static const _logoLeft = 'assets/APGOV.png';
  static const _logoRight = 'assets/amaravathi.png';

  List<({DateTime at, String title})> get _rows {
    final rows = <({DateTime at, String title})>[];
    final seenTaskIds = <String>{};

    void addTask(Task task) {
      final due = task.dueDate;
      if (due == null) return;
      if (!seenTaskIds.add(task.id)) return;
      final title = task.title.trim();
      if (title.isEmpty) return;
      rows.add((at: due, title: title));
    }

    // Meetings for the selected agenda day (past / live / upcoming).
    for (final m in data.meetings) {
      final title = m.title.trim();
      if (title.isEmpty) continue;
      rows.add((at: m.start, title: title));
    }

    // Due on selected date only — including completed (no other-day overdue).
    for (final t in data.dueToday) {
      addTask(t);
    }

    rows.sort((a, b) => a.at.compareTo(b.at));
    return rows;
  }

  String _scheduleDateLine(DateTime dt) {
    final weekday = DateFormat('EEEE').format(dt);
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return 'DAILY SCHEDULE ($weekday— $d.$m.${dt.year})';
  }

  String _clock(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final ampm = hour >= 12 ? 'PM' : 'AM';
    return '${h12.toString().padLeft(2, '0')}:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final compact = rows.length >= 14;
    final logo = compact ? 108.0 : 128.0;

    return ColoredBox(
      color: Colors.white,
      child: SizedBox(
        width: _a4WidthPx,
        height: _a4HeightPx,
        child: Padding(
          padding: const EdgeInsets.all(_a4MarginPx),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _border, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset(
                        _logoLeft,
                        width: logo,
                        height: logo,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _ScheduleNameBlock(
                          userName: data.userName,
                          dateLine: _scheduleDateLine(data.date),
                          compact: compact,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Image.asset(
                        _logoRight,
                        width: logo + 36,
                        height: logo,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: rows.isEmpty
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: _border, width: 1.4),
                            ),
                            child: const Center(
                              child: Text(
                                'No meetings or tasks scheduled for today.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                        : _FilledScheduleTable(
                            rows: [
                              for (final row in rows)
                                (
                                  time: _clock(row.at),
                                  title: row.title,
                                  at: row.at,
                                ),
                            ],
                            compact: compact,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Name before the first comma stays large and red.
/// Text after that comma is the role: royal blue, same size as the date line.
class _ScheduleNameBlock extends StatelessWidget {
  const _ScheduleNameBlock({
    required this.userName,
    required this.dateLine,
    required this.compact,
  });

  final String userName;
  final String dateLine;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final raw = userName.trim();
    final comma = raw.indexOf(',');
    final name = raw.isEmpty
        ? 'COMMISSIONER APCRDA'
        : (comma < 0 ? raw : raw.substring(0, comma).trim());
    final role = comma < 0 ? '' : raw.substring(comma + 1).trim();
    final displayName = name.isEmpty ? raw.toUpperCase() : name.toUpperCase();

    return Column(
      children: [
        Text(
          displayName.isEmpty ? 'COMMISSIONER APCRDA' : displayName,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _TodaySharePoster._titleRed,
            fontSize: compact ? 30 : 36,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: 0.4,
          ),
        ),
        if (role.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            role,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _TodaySharePoster._roleBlue,
              fontSize: compact ? 20 : 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          dateLine,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _TodaySharePoster._titleRed,
            fontSize: compact ? 20 : 24,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Time / Meeting Details grid stretched to the remaining A4 page.
class _FilledScheduleTable extends StatelessWidget {
  const _FilledScheduleTable({
    required this.rows,
    required this.compact,
  });

  final List<({String time, String title, DateTime at})> rows;
  final bool compact;

  static Color _timeColor(DateTime at) {
    final hour = at.hour;
    if (hour < 12) return _TodaySharePoster._morning;
    if (hour < 18) return _TodaySharePoster._afternoon;
    return _TodaySharePoster._evening;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: _TodaySharePoster._border, width: 1.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: compact ? 52 : 60,
            child: _gridLine(
              left: 'Time',
              right: 'Meeting Details',
              background: _TodaySharePoster._headerBg,
              fontSize: compact ? 20 : 22,
              bold: true,
              centerLeft: true,
              bottom: true,
            ),
          ),
          for (var i = 0; i < rows.length; i++)
            Expanded(
              child: _gridLine(
                left: rows[i].time,
                right: rows[i].title,
                fontSize: compact ? 18 : 22,
                boldLeft: true,
                centerLeft: true,
                leftColor: _timeColor(rows[i].at),
                bottom: i < rows.length - 1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _gridLine({
    required String left,
    required String right,
    required double fontSize,
    Color? background,
    Color? leftColor,
    bool bold = false,
    bool boldLeft = false,
    bool centerLeft = false,
    bool bottom = false,
  }) {
    final border = BorderSide(color: _TodaySharePoster._border, width: 1.2);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? Colors.white,
        border: Border(
          bottom: bottom ? border : BorderSide.none,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 28,
            child: _cell(
              left,
              fontSize: fontSize,
              bold: bold || boldLeft,
              color: leftColor ?? _TodaySharePoster._ink,
              align: centerLeft ? TextAlign.center : TextAlign.left,
            ),
          ),
          ColoredBox(
            color: _TodaySharePoster._border,
            child: const SizedBox(width: 1.4),
          ),
          Expanded(
            flex: 72,
            child: _cell(
              right,
              fontSize: fontSize,
              bold: bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(
    String text, {
    required double fontSize,
    required bool bold,
    Color color = _TodaySharePoster._ink,
    TextAlign align = TextAlign.left,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Align(
        alignment: align == TextAlign.center
            ? Alignment.center
            : Alignment.centerLeft,
        child: Text(
          text,
          textAlign: align,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            height: 1.25,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
