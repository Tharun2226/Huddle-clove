import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/network/api_config.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/app_feedback.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../../shared/widgets/huddle_card.dart';
import '../../domain/expense.dart';
import '../widgets/expense_visuals.dart';
import '../widgets/receipt_viewer.dart';

/// Add / edit expense: capture receipt, review fields, save or resubmit.
class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({super.key, this.editing});

  /// When set, form is prefilled for draft / rejected fix & resubmit.
  final Expense? editing;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _merchant = TextEditingController();
  final _notes = TextEditingController();
  final _picker = ImagePicker();

  ExpenseCategory _category = ExpenseCategory.meals;
  DateTime _date = DateTime.now();
  String? _receiptPath;
  String? _localPreviewPath;
  bool _scanning = false;
  bool _saving = false;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _amount.text = e.amount == e.amount.roundToDouble()
          ? e.amount.toStringAsFixed(0)
          : e.amount.toStringAsFixed(2);
      _merchant.text = e.merchant;
      _notes.text = e.notes;
      _category = e.category;
      _date = e.date;
      _receiptPath = e.receiptPath;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _notes.dispose();
    super.dispose();
  }

  double? get _parsedAmount => double.tryParse(_amount.text.trim());

  double? get _overage {
    final amount = _parsedAmount;
    final limit = _category.limit;
    if (amount == null || limit == null || amount <= limit) return null;
    return amount - limit;
  }

  Future<void> _scan({ImageSource source = ImageSource.camera}) async {
    if (_scanning) return;

    HapticFeedback.mediumImpact();
    setState(() => _scanning = true);
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (picked == null || !mounted) return;

      // New photo replaces the previous scan — clear stale OCR fields first.
      setState(() {
        _localPreviewPath = picked.path;
        _receiptPath = null;
        _merchant.clear();
        _amount.clear();
        _notes.clear();
        _category = ExpenseCategory.meals;
        _date = DateTime.now();
      });

      final scanned =
          await ref.read(expenseRepositoryProvider).scanReceipt(picked.path);
      if (!mounted) return;

      final overallConf = scanned.confidence['overall'];
      final lowConfidence = overallConf != null && overallConf < 40;

      setState(() {
        final merchant = scanned.merchant?.trim();
        final solidWords = merchant == null
            ? <String>[]
            : merchant
                .split(RegExp(r'\s+'))
                .where((w) => w.length >= 2)
                .toList();
        final looksLikeBusiness = merchant != null &&
            RegExp(
              r'\b(hotel|restaurant|palace|cafe|resort|petroleum|fuels?|pump|traders|mart|stores|pvt|ltd|sai|srini|enterprises)\b',
              caseSensitive: false,
            ).hasMatch(merchant);
        // Person names on UPI slips are valid merchants (To: / Paid to)
        final merchantOk = merchant != null &&
            merchant.length >= 3 &&
            RegExp(r'[A-Za-z]{2,}').hasMatch(merchant) &&
            (solidWords.isNotEmpty || looksLikeBusiness);
        _merchant.text = merchantOk ? merchant : '';

        final amount = scanned.amount;
        // Trust backend amount when positive (UPI often whole rupees; receipts have paise).
        final amountOk =
            amount != null && amount > 0 && amount < 10000000;
        _amount.text = amountOk
            ? amount.toStringAsFixed(
                amount == amount.roundToDouble() ? 0 : 2,
              )
            : '';

        if (scanned.category != null) {
          _category = scanned.category!;
        }
        if (scanned.date != null) {
          _date = scanned.date!;
        }
        _receiptPath = scanned.receiptPath;

        _notes.text = scanned.noteLines.join('\n');
      });
      HapticFeedback.lightImpact();
      if (!mounted) return;
      final filled = (scanned.amount != null && scanned.amount! > 0) ||
          (scanned.merchant != null && scanned.merchant!.trim().length >= 6) ||
          scanned.date != null;
      final scanMessage = scanned.ocrSkipped
          ? (scanned.issues.isNotEmpty
              ? scanned.issues.first
              : 'Receipt attached — enter amount & merchant')
          : filled
              ? 'Receipt scanned — review fields'
              : 'Scan uncertain — please enter amount & merchant';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(scanMessage),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppFeedback.apiMessage(
              e,
              'Could not scan receipt. Enter details manually.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(
        () => _date = DateTime(picked.year, picked.month, picked.day),
      );
    }
  }

  Future<void> _save({required bool submit}) async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);

    try {
      final me = ref.read(currentUserProvider);
      final editing = widget.editing;
      if (editing != null) {
        await ref.read(expenseRepositoryProvider).update(
              editing.copyWith(
                amount: _parsedAmount!,
                category: _category,
                date: _date,
                merchant: _merchant.text.trim(),
                notes: _notes.text.trim(),
                receiptPath: _receiptPath ?? _localPreviewPath ?? editing.receiptPath,
              ),
              submitNow: submit,
            );
      } else {
        await ref.read(expenseRepositoryProvider).create(
              ExpenseDraft(
                amount: _parsedAmount!,
                category: _category,
                date: _date,
                merchant: _merchant.text.trim(),
                notes: _notes.text.trim(),
                submitterId: me.id,
                receiptPath: _receiptPath ?? _localPreviewPath,
                submitNow: submit,
              ),
            );
      }

      if (!mounted) return;
      AppFeedback.successAndPop(
        context,
        message: submit
            ? (_isEditing ? 'Fixed and resubmitted' : 'Submitted for approval')
            : (_isEditing ? 'Changes saved' : 'Draft saved'),
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(
        AppFeedback.messengerOf(context),
        AppFeedback.apiMessage(e, 'Could not save expense'),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final editing = widget.editing;
    final rejected = editing?.status == ExpenseStatus.rejected;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          rejected
              ? 'Fix expense'
              : _isEditing
                  ? 'Edit expense'
                  : 'New Expense',
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(submit: false),
            child: Text(_isEditing ? 'Save' : 'Save draft'),
          ),
          const SizedBox(width: Insets.sm),
        ],
      ),
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
          onPressed: _saving ? null : () => _save(submit: true),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  rejected ? 'Fix & resubmit' : 'Submit for approval',
                ),
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
            if (rejected && (editing?.decisionNote.isNotEmpty ?? false)) ...[
              HuddleCard(
                color: palette.dangerContainer,
                borderColor: palette.danger.withValues(alpha: 0.25),
                elevated: false,
                padding: const EdgeInsets.all(Insets.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 18, color: palette.danger),
                        const SizedBox(width: Insets.sm),
                        Text(
                          'Manager feedback',
                          style: context.text.titleSmall?.copyWith(
                            color: palette.onDanger,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Insets.sm),
                    Text(
                      editing!.decisionNote,
                      style: context.text.bodyMedium?.copyWith(
                        color: palette.onDanger,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Insets.lg),
            ],
            _ScanCard(
              scanning: _scanning,
              receiptPath: _receiptPath,
              localPreviewPath: _localPreviewPath,
              onCamera: () => _scan(source: ImageSource.camera),
              onGallery: () => _scan(source: ImageSource.gallery),
              onClear: () => setState(() {
                _receiptPath = null;
                _localPreviewPath = null;
              }),
            ),
            const SizedBox(height: Insets.xl),
            _Label('Amount'),
            TextFormField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              onChanged: (_) => setState(() {}),
              style: context.text.headlineMedium,
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: context.text.headlineMedium?.copyWith(
                  color: palette.neutral.withValues(alpha: 0.4),
                ),
                prefixIcon: Padding(
                  padding:
                      const EdgeInsets.only(left: Insets.lg, right: Insets.sm),
                  child: Text(
                    '₹',
                    style: context.text.headlineMedium?.copyWith(
                      color: palette.neutral,
                    ),
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 0),
              ),
              validator: (value) {
                final amount = double.tryParse((value ?? '').trim());
                if (amount == null || amount <= 0) return 'Enter an amount';
                return null;
              },
            ),
            if (_overage != null) ...[
              const SizedBox(height: Insets.md),
              _PolicyWarning(category: _category, overage: _overage!),
            ],
            const SizedBox(height: Insets.xl),
            _Label('Category'),
            _CategoryGrid(
              selected: _category,
              onSelect: (category) => setState(() => _category = category),
            ),
            const SizedBox(height: Insets.xl),
            _Label('Merchant'),
            TextFormField(
              controller: _merchant,
              textCapitalization: TextCapitalization.words,
              decoration:
                  const InputDecoration(hintText: 'Where did you spend?'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Add the merchant'
                  : null,
            ),
            const SizedBox(height: Insets.xl),
            _Label('Date'),
            HuddleCard(
              onTap: _pickDate,
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
                      Fmt.dayMonthYear(_date),
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
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
            const SizedBox(height: Insets.xl),
            _Label('Notes'),
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What was this for? (optional)',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({
    required this.scanning,
    required this.receiptPath,
    required this.localPreviewPath,
    required this.onCamera,
    required this.onGallery,
    required this.onClear,
  });

  final bool scanning;
  final String? receiptPath;
  final String? localPreviewPath;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onClear;

  bool get scanned =>
      (receiptPath != null && receiptPath!.isNotEmpty) ||
      (localPreviewPath != null && localPreviewPath!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = context.colors;

    if (scanned && !scanning) {
      final preview = localPreviewPath;
      final remote =
          receiptPath == null ? '' : ApiConfig.resolveMediaUrl(receiptPath);

      return HuddleCard(
        color: palette.successContainer,
        borderColor: palette.success.withValues(alpha: 0.3),
        elevated: false,
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: palette.success, size: 22),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Receipt attached',
                        style: context.text.titleSmall?.copyWith(
                          color: palette.onSuccess,
                        ),
                      ),
                      Text(
                        'Scanned from receipt · review fields below',
                        style: context.text.bodySmall?.copyWith(
                          color: palette.onSuccess.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClear,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: palette.onSuccess,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.md),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => showReceiptViewer(
                  context,
                  filePath: preview,
                  networkUrl: remote.isNotEmpty ? remote : null,
                ),
                borderRadius: BorderRadius.circular(Radii.md),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.md),
                  child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        preview != null && File(preview).existsSync()
                            ? Image.file(File(preview), fit: BoxFit.cover)
                            : remote.isNotEmpty
                                ? Image.network(
                                    remote,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => ColoredBox(
                                      color: palette.card,
                                      child: Icon(
                                        Icons.receipt_long_rounded,
                                        color: palette.neutral,
                                      ),
                                    ),
                                  )
                                : ColoredBox(
                                    color: palette.card,
                                    child: Icon(
                                      Icons.receipt_long_rounded,
                                      color: palette.neutral,
                                    ),
                                  ),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: const EdgeInsets.all(Insets.sm),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(Radii.pill),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.open_in_full_rounded,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'View',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Insets.sm),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.photo_camera_rounded, size: 18),
                  label: const Text('Retake'),
                ),
                TextButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library_rounded, size: 18),
                  label: const Text('Gallery'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return HuddleCard(
      color: scheme.primary.withValues(alpha: 0.06),
      borderColor: scheme.primary.withValues(alpha: 0.25),
      elevated: false,
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.xl,
        Insets.lg,
        Insets.lg,
      ),
      child: Column(
        children: [
          if (scanning)
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: scheme.primary,
              ),
            )
          else
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(
                Icons.document_scanner_rounded,
                color: scheme.onPrimary,
                size: 23,
              ),
            ),
          const SizedBox(height: Insets.md),
          Text(
            scanning ? 'Scanning receipt…' : 'Scan Receipt',
            style: context.text.titleSmall?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 2),
          Text(
            scanning
                ? 'Reading text from the photo on the server'
                : 'Choose how you want to capture it',
            style: context.text.bodySmall?.copyWith(color: palette.neutral),
            textAlign: TextAlign.center,
          ),
          if (!scanning) ...[
            const SizedBox(height: Insets.lg),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onCamera,
                    icon: const Icon(Icons.photo_camera_rounded, size: 18),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onGallery,
                    icon: const Icon(Icons.photo_library_rounded, size: 18),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PolicyWarning extends StatelessWidget {
  const _PolicyWarning({required this.category, required this.overage});

  final ExpenseCategory category;
  final double overage;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: palette.warningContainer,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: palette.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.flag_rounded, size: 16, color: palette.warning),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Text(
              '${Fmt.money(overage)} over the ${Fmt.money(category.limit!)} '
              '${category.label.toLowerCase()} limit. You can still submit — '
              'it will be flagged for your manager.',
              style: context.text.bodySmall?.copyWith(
                color: palette.onWarning,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.selected, required this.onSelect});

  final ExpenseCategory selected;
  final ValueChanged<ExpenseCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      children: [
        for (final category in ExpenseCategory.values)
          _CategoryChip(
            category: category,
            selected: selected == category,
            color: category.color(palette),
            onTap: () => onSelect(category),
          ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final ExpenseCategory category;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.md - 2,
        ),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : palette.card,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.5) : palette.hairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              category.icon,
              size: 15,
              color: selected ? color : palette.neutral,
            ),
            const SizedBox(width: 6),
            Text(
              category.label,
              style: context.text.labelMedium?.copyWith(
                color: selected ? color : palette.neutral,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: Insets.xs, bottom: Insets.sm),
      child: Text(
        text.toUpperCase(),
        style:
            context.text.labelSmall?.copyWith(color: context.palette.neutral),
      ),
    );
  }
}
