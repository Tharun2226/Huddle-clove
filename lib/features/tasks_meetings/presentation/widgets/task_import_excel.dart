import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/config/org_config.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/network/api_task_repository.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/app_feedback.dart';
import '../../../../shared/utils/date_codec.dart';
import '../../../../shared/utils/formatters.dart';
import '../providers/task_providers.dart';
import 'download_bytes.dart';

const _sheetName = 'Tasks';

class TaskImportRowPayload {
  const TaskImportRowPayload({
    required this.title,
    required this.dueDate,
    this.description = '',
    this.assignees = '',
    this.priority = '',
    this.status = '',
  });

  final String title;
  final String description;
  final DateTime dueDate;
  final String assignees;
  final String priority;
  final String status;

  TaskImportRowPayload copyWith({
    String? priority,
    String? status,
  }) {
    return TaskImportRowPayload(
      title: title,
      description: description,
      dueDate: dueDate,
      assignees: assignees,
      priority: priority ?? this.priority,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'dueDate': DateCodec.encodeInstant(dueDate),
        if (assignees.trim().isNotEmpty) 'assignees': assignees.trim(),
        if (priority.trim().isNotEmpty) 'priority': priority.trim(),
        if (status.trim().isNotEmpty) 'status': status.trim(),
      };
}

/// Downloadable template from API (includes Priority/Status dropdowns).
Future<void> shareTaskImportTemplate(WidgetRef ref) async {
  final api = ApiTaskRepository(ref.read(apiClientProvider));
  final template = await api.downloadImportTemplate();
  const mime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  if (kIsWeb) {
    await downloadBytesInBrowser(
      bytes: template.bytes,
      fileName: template.fileName,
      mimeType: mime,
    );
    return;
  }

  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          template.bytes,
          mimeType: mime,
          name: template.fileName,
        ),
      ],
      fileNameOverrides: [template.fileName],
      subject: 'Huddle task import template',
    ),
  );
}

String _cellToString(Data? data) {
  if (data == null) return '';
  final value = data.value;
  if (value == null) return '';
  if (value is TextCellValue) return value.toString().trim();
  if (value is IntCellValue) return '${value.value}';
  if (value is DoubleCellValue) {
    final n = value.value;
    if (n == n.roundToDouble()) return '${n.round()}';
    return '$n';
  }
  if (value is BoolCellValue) return value.value ? 'true' : 'false';
  if (value is DateCellValue) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
  return '$value'.trim();
}

DateTime? _parseExcelDate(String raw, Data? data) {
  final text = raw.trim();
  if (text.isEmpty) {
    final value = data?.value;
    if (value is DateCellValue) {
      return DateTime(value.year, value.month, value.day);
    }
    if (value is DoubleCellValue) {
      return _excelSerialToDate(value.value);
    }
    if (value is IntCellValue) {
      return _excelSerialToDate(value.value.toDouble());
    }
    return null;
  }
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    return DateCodec.parseCalendarDate(text);
  }
  final asNum = double.tryParse(text);
  if (asNum != null && asNum > 20000 && asNum < 80000) {
    return _excelSerialToDate(asNum);
  }
  try {
    final dt = DateTime.parse(text);
    return DateTime(dt.year, dt.month, dt.day);
  } catch (_) {
    return null;
  }
}

DateTime _excelSerialToDate(double serial) {
  final utc = DateTime.utc(1899, 12, 30).add(
    Duration(milliseconds: (serial * 86400000).round()),
  );
  return DateTime(utc.year, utc.month, utc.day);
}

({int hour, int minute})? _parseTime(String raw, Data? data) {
  final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) {
    final value = data?.value;
    if (value is DoubleCellValue && value.value >= 0 && value.value < 1) {
      final totalMinutes = (value.value * 24 * 60).round();
      return (hour: (totalMinutes ~/ 60) % 24, minute: totalMinutes % 60);
    }
    return null;
  }
  final ampm = RegExp(r'^(\d{1,2}):(\d{2})\s*([AaPp][Mm])$').firstMatch(text);
  if (ampm != null) {
    var hour = int.parse(ampm.group(1)!);
    final minute = int.parse(ampm.group(2)!);
    final period = ampm.group(3)!.toUpperCase();
    if (hour < 1 || hour > 12 || minute > 59) return null;
    if (period == 'AM') {
      if (hour == 12) hour = 0;
    } else if (hour != 12) {
      hour += 12;
    }
    return (hour: hour, minute: minute);
  }
  final h24 = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
  if (h24 != null) {
    final hour = int.parse(h24.group(1)!);
    final minute = int.parse(h24.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return (hour: hour, minute: minute);
  }
  return null;
}

