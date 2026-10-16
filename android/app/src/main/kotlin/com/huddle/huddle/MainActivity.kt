package com.huddle.huddle

import android.content.Intent
import android.net.Uri
import com.huddle.huddle.alarm.AlarmScheduler
import com.huddle.huddle.alarm.AlarmService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private var alarmChannel: MethodChannel? = null

  /** Reminder payload from an alarm tap, until Dart asks for it. */
  private var pendingAlarmPayload: String? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "huddle/links")
      .setMethodCallHandler { call, result ->
        if (call.method == "openUrl") {
          val url = call.arguments as? String
          if (url.isNullOrBlank()) {
            result.error("bad_args", "URL required", null)
            return@setMethodCallHandler
          }
          try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            result.success(true)
          } catch (e: Exception) {
            result.error("open_failed", e.message, null)
          }
        } else {
          result.notImplemented()
        }
      }

    pendingAlarmPayload = takeAlarmPayload(intent)
    alarmChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "huddle/alarm").apply {
      setMethodCallHandler { call, result ->
        when (call.method) {
          "schedule" -> {
            AlarmScheduler.schedule(
              applicationContext,
              call.argument<Int>("id")!!,
              call.argument<Number>("at")!!.toLong(),
              call.argument<String>("title") ?: "",
              call.argument<String>("body") ?: "",
              call.argument<String>("payload") ?: "",
            )
            result.success(null)
          }
          "cancelAll" -> {
            AlarmScheduler.cancelAll(applicationContext)
            result.success(null)
          }
          "takeLaunchPayload" -> {
            result.success(pendingAlarmPayload)
            pendingAlarmPayload = null
          }
          else -> result.notImplemented()
        }
      }
    }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    val payload = takeAlarmPayload(intent) ?: return
    alarmChannel?.invokeMethod("onTap", payload)
  }

  /** Tapping a ringing alarm opens the app and silences it. */
  private fun takeAlarmPayload(intent: Intent?): String? {
    val payload = intent?.getStringExtra(AlarmService.EXTRA_OPEN_PAYLOAD) ?: return null
    intent.removeExtra(AlarmService.EXTRA_OPEN_PAYLOAD)
    AlarmService.stopNow()
    return payload
  }
}
