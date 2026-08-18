import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/catalog_icons.dart';
import '../../../../core/config/org_config.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/network/admin_api.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/app_feedback.dart';
import '../../../../shared/widgets/huddle_card.dart';

final _adminOrgProvider = FutureProvider<AdminOrg>((ref) {
  return ref.read(adminApiProvider).getOrg();
});

final _adminRolesProvider = FutureProvider<List<AdminRole>>((ref) {
  return ref.read(adminApiProvider).listRoles();
});

final _adminPermissionsProvider =
    FutureProvider<List<AdminPermission>>((ref) {
  return ref.read(adminApiProvider).listPermissions();
});

final _adminStatusesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(adminApiProvider).listTaskStatuses();
});

final _adminPrioritiesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(adminApiProvider).listTaskPriorities();
});

final _adminTagsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(adminApiProvider).listTaskTags();
});

class OrgSettingsScreen extends ConsumerStatefulWidget {
  const OrgSettingsScreen({super.key});

  @override
  ConsumerState<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends ConsumerState<OrgSettingsScreen> {
  final _nameCtrl = TextEditingController();
  var _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshOrgConfig() async {
    try {
      final result = await ref.read(authApiProvider).me();
      if (result.config != null) {
        ref.read(orgConfigProvider.notifier).set(result.config!);
      }
    } catch (_) {}
  }

  Future<void> _rename() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(adminApiProvider).renameOrg(name);
      ref.invalidate(_adminOrgProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Organization renamed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppFeedback.apiMessage(e, 'Could not rename organization'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setMeetingMode(MeetingMode mode) async {
    setState(() => _saving = true);
    try {
      await ref.read(adminApiProvider).updateOrg(meetingMode: mode);
      ref.invalidate(_adminOrgProvider);
      await _refreshOrgConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Meeting type updated: ${mode.label}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppFeedback.apiMessage(e, 'Could not update meeting type'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setShowTags(bool enabled) async {
    setState(() => _saving = true);
    try {
      await ref.read(adminApiProvider).updateOrg(showTags: enabled);
      ref.invalidate(_adminOrgProvider);
      await _refreshOrgConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled ? 'Tags are now visible' : 'Tags are now hidden',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppFeedback.apiMessage(e, 'Could not update tags setting'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orgAsync = ref.watch(_adminOrgProvider);
    final rolesAsync = ref.watch(_adminRolesProvider);
    final permsAsync = ref.watch(_adminPermissionsProvider);
    final statusesAsync = ref.watch(_adminStatusesProvider);
    final prioritiesAsync = ref.watch(_adminPrioritiesProvider);
    final tagsAsync = ref.watch(_adminTagsProvider);
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('Organization Settings')),
      body: ListView(
        padding: const EdgeInsets.all(Insets.screen),
        children: [
          HuddleCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Organization Name', style: context.text.titleMedium),
                const SizedBox(height: Insets.sm),
                orgAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Error: $e'),
                  data: (org) {
                    if (_nameCtrl.text.isEmpty) _nameCtrl.text = org.name;
                    return Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: Insets.md),
                        FilledButton(
                          onPressed: _saving ? null : _rename,
                          child: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Save'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.lg),

          HuddleCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Meeting types', style: context.text.titleMedium),
                const SizedBox(height: Insets.xs),
                Text(
                  'Control whether members can schedule online, in-person, or both.',
                  style: context.text.bodyMedium?.copyWith(color: palette.neutral),
                ),
                const SizedBox(height: Insets.md),
                orgAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Error: $e'),
                  data: (org) => SegmentedButton<MeetingMode>(
                    showSelectedIcon: false,
                    segments: [
                      for (final mode in MeetingMode.values)
                        ButtonSegment(
                          value: mode,
                          label: Text(mode.label),
                          enabled: !_saving,
                        ),
                    ],
                    selected: {org.meetingMode},
                    onSelectionChanged: _saving
                        ? null
                        : (s) {
                            final next = s.first;
                            if (next != org.meetingMode) {
                              _setMeetingMode(next);
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.lg),

          HuddleCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Task tags', style: context.text.titleMedium),
                const SizedBox(height: Insets.xs),
                Text(
                  'Show or hide tags on tasks across the app.',
                  style: context.text.bodyMedium?.copyWith(color: palette.neutral),
                ),
                const SizedBox(height: Insets.sm),
                orgAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Error: $e'),
                  data: (org) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(org.showTags ? 'Tags visible' : 'Tags hidden'),
                    subtitle: Text(
                      org.showTags
                          ? 'Members can see and set tags on tasks'
                          : 'Tags stay hidden on create, lists, and details',
                      style: context.text.bodySmall
                          ?.copyWith(color: palette.neutral),
                    ),
                    value: org.showTags,
                    onChanged: _saving ? null : _setShowTags,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.lg),

          Text('Roles & permissions', style: context.text.titleMedium),
          const SizedBox(height: Insets.xs),
          Text(
            'Choose what each role can do. Changes apply on the user’s next request.',
            style: context.text.bodyMedium?.copyWith(color: palette.neutral),
          ),
          const SizedBox(height: Insets.md),
          rolesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: Insets.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Failed to load roles: $e'),
            data: (roles) {
              final permissions =
                  permsAsync.asData?.value ?? const <AdminPermission>[];
              if (roles.isEmpty) {
                return Text(
                  'No roles configured.',
                  style: context.text.bodySmall?.copyWith(color: palette.neutral),
                );
              }
              return Column(
                children: [
                  for (final role in roles) ...[
                    _RolePermissionsCard(
                      role: role,
                      catalog: permissions,
                      onSaved: () => ref.invalidate(_adminRolesProvider),
                    ),
                    const SizedBox(height: Insets.sm),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: Insets.xl),

          _CatalogSection(
            title: 'Task statuses',
            subtitle: 'Name, color, icon, default, and done marker.',
            showIcon: true,
            items: statusesAsync,
            onAdd: () => _openCatalogEditor(
              kind: _CatalogKind.status,
              onSaved: () async {
                ref.invalidate(_adminStatusesProvider);
                await _refreshOrgConfig();
              },
            ),
            onEdit: (item) => _openCatalogEditor(
              kind: _CatalogKind.status,
              existing: item,
              onSaved: () async {
                ref.invalidate(_adminStatusesProvider);
                await _refreshOrgConfig();
              },
            ),
            onDelete: (item) async {
              await ref.read(adminApiProvider).deleteTaskStatus(item['id'] as String);
              ref.invalidate(_adminStatusesProvider);
              await _refreshOrgConfig();
            },
            showDone: true,
          ),
          const SizedBox(height: Insets.xl),

          _CatalogSection(
            title: 'Task priorities',
            subtitle: 'Name, color, icon, and which one is default.',
            showIcon: true,
            items: prioritiesAsync,
            onAdd: () => _openCatalogEditor(
              kind: _CatalogKind.priority,
              onSaved: () async {
                ref.invalidate(_adminPrioritiesProvider);
                await _refreshOrgConfig();
              },
            ),
            onEdit: (item) => _openCatalogEditor(
              kind: _CatalogKind.priority,
              existing: item,
              onSaved: () async {
                ref.invalidate(_adminPrioritiesProvider);
                await _refreshOrgConfig();
              },
            ),
            onDelete: (item) async {
              await ref
                  .read(adminApiProvider)
                  .deleteTaskPriority(item['id'] as String);
              ref.invalidate(_adminPrioritiesProvider);
              await _refreshOrgConfig();
            },
          ),
          const SizedBox(height: Insets.xl),

          _CatalogSection(
            title: 'Task tags',
            subtitle: 'Labels like Frontend / Backend with colors.',
            items: tagsAsync,
            onAdd: () => _openCatalogEditor(
              kind: _CatalogKind.tag,
              onSaved: () async {
                ref.invalidate(_adminTagsProvider);
                await _refreshOrgConfig();
              },
            ),
            onEdit: (item) => _openCatalogEditor(
              kind: _CatalogKind.tag,
              existing: item,
              onSaved: () async {
                ref.invalidate(_adminTagsProvider);
                await _refreshOrgConfig();
              },
            ),
            onDelete: (item) async {
              await ref.read(adminApiProvider).deleteTaskTag(item['id'] as String);
              ref.invalidate(_adminTagsProvider);
              await _refreshOrgConfig();
            },
          ),
          const SizedBox(height: Insets.xxl),
        ],
      ),
    );
  }

  Future<void> _openCatalogEditor({
    required _CatalogKind kind,
    Map<String, dynamic>? existing,
    required Future<void> Function() onSaved,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CatalogEditorSheet(kind: kind, existing: existing),
    );
    if (saved == true) await onSaved();
  }
}

enum _CatalogKind { status, priority, tag }

class _CatalogSection extends StatelessWidget {
  const _CatalogSection({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    this.showDone = false,
    this.showIcon = false,
  });

  final String title;
  final String subtitle;
  final AsyncValue<List<Map<String, dynamic>>> items;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic> item) onEdit;
  final Future<void> Function(Map<String, dynamic> item) onDelete;
  final bool showDone;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: context.text.bodySmall?.copyWith(color: palette.neutral),
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: Insets.md),
        items.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Failed to load: $e'),
          data: (list) {
            if (list.isEmpty) {
              return Text(
                'None yet. Tap Add to create one.',
                style: context.text.bodySmall?.copyWith(color: palette.neutral),
              );
            }
            return Column(
              children: [
                for (final item in list) ...[
                  HuddleCard(
                    padding: const EdgeInsets.all(Insets.md),
                    child: Row(
                      children: [
                        if (showIcon) ...[
                          Icon(
                            CatalogIcons.resolve(item['icon'] as String?),
                            size: 20,
                            color: parseOrgColor(
                              (item['color'] as String?) ?? '#6B7280',
                            ),
                          ),
                          const SizedBox(width: Insets.sm),
                        ],
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: parseOrgColor(
                              (item['color'] as String?) ?? '#6B7280',
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: Text(
                            item['name'] as String? ?? '',
                            style: context.text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (item['isDefault'] == true)
                          Padding(
                            padding: const EdgeInsets.only(right: Insets.xs),
                            child: Text(
                              'Default',
                              style: context.text.labelSmall
                                  ?.copyWith(color: palette.info),
                            ),
                          ),
                        if (showDone && item['isDone'] == true)
                          Padding(
                            padding: const EdgeInsets.only(right: Insets.xs),
                            child: Text(
                              'Done',
                              style: context.text.labelSmall
                                  ?.copyWith(color: palette.success),
                            ),
                          ),
                        IconButton(
                          tooltip: 'Edit',
                          onPressed: () => onEdit(item),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Remove item?'),
                                content: Text(
                                  'Remove “${item['name']}”? Existing tasks keep their current values.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Remove'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) await onDelete(item);
                          },
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: palette.danger,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Insets.sm),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CatalogEditorSheet extends ConsumerStatefulWidget {
  const _CatalogEditorSheet({required this.kind, this.existing});

  final _CatalogKind kind;
  final Map<String, dynamic>? existing;

  @override
  ConsumerState<_CatalogEditorSheet> createState() =>
      _CatalogEditorSheetState();
}

class _CatalogEditorSheetState extends ConsumerState<_CatalogEditorSheet> {
  static const _colors = [
    '#6B7280',
    '#EF4444',
    '#F59E0B',
    '#10B981',
    '#3B82F6',
    '#8B5CF6',
    '#EC4899',
    '#14B8A6',
    '#64748B',
  ];

  late final TextEditingController _name;
  late String _color;
  late String _icon;
  late bool _isDefault;
  late bool _isDone;
  var _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;
  bool get _supportsIcon =>
      widget.kind == _CatalogKind.status ||
      widget.kind == _CatalogKind.priority;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?['name'] as String? ?? '');
    _color = (existing?['color'] as String?) ?? '#6B7280';
    _icon = (existing?['icon'] as String?) ??
        (widget.kind == _CatalogKind.priority ? 'remove' : 'circle_outlined');
    _isDefault = existing?['isDefault'] as bool? ?? false;
    _isDone = existing?['isDone'] as bool? ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _title => switch (widget.kind) {
        _CatalogKind.status => _isEdit ? 'Edit status' : 'New status',
        _CatalogKind.priority => _isEdit ? 'Edit priority' : 'New priority',
        _CatalogKind.tag => _isEdit ? 'Edit tag' : 'New tag',
      };

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final api = ref.read(adminApiProvider);
    final id = widget.existing?['id'] as String?;

    try {
      switch (widget.kind) {
        case _CatalogKind.status:
          if (id == null) {
            await api.createTaskStatus(
              name: name,
              color: _color,
              icon: _icon,
              isDefault: _isDefault,
              isDone: _isDone,
            );
          } else {
            await api.updateTaskStatus(
              id,
              name: name,
              color: _color,
              icon: _icon,
              isDefault: _isDefault,
              isDone: _isDone,
            );
          }
        case _CatalogKind.priority:
          if (id == null) {
            await api.createTaskPriority(
              name: name,
              color: _color,
              icon: _icon,
              isDefault: _isDefault,
            );
          } else {
            await api.updateTaskPriority(
              id,
              name: name,
              color: _color,
              icon: _icon,
              isDefault: _isDefault,
            );
          }
        case _CatalogKind.tag:
          if (id == null) {
            await api.createTaskTag(
              name: name,
              color: _color,
              isDefault: _isDefault,
            );
          } else {
            await api.updateTaskTag(
              id,
              name: name,
              color: _color,
              isDefault: _isDefault,
            );
          }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Insets.screen,
        0,
        Insets.screen,
        Insets.screen + bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title, style: context.text.titleLarge),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
          if (_supportsIcon) ...[
            const SizedBox(height: Insets.lg),
            Text('Icon', style: context.text.labelLarge),
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                for (final entry in CatalogIcons.entries)
                  InkWell(
                    onTap: () => setState(() => _icon = entry.key),
                    borderRadius: BorderRadius.circular(Radii.sm),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _icon == entry.key
                            ? parseOrgColor(_color).withValues(alpha: 0.14)
                            : palette.neutralContainer,
                        borderRadius: BorderRadius.circular(Radii.sm),
                        border: Border.all(
                          color: _icon == entry.key
                              ? parseOrgColor(_color)
                              : palette.hairline,
                          width: _icon == entry.key ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        entry.icon,
                        size: 20,
                        color: _icon == entry.key
                            ? parseOrgColor(_color)
                            : palette.neutral,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Insets.lg),
          Text('Color', style: context.text.labelLarge),
          const SizedBox(height: Insets.sm),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final hex in _colors)
                InkWell(
                  onTap: () => setState(() => _color = hex),
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: parseOrgColor(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == hex
                            ? context.colors.primary
                            : palette.hairline,
                        width: _color == hex ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Insets.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Default'),
            subtitle: Text(
              'Used when creating new tasks',
              style: context.text.bodySmall?.copyWith(color: palette.neutral),
            ),
            value: _isDefault,
            onChanged: (v) => setState(() => _isDefault = v),
          ),
          if (widget.kind == _CatalogKind.status)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Marks task done'),
              subtitle: Text(
                'Completing a task moves it here',
                style: context.text.bodySmall?.copyWith(color: palette.neutral),
              ),
              value: _isDone,
              onChanged: (v) => setState(() => _isDone = v),
            ),
          if (_error != null) ...[
            const SizedBox(height: Insets.sm),
            Text(
              _error!,
              style: context.text.bodySmall?.copyWith(color: palette.danger),
            ),
          ],
          const SizedBox(height: Insets.lg),
          SizedBox(
            width: double.infinity,
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
                  : Text(_isEdit ? 'Save changes' : 'Create'),
            ),
          ),
        ],
      ),
      ),
      ),
    );
  }
}

class _RolePermissionsCard extends ConsumerStatefulWidget {
  const _RolePermissionsCard({
    required this.role,
    required this.catalog,
    required this.onSaved,
  });

  final AdminRole role;
  final List<AdminPermission> catalog;
  final VoidCallback onSaved;

  @override
  ConsumerState<_RolePermissionsCard> createState() =>
      _RolePermissionsCardState();
}

class _RolePermissionsCardState extends ConsumerState<_RolePermissionsCard> {
  late Set<String> _selected;
  var _expanded = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.role.permissions};
  }

  @override
  void didUpdateWidget(covariant _RolePermissionsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.role.permissions != widget.role.permissions) {
      _selected = {...widget.role.permissions};
    }
  }

  bool get _dirty {
    final original = widget.role.permissions.toSet();
    return _selected.length != original.length ||
        !_selected.containsAll(original);
  }

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    setState(() => _saving = true);
    try {
      await ref.read(adminApiProvider).updateRolePermissions(
            roleId: widget.role.id,
            permissions: _selected.toList()..sort(),
          );
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.role.name} permissions updated'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update permissions: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final role = widget.role;
    final catalog = widget.catalog;

    return HuddleCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: role.isAdmin
                ? null
                : () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(Radii.md),
            child: Padding(
              padding: const EdgeInsets.all(Insets.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          role.name,
                          style: context.text.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          role.isAdmin
                              ? 'Admins have full access automatically'
                              : '${_selected.length} permission${_selected.length == 1 ? '' : 's'}',
                          style: context.text.bodySmall
                              ?.copyWith(color: palette.neutral),
                        ),
                      ],
                    ),
                  ),
                  if (role.isAdmin)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: palette.warningContainer,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: Text(
                        'Admin',
                        style: context.text.labelSmall
                            ?.copyWith(color: palette.warning),
                      ),
                    ),
                  if (role.isDefault) ...[
                    const SizedBox(width: Insets.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: palette.infoContainer,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: Text(
                        'Default',
                        style: context.text.labelSmall
                            ?.copyWith(color: palette.info),
                      ),
                    ),
                  ],
                  if (!role.isAdmin) ...[
                    const SizedBox(width: Insets.xs),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: palette.neutral,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded && !role.isAdmin) ...[
            const Divider(height: 1),
            if (catalog.isEmpty)
              const Padding(
                padding: EdgeInsets.all(Insets.md),
                child: LinearProgressIndicator(),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.sm,
                  Insets.sm,
                  Insets.sm,
                  Insets.md,
                ),
                child: Column(
                  children: [
                    for (final perm in catalog)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: Insets.sm,
                        ),
                        value: _selected.contains(perm.code),
                        title: Text(perm.label),
                        subtitle: Text(
                          perm.code,
                          style: context.text.bodySmall
                              ?.copyWith(color: palette.neutral),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selected.add(perm.code);
                            } else {
                              _selected.remove(perm.code);
                            }
                          });
                        },
                      ),
                    const SizedBox(height: Insets.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _dirty && !_saving ? _save : null,
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save permissions'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
