import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/network/super_admin_api.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/app_feedback.dart';
import '../../../../shared/widgets/huddle_card.dart';

final _orgsProvider = FutureProvider<List<SuperAdminOrg>>((ref) {
  return ref.read(superAdminApiProvider).listOrganizations();
});

final _orgDetailProvider = FutureProvider.family<OrgDetail, String>((ref, id) {
  return ref.read(superAdminApiProvider).getOrganizationDetail(id);
});

class SuperAdminDashboard extends ConsumerWidget {
  const SuperAdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgsAsync = ref.watch(_orgsProvider);
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            useSafeArea: true,
            builder: (_) => const _CreateOrgSheet(),
          );
          if (created == true) ref.invalidate(_orgsProvider);
        },
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('New Organization'),
      ),
      body: orgsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(Insets.xxl),
            child: Text('Failed to load organizations.\n$e', textAlign: TextAlign.center),
          ),
        ),
        data: (orgs) {
          if (orgs.isEmpty) {
            return Center(
              child: Text('No organizations yet.', style: context.text.bodyLarge?.copyWith(color: palette.neutral)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(Insets.screen),
            itemCount: orgs.length,
            separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
            itemBuilder: (context, i) => _OrgCard(org: orgs[i]),
          );
        },
      ),
    );
  }
}

class _OrgCard extends StatelessWidget {
  const _OrgCard({required this.org});
  final SuperAdminOrg org;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final date = '${org.createdAt.day}/${org.createdAt.month}/${org.createdAt.year}';

    return HuddleCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _OrgDetailScreen(orgId: org.id, orgName: org.name)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(org.name, style: context.text.titleMedium),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: org.isActive ? palette.infoContainer : palette.warningContainer,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  org.isActive ? '${org.memberCount} members' : 'Inactive',
                  style: context.text.labelSmall?.copyWith(
                    color: org.isActive ? palette.info : palette.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          Row(
            children: [
              Text(
                '${org.memberCount} member${org.memberCount == 1 ? '' : 's'}',
                style: context.text.bodySmall?.copyWith(color: palette.neutral),
              ),
              const Spacer(),
              Text(
                'Created $date',
                style: context.text.bodySmall?.copyWith(color: palette.neutral),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrgDetailScreen extends ConsumerWidget {
  const _OrgDetailScreen({required this.orgId, required this.orgName});
  final String orgId, orgName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(_orgDetailProvider(orgId));
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(title: Text(orgName)),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (detail) {
          return ListView(
            padding: const EdgeInsets.all(Insets.screen),
            children: [
              HuddleCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Organization', style: context.text.titleMedium),
                    const SizedBox(height: Insets.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Status',
                          style: context.text.bodyMedium?.copyWith(
                            color: palette.neutral,
                          ),
                        ),
                        Text(
                          detail.isActive ? 'Active' : 'Inactive',
                          style: context.text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Insets.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Members',
                          style: context.text.bodyMedium?.copyWith(
                            color: palette.neutral,
                          ),
                        ),
                        Text(
                          '${detail.members.length}',
                          style: context.text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Insets.md),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: () async {
                          await ref.read(superAdminApiProvider).setOrganizationActive(
                            orgId,
                            !detail.isActive,
                          );
                          ref.invalidate(_orgDetailProvider(orgId));
                          ref.invalidate(_orgsProvider);
                        },
                        child: Text(
                          detail.isActive
                              ? 'Deactivate Organization'
                              : 'Activate Organization',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Insets.lg),
              Text('Members (${detail.members.length})', style: context.text.titleMedium),
              const SizedBox(height: Insets.md),
              for (final member in detail.members) ...[
                HuddleCard(
                  padding: const EdgeInsets.all(Insets.md),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: palette.avatarFor(member.id),
                        child: Text(
                          member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: Insets.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(member.name, style: context.text.titleSmall),
                            Text(member.email, style: context.text.bodySmall?.copyWith(color: palette.neutral)),
                          ],
                        ),
                      ),
                      if (member.isAdmin)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: palette.warningContainer,
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                          child: Text('Admin', style: context.text.labelSmall?.copyWith(color: palette.warning)),
                        ),
                      if (member.roles.isNotEmpty) ...[
                        const SizedBox(width: Insets.xs),
                        Text(member.roles.join(', '), style: context.text.labelSmall?.copyWith(color: palette.neutral)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Insets.sm),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CreateOrgSheet extends ConsumerStatefulWidget {
  const _CreateOrgSheet();

  @override
  ConsumerState<_CreateOrgSheet> createState() => _CreateOrgSheetState();
}

class _CreateOrgSheetState extends ConsumerState<_CreateOrgSheet> {
  final _formKey = GlobalKey<FormState>();
  final _orgName = TextEditingController();
  final _adminName = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminPassword = TextEditingController();
  final _adminTitle = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _orgName.dispose();
    _adminName.dispose();
    _adminEmail.dispose();
    _adminPassword.dispose();
    _adminTitle.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(superAdminApiProvider).createOrganization(
            organizationName: _orgName.text.trim(),
            adminName: _adminName.text.trim(),
            adminEmail: _adminEmail.text.trim(),
            adminPassword: _adminPassword.text,
            adminTitle: _adminTitle.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = AppFeedback.apiMessage(
            e,
            'Could not create organization. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = context.colors;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Insets.screen,
        0,
        Insets.screen,
        Insets.lg + bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Icon(
                      Icons.apartment_rounded,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New organization',
                          style: context.text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Creates the workspace and its first admin account.',
                          style: context.text.bodySmall?.copyWith(
                            color: palette.neutral,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.xl),
              Text(
                'ORGANIZATION',
                style: context.text.labelSmall?.copyWith(color: palette.neutral),
              ),
              const SizedBox(height: Insets.sm),
              TextFormField(
                controller: _orgName,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Organization name',
                  hintText: 'Acme Corp',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: Insets.xl),
              Text(
                'FIRST ADMIN',
                style: context.text.labelSmall?.copyWith(color: palette.neutral),
              ),
              const SizedBox(height: Insets.sm),
              TextFormField(
                controller: _adminName,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Full name',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: Insets.md),
              TextFormField(
                controller: _adminEmail,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  labelText: 'Work email',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                ),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return 'Required';
                  if (!value.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: Insets.md),
              TextFormField(
                controller: _adminPassword,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Temporary password',
                  helperText: 'At least 6 characters — they can change it later.',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.length < 6) {
                    return 'Minimum 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: Insets.md),
              TextFormField(
                controller: _adminTitle,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Title (optional)',
                  hintText: 'CEO, Founder…',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: Insets.md),
                Container(
                  padding: const EdgeInsets.all(Insets.md),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Text(
                    _error!,
                    style: context.text.bodySmall?.copyWith(color: scheme.error),
                  ),
                ),
              ],
              const SizedBox(height: Insets.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create organization'),
                    ),
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
