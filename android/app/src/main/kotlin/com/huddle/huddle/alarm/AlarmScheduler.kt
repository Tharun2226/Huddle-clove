package com.huddle.huddle.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONObject

/**
 * Schedules alarm-style reminders with AlarmManager.setAlarmClock, the most
 * reliable path (exempt from Doze and allowed to start the ringing service).
 * Alarms are mirrored in SharedPreferences so they survive a reboot.
 */
object AlarmScheduler {
  private const val PREFS = "huddle_native_alarms"
  private const val KEY = "alarms"

  const val EXTRA_ID = "alarm_id"
  const val EXTRA_TITLE = "alarm_title"
  const val EXTRA_BODY = "alarm_body"
  const val EXTRA_PAYLOAD = "alarm_payload"
  const val ACTION_FIRE = "com.huddle.huddle.alarm.FIRE"

  fun schedule(ctx: Context, id: Int, atMs: Long, title: String, body: String, payload: String) {
    val all = load(ctx)
    all.put(
      id.toString(),
      JSONObject()
        .put("at", atMs)
        .put("title", title)
        .put("body", body)
        .put("payload", payload),
    )
    save(ctx, all)
    arm(ctx, id, atMs, title, body, payload)
  }

  fun cancelAll(ctx: Context) {
    val all = load(ctx)
    val am = ctx.getSystemService(AlarmManager::class.java)
    for (key in all.keys()) {
      am.cancel(fireIntent(ctx, key.toInt(), "", "", ""))
    }
    save(ctx, JSONObject())
  }

  /** Drops a fired alarm from the stored list. */
  fun remove(ctx: Context, id: Int) {
    val all = load(ctx)
    all.remove(id.toString())
    save(ctx, all)
  }

  /** Re-arms stored alarms after a reboot or app update. */
  fun restore(ctx: Context) {
    val all = load(ctx)
    val now = System.currentTimeMillis()
    val keep = JSONObject()
    for (key in all.keys()) {
      val a = all.getJSONObject(key)
      val at = a.getLong("at")
      if (at <= now) continue
      keep.put(key, a)
      arm(ctx, key.toInt(), at, a.getString("title"), a.getString("body"), a.getString("payload"))
    }
    save(ctx, keep)
  }

  private fun arm(ctx: Context, id: Int, atMs: Long, title: String, body: String, payload: String) {
    val am = ctx.getSystemService(AlarmManager::class.java)
    val fire = fireIntent(ctx, id, title, body, payload)
    val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
    if (canExact) {
      val show = PendingIntent.getActivity(
        ctx,
        id,
        ctx.packageManager.getLaunchIntentForPackage(ctx.packageName),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
      )
      am.setAlarmClock(AlarmManager.AlarmClockInfo(atMs, show), fire)
    } else {
      // Without "Alarms & reminders" access the alarm may be a few minutes late.
      am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, fire)
    }
  }

  private fun fireIntent(ctx: Context, id: Int, title: String, body: String, payload: String): PendingIntent {
    val intent = Intent(ctx, AlarmReceiver::class.java)
      .setAction(ACTION_FIRE)
      .putExtra(EXTRA_ID, id)
      .putExtra(EXTRA_TITLE, title)
      .putExtra(EXTRA_BODY, body)
      .putExtra(EXTRA_PAYLOAD, payload)
    return PendingIntent.getBroadcast(
      ctx,
      id,
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }

  private fun load(ctx: Context): JSONObject {
    val raw = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
    return try {
      if (raw.isNullOrEmpty()) JSONObject() else JSONObject(raw)
    } catch (_: Exception) {
      JSONObject()
    }
  }

  private fun save(ctx: Context, all: JSONObject) {
    ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(KEY, all.toString())
      .apply()
  }
}
