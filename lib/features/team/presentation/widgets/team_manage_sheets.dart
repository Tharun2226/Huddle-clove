import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/domain/app_user.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/config/org_config.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/app_feedback.dart';

Future<void> showCreateUserSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _CreateUserSheet(),
  );
}

class _CreateUserSheet extends ConsumerStatefulWidget {
  const _CreateUserSheet();

  @override
  ConsumerState<_CreateUserSheet> createState() => _CreateUserSheetState();
}

class _CreateUserSheetState extends ConsumerState<_CreateUserSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController(text: 'test@123');
  final _title = TextEditingController();
  var _role = UserRole.member;
  String? _selectedRoleId;
  String? _selectedManagerId;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _title.dispose();
    super.dispose();
  }

  bool get _isAdminCreator => ref.read(currentUserProvider).isAdmin;

  Future<void> _submit() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty) {
      setState(() => _error = 'Name and email are required.');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    final me = ref.read(currentUserProvider);
    final orgRoles = ref.read(orgConfigProvider).roles;
    String? roleId = _selectedRoleId;
    String? managerId;
    var role = _role;
    final password = _password.text;
    final email = _email.text.trim();
    final name = _name.text.trim();

    if (!me.isAdmin) {
      // Managers can only create members on their own team.
      role = UserRole.member;
      roleId = orgRoles
              .where((r) => r.slug == 'member')
              .firstOrNull
              ?.id ??
          orgRoles.where((r) => r.isDefault && !r.isAdmin).firstOrNull?.id ??
          orgRoles.where((r) => !r.isAdmin).firstOrNull?.id;
      managerId = me.id;
    } else {
      managerId = _isMemberSelection ? _selectedManagerId : null;
      if (roleId == null || roleId.isEmpty) {
        setState(() => _error = 'Select a role for the new user.');
        return;
      }
    }

    if (roleId == null || roleId.isEmpty) {
      setState(
        () => _error = 'Member role is not configured for this organization.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionControllerProvider.notifier).createUser(
            email: email,
            name: name,
            password: password,
            roleId: roleId,
            managerId: managerId,
            role: role,
            title: _title.text.trim(),
          );
      // Must use WidgetRef here — refreshing from SessionController cycles
      // with remoteTeamProvider (it watches the session).
      ref.invalidate(remoteTeamProvider);
      await ref.read(remoteTeamProvider.future);
      if (!mounted) return;
      AppFeedback.successAndPop(
        context,
        message: 'User created',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AppFeedback.apiMessage(
            e,
            'Could not create user. Email may already be registered.',
          );
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Insets.screen,
        Insets.sm,
        Insets.screen,
        Insets.xxl + bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Create user', style: context.text.titleLarge),
              const SizedBox(height: Insets.sm),
              Text(
                'No email invite is sent. Share the email and temporary password so they can sign in.',
                style: context.text.bodyMedium?.copyWith(color: palette.neutral),
              ),
              const SizedBox(height: Insets.lg),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  border: OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Title (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Temporary password',
                border: OutlineInputBorder(),
              ),
            ),
            if (_isAdminCreator) ...[
              const SizedBox(height: Insets.md),
              Text('Role', style: context.text.labelLarge),
              const SizedBox(height: Insets.sm),
              _buildRolePicker(),
              if (_isMemberSelection) ...[
                const SizedBox(height: Insets.md),
                Text('Manager', style: context.text.labelLarge),
                const SizedBox(height: Insets.sm),
                _buildManagerPicker(),
              ],
            ] else ...[
              const SizedBox(height: Insets.md),
              Text(
                'Creates a member on your team.',
                style: context.text.bodyMedium?.copyWith(color: palette.neutral),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Insets.md),
              Text(
                _error!,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.error,
                ),
              ),
            ],
            const SizedBox(height: Insets.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create user'),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildRolePicker() {
    final orgRoles = ref.watch(orgConfigProvider).roles;
    if (orgRoles.isNotEmpty) {
      _selectedRoleId ??=
          orgRoles.where((r) => r.isDefault).firstOrNull?.id ??
              orgRoles.first.id;
      final selected =
          orgRoles.where((r) => r.id == _selectedRoleId).firstOrNull;
      return _SelectField(
        valueText: selected?.name ?? 'Select role',
        onTap: () async {
          final picked = await showOptionPickerSheet<String>(
            context: context,
            title: 'Select role',
            options: [
              for (final r in orgRoles)
                PickerOption(value: r.id, label: r.name),
            ],
            selected: _selectedRoleId,
          );
          if (picked != null) setState(() => _selectedRoleId = picked);
        },
      );
    }
    return SegmentedButton<UserRole>(
      segments: const [
        ButtonSegment(value: UserRole.member, label: Text('Member')),
        ButtonSegment(value: UserRole.manager, label: Text('Manager')),
      ],
      selected: {_role},
      onSelectionChanged: (s) => setState(() => _role = s.first),
    );
  }

  Widget _buildManagerPicker() {
    final managers = ref
        .watch(teamProvider)
        .where((user) => user.role == UserRole.manager || user.isAdmin)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (managers.isEmpty) {
      return const Text('No managers available yet.');
    }
    _selectedManagerId ??= managers.first.id;
    final selected =
        managers.where((m) => m.id == _selectedManagerId).firstOrNull;
    return _SelectField(
      valueText: selected == null
          ? 'Select manager'
          : selected.isAdmin
              ? '${selected.name} (Admin)'
              : selected.name,
      onTap: () async {
        final picked = await showOptionPickerSheet<String>(
          context: context,
          title: 'Select manager',
          options: [
            for (final manager in managers)
              PickerOption(
                value: manager.id,
                label: manager.isAdmin
                    ? '${manager.name} (Admin)'
                    : manager.name,
              ),
          ],
          selected: _selectedManagerId,
        );
        if (picked != null) setState(() => _selectedManagerId = picked);
      },
    );
  }

  bool get _isMemberSelection {
    final orgRoles = ref.read(orgConfigProvider).roles;
    if (orgRoles.isNotEmpty) {
      final selected = orgRoles.firstWhere(
        (role) => role.id == _selectedRoleId,
        orElse: () => orgRoles.first,
      );
      return selected.slug == 'member';
    }
    return _role == UserRole.member;
  }
}

