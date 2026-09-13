package com.addvalue.crewclock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import androidx.core.content.ContextCompat

class NativeAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("alarm_id").orEmpty()
        if (id.endsWith("_snooze")) {
            NativeAlarmPrefs.saveSnooze(context, id.removeSuffix("_snooze"), null)
        }
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "CrewClock:AlarmReceiverWakeLock"
        )
        // Acquire for 10 seconds to give the service enough time to start
        wakeLock.acquire(10 * 1000L)

        val serviceIntent = Intent(context, AlarmRingingService::class.java).apply {
            putExtras(intent)
        }
        ContextCompat.startForegroundService(context, serviceIntent)
    }
}
