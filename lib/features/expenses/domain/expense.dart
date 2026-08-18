import 'package:flutter/foundation.dart';

/// The Expensify lifecycle from the build guide:
/// Draft → Submitted → Approved → Reimbursed, with Rejected as a side exit.
enum ExpenseStatus {
  draft('Draft'),
  submitted('Submitted'),
  approved('Approved'),
  reimbursed('Reimbursed'),
  rejected('Rejected');

  const ExpenseStatus(this.label);
  final String label;

  bool get isEditable => this == ExpenseStatus.draft || this == ExpenseStatus.rejected;
  bool get isPendingApproval => this == ExpenseStatus.submitted;
  bool get isSettled => this == ExpenseStatus.reimbursed;

  /// Creator may delete until a manager/admin has approved (or reimbursed).
  bool get canDeleteByOwner =>
      this == ExpenseStatus.draft ||
      this == ExpenseStatus.submitted ||
      this == ExpenseStatus.rejected;

  /// 0..1 progress along the happy path, for the status tracker UI.
  double get progress => switch (this) {
    ExpenseStatus.draft => 0.0,
    ExpenseStatus.submitted => 1 / 3,
    ExpenseStatus.approved => 2 / 3,
    ExpenseStatus.reimbursed => 1.0,
    ExpenseStatus.rejected => 1 / 3,
  };
}

enum ExpenseCategory {
  meals('Meals', 2000),
  travel('Travel', 10000),
  accommodation('Accommodation', 8000),
  supplies('Supplies', 5000),
  software('Software', 15000),
  client('Client Entertainment', 5000),
  other('Other', null);

  const ExpenseCategory(this.label, this.limit);
  final String label;

  /// Soft policy cap in ₹ — the guide's optional "flag expenses over a category
  /// limit before submission". Null means uncapped.
  final double? limit;
}

@immutable
class Expense {
  const Expense({
    required this.id,
    required this.amount,
    required this.category,
    required this.date,
    required this.merchant,
    required this.submitterId,
    required this.createdAt,
    this.status = ExpenseStatus.draft,
    this.notes = '',
    this.receiptPath,
    this.decidedAt,
    this.decidedBy,
    this.decisionNote = '',
    this.reimbursedAt,
  });

  final String id;
  final double amount;
  final ExpenseCategory category;
  final DateTime date;
  final String merchant;
  final String notes;
  final ExpenseStatus status;
  final String submitterId;
  final String? receiptPath;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final String? decidedBy;
  final String decisionNote;
  final DateTime? reimbursedAt;

  /// True when the amount exceeds the category's soft policy cap.
  bool get breachesPolicy {
    final limit = category.limit;
    return limit != null && amount > limit;
  }

  double? get overageAmount {
    final limit = category.limit;
    if (limit == null || amount <= limit) return null;
    return amount - limit;
  }

  Expense copyWith({
    double? amount,
    ExpenseCategory? category,
    DateTime? date,
    String? merchant,
    String? notes,
    ExpenseStatus? status,
    String? receiptPath,
    bool clearReceipt = false,
    DateTime? decidedAt,
    String? decidedBy,
    String? decisionNote,
    DateTime? reimbursedAt,
  }) {
    return Expense(
      id: id,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      date: date ?? this.date,
      merchant: merchant ?? this.merchant,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      submitterId: submitterId,
      receiptPath: clearReceipt ? null : (receiptPath ?? this.receiptPath),
      createdAt: createdAt,
      decidedAt: decidedAt ?? this.decidedAt,
      decidedBy: decidedBy ?? this.decidedBy,
      decisionNote: decisionNote ?? this.decisionNote,
      reimbursedAt: reimbursedAt ?? this.reimbursedAt,
    );
  }
}

@immutable
class ExpenseDraft {
  const ExpenseDraft({
    required this.amount,
    required this.category,
    required this.date,
    required this.merchant,
    required this.submitterId,
    this.notes = '',
    this.receiptPath,
    this.submitNow = false,
  });

  final double amount;
  final ExpenseCategory category;
  final DateTime date;
  final String merchant;
  final String notes;
  final String submitterId;
  final String? receiptPath;

  /// Save as draft vs. push straight into the approval queue.
  final bool submitNow;
}

/// Result of Nest receipt OCR (`POST /expenses/scan`).
/// Null fields mean the server could not confidently extract that value.
@immutable
class ScannedReceipt {
  const ScannedReceipt({
    required this.receiptPath,
    this.merchant,
    this.amount,
    this.date,
    this.tax,
    this.invoiceNumber,
    this.gstin,
    this.currency,
    this.category,
    this.noteLines = const [],
    this.riskScore = 0,
    this.riskLevel,
    this.rawText,
    this.confidence = const {},
    this.issues = const [],
    this.ocrSkipped = false,
  });

  final String? merchant;
  final double? amount;
  final DateTime? date;
  final double? tax;
  final String? invoiceNumber;
  final String? gstin;
  final String? currency;
  final ExpenseCategory? category;
  /// Pre-built note rows from OCR (Invoice, GSTIN, UTR, UPI IDs, …).
  final List<String> noteLines;
  final int riskScore;
  final String? riskLevel;
  final String? rawText;
  final String receiptPath;
  final Map<String, double> confidence;
  final List<String> issues;
  /// Server skipped OCR (e.g. Vercel) — receipt saved, user enters fields.
  final bool ocrSkipped;

  bool get hasExtractedFields =>
      (merchant != null && merchant!.trim().isNotEmpty) ||
      (amount != null && amount! > 0) ||
      date != null ||
      category != null ||
      noteLines.isNotEmpty ||
      (invoiceNumber != null && invoiceNumber!.trim().isNotEmpty);
}