List<TaskImportRowPayload> parseTaskImportBytes(Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables[_sheetName] ??
      excel.tables.values.cast<Sheet?>().firstWhere(
            (s) => s != null,
            orElse: () => null,
          );
  if (sheet == null) {
    throw StateError('No worksheet found in the Excel file');
  }

  final headerRow = sheet.rows.isEmpty ? const <Data?>[] : sheet.rows.first;
  final headerMap = <String, int>{};
  for (var c = 0; c < headerRow.length; c++) {
    final key = _normalizeHeader(_cellToString(headerRow[c]));
    if (key.isEmpty) continue;
    headerMap[key] = c;
  }

  int? col(String name) => headerMap[name];
  final titleCol = col('title');
  if (titleCol == null) {
    throw StateError('Missing Title column');
  }
  final descCol = col('description');
  final dateCol = col('date');
  final timeCol = col('time');
  final assigneesCol = col('assignees');
  final priorityCol = col('priority');
  final statusCol = col('status');

  final rows = <TaskImportRowPayload>[];
  for (var r = 1; r < sheet.rows.length; r++) {
    final row = sheet.rows[r];
    String at(int? c) {
      if (c == null || c >= row.length) return '';
      return _cellToString(row[c]);
    }

    Data? dataAt(int? c) {
      if (c == null || c >= row.length) return null;
      return row[c];
    }

    final title = at(titleCol);
    if (title.isEmpty) continue;

    final date = _parseExcelDate(at(dateCol), dataAt(dateCol)) ??
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final time = _parseTime(at(timeCol), dataAt(timeCol));
    final due = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 17,
      time?.minute ?? 0,
    );

    rows.add(
      TaskImportRowPayload(
        title: title,
        description: at(descCol),
        dueDate: due,
        assignees: at(assigneesCol),
        priority: _stripDropdownMark(at(priorityCol)),
        status: _stripDropdownMark(at(statusCol)),
      ),
    );
  }

  if (rows.isEmpty) {
    throw StateError('No task rows found (Title is required on each row)');
  }
  return rows;
}

String _normalizeHeader(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[▼▾]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _stripDropdownMark(String raw) {
  return raw.trim().replaceAll(RegExp(r'\s*[▼▾]\s*$'), '').trim();
}

Future<void> showTaskImportSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text('Download Excel template'),
            subtitle: const Text('Sample row only — set Priority/Status in app'),
            onTap: () async {
              Navigator.pop(ctx);
              final messenger = AppFeedback.messengerOf(context);
              try {
                await shareTaskImportTemplate(ref);
              } catch (e) {
                AppFeedback.error(messenger, 'Could not download template: $e');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_rounded),
            title: const Text('Import from Excel'),
            subtitle: const Text('Creates tasks from your filled sheet'),
            onTap: () async {
              Navigator.pop(ctx);
              await _importTasksFromPicker(context, ref);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _importTasksFromPicker(BuildContext context, WidgetRef ref) async {
  final messenger = AppFeedback.messengerOf(context);
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['xlsx', 'xls'],
  );
  if (files.isEmpty) return;

  final file = files.first;
  late final Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (e) {
    AppFeedback.error(messenger, 'Could not read the selected file');
    return;
  }

  late final List<TaskImportRowPayload> rows;
  try {
    rows = parseTaskImportBytes(bytes);
  } catch (e) {
    AppFeedback.error(messenger, '$e');
    return;
  }

  if (!context.mounted) return;
  final config = ref.read(orgConfigProvider);
  final reviewed = await showModalBottomSheet<List<TaskImportRowPayload>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _TaskImportReviewSheet(rows: rows, config: config),
  );
  if (reviewed == null || reviewed.isEmpty || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final api = ApiTaskRepository(ref.read(apiClientProvider));
    final result = await api.importTasks([
      for (final row in reviewed) row.toJson(),
    ]);
    ref.invalidate(tasksProvider);
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

    final created = result.createdCount;
    final failed = result.failedCount;
    if (failed == 0) {
      AppFeedback.success(
        messenger,
        'Imported $created task${created == 1 ? '' : 's'}',
      );
    } else {
      final firstError = result.failed.isNotEmpty
          ? result.failed.first.error
          : 'Unknown error';
      AppFeedback.error(
        messenger,
        'Imported $created, failed $failed. First error: $firstError',
        duration: const Duration(seconds: 5),
      );
    }
  } catch (e) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    AppFeedback.error(messenger, 'Import failed: $e');
  }
}