Future<void> showChangeRoleSheet(
  BuildContext context,
  WidgetRef ref, {
  required AppUser person,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => _ChangeRoleSheet(person: person),
  );
}

class _ChangeRoleSheet extends ConsumerStatefulWidget {
  const _ChangeRoleSheet({required this.person});

  final AppUser person;

  @override
  ConsumerState<_ChangeRoleSheet> createState() => _ChangeRoleSheetState();
}

class _ChangeRoleSheetState extends ConsumerState<_ChangeRoleSheet> {
  late UserRole _role = widget.person.role;
  String? _selectedRoleId;
  String? _selectedManagerId;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedManagerId = widget.person.managerId;
  }

  String _apiErrorMessage(Object error) {
    try {
      final response = (error as dynamic).response;
      final data = response?.data;
      if (data is Map && data['message'] != null) {
        final message = data['message'];
        if (message is List) return message.join(', ');
        return message.toString();
      }
    } catch (_) {}
    return 'Could not update user.';
  }

  Future<void> _save() async {
    if (_busy) return;
    final orgRoles = ref.read(orgConfigProvider).roles;
    if (orgRoles.isNotEmpty) {
      _selectedRoleId ??= orgRoles
          .where((r) => r.slug == widget.person.role.name)
          .firstOrNull
          ?.id ??
          orgRoles.first.id;
    }

    final roleChanged = orgRoles.isNotEmpty
        ? _selectedRoleId !=
            orgRoles
                .where((r) => r.slug == widget.person.role.name)
                .firstOrNull
                ?.id
        : _role != widget.person.role;
    final managerChanged = _isMemberSelection
        ? _selectedManagerId != widget.person.managerId
        : widget.person.managerId != null;

    if (!roleChanged && !managerChanged) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated =
          await ref.read(sessionControllerProvider.notifier).updateTeammate(
                id: widget.person.id,
                roleId: _selectedRoleId,
                managerId: _isMemberSelection ? _selectedManagerId : '',
                role: orgRoles.isEmpty ? _role : null,
              );
      ref.invalidate(remoteTeamProvider);
      await ref.read(remoteTeamProvider.future);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        final roleLabel = orgRoles.isNotEmpty
            ? (orgRoles
                    .where((r) => r.id == _selectedRoleId)
                    .firstOrNull
                    ?.name ??
                updated.role.label)
            : _role.label;
        final managerNote = updated.managerName != null
            ? ' · Manager: ${updated.managerName}'
            : '';
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${widget.person.firstName} updated ($roleLabel)$managerNote',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _apiErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.screen,
        Insets.sm,
        Insets.screen,
        Insets.xxl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.person.name, style: context.text.titleLarge),
            const SizedBox(height: Insets.xs),
            Text(
              widget.person.email,
              style: context.text.bodyMedium?.copyWith(color: palette.neutral),
            ),
            const SizedBox(height: Insets.lg),
            Text('Role', style: context.text.labelLarge),
            const SizedBox(height: Insets.sm),
            _buildRolePicker(),
            if (_isMemberSelection) ...[
              const SizedBox(height: Insets.md),
              Text('Manager', style: context.text.labelLarge),
              const SizedBox(height: Insets.sm),
              _buildManagerPicker(),
            ],
            if (_error != null) ...[
              const SizedBox(height: Insets.md),
              Text(
                _error!,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.error,
                ),
              ),
            ],
            const SizedBox(height: Insets.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRolePicker() {
    final orgRoles = ref.watch(orgConfigProvider).roles;
    if (orgRoles.isNotEmpty) {
      _selectedRoleId ??= orgRoles
              .where((r) => r.slug == widget.person.role.name)
              .firstOrNull
              ?.id ??
          orgRoles.first.id;
      final selected =
          orgRoles.where((r) => r.id == _selectedRoleId).firstOrNull;
      return _SelectField(
        valueText: selected?.name ?? 'Select role',
        onTap: () async {
          final picked = await showOptionPickerSheet<String>(
            context: context,
            title: 'Select role',
            options: [
              for (final r in orgRoles)
                PickerOption(value: r.id, label: r.name),
            ],
            selected: _selectedRoleId,
          );
          if (picked != null) setState(() => _selectedRoleId = picked);
        },
      );
    }
    return SegmentedButton<UserRole>(
      segments: const [
        ButtonSegment(value: UserRole.member, label: Text('Member')),
        ButtonSegment(value: UserRole.manager, label: Text('Manager')),
      ],
      selected: {_role},
      onSelectionChanged: (s) => setState(() => _role = s.first),
    );
  }

  Widget _buildManagerPicker() {
    final team = ref.watch(teamProvider);
    final managers = team
        .where(
          (user) =>
              user.id != widget.person.id &&
              (user.role == UserRole.manager || user.isAdmin),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    // Keep the current manager selectable even if their role changed.
    final current = team.where((u) => u.id == _selectedManagerId).firstOrNull;
    if (current != null && !managers.any((m) => m.id == current.id)) {
      managers.insert(0, current);
    }

    if (managers.isEmpty) {
      return const Text('No managers available yet.');
    }
    if (_selectedManagerId == null ||
        !managers.any((m) => m.id == _selectedManagerId)) {
      _selectedManagerId = managers.first.id;
    }
    final selected =
        managers.where((m) => m.id == _selectedManagerId).firstOrNull;
    return _SelectField(
      valueText: selected == null
          ? 'Select manager'
          : selected.isAdmin
              ? '${selected.name} (Admin)'
              : selected.name,
      onTap: () async {
        final picked = await showOptionPickerSheet<String>(
          context: context,
          title: 'Select manager',
          options: [
            for (final manager in managers)
              PickerOption(
                value: manager.id,
                label: manager.isAdmin
                    ? '${manager.name} (Admin)'
                    : manager.name,
              ),
          ],
          selected: _selectedManagerId,
        );
        if (picked != null) setState(() => _selectedManagerId = picked);
      },
    );
  }

  bool get _isMemberSelection {
    final orgRoles = ref.read(orgConfigProvider).roles;
    if (orgRoles.isNotEmpty) {
      final selectedId = _selectedRoleId;
      if (selectedId == null) return widget.person.role == UserRole.member;
      final selected = orgRoles.where((role) => role.id == selectedId).firstOrNull;
      return selected?.slug == 'member';
    }
    return _role == UserRole.member;
  }
}

class PickerOption<T> {
  const PickerOption({required this.value, required this.label});
  final T value;
  final String label;
}

Future<T?> showOptionPickerSheet<T>({
  required BuildContext context,
  required String title,
  required List<PickerOption<T>> options,
  required T? selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final maxHeight = MediaQuery.sizeOf(context).height * 0.55;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.screen,
                  Insets.sm,
                  Insets.screen,
                  Insets.md,
                ),
                child: Text(title, style: context.text.titleMedium),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options[index];
                    final isSelected = option.value == selected;
                    return ListTile(
                      title: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_rounded,
                              color: context.colors.primary,
                            )
                          : null,
                      selected: isSelected,
                      onTap: () => Navigator.pop(context, option.value),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Compact select that opens a picker sheet — avoids DropdownButtonFormField
/// overflowing inside parent bottom sheets.
class _SelectField extends StatelessWidget {
  const _SelectField({required this.valueText, required this.onTap});

  final String valueText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InputDecorator(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: Insets.md,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  valueText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyLarge,
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: palette.neutral,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
