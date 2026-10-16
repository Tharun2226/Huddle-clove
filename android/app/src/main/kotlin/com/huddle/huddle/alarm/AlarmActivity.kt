package com.huddle.huddle.alarm

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.lang.ref.WeakReference

/** Full-screen alarm shown over the lock screen while the alarm rings. */
class AlarmActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    if (!AlarmService.isRinging) {
      finish()
      return
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
      setShowWhenLocked(true)
      setTurnScreenOn(true)
    } else {
      @Suppress("DEPRECATION")
      window.addFlags(
        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
          WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
      )
    }
    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    AlarmService.activity = WeakReference(this)

    val id = intent.getIntExtra(AlarmScheduler.EXTRA_ID, 0)
    val payload = intent.getStringExtra(AlarmScheduler.EXTRA_PAYLOAD) ?: ""
    setContentView(
      buildUi(
        intent.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "Reminder",
        intent.getStringExtra(AlarmScheduler.EXTRA_BODY) ?: "",
        onOpen = {
          AlarmService.stopNow()
          try {
            AlarmService.openAppIntent(this, id, payload).send()
          } catch (_: Exception) {
          }
          finish()
        },
      ),
    )
  }

  override fun dispatchKeyEvent(event: KeyEvent): Boolean {
    when (event.keyCode) {
      KeyEvent.KEYCODE_VOLUME_UP,
      KeyEvent.KEYCODE_VOLUME_DOWN,
      KeyEvent.KEYCODE_VOLUME_MUTE,
      KeyEvent.KEYCODE_HEADSETHOOK,
      KeyEvent.KEYCODE_CAMERA -> {
        if (event.action == KeyEvent.ACTION_UP) stop()
        return true
      }
    }
    return super.dispatchKeyEvent(event)
  }

  @Deprecated("Back also silences the alarm")
  override fun onBackPressed() = stop()

  private fun stop() {
    AlarmService.stopNow()
    finish()
  }

  private fun dp(v: Float) =
    TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, resources.displayMetrics).toInt()

  private fun buildUi(title: String, body: String, onOpen: () -> Unit): LinearLayout {
    val root = LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL
      gravity = Gravity.CENTER
      setPadding(dp(32f), dp(48f), dp(32f), dp(48f))
      background = GradientDrawable(
        GradientDrawable.Orientation.TOP_BOTTOM,
        intArrayOf(Color.parseColor("#312E81"), Color.parseColor("#0F172A")),
      )
    }
    fun text(s: String, size: Float, color: Int, bold: Boolean = false) =
      TextView(this).apply {
        text = s
        setTextColor(color)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
        gravity = Gravity.CENTER
        if (bold) typeface = Typeface.DEFAULT_BOLD
      }

    root.addView(text("⏰", 64f, Color.WHITE))
    root.addView(
      text(title, 26f, Color.WHITE, bold = true).apply { setPadding(0, dp(16f), 0, dp(8f)) },
    )
    if (body.isNotEmpty()) root.addView(text(body, 16f, Color.parseColor("#C7D2FE")))

    val stop = Button(this).apply {
      text = "Stop"
      isAllCaps = false
      setTextColor(Color.parseColor("#1E1B4B"))
      setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
      typeface = Typeface.DEFAULT_BOLD
      background = GradientDrawable().apply {
        cornerRadius = dp(32f).toFloat()
        setColor(Color.WHITE)
      }
      setOnClickListener { stop() }
    }
    root.addView(
      stop,
      LinearLayout.LayoutParams(dp(220f), dp(64f)).apply { topMargin = dp(56f) },
    )

    val open = Button(this).apply {
      text = "Open Huddle"
      isAllCaps = false
      setTextColor(Color.parseColor("#C7D2FE"))
      setBackgroundColor(Color.TRANSPARENT)
      setOnClickListener { onOpen() }
    }
    root.addView(
      open,
      LinearLayout.LayoutParams(dp(220f), dp(52f)).apply { topMargin = dp(12f) },
    )
    root.addView(
      text("Press power or a volume button to silence", 13f, Color.parseColor("#94A3B8"))
        .apply { setPadding(0, dp(24f), 0, 0) },
    )
    return root
  }
}
