package com.addvalue.crewclock

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

object NativeAlarmScheduler {
    private const val REQUEST_BASE = 120000

    fun scheduleAlarms(context: Context, json: String) {
        val appContext = context.applicationContext
        val alarms = JSONArray(json)
        val retainedIds = (0 until alarms.length()).mapNotNull {
            alarms.optJSONObject(it)?.optString("id")
        }.toSet()
        cancelAll(appContext, NativeAlarmPrefs.getAlarmsJson(appContext), retainedIds)
        NativeAlarmPrefs.saveAlarmsJson(appContext, json)
        val manager = appContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !manager.canScheduleExactAlarms()) {
            if (alarms.length() > 0) throw SecurityException("Allow alarms and reminders in Settings.")
            return
        }
        val now = System.currentTimeMillis()
        for (index in 0 until alarms.length()) {
            val alarm = alarms.optJSONObject(index) ?: continue
            val timeText = alarm.optString("time", "")
            val triggerAt = runCatching { Instant.parse(timeText).toEpochMilli() }.getOrNull()
                ?: continue

            if (triggerAt <= now) continue
            if (!alarm.optBooleanCompat("armed")) continue
            if (alarm.optBooleanCompat("dism") || alarm.optBooleanCompat("missed")) continue

            val requestCode = requestCodeFor(alarm.optString("id", index.toString()))
            val intent = Intent(appContext, NativeAlarmReceiver::class.java).apply {
                putExtra("alarm_id", alarm.optString("id"))
                putExtra("label", alarm.optString("lbl", "CrewClock Alarm"))
                putExtra("type", alarm.optString("type"))
                putExtra("fnum", alarm.optString("fnum"))
                putExtra("depApt", alarm.optString("depApt"))
                putExtra("arrApt", alarm.optString("arrApt"))
                putExtra("time", timeText)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                appContext,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val showIntent = PendingIntent.getActivity(
                appContext,
                requestCode,
                Intent(appContext, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val alarmManager = appContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAlarmClock(
                    AlarmManager.AlarmClockInfo(triggerAt, showIntent),
                    pendingIntent,
                )
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            }
        }
    }

    fun rescheduleSavedAlarms(context: Context) {
        scheduleAlarms(context, NativeAlarmPrefs.getAlarmsJson(context))
        val snoozes = NativeAlarmPrefs.snoozes(context)
        for (id in snoozes.keys()) {
            val saved = snoozes.getJSONObject(id)
            val triggerAt = saved.getLong("triggerAt")
            if (triggerAt <= System.currentTimeMillis()) {
                NativeAlarmPrefs.saveSnooze(context, id, null)
                continue
            }
            val source = Intent().putExtra("alarm_id", id)
            for (key in listOf("label", "type", "fnum", "depApt", "arrApt")) {
                source.putExtra(key, saved.optString(key))
            }
            scheduleSnooze(context, source, triggerAtOverride = triggerAt)
        }
    }

    fun scheduleSnooze(context: Context, sourceIntent: Intent, minutes: Int = 5, triggerAtOverride: Long? = null) {
        val appContext = context.applicationContext
        val manager = appContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !manager.canScheduleExactAlarms()) return
        val triggerAt = triggerAtOverride ?: (System.currentTimeMillis() + minutes.coerceAtLeast(1) * 60_000L)
        val alarmId = sourceIntent.getStringExtra("alarm_id").orEmpty()
            .removeSuffix("_snooze")
            .ifBlank { "snooze_${System.currentTimeMillis()}" }
        val requestCode = requestCodeFor("${alarmId}_snooze")
        val saved = JSONObject().put("triggerAt", triggerAt)
        for (key in listOf("label", "type", "fnum", "depApt", "arrApt")) {
            saved.put(key, sourceIntent.getStringExtra(key).orEmpty())
        }
        NativeAlarmPrefs.saveSnooze(context, alarmId, saved)

        val alarmIntent = Intent(appContext, NativeAlarmReceiver::class.java).apply {
            putExtras(sourceIntent)
            putExtra("alarm_id", "${alarmId}_snooze")
            putExtra("label", sourceIntent.getStringExtra("label") ?: "CrewClock Alarm")
            putExtra("time", java.time.Instant.ofEpochMilli(triggerAt).toString())
        }
        val pendingIntent = PendingIntent.getBroadcast(
            appContext,
            requestCode,
            alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val showIntent = PendingIntent.getActivity(
            appContext,
            requestCode,
            Intent(appContext, AlarmAlertActivity::class.java).apply {
                putExtras(alarmIntent)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val alarmManager = appContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(triggerAt, showIntent),
                pendingIntent,
            )
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        }
    }

    private fun cancelAll(context: Context, json: String, retainedIds: Set<String>) {
        val alarms = JSONArray(json)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (index in 0 until alarms.length()) {
            val alarm = alarms.optJSONObject(index) ?: continue
            val id = alarm.optString("id", index.toString())
            val pendingIds = if (id !in retainedIds) {
                NativeAlarmPrefs.saveSnooze(context, id, null)
                listOf(id, "${id}_snooze")
            } else listOf(id)
            for (pendingId in pendingIds) {
            val requestCode = requestCodeFor(pendingId)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                Intent(context, NativeAlarmReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )
            if (pendingIntent != null) {
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
            }
            }
        }
    }

    private fun requestCodeFor(id: String): Int {
        var hash = 0x811c9dc5.toInt()
        for (ch in id) {
            hash = hash xor ch.code
            hash *= 0x01000193
        }
        return REQUEST_BASE + (hash and 0x0fffffff)
    }
}
