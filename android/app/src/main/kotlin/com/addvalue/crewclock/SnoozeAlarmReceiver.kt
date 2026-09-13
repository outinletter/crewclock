package com.addvalue.crewclock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class SnoozeAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        NativeAlarmScheduler.scheduleSnooze(context, intent, 5)
        AlarmRingingService.stop(context)
    }
}

