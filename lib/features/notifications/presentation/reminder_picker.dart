import 'package:flutter/material.dart';

import '../../../shared/theme/app_tokens.dart';
import '../services/reminder_service.dart';

/// Optional "Remind me" control for tasks / meetings: when, and whether it
/// arrives as a notification, an alarm, or both. Hidden where on-device
/// reminders are unsupported (web, iOS for now).
class ReminderPicker extends StatelessWidget {
  const ReminderPicker({
    super.key,
    required this.value,
    required this.style,
    required this.onChanged,
    required this.onStyleChanged,
    this.label = 'Remind me (this phone)',
    this.showHint = true,
  });

  /// Explain the selected style below the buttons. Off in dense lists.
  final bool showHint;

  /// Minutes before; null means no reminder.
  final int? value;
  final ReminderStyle style;
  final ValueChanged<int?> onChanged;
  final ValueChanged<ReminderStyle> onStyleChanged;
  final String label;

  static const _styleHints = {
    ReminderStyle.notification: 'A normal notification.',
    ReminderStyle.alarm: 'Alarm sound that keeps ringing until you dismiss it.',
    ReminderStyle.both: 'Notification at the reminder time, then an alarm '
        'when it starts.',
  };

  @override
  Widget build(BuildContext context) {
    if (!ReminderService.isSupported) return const SizedBox.shrink();
    final options = {
      ...reminderOptions,
      // Keep an unusual stored value selectable.
      if (!reminderOptions.containsKey(value)) value: '$value minutes before',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon:
                const Icon(Icons.notifications_active_outlined, size: 20),
            border: const OutlineInputBorder(borderRadius: Radii.field),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: Insets.sm,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              isExpanded: true,
              value: value,
              items: [
                for (final e in options.entries)
                  DropdownMenuItem<int?>(value: e.key, child: Text(e.value)),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
        if (value != null) ...[
          const SizedBox(height: Insets.sm),
          SegmentedButton<ReminderStyle>(
            segments: const [
              ButtonSegment(
                value: ReminderStyle.notification,
                icon: Icon(Icons.notifications_none_rounded, size: 18),
                label: Text('Notification'),
              ),
              ButtonSegment(
                value: ReminderStyle.alarm,
                icon: Icon(Icons.alarm_rounded, size: 18),
                label: Text('Alarm'),
              ),
              ButtonSegment(
                value: ReminderStyle.both,
                icon: Icon(Icons.notifications_active_rounded, size: 18),
                label: Text('Both'),
              ),
            ],
            selected: {style},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onStyleChanged(s.first),
          ),
          if (showHint) ...[
            const SizedBox(height: Insets.xs),
            Text(
              _styleHints[style]!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ],
    );
  }
}
