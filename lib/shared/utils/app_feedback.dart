import 'package:flutter/material.dart';

/// Consistent success / error feedback — short floating snackbars only.
///
/// Always capture [ScaffoldMessenger] **before** popping a route so snackbars
/// still appear on the parent screen.
class AppFeedback {
  AppFeedback._();

  static ScaffoldMessengerState? messengerOf(BuildContext context) =>
      ScaffoldMessenger.maybeOf(context);

  static void success(
    ScaffoldMessengerState? messenger,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: duration,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  static void error(
    ScaffoldMessengerState? messenger,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: duration,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          backgroundColor: const Color(0xFFB42318),
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  /// Pop the current route, then show a short success snackbar on the parent.
  static void successAndPop(
    BuildContext context, {
    required String message,
    Object? popResult,
  }) {
    final messenger = messengerOf(context);
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(popResult);
    }
    success(messenger, message);
  }

  /// Pull a readable message out of Dio / Nest validation errors.
  /// Never shows raw DioException / HTTP dump text in the UI.
  static String apiMessage(Object error, [String fallback = 'Something went wrong']) {
    try {
      final response = (error as dynamic).response;
      final status = response?.statusCode as int?;
      final data = response?.data;

      if (data is Map && data['message'] != null) {
        final message = data['message'];
        final text = message is List
            ? message.map((e) => e.toString()).join(', ')
            : message.toString().trim();
        if (text.isNotEmpty &&
            text.toLowerCase() != 'internal server error') {
          return text;
        }
      }

      switch (status) {
        case 400:
          return 'Please check the details and try again';
        case 401:
          return 'Please sign in again';
        case 403:
          return 'You do not have permission for this';
        case 404:
          return 'Not found';
        case 409:
          return 'That already exists';
        case 500:
        case 502:
        case 503:
        case 504:
          return fallback;
      }
    } catch (_) {}

    final raw = error.toString();
    if (raw.contains('DioException') ||
        raw.contains('status code of') ||
        raw.contains('SocketException') ||
        raw.contains('TimeoutException')) {
      return fallback;
    }
    final cleaned = raw.replaceFirst('Exception: ', '').trim();
    return cleaned.isEmpty ? fallback : cleaned;
  }
}
