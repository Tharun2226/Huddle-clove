package com.huddle.huddle.alarm

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.VolumeProvider
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import com.huddle.huddle.MainActivity
import com.huddle.huddle.R
import java.lang.ref.WeakReference

/**
 * Rings an alarm: plays the bundled tone on the alarm stream, vibrates and
 * shows a full-screen / heads-up alert with a Stop button.
 *
 * Ringing stops after [RING_MS], or as soon as the user taps Stop, taps the
 * alert, swipes it away, or presses the power or a volume button.
 */
class AlarmService : Service() {
  companion object {
    const val ACTION_START = "com.huddle.huddle.alarm.START"
    const val ACTION_STOP = "com.huddle.huddle.alarm.STOP"
    const val EXTRA_OPEN_PAYLOAD = "huddle_alarm_open_payload"

    private const val TAG = "HuddleAlarm"
    private const val CHANNEL_ID = "huddle_alarm_ringing_v1"
    private const val FALLBACK_CHANNEL_ID = "huddle_alarm_fallback_v1"
    private const val NOTIFICATION_ID = 0x48A1
    private const val RING_MS = 15_000L

    /** Ignore screen / volume events this soon after ringing starts — the
     *  full-screen alert itself may turn the screen on. */
    private const val GRACE_MS = 1_500L

    @Volatile private var instance: AlarmService? = null
    var activity: WeakReference<Activity>? = null

    val isRinging: Boolean get() = instance != null

    /** Silences the current alarm, if any. */
    fun stopNow() {
      Handler(Looper.getMainLooper()).post { instance?.stopRinging() }
    }

    fun toneUri(ctx: Context): Uri =
      Uri.parse("android.resource://${ctx.packageName}/${R.raw.huddle_alarm}")

    fun openAppIntent(ctx: Context, id: Int, payload: String): PendingIntent {
      val open = Intent(ctx, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        .putExtra(EXTRA_OPEN_PAYLOAD, payload)
      return PendingIntent.getActivity(
        ctx,
        id,
        open,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
      )
    }

    /** Plain alarm notification, used when the ringing service can't start. */
    fun postFallback(ctx: Context, fired: Intent) {
      val nm = ctx.getSystemService(NotificationManager::class.java)
      val id = fired.getIntExtra(AlarmScheduler.EXTRA_ID, 0)
      val payload = fired.getStringExtra(AlarmScheduler.EXTRA_PAYLOAD) ?: ""
      val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val channel = NotificationChannel(
          FALLBACK_CHANNEL_ID,
          "Reminder alarms (backup)",
          NotificationManager.IMPORTANCE_HIGH,
        ).apply {
          setSound(
            toneUri(ctx),
            AudioAttributes.Builder()
              .setUsage(AudioAttributes.USAGE_ALARM)
              .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
              .build(),
          )
        }
        nm.createNotificationChannel(channel)
        Notification.Builder(ctx, FALLBACK_CHANNEL_ID).setTimeoutAfter(RING_MS)
      } else {
        @Suppress("DEPRECATION")
        Notification.Builder(ctx)
          .setPriority(Notification.PRIORITY_MAX)
          .setSound(toneUri(ctx), AudioManager.STREAM_ALARM)
      }
      val n = builder
        .setSmallIcon(R.mipmap.ic_launcher)
        .setContentTitle(fired.getStringExtra(AlarmScheduler.EXTRA_TITLE))
        .setContentText(fired.getStringExtra(AlarmScheduler.EXTRA_BODY))
        .setCategory(Notification.CATEGORY_ALARM)
        .setAutoCancel(true)
        .setContentIntent(openAppIntent(ctx, id, payload))
        .build()
      nm.notify(id, n)
    }
  }

  private val handler = Handler(Looper.getMainLooper())
  private var player: MediaPlayer? = null
  private var vibrator: Vibrator? = null
  private var session: MediaSession? = null
  private var focusRequest: AudioFocusRequest? = null
  private var receiver: BroadcastReceiver? = null
  private var startedAt = 0L
  private val timeout = Runnable { stopRinging() }

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (intent?.action == ACTION_STOP || intent == null) {
      stopRinging()
      return START_NOT_STICKY
    }

    // A new alarm while one is ringing replaces it.
    releaseRinging()
    instance = this
    startedAt = SystemClock.elapsedRealtime()

    val id = intent.getIntExtra(AlarmScheduler.EXTRA_ID, 0)
    val title = intent.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "Reminder"
    val body = intent.getStringExtra(AlarmScheduler.EXTRA_BODY) ?: ""
    val payload = intent.getStringExtra(AlarmScheduler.EXTRA_PAYLOAD) ?: ""

