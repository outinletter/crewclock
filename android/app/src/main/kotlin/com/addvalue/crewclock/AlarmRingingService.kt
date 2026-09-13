package com.addvalue.crewclock

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class AlarmRingingService : Service() {
    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val alertHandler = Handler(Looper.getMainLooper())

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        NativeAlarmPrefs.setActiveAlarm(this, intent.getStringExtra("alarm_id").orEmpty())
        acquireWakeLock()
        val label = intent?.getStringExtra("label")?.takeIf { it.isNotBlank() }
            ?: "CrewClock Alarm"
        val route = buildRouteText(intent)

        startForeground(FOREGROUND_ID, buildNotification(label, route, intent))
        startRingtone()
        // Full-screen presentation is controlled by the notification permission.
        // Do not repeatedly launch an activity over other apps.
        alertHandler.removeCallbacksAndMessages(null)
        alertHandler.postDelayed({ stop(this) }, 7 * 60_000L)

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        alertHandler.removeCallbacksAndMessages(null)
        stopRingtone()
        releaseWakeLock()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
    }

    private fun buildAlertIntent(sourceIntent: Intent?): Intent {
        return Intent(this, AlarmAlertActivity::class.java).apply {
            sourceIntent?.extras?.let { putExtras(it) }
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
    }

    private fun startRingtone() {
        stopRingtone()
        val soundUri = NativeAlarmPrefs.getAlarmSoundUri(this)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        player = runCatching { createLoopingPlayer(soundUri) }
            .getOrElse {
                val defaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                runCatching { createLoopingPlayer(defaultUri) }.getOrNull()
            }
    }

    private fun stopRingtone() {
        player?.let {
            runCatching { if (it.isPlaying) it.stop() }
            it.release()
        }
        player = null
    }

    private fun createLoopingPlayer(soundUri: Uri): MediaPlayer {
        return MediaPlayer().apply {
            setDataSource(this@AlarmRingingService, soundUri)
            setWakeMode(this@AlarmRingingService, PowerManager.PARTIAL_WAKE_LOCK)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
            } else {
                @Suppress("DEPRECATION")
                setAudioStreamType(android.media.AudioManager.STREAM_ALARM)
            }
            isLooping = true
            prepare()
            start()
        }
    }

    private fun buildNotification(
        title: String,
        route: String,
        sourceIntent: Intent?,
    ): android.app.Notification {
        ensureChannel()

        val alertIntent = buildAlertIntent(sourceIntent)
        val alertPendingIntent = PendingIntent.getActivity(
            this,
            1,
            alertIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopPendingIntent = PendingIntent.getBroadcast(
            this,
            2,
            Intent(this, StopAlarmReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val snoozePendingIntent = PendingIntent.getBroadcast(
            this,
            3,
            Intent(this, SnoozeAlarmReceiver::class.java).apply {
                sourceIntent?.extras?.let { putExtras(it) }
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(route.ifEmpty { "Alarm ringing" })
            .setStyle(NotificationCompat.BigTextStyle().bigText(route.ifEmpty { title }))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(alertPendingIntent, true)
            .setContentIntent(alertPendingIntent)
            .addAction(0, "Dismiss Alarm", stopPendingIntent)
            .addAction(0, "Snooze 5 min", snoozePendingIntent)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "CrewClock Ringing Alarm",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Persistent ringing alarms"
            setSound(null, null)
            enableVibration(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildRouteText(intent: Intent?): String {
        val fnum = intent?.getStringExtra("fnum").orEmpty()
        val dep = intent?.getStringExtra("depApt").orEmpty()
        val arr = intent?.getStringExtra("arrApt").orEmpty()
        val route = listOf(dep, arr).filter { it.isNotBlank() && it != "???" }
            .joinToString(" -> ")
        return listOf(fnum, route).filter { it.isNotBlank() }.joinToString(" ")
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "CrewClock:AlarmRingingWakeLock"
            ).apply {
                acquire(8 * 60_000L)
            }
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        wakeLock = null
    }

    companion object {
        private const val CHANNEL_ID = "crewclock_ringing_alarm_channel"
        private const val FOREGROUND_ID = 7001

        fun stop(context: Context) {
            NativeAlarmPrefs.markActiveAlarmDismissed(context)
            context.stopService(Intent(context, AlarmRingingService::class.java))
        }
    }
}
