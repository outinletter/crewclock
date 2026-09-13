package com.addvalue.crewclock

import android.content.Context
import android.media.RingtoneManager
import android.net.Uri
import org.json.JSONObject

object NativeAlarmPrefs {
    fun snoozes(context: Context): JSONObject = JSONObject(
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("snoozes", "{}") ?: "{}"
    )

    fun saveSnooze(context: Context, id: String, data: JSONObject?) {
        val saved = snoozes(context)
        if (data == null) saved.remove(id) else saved.put(id, data)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("snoozes", saved.toString()).apply()
    }
    fun setActiveAlarm(context: Context, id: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("active_alarm_id", id).apply()
    }

    fun markActiveAlarmDismissed(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val id = prefs.getString("active_alarm_id", null) ?: return
        val ids = prefs.getStringSet("dismissed_alarm_ids", emptySet()).orEmpty().toMutableSet()
        ids.add(id.removeSuffix("_snooze"))
        prefs.edit().putStringSet("dismissed_alarm_ids", ids).remove("active_alarm_id").apply()
    }

    fun dismissedAlarmIds(context: Context): List<String> =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getStringSet("dismissed_alarm_ids", emptySet()).orEmpty().toList()

    fun acknowledgeDismissals(context: Context, ids: List<String>) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val remaining = prefs.getStringSet("dismissed_alarm_ids", emptySet()).orEmpty() - ids.toSet()
        prefs.edit().putStringSet("dismissed_alarm_ids", remaining).apply()
    }

    private const val PREFS = "crewclock_native_alarm"
    private const val KEY_ALARMS_JSON = "alarms_json"
    private const val KEY_ALARM_SOUND_URI = "alarm_sound_uri"

    fun saveAlarmsJson(context: Context, json: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_ALARMS_JSON, json)
            .apply()
    }

    fun getAlarmsJson(context: Context): String {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_ALARMS_JSON, "[]") ?: "[]"
    }

    fun setAlarmSoundUri(context: Context, uri: Uri?) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_ALARM_SOUND_URI, uri?.toString())
            .apply()
    }

    fun getAlarmSoundUri(context: Context): Uri? {
        val saved = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_ALARM_SOUND_URI, null)
        return if (saved.isNullOrBlank()) {
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        } else {
            Uri.parse(saved)
        }
    }
}