    val notification = buildNotification(id, title, body, payload)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
    } else {
      startForeground(NOTIFICATION_ID, notification)
    }

    requestFocus()
    play()
    vibrate()
    listenForButtons()
    handler.postDelayed(timeout, RING_MS)
    return START_NOT_STICKY
  }

  override fun onDestroy() {
    releaseRinging()
    super.onDestroy()
  }

  fun stopRinging() {
    releaseRinging()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      stopForeground(STOP_FOREGROUND_REMOVE)
    } else {
      @Suppress("DEPRECATION")
      stopForeground(true)
    }
    stopSelf()
  }

  private fun releaseRinging() {
    handler.removeCallbacks(timeout)
    player?.let {
      try {
        it.stop()
      } catch (_: Exception) {
      }
      it.release()
    }
    player = null
    vibrator?.cancel()
    vibrator = null
    session?.release()
    session = null
    receiver?.let {
      try {
        unregisterReceiver(it)
      } catch (_: Exception) {
      }
    }
    receiver = null
    abandonFocus()
    activity?.get()?.finish()
    activity = null
    if (instance === this) instance = null
  }

  private val alarmAttributes: AudioAttributes =
    AudioAttributes.Builder()
      .setUsage(AudioAttributes.USAGE_ALARM)
      .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
      .build()

  private fun play() {
    try {
      player = MediaPlayer().apply {
        setAudioAttributes(alarmAttributes)
        setDataSource(this@AlarmService, toneUri(this@AlarmService))
        setWakeMode(this@AlarmService, PowerManager.PARTIAL_WAKE_LOCK)
        isLooping = false
        setOnCompletionListener { stopRinging() }
        prepare()
        start()
      }
    } catch (e: Exception) {
      Log.w(TAG, "Could not play alarm tone: $e")
    }
  }

  private fun vibrate() {
    @Suppress("DEPRECATION")
    val v = getSystemService(Vibrator::class.java) ?: return
    if (!v.hasVibrator()) return
    vibrator = v
    val pattern = longArrayOf(0, 500, 700, 500, 1300)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      v.vibrate(VibrationEffect.createWaveform(pattern, 1), alarmAttributes)
    } else {
      @Suppress("DEPRECATION")
      v.vibrate(pattern, 1, alarmAttributes)
    }
  }

  private fun requestFocus() {
    val am = getSystemService(AudioManager::class.java)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        .setAudioAttributes(alarmAttributes)
        .build()
      focusRequest = req
      am.requestAudioFocus(req)
    } else {
      @Suppress("DEPRECATION")
      am.requestAudioFocus(null, AudioManager.STREAM_ALARM, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
    }
  }

  private fun abandonFocus() {
    val am = getSystemService(AudioManager::class.java)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      focusRequest?.let { am.abandonAudioFocusRequest(it) }
      focusRequest = null
    } else {
      @Suppress("DEPRECATION")
      am.abandonAudioFocus(null)
    }
  }

  private fun inGrace() = SystemClock.elapsedRealtime() - startedAt < GRACE_MS

  /** Power and volume buttons stop the alarm, like a clock app. */
  private fun listenForButtons() {
    val screenWasOn = getSystemService(PowerManager::class.java).isInteractive
    val r = object : BroadcastReceiver() {
      override fun onReceive(c: Context, i: Intent) {
        when (i.action) {
          Intent.ACTION_SCREEN_OFF -> stopRinging()
          // Screen was off: a power press turns it on.
          Intent.ACTION_SCREEN_ON -> if (!screenWasOn && !inGrace()) stopRinging()
          "android.media.VOLUME_CHANGED_ACTION" -> if (!inGrace()) stopRinging()
        }
      }
    }
    val filter = IntentFilter().apply {
      addAction(Intent.ACTION_SCREEN_OFF)
      addAction(Intent.ACTION_SCREEN_ON)
      addAction("android.media.VOLUME_CHANGED_ACTION")
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      registerReceiver(r, filter, Context.RECEIVER_EXPORTED)
    } else {
      registerReceiver(r, filter)
    }
    receiver = r

    // An active session with its own volume handling receives volume key
    // presses even when the volume is already at its limit.
    session = MediaSession(this, "HuddleAlarm").apply {
      setPlaybackToRemote(object : VolumeProvider(VOLUME_CONTROL_RELATIVE, 10, 5) {
        override fun onAdjustVolume(direction: Int) = stopRinging()
      })
      setCallback(object : MediaSession.Callback() {
        override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
          stopRinging()
          return true
        }
      })
      setPlaybackState(
        PlaybackState.Builder()
          .setState(PlaybackState.STATE_PLAYING, 0, 1f)
          .setActions(PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP)
          .build(),
      )
      isActive = true
    }
  }

  private fun buildNotification(id: Int, title: String, body: String, payload: String): Notification {
    val nm = getSystemService(NotificationManager::class.java)
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    val stop = PendingIntent.getService(
      this,
      1,
      Intent(this, AlarmService::class.java).setAction(ACTION_STOP),
      flags,
    )
    val fullScreen = PendingIntent.getActivity(
      this,
      2,
      Intent(this, AlarmActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION)
        .putExtra(AlarmScheduler.EXTRA_ID, id)
        .putExtra(AlarmScheduler.EXTRA_TITLE, title)
        .putExtra(AlarmScheduler.EXTRA_BODY, body)
        .putExtra(AlarmScheduler.EXTRA_PAYLOAD, payload),
      flags,
    )

    val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val channel = NotificationChannel(CHANNEL_ID, "Ringing alarms", NotificationManager.IMPORTANCE_HIGH).apply {
        description = "Shows the alarm while it is ringing"
        setSound(null, null) // the service plays the tone itself
        enableVibration(false)
        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
      }
      nm.createNotificationChannel(channel)
      Notification.Builder(this, CHANNEL_ID)
    } else {
      @Suppress("DEPRECATION")
      Notification.Builder(this).setPriority(Notification.PRIORITY_MAX)
    }

    val stopAction = Notification.Action.Builder(null, "Stop", stop).build()
    return builder
      .setSmallIcon(R.mipmap.ic_launcher)
      .setContentTitle(title)
      .setContentText(body)
      .setCategory(Notification.CATEGORY_ALARM)
      .setVisibility(Notification.VISIBILITY_PUBLIC)
      .setOngoing(true)
      .setAutoCancel(true)
      .setContentIntent(openAppIntent(this, id, payload))
      .setDeleteIntent(stop)
      .setFullScreenIntent(fullScreen, true)
      .addAction(stopAction)
      .build()
  }
}
