import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../features/expenses/domain/expense.dart';
import '../../shared/utils/date_codec.dart';
import 'api_client.dart';
import 'api_config.dart';

class ExpenseMappers {
  static ExpenseStatus statusFrom(String v) => switch (v.toLowerCase()) {
    'submitted' => ExpenseStatus.submitted,
    'approved' => ExpenseStatus.approved,
    'reimbursed' => ExpenseStatus.reimbursed,
    'rejected' => ExpenseStatus.rejected,
    _ => ExpenseStatus.draft,
  };

  static ExpenseCategory categoryFrom(String v) => switch (v.toLowerCase()) {
    'meals' => ExpenseCategory.meals,
    'travel' => ExpenseCategory.travel,
    'accommodation' => ExpenseCategory.accommodation,
    'supplies' => ExpenseCategory.supplies,
    'software' => ExpenseCategory.software,
    'client' => ExpenseCategory.client,
    _ => ExpenseCategory.other,
  };

  static String categoryTo(ExpenseCategory c) => c.name.toUpperCase();

  static Expense fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'] as String,
      amount: (json['amount'] as num).toDouble(),
      category: categoryFrom(json['category'] as String),
      date: DateCodec.parseCalendarDate(json['date'] as String?) ??
          DateTime.now(),
      merchant: json['merchant'] as String,
      notes: (json['notes'] as String?) ?? '',
      status: statusFrom(json['status'] as String),
      submitterId: json['submitterId'] as String,
      receiptPath: json['receiptPath'] as String?,
      createdAt: DateCodec.parseInstant(json['createdAt'] as String?) ??
          DateTime.now(),
      decidedAt: DateCodec.parseInstant(json['decidedAt'] as String?),
      decidedBy: json['decidedBy'] as String?,
      decisionNote: (json['decisionNote'] as String?) ?? '',
      reimbursedAt: DateCodec.parseInstant(json['reimbursedAt'] as String?),
    );
  }
}

class ApiExpenseRepository {
  ApiExpenseRepository(this._client);

  final ApiClient _client;

  Future<List<Expense>> fetchExpenses() async {
    final res = await _client.dio.get<List<dynamic>>('/expenses');
    return [
      for (final row in res.data ?? const [])
        ExpenseMappers.fromJson(row as Map<String, dynamic>),
    ];
  }

  bool _isRemoteReceipt(String? path) {
    if (path == null || path.isEmpty) return false;
    return path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('/uploads/');
  }

  Future<MultipartFile> _multipartFromPath(String path) {
    return MultipartFile.fromFile(
      path,
      filename: p.basename(path),
    );
  }

