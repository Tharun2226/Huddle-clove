import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_tokens.dart';
import '../utils/formatters.dart';

DateTime calendarDay(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool isCalendarToday(DateTime d) => isSameCalendarDay(d, DateTime.now());

/// Selected day for the Today home agenda (defaults to today).
class TodayAgendaDateController extends Notifier<DateTime> {
  @override
  DateTime build() => calendarDay(DateTime.now());

  void set(DateTime date) => state = calendarDay(date);

  void goToday() => state = calendarDay(DateTime.now());
}

final todayAgendaDateProvider =
    NotifierProvider<TodayAgendaDateController, DateTime>(
  TodayAgendaDateController.new,
);

/// Selected day for Work → Tasks / Meetings.
/// `null` means show all dates (full board). Defaults to all.
class WorkAgendaDateController extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void set(DateTime date) => state = calendarDay(date);

  void goToday() => state = calendarDay(DateTime.now());

  void clear() => state = null;
}

final workAgendaDateProvider =
    NotifierProvider<WorkAgendaDateController, DateTime?>(
  WorkAgendaDateController.new,
);

Future<void> pickAgendaDate({
  required BuildContext context,
  required DateTime initialDate,
  required ValueChanged<DateTime> onPicked,
}) async {
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: calendarDay(initialDate),
    firstDate: now.subtract(const Duration(days: 365 * 2)),
    lastDate: now.add(const Duration(days: 365 * 2)),
  );
  if (picked != null) onPicked(picked);
}

/// Tappable date control used on Today and Work.
class AgendaDateButton extends StatelessWidget {
  const AgendaDateButton({
    super.key,
    required this.date,
    required this.onPick,
    this.onToday,
    this.onClear,
    this.allowAll = false,
    this.compact = false,
  });

  /// When [allowAll] and this is null, shows "All dates".
  final DateTime? date;
  final VoidCallback onPick;
  final VoidCallback? onToday;
  final VoidCallback? onClear;
  final bool allowAll;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final selected = date;
    final label = selected == null
        ? 'All dates'
        : isCalendarToday(selected)
            ? 'Today · ${Fmt.dayMonth(selected)}'
            : Fmt.friendlyDate(selected) == Fmt.weekdayShort(selected)
                ? '${Fmt.weekdayShort(selected)}, ${Fmt.dayMonth(selected)}'
                : Fmt.friendlyDate(selected);

    return Row(
      children: [
        Expanded(
          child: Material(
            color: palette.neutralContainer,
            borderRadius: BorderRadius.circular(Radii.md),
            child: InkWell(
              onTap: onPick,
              borderRadius: BorderRadius.circular(Radii.md),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: Insets.md,
                  vertical: compact ? Insets.sm : Insets.md,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 20,
                      color: context.colors.primary,
                    ),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: Text(
                        label,
                        style: context.text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: palette.neutral,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (selected != null && !isCalendarToday(selected) && onToday != null) ...[
          const SizedBox(width: Insets.sm),
          TextButton(
            onPressed: onToday,
            child: const Text('Today'),
          ),
        ],
        if (allowAll && selected != null && onClear != null) ...[
          const SizedBox(width: Insets.xs),
          TextButton(
            onPressed: onClear,
            child: const Text('All'),
          ),
        ],
      ],
    );
  }
}
