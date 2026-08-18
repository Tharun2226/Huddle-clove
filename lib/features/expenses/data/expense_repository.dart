import '../domain/expense.dart';

/// Expense persistence. Implemented by the Nest-backed HTTP repository.
abstract interface class ExpenseRepository {
  Stream<List<Expense>> watchExpenses();

  Future<Expense> create(ExpenseDraft draft);
  Future<Expense> update(Expense expense, {bool submitNow = false});
  Future<Expense> submit(String expenseId);
  Future<Expense> approve(String expenseId, {required String managerId});
  Future<Expense> reject(String expenseId, {required String managerId, required String reason});
  Future<Expense> markReimbursed(String expenseId, {required String managerId});
  Future<void> delete(String expenseId);

  /// Scan a receipt image via Nest OCR and return extracted fields.
  Future<ScannedReceipt> scanReceipt(String imagePath);
}
