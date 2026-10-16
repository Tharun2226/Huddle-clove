package com.huddle.huddle.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** Fires a scheduled alarm, and restores alarms after reboot / app update. */
class AlarmReceiver : BroadcastReceiver() {
  override fun onReceive(ctx: Context, intent: Intent) {
    when (intent.action) {
      AlarmScheduler.ACTION_FIRE -> {
        val id = intent.getIntExtra(AlarmScheduler.EXTRA_ID, 0)
        AlarmScheduler.remove(ctx, id)
        val start = Intent(ctx, AlarmService::class.java)
          .setAction(AlarmService.ACTION_START)
          .putExtras(intent)
        try {
          ctx.startForegroundService(start)
        } catch (e: Exception) {
          // Background start refused (e.g. inexact alarm on Android 12+):
          // fall back to a plain alarm notification so it is not lost.
          Log.w("HuddleAlarm", "Could not start alarm service: $e")
          AlarmService.postFallback(ctx, intent)
        }
      }
      Intent.ACTION_BOOT_COMPLETED,
      Intent.ACTION_MY_PACKAGE_REPLACED,
      "android.intent.action.QUICKBOOT_POWERON" -> AlarmScheduler.restore(ctx)
    }
  }
}
