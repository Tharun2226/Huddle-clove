import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/config/org_config.dart';
import '../../../../core/di/providers.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/app_feedback.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/huddle_card.dart';
import '../../domain/meeting.dart';
import '../../domain/task.dart';

/// Opens a create/edit meeting sheet. When [task] is set, the meeting is linked
/// via `taskId`. Pass [meeting] to edit an existing one.
Future<Meeting?> showCreateMeetingSheet(
  BuildContext context,
  WidgetRef ref, {
  Task? task,
  Meeting? meeting,
}) {
  return showModalBottomSheet<Meeting>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _CreateMeetingSheet(task: task, meeting: meeting),
  );
}

class _CreateMeetingSheet extends ConsumerStatefulWidget {
  const _CreateMeetingSheet({this.task, this.meeting});

  final Task? task;
  final Meeting? meeting;

  @override
  ConsumerState<_CreateMeetingSheet> createState() => _CreateMeetingSheetState();
}

class _CreateMeetingSheetState extends ConsumerState<_CreateMeetingSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _agenda;
  late final TextEditingController _location;
  late final TextEditingController _link;
  late final TextEditingController _notes;
  late final TextEditingController _guestName;

  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late DateTime _oneOffDate;
  late Set<String> _attendeeIds;
  late List<ExternalAttendee> _externalAttendees;
  late bool _isOnline;
  MeetingRecurrence _recurrence = MeetingRecurrence.none;
  final Set<int> _weekdays = {};
  var _saving = false;
  String? _error;

  bool get _isEditing => widget.meeting != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.meeting;
    final task = widget.task;
    final now = DateTime.now();
    final meId = ref.read(currentUserProvider).id;

    _guestName = TextEditingController();

    if (existing != null) {
      _title = TextEditingController(text: existing.title);
      _agenda = TextEditingController(text: existing.notes);
      _location = TextEditingController(text: existing.location);
      _link = TextEditingController(text: existing.link);
      _notes = TextEditingController();
      _startTime = TimeOfDay.fromDateTime(existing.start);
      _endTime = TimeOfDay.fromDateTime(existing.end);
      _oneOffDate = DateTime(
        existing.start.year,
        existing.start.month,
        existing.start.day,
      );
      _attendeeIds = {...existing.attendeeIds, meId};
      _externalAttendees = [...existing.externalAttendees];
      _isOnline = _clampOnline(existing.isOnline);
      _recurrence = existing.recurrence;
      _weekdays.addAll(existing.weekdays);
    } else {
      final hour = (now.hour + 1).clamp(0, 23);
      _title = TextEditingController(
        text: task == null ? '' : 'Meeting: ${task.title}',
      );
      _agenda = TextEditingController(
        text: task == null
            ? ''
            : task.description.trim().isEmpty
                ? ''
                : task.description,
      );
      _location = TextEditingController();
      _link = TextEditingController();
      _notes = TextEditingController();
      _startTime = TimeOfDay(hour: hour, minute: 0);
      _endTime = TimeOfDay(hour: hour, minute: 30);
      if (_endTime.hour == _startTime.hour &&
          _endTime.minute <= _startTime.minute) {
        _endTime = TimeOfDay(hour: (hour + 1).clamp(0, 23), minute: 0);
      }
      _oneOffDate = DateTime(now.year, now.month, now.day);
      _attendeeIds = {meId};
      _externalAttendees = [];
      _isOnline = _clampOnline(true);
      if (task?.dueDate != null) {
        final due = task!.dueDate!;
        _oneOffDate = DateTime(due.year, due.month, due.day);
        _startTime = TimeOfDay(hour: due.hour, minute: due.minute);
        final endMinutes = due.hour * 60 + due.minute + 30;
        _endTime =
            TimeOfDay(hour: (endMinutes ~/ 60) % 24, minute: endMinutes % 60);
      }
    }
  }

  bool _clampOnline(bool preferred) {
    final config = ref.read(orgConfigProvider);
    if (!config.allowsOnlineMeetings) return false;
    if (!config.allowsInPersonMeetings) return true;
    return preferred;
  }

  @override
  void dispose() {
    _title.dispose();
    _agenda.dispose();
    _location.dispose();
    _link.dispose();
    _notes.dispose();
    _guestName.dispose();
    super.dispose();
  }

  DateTime _combine(DateTime day, TimeOfDay time) =>
      DateTime(day.year, day.month, day.day, time.hour, time.minute);

  DateTime get _anchorDay {
    if (_recurrence == MeetingRecurrence.none) return _oneOffDate;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _addExternalGuest() {
    final name = _guestName.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter an attendee name.');
      return;
    }
    final already = _externalAttendees.any(
      (g) => g.name.toLowerCase() == name.toLowerCase(),
    );
    if (already) {
      setState(() => _error = 'That name is already added.');
      return;
    }
    setState(() {
      _error = null;
      _externalAttendees = [
        ..._externalAttendees,
        ExternalAttendee(name: name),
      ];
      _guestName.clear();
    });
  }

  Future<void> _pickOneOffDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _oneOffDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;
    setState(() => _oneOffDate = DateTime(date.year, date.month, date.day));
  }

  Future<void> _pickStartTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (time == null || !mounted) return;
    setState(() {
      final startMins = _startTime.hour * 60 + _startTime.minute;
      final endMins = _endTime.hour * 60 + _endTime.minute;
      final duration = endMins - startMins;
      _startTime = time;
      final nextEnd = time.hour * 60 + time.minute + (duration > 0 ? duration : 30);
      _endTime = TimeOfDay(hour: (nextEnd ~/ 60) % 24, minute: nextEnd % 60);
    });
  }

  Future<void> _pickEndTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (time == null || !mounted) return;
    setState(() => _endTime = time);
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final me = ref.read(currentUserProvider);
    if (_isOnline) {
      if (_attendeeIds.isEmpty) {
        setState(() => _error = 'Select at least one attendee.');
        return;
      }
    } else if (_externalAttendees.isEmpty) {
      setState(() => _error = 'Add at least one attendee.');
      return;
    }
    if (_recurrence == MeetingRecurrence.weekly && _weekdays.isEmpty) {
      setState(() => _error = 'Select at least one weekday for weekly meetings.');
      return;
    }

    final start = _combine(_anchorDay, _startTime);
    var end = _combine(_anchorDay, _endTime);
    if (!end.isAfter(start)) {
      end = end.add(const Duration(days: 1));
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final agenda = _agenda.text.trim();
    final extraNotes = _notes.text.trim();
    final notes = [
      if (agenda.isNotEmpty) agenda,
      if (extraNotes.isNotEmpty) extraNotes,
    ].join('\n\n');

    final draft = MeetingDraft(
      title: _title.text.trim(),
      start: start,
      end: end,
      // Online: team users. In-person: organizer only + named guests.
      attendeeIds: _isOnline ? {..._attendeeIds, me.id}.toList() : [me.id],
      location: _location.text.trim(),
      notes: notes,
      link: _isOnline ? _link.text.trim() : '',
      isOnline: _isOnline,
      externalAttendees: _isOnline ? const [] : _externalAttendees,
      recurrence: _recurrence,
      weekdays: _weekdays.toList()..sort(),
      taskId: widget.meeting?.taskId ?? widget.task?.id,
    );
    try {
      final repo = ref.read(taskRepositoryProvider);
      final meeting = _isEditing
          ? await repo.updateMeeting(
              widget.meeting!.id,
              draft,
              actorId: me.id,
            )
          : await repo.createMeeting(draft, actorId: me.id);
      if (!mounted) return;
      AppFeedback.successAndPop(
        context,
        message: _isEditing ? 'Meeting updated' : 'Meeting scheduled',
        popResult: meeting,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = AppFeedback.apiMessage(e, 'Could not save meeting');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final maxHeight = media.size.height * 0.9;
    final isOneOff = _recurrence == MeetingRecurrence.none;
    final me = ref.watch(currentUserProvider);
    final team = ref.watch(teamProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Insets.screen,
                0,
                Insets.screen,
                Insets.screen,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isEditing
                        ? 'Edit meeting'
                        : widget.task == null
                            ? 'New meeting'
                            : 'Meeting from task',
                    style: context.text.headlineSmall,
                  ),
                  if (widget.task != null || widget.meeting?.taskId != null) ...[
                    const SizedBox(height: Insets.sm),
                    Text(
                      widget.task != null
                          ? 'Linked to “${widget.task!.title}”'
                          : 'Linked to this task',
                      style: context.text.bodySmall?.copyWith(color: palette.neutral),
                    ),
                  ],
                  const SizedBox(height: Insets.xl),

                  Builder(
                    builder: (context) {
                      final config = ref.watch(orgConfigProvider);
                      final allowOnline = config.allowsOnlineMeetings;
                      final allowInPerson = config.allowsInPersonMeetings;
                      final canToggle = allowOnline && allowInPerson;
                      // Org locked to one mode — don't show a fake choice UI.
                      if (!canToggle) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: Insets.xl),
                          child: Row(
                            children: [
                              Icon(
                                _isOnline
                                    ? Icons.videocam_outlined
                                    : Icons.place_outlined,
                                size: 18,
                                color: palette.neutral,
                              ),
                              const SizedBox(width: Insets.sm),
                              Text(
                                _isOnline
                                    ? 'Online meeting'
                                    : 'In-person meeting',
                                style: context.text.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Meeting type',
                            style: context.text.labelMedium,
                          ),
                          const SizedBox(height: Insets.sm),
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: true,
                                label: Text('Online'),
                                icon: Icon(
                                  Icons.videocam_outlined,
                                  size: 18,
                                ),
                              ),
                              ButtonSegment(
                                value: false,
                                label: Text('In person'),
                                icon: Icon(
                                  Icons.place_outlined,
                                  size: 18,
                                ),
                              ),
                            ],
                            selected: {_isOnline},
                            onSelectionChanged: (s) => setState(() {
                              _isOnline = s.first;
                              _error = null;
                            }),
                          ),
                          const SizedBox(height: Insets.xl),
                        ],
                      );
                    },
                  ),

                  Text('Meeting title', style: context.text.labelMedium),
                  const SizedBox(height: Insets.sm),
                  TextFormField(
                    controller: _title,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Meeting title'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Add a title' : null,
                  ),
                  const SizedBox(height: Insets.xl),

                  Text(
                    'Agenda / description (optional)',
                    style: context.text.labelMedium,
                  ),
                  const SizedBox(height: Insets.sm),
                  TextFormField(
                    controller: _agenda,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Topics to cover…',
                    ),
                  ),
                  const SizedBox(height: Insets.xl),

                  Text('Repeats', style: context.text.labelMedium),
                  const SizedBox(height: Insets.sm),
                  Wrap(
                    spacing: Insets.sm,
                    runSpacing: Insets.sm,
                    children: [
                      for (final option in MeetingRecurrence.values)
                        ChoiceChip(
                          label: Text(option.label),
                          selected: _recurrence == option,
                          onSelected: (_) => setState(() {
                            _recurrence = option;
                            if (option == MeetingRecurrence.weekly &&
                                _weekdays.isEmpty) {
                              _weekdays.add(DateTime.now().weekday);
                            }
                          }),
                        ),
                    ],
                  ),
                  if (_recurrence == MeetingRecurrence.weekly) ...[
                    const SizedBox(height: Insets.md),
                    Text(
                      'On these days',
                      style: context.text.bodySmall?.copyWith(color: palette.neutral),
                    ),
                    const SizedBox(height: Insets.sm),
                    Wrap(
                      spacing: Insets.sm,
                      runSpacing: Insets.sm,
                      children: [
                        for (final entry in const [
                          (1, 'Mon'),
                          (2, 'Tue'),
                          (3, 'Wed'),
                          (4, 'Thu'),
                          (5, 'Fri'),
                          (6, 'Sat'),
                          (7, 'Sun'),
                        ])
                          FilterChip(
                            label: Text(entry.$2),
                            selected: _weekdays.contains(entry.$1),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                _weekdays.add(entry.$1);
                              } else {
                                _weekdays.remove(entry.$1);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: Insets.xl),

                  Text(
                    isOneOff ? 'Date & time' : 'Time',
                    style: context.text.labelMedium,
                  ),
                  const SizedBox(height: Insets.sm),
                  if (!isOneOff)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Insets.sm),
                      child: Text(
                        _recurrence == MeetingRecurrence.daily
                            ? 'Runs every day at this time'
                            : 'Runs on the selected days at this time',
                        style: context.text.bodySmall?.copyWith(
                          color: palette.neutral,
                        ),
                      ),
                    ),
                  if (isOneOff) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickOneOffDate,
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: Text(Fmt.friendlyDate(_oneOffDate)),
                      ),
                    ),
                    const SizedBox(height: Insets.sm),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickStartTime,
                          icon: const Icon(Icons.schedule_rounded, size: 18),
                          label: Text('Starts ${_startTime.format(context)}'),
                        ),
                      ),
                      const SizedBox(width: Insets.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickEndTime,
                          icon: const Icon(Icons.timelapse_rounded, size: 18),
                          label: Text('Ends ${_endTime.format(context)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Insets.xl),

                  if (_isOnline) ...[
                    Text('Meeting link (optional)', style: context.text.labelMedium),
                    const SizedBox(height: Insets.sm),
                    TextFormField(
                      controller: _link,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        hintText: 'https://meet.google.com/…',
                        prefixIcon: Icon(Icons.link_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: Insets.xl),
                  ],

                  Text('Location (optional)', style: context.text.labelMedium),
                  const SizedBox(height: Insets.sm),
                  TextFormField(
                    controller: _location,
                    decoration: InputDecoration(
                      hintText: _isOnline
                          ? 'Room / dial-in notes…'
                          : 'Office, room, address…',
                      prefixIcon: const Icon(Icons.place_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: Insets.xl),

                  Text('Attendees', style: context.text.labelMedium),
                  const SizedBox(height: Insets.sm),
                  if (_isOnline)
                    HuddleCard(
                      padding: const EdgeInsets.all(Insets.sm),
                      child: Column(
                        children: [
                          for (final user in team)
                            CheckboxListTile(
                              value: _attendeeIds.contains(user.id),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: Insets.sm,
                              ),
                              controlAffinity: ListTileControlAffinity.trailing,
                              title: Row(
                                children: [
                                  UserAvatar(user: user, size: 28),
                                  const SizedBox(width: Insets.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          user.id == me.id ? 'Me' : user.name,
                                          style: context.text.bodyMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          user.roleNames.isNotEmpty
                                              ? user.roleNames.first
                                              : user.role.label,
                                          style:
                                              context.text.bodySmall?.copyWith(
                                            color: palette.neutral,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _attendeeIds.add(user.id);
                                  } else if (user.id != me.id) {
                                    _attendeeIds.remove(user.id);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    )
                  else ...[
                    if (_externalAttendees.isNotEmpty) ...[
                      Wrap(
                        spacing: Insets.sm,
                        runSpacing: Insets.sm,
                        children: [
                          for (var i = 0; i < _externalAttendees.length; i++)
                            InputChip(
                              avatar: CircleAvatar(
                                backgroundColor:
                                    context.colors.primary.withValues(alpha: 0.12),
                                child: Text(
                                  _externalAttendees[i].name.isEmpty
                                      ? '?'
                                      : _externalAttendees[i]
                                          .name[0]
                                          .toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.colors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              label: Text(_externalAttendees[i].name),
                              onDeleted: () => setState(() {
                                _externalAttendees = [
                                  for (var j = 0;
                                      j < _externalAttendees.length;
                                      j++)
                                    if (j != i) _externalAttendees[j],
                                ];
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: Insets.md),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _guestName,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _addExternalGuest(),
                            decoration: const InputDecoration(
                              hintText: 'Attendee name',
                              prefixIcon: Icon(Icons.person_outline, size: 20),
                            ),
                          ),
                        ),
                        const SizedBox(width: Insets.sm),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: FilledButton.tonalIcon(
                            onPressed: _addExternalGuest,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: Insets.xl),

                  Text('Notes (optional)', style: context.text.labelMedium),
                  const SizedBox(height: Insets.sm),
                  TextFormField(
                    controller: _notes,
                    minLines: 2,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Anything else to remember…',
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: Insets.md),
                    Text(
                      _error!,
                      style: context.text.bodySmall?.copyWith(color: palette.danger),
                    ),
                  ],

                  const SizedBox(height: Insets.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isEditing ? 'Save changes' : 'Create meeting'),
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
