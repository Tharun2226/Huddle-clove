import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/config/catalog_icons.dart';
import '../../../../core/config/org_config.dart';
import '../../../../core/di/providers.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/app_feedback.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/huddle_card.dart';
import '../../domain/task.dart';
import '../providers/task_providers.dart';
import '../widgets/task_visuals.dart';

/// Create and edit in one screen — the fields are identical, and keeping them
/// together means the two flows cannot drift apart.
class TaskEditorScreen extends ConsumerStatefulWidget {
  const TaskEditorScreen({
    super.key,
    this.taskId,
    this.initialAssigneeId,
    this.initialDueDate,
  });

  /// Null means "create".
  final String? taskId;

  /// Pre-selects a person when creating from the team board.
  final String? initialAssigneeId;

  /// Prefills due calendar day when creating (defaults to today @ 17:00).
  final DateTime? initialDueDate;

  @override
  ConsumerState<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends ConsumerState<TaskEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  final _checklistInput = TextEditingController();
  final _tagInput = TextEditingController();
  late final TextEditingController _others;

  late Set<String> _assigneeIds;
  late String? _statusId;
  late String? _priorityId;
  late TaskStatus _status;
  late TaskPriority _priority;
  DateTime? _dueDate;
  final List<String> _tags = [];
  final List<String> _checklist = [];
  bool _saving = false;
  bool _showOthers = false;

  bool get _isEditing => widget.taskId != null;

