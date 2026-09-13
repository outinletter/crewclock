package com.addvalue.crewclock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class NativeAlarmBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        runCatching { NativeAlarmScheduler.rescheduleSavedAlarms(context) }
    }
}
