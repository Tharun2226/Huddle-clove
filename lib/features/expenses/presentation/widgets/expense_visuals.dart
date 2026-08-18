import 'package:flutter/material.dart';

import '../../../../shared/theme/app_tokens.dart';
import '../../domain/expense.dart';

extension ExpenseStatusVisuals on ExpenseStatus {
  Color color(AppPalette p) => switch (this) {
    ExpenseStatus.draft => p.neutral,
    ExpenseStatus.submitted => p.warning,
    ExpenseStatus.approved => p.info,
    ExpenseStatus.reimbursed => p.success,
    ExpenseStatus.rejected => p.danger,
  };

  IconData get icon => switch (this) {
    ExpenseStatus.draft => Icons.edit_note_rounded,
    ExpenseStatus.submitted => Icons.hourglass_top_rounded,
    ExpenseStatus.approved => Icons.verified_rounded,
    ExpenseStatus.reimbursed => Icons.payments_rounded,
    ExpenseStatus.rejected => Icons.cancel_rounded,
  };

  /// Plain-language explanation shown on the detail screen, so the user never
  /// has to guess what a status means for them.
  String get explainer => switch (this) {
    ExpenseStatus.draft => 'Not submitted yet. Only you can see this.',
    ExpenseStatus.submitted => 'Waiting on your manager to approve.',
    ExpenseStatus.approved => 'Approved. Payment is being processed.',
    ExpenseStatus.reimbursed => 'Paid out. Nothing left to do.',
    ExpenseStatus.rejected => 'Sent back to you. Fix it and resubmit.',
  };
}

extension ExpenseCategoryVisuals on ExpenseCategory {
  IconData get icon => switch (this) {
    ExpenseCategory.meals => Icons.restaurant_rounded,
    ExpenseCategory.travel => Icons.local_taxi_rounded,
    ExpenseCategory.accommodation => Icons.hotel_rounded,
    ExpenseCategory.supplies => Icons.inventory_2_rounded,
    ExpenseCategory.software => Icons.code_rounded,
    ExpenseCategory.client => Icons.handshake_rounded,
    ExpenseCategory.other => Icons.receipt_long_rounded,
  };

  Color color(AppPalette p) => p.avatarFor(name);
}