  /// Upload a local receipt image; returns the server path under `/uploads/...`.
  Future<String> uploadReceipt(String localPath) async {
    final form = FormData.fromMap({
      'file': await _multipartFromPath(localPath),
    });
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/expenses/receipt',
      data: form,
    );
    final url = res.data?['receiptUrl'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('Receipt upload failed');
    }
    return url;
  }

  /// OCR via Nest `POST /expenses/scan` (Tesseract). File is stored on the API.
  Future<ScannedReceipt> scanReceipt(String localPath) async {
    final form = FormData.fromMap({
      'file': await _multipartFromPath(localPath),
    });

    final res = await _client.dio.post<Map<String, dynamic>>(
      '/expenses/scan',
      data: form,
      options: Options(
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 90),
      ),
    );

    final data = res.data;
    if (data == null) {
      throw StateError('Receipt scan failed');
    }
    if (data['success'] == false) {
      throw StateError(
        (data['error'] as String?) ?? 'Receipt was rejected by the scanner',
      );
    }

    final confidence = <String, double>{};
    final confRaw = data['confidence'];
    if (confRaw is num) {
      confidence['overall'] = confRaw.toDouble();
    } else if (confRaw is Map) {
      for (final entry in confRaw.entries) {
        final v = entry.value;
        if (v is num) confidence['${entry.key}'] = v.toDouble();
      }
    }

    final issues = <String>[];
    final issuesRaw = data['issues'];
    if (issuesRaw is List) {
      for (final item in issuesRaw) {
        if (item is Map && item['message'] is String) {
          issues.add(item['message'] as String);
        } else if (item is String) {
          issues.add(item);
        }
      }
    }

    final merchant = (data['merchant'] as String?)?.trim();
    final amount = _asDouble(data['amount']);
    final tax = _asDouble(data['tax']);
    final dateRaw = data['date'] as String?;
    final invoiceNumber = (data['invoiceNumber'] as String?)?.trim();
    final gstin = (data['gstin'] as String?)?.trim();
    final currency = (data['currency'] as String?)?.trim();
    final categoryRaw = (data['category'] as String?)?.trim();
    final noteLines = <String>[
      for (final row in (data['noteLines'] as List<dynamic>? ?? const []))
        if (row.toString().trim().isNotEmpty) row.toString().trim(),
    ];
    // Backward-compatible fallback if older API has no noteLines
    if (noteLines.isEmpty) {
      if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
        noteLines.add('Invoice: $invoiceNumber');
      }
      if (gstin != null && gstin.isNotEmpty) {
        noteLines.add('GSTIN: $gstin');
      }
    }

    return ScannedReceipt(
      // Keep local path so Nest can persist the image on expense create
      // (scan already stores a copy; create may re-upload the local file).
      receiptPath: localPath,
      merchant: (merchant == null || merchant.isEmpty) ? null : merchant,
      amount: (amount == null || amount <= 0) ? null : amount,
      tax: (tax == null || tax <= 0) ? null : tax,
      date: DateCodec.parseCalendarDate(dateRaw),
      invoiceNumber:
          (invoiceNumber == null || invoiceNumber.isEmpty) ? null : invoiceNumber,
      gstin: (gstin == null || gstin.isEmpty) ? null : gstin,
      currency: (currency == null || currency.isEmpty) ? null : currency,
      category: categoryRaw != null && categoryRaw.isNotEmpty
          ? ExpenseMappers.categoryFrom(categoryRaw)
          : null,
      noteLines: noteLines,
      riskScore: (data['riskScore'] as num?)?.toInt() ?? 0,
      riskLevel: data['riskLevel'] as String?,
      rawText: data['rawText'] as String?,
      confidence: confidence,
      issues: issues,
      ocrSkipped: data['ocrSkipped'] == true,
    );
  }

  Future<Expense> create(ExpenseDraft draft) async {
    var receiptUrl = draft.receiptPath;
    if (receiptUrl != null &&
        receiptUrl.isNotEmpty &&
        !_isRemoteReceipt(receiptUrl)) {
      receiptUrl = await uploadReceipt(receiptUrl);
    }

    final res = await _client.dio.post<Map<String, dynamic>>(
      '/expenses',
      data: {
        'amount': draft.amount,
        'category': ExpenseMappers.categoryTo(draft.category),
        'date': DateCodec.encodeCalendarDate(draft.date),
        'merchant': draft.merchant,
        'notes': draft.notes,
        if (receiptUrl != null && receiptUrl.isNotEmpty)
          'receiptUrl': receiptUrl.startsWith('http')
              ? receiptUrl.replaceFirst(ApiConfig.origin, '')
              : receiptUrl,
        'submitNow': draft.submitNow,
      },
    );
    return ExpenseMappers.fromJson(res.data!);
  }

  Future<Expense> update(Expense expense, {bool submitNow = false}) async {
    var receiptUrl = expense.receiptPath;
    if (receiptUrl != null &&
        receiptUrl.isNotEmpty &&
        !_isRemoteReceipt(receiptUrl)) {
      receiptUrl = await uploadReceipt(receiptUrl);
    }

    final res = await _client.dio.patch<Map<String, dynamic>>(
      '/expenses/${expense.id}',
      data: {
        'amount': expense.amount,
        'category': ExpenseMappers.categoryTo(expense.category),
        'date': DateCodec.encodeCalendarDate(expense.date),
        'merchant': expense.merchant,
        'notes': expense.notes,
        if (receiptUrl != null && receiptUrl.isNotEmpty)
          'receiptUrl': receiptUrl.startsWith('http')
              ? receiptUrl.replaceFirst(ApiConfig.origin, '')
              : receiptUrl,
        'submitNow': submitNow,
      },
    );
    return ExpenseMappers.fromJson(res.data!);
  }

  Future<Expense> submit(String id) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/expenses/$id/submit',
    );
    return ExpenseMappers.fromJson(res.data!);
  }

  Future<Expense> approve(String id, {String note = ''}) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/expenses/$id/approve',
      data: note.trim().isEmpty ? <String, dynamic>{} : {'note': note.trim()},
    );
    final data = res.data;
    if (data == null) throw StateError('Approve failed');
    return ExpenseMappers.fromJson(data);
  }

  Future<Expense> reject(String id, {required String reason}) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/expenses/$id/reject',
      data: {'note': reason.trim()},
    );
    final data = res.data;
    if (data == null) throw StateError('Reject failed');
    return ExpenseMappers.fromJson(data);
  }

  Future<Expense> reimburse(String id) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/expenses/$id/reimburse',
      data: const {},
    );
    return ExpenseMappers.fromJson(res.data!);
  }

  Future<void> delete(String id) async {
    await _client.dio.delete<void>('/expenses/$id');
  }
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '').trim());
  }
  return null;
}