class _TaskImportReviewSheet extends StatefulWidget {
  const _TaskImportReviewSheet({
    required this.rows,
    required this.config,
  });

  final List<TaskImportRowPayload> rows;
  final OrgConfig config;

  @override
  State<_TaskImportReviewSheet> createState() => _TaskImportReviewSheetState();
}

class _TaskImportReviewSheetState extends State<_TaskImportReviewSheet> {
  late List<TaskImportRowPayload> _rows;

  List<String> get _priorities {
    final names = widget.config.taskPriorities.map((p) => p.name).toList();
    return names.isNotEmpty
        ? names
        : const ['Urgent', 'High', 'Normal', 'Low'];
  }

  List<String> get _statuses {
    final names = widget.config.taskStatuses.map((s) => s.name).toList();
    return names.isNotEmpty
        ? names
        : const ['To Do', 'In Progress', 'In Review', 'Done'];
  }

  String get _defaultPriority =>
      widget.config.defaultPriority?.name ??
      (_priorities.contains('Normal') ? 'Normal' : _priorities.first);

  String get _defaultStatus =>
      widget.config.defaultStatus?.name ??
      (_statuses.contains('To Do') ? 'To Do' : _statuses.first);

  @override
  void initState() {
    super.initState();
    _rows = [
      for (final row in widget.rows)
        row.copyWith(
          priority: _matchOrDefault(row.priority, _priorities, _defaultPriority),
          status: _matchOrDefault(row.status, _statuses, _defaultStatus),
        ),
    ];
  }

  String _matchOrDefault(String raw, List<String> options, String fallback) {
    final cleaned = _stripDropdownMark(raw);
    if (cleaned.isEmpty) return fallback;
    for (final option in options) {
      if (option.toLowerCase() == cleaned.toLowerCase()) return option;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height * 0.85;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.screen,
                Insets.sm,
                Insets.screen,
                Insets.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Review import',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(
                    'Tap Priority or Status to open the dropdown.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  Insets.screen,
                  0,
                  Insets.screen,
                  Insets.lg,
                ),
                itemCount: _rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  return Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    borderRadius: Radii.field,
                    child: Padding(
                      padding: const EdgeInsets.all(Insets.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            row.title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: Insets.xs),
                          Text(
                            '${Fmt.friendlyDate(row.dueDate)}, ${Fmt.time(row.dueDate)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: Insets.md),
                          Row(
                            children: [
                              Expanded(
                                child: _ImportDropdown(
                                  label: 'Priority',
                                  value: row.priority,
                                  options: _priorities,
                                  onChanged: (value) {
                                    setState(() {
                                      _rows[index] =
                                          row.copyWith(priority: value);
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: Insets.sm),
                              Expanded(
                                child: _ImportDropdown(
                                  label: 'Status',
                                  value: row.status,
                                  options: _statuses,
                                  onChanged: (value) {
                                    setState(() {
                                      _rows[index] =
                                          row.copyWith(status: value);
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.screen,
                  Insets.sm,
                  Insets.screen,
                  Insets.md,
                ),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _rows),
                  child: Text('Import ${_rows.length} task${_rows.length == 1 ? '' : 's'}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportDropdown extends StatelessWidget {
  const _ImportDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = options.contains(value) ? value : options.first;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(borderRadius: Radii.field),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.sm,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: safeValue,
          icon: const Icon(Icons.arrow_drop_down),
          items: [
            for (final option in options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}