  static List<String> _parseOthers(String raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final part in raw.split(RegExp(r'[\n,;]+'))) {
      final name = part.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (!seen.add(key)) continue;
      out.add(name);
    }
    return out;
  }

  bool get _hasExternalAssignees => _parseOthers(_others.text).isNotEmpty;

  bool get _hasAssignees => _assigneeIds.isNotEmpty || _hasExternalAssignees;

  String? _assigneeError;
  String? _dueDateError;

  @override
  void initState() {
    super.initState();
    final existing = widget.taskId == null
        ? null
        : ref.read(taskByIdProvider(widget.taskId!));
    final me = ref.read(sessionControllerProvider);
    final config = ref.read(orgConfigProvider);

    _title = TextEditingController(text: existing?.title ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _others = TextEditingController(
      text: (existing?.externalAssignees ?? const []).join('\n'),
    );
    _showOthers = existing?.externalAssignees.isNotEmpty == true;
    final initial = existing?.allAssigneeIds ??
        [
          if (widget.initialAssigneeId != null) widget.initialAssigneeId!,
          if (widget.initialAssigneeId == null && me != null) me.id,
        ];
    _assigneeIds = {...initial};
    // Default to Me on create only — Others-only tasks stay unchecked for org.
    if (!_isEditing && _assigneeIds.isEmpty && me != null) {
      _assigneeIds = {me.id};
    }

    _status = existing?.status ?? TaskStatus.todo;
    _priority = existing?.priority ?? TaskPriority.normal;
    _statusId = existing?.statusId.isNotEmpty == true
        ? existing!.statusId
        : (existing != null
            ? existing.orgStatus(config)?.id
            : config.defaultStatus?.id);
    _priorityId = existing?.priorityId.isNotEmpty == true
        ? existing!.priorityId
        : (existing != null
            ? existing.orgPriority(config)?.id
            : config.defaultPriority?.id);
    if (_statusId == null && config.taskStatuses.isNotEmpty) {
      _statusId = config.defaultStatus?.id ?? config.taskStatuses.first.id;
    }
    if (_priorityId == null && config.taskPriorities.isNotEmpty) {
      _priorityId =
          config.defaultPriority?.id ?? config.taskPriorities.first.id;
    }
    if (_statusId != null) {
      final org = config.taskStatuses.where((s) => s.id == _statusId).firstOrNull;
      if (org != null) _status = taskStatusFromOrg(org);
    }
    if (_priorityId != null) {
      final org =
          config.taskPriorities.where((p) => p.id == _priorityId).firstOrNull;
      if (org != null) _priority = taskPriorityFromOrg(org);
    }
    _dueDate = existing?.dueDate;
    if (_dueDate == null && !_isEditing) {
      final now = DateTime.now();
      final day = widget.initialDueDate ?? DateTime(now.year, now.month, now.day);
      // Never start in the past — clamp to today.
      final today = DateTime(now.year, now.month, now.day);
      final safeDay = day.isBefore(today) ? today : day;
      _dueDate = DateTime(safeDay.year, safeDay.month, safeDay.day, 17, 0);
    }
    _tags.addAll(existing?.tags ?? const []);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _others.dispose();
    _checklistInput.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  void _addChecklistItem() {
    final label = _checklistInput.text.trim();
    if (label.isEmpty) return;
    setState(() {
      _checklist.add(label);
      _checklistInput.clear();
    });
  }

  void _addTag([String? raw]) {
    final tag = (raw ?? _tagInput.text).trim();
    if (tag.isEmpty) return;
    final exists = _tags.any((t) => t.toLowerCase() == tag.toLowerCase());
    if (exists) {
      _tagInput.clear();
      return;
    }
    setState(() {
      _tags.add(tag);
      _tagInput.clear();
    });
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = today.add(const Duration(days: 365 * 2));
    var initial = _dueDate ?? today;
    if (initial.isBefore(today)) initial = today;

    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: today,
      lastDate: last,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _dueDate ?? DateTime(now.year, now.month, now.day, 17),
      ),
    );
    if (!mounted) return;
    if (time == null) return;

    setState(() {
      _dueDate = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _dueDateError = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;

    final externalAssignees = _parseOthers(_others.text);
    String? assigneeError;
    String? dueDateError;

    if (!_hasAssignees) {
      assigneeError =
          'Select someone in the org or add at least one name under Others';
    }
    if (_dueDate == null) {
      dueDateError = 'Pick a due date';
    }

    if (assigneeError != null || dueDateError != null) {
      setState(() {
        _assigneeError = assigneeError;
        _dueDateError = dueDateError;
      });
      return;
    }

    setState(() {
      _assigneeError = null;
      _dueDateError = null;
      _saving = true;
    });

    final me = ref.read(currentUserProvider);
    final repo = ref.read(taskRepositoryProvider);
    final assigneeList = _assigneeIds.toList();
    // DB still needs an owner when only external names are listed.
    final primaryAssigneeId =
        assigneeList.isNotEmpty ? assigneeList.first : me.id;

    try {
      final config = ref.read(orgConfigProvider);
      final resolvedStatusId = _statusId ??
          config.taskStatuses
              .where((s) => s.slug == switch (_status) {
                    TaskStatus.todo => 'todo',
                    TaskStatus.inProgress => 'in_progress',
                    TaskStatus.inReview => 'in_review',
                    TaskStatus.done => 'done',
                  })
              .firstOrNull
              ?.id;
      final resolvedPriorityId = _priorityId ??
          config.taskPriorities
              .where((p) => p.slug == _priority.name)
              .firstOrNull
              ?.id;

      if (_isEditing) {
        final existing = ref.read(taskByIdProvider(widget.taskId!));
        if (existing == null) return;
        await repo.updateTask(
          existing.copyWith(
            title: _title.text.trim(),
            description: _description.text.trim(),
            status: _status,
            priority: _priority,
            statusId: resolvedStatusId ?? existing.statusId,
            priorityId: resolvedPriorityId ?? existing.priorityId,
            dueDate: _dueDate,
            clearDueDate: false,
            assigneeId: primaryAssigneeId,
            assigneeIds: assigneeList,
            externalAssignees: externalAssignees,
            tags: List<String>.from(_tags),
          ),
          actorId: me.id,
        );
      } else {
        await repo.createTask(
          TaskDraft(
            title: _title.text.trim(),
            description: _description.text.trim(),
            status: _status,
            priority: _priority,
            statusId: resolvedStatusId,
            priorityId: resolvedPriorityId,
            dueDate: _dueDate,
            assigneeId: primaryAssigneeId,
            assigneeIds: assigneeList,
            externalAssignees: externalAssignees,
            tags: List<String>.from(_tags),
            checklist: List<String>.from(_checklist),
          ),
          actorId: me.id,
        );
      }

      if (!mounted) return;
      AppFeedback.successAndPop(
        context,
        message: _isEditing ? 'Task updated' : 'Task created',
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(
        AppFeedback.messengerOf(context),
        AppFeedback.apiMessage(e, 'Could not save task'),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isManager = ref.watch(isManagerProvider);
    final team = ref.watch(teamProvider);
    final me = ref.watch(currentUserProvider);
    // Members can only create work for themselves; managers assign to anyone.
    final assignable = isManager ? team : [me];
    final suggestedTags = ref.watch(orgConfigProvider).taskTags;
    final tagNames = suggestedTags.isNotEmpty
        ? [for (final t in suggestedTags) t.name]
        : const ['Frontend', 'Backend', 'Design', 'Mobile', 'QA', 'DevOps'];

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Task' : 'New Task')),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          Insets.screen,
          Insets.md,
          Insets.screen,
          Insets.md + MediaQuery.viewPaddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: palette.card,
          border: Border(top: BorderSide(color: palette.hairline)),
        ),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_isEditing ? 'Save changes' : 'Create task'),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(
            Insets.screen,
            Insets.sm,
            Insets.screen,
            Insets.xxl,
          ),
          children: [
            _Label('Title', required: true),
            TextFormField(
              controller: _title,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'What needs to happen?',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Give the task a title'
                  : null,
            ),
            const SizedBox(height: Insets.xl),

            _Label('Description'),
            TextFormField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Add context, links, acceptance criteria…',
              ),
            ),
            const SizedBox(height: Insets.xl),

            _Label('Assignees', required: true),
            Text(
              'Pick org members and/or tap Others for people outside Huddle. '
              'If Others has names, you can uncheck all org users.',
              style: context.text.bodySmall?.copyWith(color: palette.neutral),
            ),
            if (_assigneeError != null) ...[
              const SizedBox(height: Insets.xs),
              Text(
                _assigneeError!,
                style: context.text.bodySmall?.copyWith(color: palette.danger),
              ),
            ],
            const SizedBox(height: Insets.sm),
            HuddleCard(
              padding: const EdgeInsets.all(Insets.sm),
              child: Column(
                children: [
                  for (final user in assignable)
                    CheckboxListTile(
                      value: _assigneeIds.contains(user.id),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: Insets.sm,
                      ),
                      controlAffinity: ListTileControlAffinity.trailing,
                      title: Row(
                        children: [
                          UserAvatar(user: user, size: 28),
                          const SizedBox(width: Insets.md),
                          Expanded(
                            child: Text(
                              user.id == me.id ? 'Me' : user.name,
                              style: context.text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _assigneeIds.add(user.id);
                          } else {
                            final canRemove =
                                _assigneeIds.length > 1 || _hasExternalAssignees;
                            if (canRemove) {
                              _assigneeIds.remove(user.id);
                            }
                          }
                          _assigneeError = null;
                        });
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: Insets.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _showOthers = !_showOthers),
                icon: Icon(
                  _showOthers
                      ? Icons.expand_less_rounded
                      : Icons.person_add_alt_1_outlined,
                  size: 18,
                ),
                label: Text(_showOthers ? 'Hide others' : 'Others'),
              ),
            ),
            if (_showOthers) ...[
              const SizedBox(height: Insets.sm),
              TextFormField(
                controller: _others,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {
                  _assigneeError = null;
                }),
                decoration: const InputDecoration(
                  hintText: 'One name per line\n(e.g. Client contact, Vendor)',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                  labelText: 'Other people',
                ),
              ),
              const SizedBox(height: Insets.xs),
              Text(
                'These names are free text — they do not need a Huddle account.',
                style: context.text.bodySmall?.copyWith(color: palette.neutral),
              ),
            ],
            const SizedBox(height: Insets.xl),

            if (ref.watch(orgConfigProvider).showTags) ...[
            _Label('Tags'),
            Text(
              'Label areas of work — Frontend, Backend, and more.',
              style: context.text.bodySmall?.copyWith(color: palette.neutral),
            ),
            const SizedBox(height: Insets.sm),
            HuddleCard(
              padding: const EdgeInsets.all(Insets.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Insets.sm,
                    runSpacing: Insets.sm,
                    children: [
                      for (final suggestion in tagNames)
                        FilterChip(
                          label: Text(suggestion),
                          selected: _tags.any(
                            (t) => t.toLowerCase() == suggestion.toLowerCase(),
                          ),
                          onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            if (!_tags.any(
                              (t) =>
                                  t.toLowerCase() == suggestion.toLowerCase(),
                            )) {
                              _tags.add(suggestion);
                            }
                          } else {
                            _tags.removeWhere(
                              (t) =>
                                  t.toLowerCase() == suggestion.toLowerCase(),
                            );
                          }
                        });
                      },
                        ),
                    ],
                  ),
                  if (_tags.isNotEmpty) ...[
                    const SizedBox(height: Insets.md),
                    Wrap(
                      spacing: Insets.sm,
                      runSpacing: Insets.sm,
                      children: [
                        for (final tag in _tags)
                          InputChip(
                            label: Text(tag),
                            onDeleted: () => setState(() => _tags.remove(tag)),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: Insets.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagInput,
                          textInputAction: TextInputAction.done,
                          onSubmitted: _addTag,
                          decoration: const InputDecoration(
                            hintText: 'Add a custom tag',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: Insets.sm),
                      IconButton.filled(
                        onPressed: _addTag,
                        tooltip: 'Add tag',
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: Insets.xl),
            ],

            _Label('Priority'),
            Builder(
              builder: (context) {
                final config = ref.watch(orgConfigProvider);
                final priorities = config.taskPriorities;
                if (priorities.isEmpty) {
                  return Row(
                    children: [
                      for (final priority in TaskPriority.values) ...[
                        Expanded(
                          child: _ChoiceButton(
                            label: priority.label,
                            icon: priority.icon,
                            color: priority.color(palette),
                            selected: _priority == priority,
                            onTap: () => setState(() {
                              _priority = priority;
                              _priorityId = null;
                            }),
                          ),
                        ),
                        if (priority != TaskPriority.values.last)
                          const SizedBox(width: Insets.sm),
                      ],
                    ],
                  );
                }
                return Wrap(
                  spacing: Insets.sm,
                  runSpacing: Insets.sm,
                  children: [
                    for (final priority in priorities)
                      SizedBox(
                        width: (MediaQuery.sizeOf(context).width -
                                Insets.screen * 2 -
                                Insets.sm) /
                            2,
                        child: _ChoiceButton(
                          label: priority.name,
                          icon: CatalogIcons.resolve(
                            priority.icon,
                            fallback: Icons.remove_rounded,
                          ),
                          color: parseOrgColor(priority.color),
                          selected: _priorityId == priority.id,
                          onTap: () => setState(() {
                            _priorityId = priority.id;
                            _priority = taskPriorityFromOrg(priority);
                          }),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: Insets.xl),

            _Label('Status'),
            Builder(
              builder: (context) {
                final config = ref.watch(orgConfigProvider);
                final statuses = config.taskStatuses;
                if (statuses.isEmpty) {
                  return Row(
                    children: [
                      for (final status in TaskStatus.values) ...[
                        Expanded(
                          child: _ChoiceButton(
                            label: status.shortLabel,
                            icon: status.icon,
                            color: status.color(palette),
                            selected: _status == status,
                            onTap: () => setState(() {
                              _status = status;
                              _statusId = null;
                            }),
                          ),
                        ),
                        if (status != TaskStatus.values.last)
                          const SizedBox(width: Insets.sm),
                      ],
                    ],
                  );
                }
                return Wrap(
                  spacing: Insets.sm,
                  runSpacing: Insets.sm,
                  children: [
                    for (final status in statuses)
                      SizedBox(
                        width: (MediaQuery.sizeOf(context).width -
                                Insets.screen * 2 -
                                Insets.sm) /
                            2,
                        child: _ChoiceButton(
                          label: status.name,
                          icon: CatalogIcons.resolve(status.icon),
                          color: parseOrgColor(status.color),
                          selected: _statusId == status.id,
                          onTap: () => setState(() {
                            _statusId = status.id;
                            _status = taskStatusFromOrg(status);
                          }),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (!_isEditing) ...[
              const SizedBox(height: Insets.xl),

              _Label('Checklist'),
              HuddleCard(
                padding: const EdgeInsets.all(Insets.md),
                child: Column(
                  children: [
                    if (_checklist.isEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Optional. Add steps before you create the task.',
                          style: context.text.bodySmall?.copyWith(
                            color: palette.neutral,
                          ),
                        ),
                      ),
                    for (var i = 0; i < _checklist.length; i++) ...[
                      if (i > 0) const SizedBox(height: Insets.sm),
                      Row(
                        children: [
                          Icon(
                            Icons.check_box_outline_blank_rounded,
                            size: 18,
                            color: palette.neutral,
                          ),
                          const SizedBox(width: Insets.sm),
                          Expanded(
                            child: Text(
                              _checklist[i],
                              style: context.text.bodyMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                setState(() => _checklist.removeAt(i)),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: Insets.md),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _checklistInput,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _addChecklistItem(),
                            decoration: const InputDecoration(
                              hintText: 'Add a checklist item',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: Insets.sm),
                        IconButton.filled(
                          onPressed: _addChecklistItem,
                          tooltip: 'Add item',
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: Insets.xl),

            _Label('Due date', required: true),
            if (_dueDateError != null) ...[
              Text(
                _dueDateError!,
                style: context.text.bodySmall?.copyWith(color: palette.danger),
              ),
              const SizedBox(height: Insets.xs),
            ],
            HuddleCard(
              onTap: () async {
                await _pickDueDate();
                if (mounted) setState(() => _dueDateError = null);
              },
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.lg,
                vertical: Insets.lg,
              ),
              child: Row(
                children: [
                  Icon(Icons.event_rounded, size: 18, color: palette.neutral),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: Text(
                      _dueDate == null
                          ? 'Tap to pick date and time'
                          : '${Fmt.friendlyDate(_dueDate!)}, ${Fmt.time(_dueDate!)}',
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: _dueDate == null ? null : FontWeight.w600,
                        color: _dueDate == null ? palette.neutral : null,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: palette.neutral,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: Insets.xs, bottom: Insets.sm),
      child: Text(
        required ? '$text *'.toUpperCase() : text.toUpperCase(),
        style: context.text.labelSmall?.copyWith(color: context.palette.neutral),
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.standard,
        padding: const EdgeInsets.symmetric(vertical: Insets.md),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : palette.card,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.5) : palette.hairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: selected ? color : palette.neutral),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(
                letterSpacing: 0,
                color: selected ? color : palette.neutral,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
