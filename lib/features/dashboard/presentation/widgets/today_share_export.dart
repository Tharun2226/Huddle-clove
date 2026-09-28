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
    final image = await boundary.toImage(pixelRatio: 1);
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

/// A4 portrait at 200 DPI (210×297 mm) so the shared PNG prints at paper size.
const _a4Dpi = 200;
const _a4WidthPx = 1654.0;
const _a4HeightPx = 2339.0;
const _a4MarginPx = 94.0;

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
    final compact = rows.length >= 10;

    final content = Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _border, width: 1.6),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: EdgeInsets.fromLTRB(18, 16, 18, compact ? 16 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    _logoLeft,
                    width: 140,
                    height: 140,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          data.userName.trim().isEmpty
                              ? 'COMMISSIONER APCRDA'
                              : data.userName.trim().toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _titleRed,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _scheduleDateLine(data.date),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _titleRed,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Image.asset(
                    _logoRight,
                    width: 180,
                    height: 140,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ],
              ),
              SizedBox(height: compact ? 12 : 16),
              if (rows.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 28,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: _border, width: 1.2),
                  ),
                  child: const Text(
                    'No meetings or tasks scheduled for today.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Table(
                  border: TableBorder.all(color: _border, width: 1.2),
                  columnWidths: const {
                    0: FlexColumnWidth(1.15),
                    1: FlexColumnWidth(3.6),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: _headerBg),
                      children: [
                        _headerCell('Time', compact: compact),
                        _headerCell('Meeting Details', compact: compact),
                      ],
                    ),
                    for (final row in rows)
                      TableRow(
                        children: [
                          _bodyCell(
                            _clock(row.at),
                            compact: compact,
                            bold: true,
                          ),
                          _bodyCell(row.title, compact: compact),
                        ],
                      ),
                  ],
                ),
            ],
          ),
        );

    final contentWidth = _a4WidthPx - (_a4MarginPx * 2);
    return ColoredBox(
      color: Colors.white,
      child: SizedBox(
        width: _a4WidthPx,
        height: _a4HeightPx,
        child: Padding(
          padding: const EdgeInsets.all(_a4MarginPx),
          child: Align(
            alignment: Alignment.topCenter,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: contentWidth,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String text, {required bool compact}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compact ? 10 : 14,
      ),
      child: Text(
        text,
        textAlign: TextAlign.left,
        style: TextStyle(
          color: _ink,
          fontSize: compact ? 20 : 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _bodyCell(
    String text, {
    required bool compact,
    bool bold = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compact ? 10 : 14,
      ),
      child: Text(
        text,
        textAlign: TextAlign.left,
        style: TextStyle(
          color: _ink,
          fontSize: compact ? 18 : 20,
          height: 1.35,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
