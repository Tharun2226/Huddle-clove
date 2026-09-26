import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/theme/app_tokens.dart';
import 'task_import_models.dart';

final _dateInLine = RegExp(
  r'(?:Meeting\s+on\s+)?'
  r'(\d{1,2})[./\-](\d{1,2})[./\-](\d{4})'
  r'(?:\s*\([^)]*\))?',
  caseSensitive: false,
);

final _timeEntry = RegExp(
  r'^(\d{1,2}):(\d{2})\s*([AaPp][Mm])\s*[-–—]\s*(.+)$',
);

final _noiseWords = RegExp(
  r'\b(schedule|agenda|timetable|programme|program)\b',
  caseSensitive: false,
);

/// Strip WhatsApp/markdown bold markers (`*text*` / leftover `*`).
String stripScheduleMarkup(String raw) {
  return raw
      .replaceAll('*', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Pull assignee label from lines like "Additional commissioner sir Schedule".
///
/// Drops Schedule/agenda noise, then keeps text before "sir" when present.
String extractScheduleAssigneeName(String raw) {
  var s = stripScheduleMarkup(raw);
  if (s.isEmpty) return '';
  s = s.replaceAll(_noiseWords, '').replaceAll(RegExp(r'\s+'), ' ').trim();
  final beforeSir = RegExp(
    r'^(.+?)\s+sir\b',
    caseSensitive: false,
  ).firstMatch(s);
  if (beforeSir != null) {
    return beforeSir.group(1)!.trim();
  }
  return s;
}

DateTime? _parseDdMmYyyy(String day, String month, String year) {
  final d = int.tryParse(day);
  final m = int.tryParse(month);
  final y = int.tryParse(year);
  if (d == null || m == null || y == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, m, d);
  if (dt.year != y || dt.month != m || dt.day != d) return null;
  return dt;
}

({int hour, int minute})? _parseAmPm(String h, String min, String period) {
  var hour = int.tryParse(h);
  final minute = int.tryParse(min);
  if (hour == null || minute == null) return null;
  if (hour < 1 || hour > 12 || minute > 59) return null;
  final p = period.toUpperCase();
  if (p == 'AM') {
    if (hour == 12) hour = 0;
  } else if (hour != 12) {
    hour += 12;
  }
  return (hour: hour, minute: minute);
}

bool _looksLikePersonHeader(String line) {
  if (line.isEmpty) return false;
  if (_dateInLine.hasMatch(line)) return false;
  if (_timeEntry.hasMatch(line)) return false;
  final lower = line.toLowerCase();
  if (lower.contains('sir') || _noiseWords.hasMatch(line)) return true;
  // Short heading line before timed items (no leading digits).
  if (!RegExp(r'^\d').hasMatch(line) && line.length >= 3 && line.length <= 80) {
    return true;
  }
  return false;
}

/// Parse pasted commissioner/office schedules into import rows.
///
/// Example:
/// ```
/// Meeting on 11.08.2026 (Friday)
///
/// Additional commissioner sir Schedule
///
/// 9:00 AM - Teleconference on E3, E13, E15
/// 9:15 AM - Teleconference with SDCs of LPS - 2.0
/// ```
List<TaskImportRowPayload> parseSchedulePasteText(String raw) {
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (text.isEmpty) {
    throw StateError('Paste is empty');
  }

  DateTime? currentDate;
  String currentAssignee = '';
  final rows = <TaskImportRowPayload>[];

  for (final lineRaw in text.split('\n')) {
    final line = stripScheduleMarkup(lineRaw);
    if (line.isEmpty) continue;

    final dateMatch = _dateInLine.firstMatch(line);
    if (dateMatch != null && !_timeEntry.hasMatch(line)) {
      final parsed = _parseDdMmYyyy(
        dateMatch.group(1)!,
        dateMatch.group(2)!,
        dateMatch.group(3)!,
      );
      if (parsed != null) currentDate = parsed;
      continue;
    }

    final timeMatch = _timeEntry.firstMatch(line);
    if (timeMatch != null) {
      final clock = _parseAmPm(
        timeMatch.group(1)!,
        timeMatch.group(2)!,
        timeMatch.group(3)!,
      );
      final title = stripScheduleMarkup(timeMatch.group(4)!);
      if (clock == null || title.isEmpty) continue;
      if (currentDate == null) {
        throw StateError(
          'Add a date line first, e.g. Meeting on 11.08.2026 (Friday)',
        );
      }
      final due = DateTime(
        currentDate.year,
        currentDate.month,
        currentDate.day,
        clock.hour,
        clock.minute,
      );
      rows.add(
        TaskImportRowPayload(
          title: title,
          dueDate: due,
          assignees: currentAssignee,
        ),
      );
      continue;
    }

    if (_looksLikePersonHeader(line)) {
      final name = extractScheduleAssigneeName(line);
      if (name.isNotEmpty) currentAssignee = name;
    }
  }

  if (rows.isEmpty) {
    throw StateError(
      'No timed items found. Use lines like: 9:00 AM - Title',
    );
  }
  return rows;
}

Future<List<TaskImportRowPayload>?> showSchedulePasteDialog(
  BuildContext context, {
  String? initialText,
}) async {
  return showModalBottomSheet<List<TaskImportRowPayload>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _SchedulePasteSheet(initialText: initialText),
  );
}

class _SchedulePasteSheet extends StatefulWidget {
  const _SchedulePasteSheet({this.initialText});

  final String? initialText;

  @override
  State<_SchedulePasteSheet> createState() => _SchedulePasteSheetState();
}

class _SchedulePasteSheetState extends State<_SchedulePasteSheet> {
  late final TextEditingController _controller;
  String? _error;
  int? _previewCount;
  String? _previewAssignee;
  String? _previewDate;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _tryPreview() {
    try {
      final rows = parseSchedulePasteText(_controller.text);
      setState(() {
        _error = null;
        _previewCount = rows.length;
        _previewAssignee =
            rows.first.assignees.isEmpty ? null : rows.first.assignees;
        final d = rows.first.dueDate;
        _previewDate =
            '${d.day.toString().padLeft(2, '0')}.'
            '${d.month.toString().padLeft(2, '0')}.'
            '${d.year}';
      });
    } catch (e) {
      setState(() {
        _error = '$e'.replaceFirst('Bad state: ', '');
        _previewCount = null;
        _previewAssignee = null;
        _previewDate = null;
      });
    }
  }

  void _submit() {
    try {
      final rows = parseSchedulePasteText(_controller.text);
      Navigator.pop(context, rows);
    } catch (e) {
      setState(() {
        _error = '$e'.replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      setState(() => _error = 'Clipboard is empty');
      return;
    }
    setState(() {
      _controller.text = text;
      _error = null;
    });
    _tryPreview();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            0,
            Insets.lg,
            Insets.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Paste schedule',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Insets.sm),
              Text(
                'Date + person heading + timed lines. Each time becomes a task; '
                'assignee goes to Others (name before “sir”).',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _controller,
                maxLines: 12,
                minLines: 8,
                onChanged: (_) {
                  if (_previewCount != null || _error != null) {
                    _tryPreview();
                  }
                },
                decoration: const InputDecoration(
                  hintText:
                      'Meeting on 11.08.2026 (Friday)\n\n'
                      'Additional commissioner sir Schedule\n\n'
                      '9:00 AM - Teleconference…',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: Insets.sm),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error),
                ),
              ],
              if (_previewCount != null) ...[
                const SizedBox(height: Insets.sm),
                Text(
                  '$_previewCount task${_previewCount == 1 ? '' : 's'}'
                  '${_previewDate != null ? ' · $_previewDate' : ''}'
                  '${_previewAssignee != null ? ' · Others: $_previewAssignee' : ''}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              const SizedBox(height: Insets.md),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('Clipboard'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _tryPreview,
                    child: const Text('Preview'),
                  ),
                  const SizedBox(width: Insets.sm),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
