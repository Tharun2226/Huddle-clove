import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android-side alarm (see android/.../alarm/): rings on the alarm stream
/// for 15 s with a full-screen Stop screen, and stops on Stop, a tap, or
/// the power / volume buttons.
class NativeAlarm {
  static const _channel = MethodChannel('huddle/alarm');

  /// Clears every alarm scheduled by [schedule].
  static Future<void> cancelAll() async {
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } on MissingPluginException {
      // Not running on Android (tests, other platforms).
    }
  }

  static Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      await _channel.invokeMethod<void>('schedule', {
        'id': id,
        'at': at.millisecondsSinceEpoch,
        'title': title,
        'body': body,
        'payload': payload,
      });
    } on MissingPluginException {
      debugPrint('Native alarm unavailable');
    }
  }

  /// Calls [onTap] with the reminder payload when a ringing alarm is tapped,
  /// including the tap that launched the app.
  static Future<void> listenForTaps(void Function(String payload) onTap) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onTap' && call.arguments is String) {
        onTap(call.arguments as String);
      }
    });
    try {
      final launch = await _channel.invokeMethod<String>('takeLaunchPayload');
      if (launch != null && launch.isNotEmpty) onTap(launch);
    } on MissingPluginException {
      // Not running on Android.
    }
  }
}
