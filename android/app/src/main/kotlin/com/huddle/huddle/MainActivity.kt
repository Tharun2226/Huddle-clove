package com.huddle.huddle

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
  }
}
