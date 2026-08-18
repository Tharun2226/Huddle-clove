import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/app_notification.dart';

/// Top-level background handler (must be a top-level or static function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

typedef NotificationTapCallback = void Function({
  required NotificationType type,
  String? referenceId,
  String? notificationId,
  String? referenceKind,
});

/// Holds a notification tap until GoRouter / session is ready.
class PendingNotificationNav {
  static NotificationType? type;
  static String? referenceId;
  static String? notificationId;
  static String? referenceKind;

  static bool get hasPending => type != null;

  static void store({
    required NotificationType type,
    String? referenceId,
    String? notificationId,
    String? referenceKind,
  }) {
    PendingNotificationNav.type = type;
    PendingNotificationNav.referenceId = referenceId;
    PendingNotificationNav.notificationId = notificationId;
    PendingNotificationNav.referenceKind = referenceKind;
  }

  static void clear() {
    type = null;
    referenceId = null;
    notificationId = null;
    referenceKind = null;
  }
}

/// Owns FCM + local notification channel setup.
class PushNotificationService {
  PushNotificationService();

  final _messaging = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();

  bool _ready = false;
  bool _listenersBound = false;
  NotificationTapCallback? onTap;

  static const _channelId = 'huddle_default';
  static const _channelName = 'Huddle';

  Future<bool> ensureInitialized() async {
    if (_ready) return true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (e) {
      debugPrint('Firebase.initializeApp failed: $e');
      return false;
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      settings: const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (response) {
        _dispatchTap(
          type: NotificationType.fromApi(
            _payloadMap(response.payload)?['type'] as String?,
          ),
          referenceId: _payloadMap(response.payload)?['referenceId'] as String?,
          notificationId:
              _payloadMap(response.payload)?['notificationId'] as String?,
          referenceKind:
              _payloadMap(response.payload)?['referenceKind'] as String?,
        );
      },
    );

    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Huddle alerts',
        importance: Importance.high,
      ),
    );

    // Cold start from a local notification tap.
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final payload = launch?.notificationResponse?.payload;
      final map = _payloadMap(payload);
      if (map != null) {
        PendingNotificationNav.store(
          type: NotificationType.fromApi(map['type'] as String?),
          referenceId: map['referenceId'] as String?,
          notificationId: map['notificationId'] as String?,
          referenceKind: map['referenceKind'] as String?,
        );
      }
    }

    _ready = true;
    return true;
  }

  Future<void> requestPermissionAndRegister(
    Future<void> Function(String token) register,
  ) async {
    if (!_ready && !await ensureInitialized()) return;

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('Notification permission denied');
      return;
    }

    if (Platform.isAndroid) {
      final androidPlugin = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }

    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await register(token);
    }

    if (_listenersBound) return;
    _listenersBound = true;

    _messaging.onTokenRefresh.listen((t) async {
      if (t.isNotEmpty) await register(t);
    });

    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_openFromRemote);

    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      _openFromRemote(initial);
    }
  }

  /// Call after login / HomeShell so a queued tap can navigate.
  void flushPendingTap() {
    if (!PendingNotificationNav.hasPending) return;
    final type = PendingNotificationNav.type!;
    final referenceId = PendingNotificationNav.referenceId;
    final notificationId = PendingNotificationNav.notificationId;
    final referenceKind = PendingNotificationNav.referenceKind;
    PendingNotificationNav.clear();
    _emit(
      type: type,
      referenceId: referenceId,
      notificationId: notificationId,
      referenceKind: referenceKind,
    );
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] ?? 'Huddle';
    final body = notification?.body ?? message.data['body'] ?? '';
    final payload = jsonEncode({
      'type': message.data['type'],
      'referenceId': message.data['referenceId'],
      'notificationId': message.data['notificationId'],
      'referenceKind': message.data['referenceKind'],
    });

    await _local.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Huddle alerts',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: payload,
    );
  }

  void _openFromRemote(RemoteMessage message) {
    _dispatchTap(
      type: NotificationType.fromApi(message.data['type'] as String?),
      referenceId: message.data['referenceId'] as String?,
      notificationId: message.data['notificationId'] as String?,
      referenceKind: message.data['referenceKind'] as String?,
    );
  }

  void _dispatchTap({
    required NotificationType type,
    String? referenceId,
    String? notificationId,
    String? referenceKind,
  }) {
    // Always stash — emit may run before router/session is ready.
    PendingNotificationNav.store(
      type: type,
      referenceId: referenceId,
      notificationId: notificationId,
      referenceKind: referenceKind,
    );
    _emit(
      type: type,
      referenceId: referenceId,
      notificationId: notificationId,
      referenceKind: referenceKind,
    );
  }

  void _emit({
    required NotificationType type,
    String? referenceId,
    String? notificationId,
    String? referenceKind,
  }) {
    final callback = onTap;
    if (callback == null) return;

    void run() {
      callback(
        type: type,
        referenceId: referenceId,
        notificationId: notificationId,
        referenceKind: referenceKind,
      );
      // Clear only after a successful handoff attempt.
      if (PendingNotificationNav.referenceId == referenceId &&
          PendingNotificationNav.type == type) {
        PendingNotificationNav.clear();
      }
    }

    // Wait a frame so the activity is resumed and GoRouter is mounted.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 250), run);
    });
  }

  Map<String, dynamic>? _payloadMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
