package com.addvalue.crewclock

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "crewclock/native_alarm"
    private val batteryChannelName = "crewclock/battery_optimization"
    private val soundRequestCode = 8042
    private var pendingSoundResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDismissedAlarmIds" -> result.success(NativeAlarmPrefs.dismissedAlarmIds(this))
                    "acknowledgeDismissals" -> {
                        val ids = (call.arguments as? List<*>)?.filterIsInstance<String>().orEmpty()
                        NativeAlarmPrefs.acknowledgeDismissals(this, ids)
                        result.success(null)
                    }
                    "scheduleAlarms" -> {
                        val json = call.arguments as? String ?: "[]"
                        try {
                            NativeAlarmScheduler.scheduleAlarms(this, json)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("alarm_schedule_failed", e.message, null)
                        }
                    }
                    "chooseAlarmSound" -> {
                        chooseAlarmSound(result)
                    }
                    "stopAlarm" -> {
                        AlarmRingingService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, batteryChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "requestIgnoreBatteryOptimizations") {
                    requestIgnoreBatteryOptimizations()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun requestIgnoreBatteryOptimizations() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        }
    }

    private fun chooseAlarmSound(result: MethodChannel.Result) {
        if (pendingSoundResult != null) {
            result.error("busy", "Alarm sound picker is already open.", null)
            return
        }

        val current = NativeAlarmPrefs.getAlarmSoundUri(this)
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Choose alarm sound")
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, current)
        }

        pendingSoundResult = result
        startActivityForResult(intent, soundRequestCode)
    }

    @Deprecated("Deprecated in Android API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != soundRequestCode) return

        val result = pendingSoundResult
        pendingSoundResult = null

        if (resultCode == Activity.RESULT_OK) {
            val uri: Uri? = data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
            NativeAlarmPrefs.setAlarmSoundUri(this, uri)
            result?.success(uri?.toString())
        } else {
            result?.success(null)
        }
    }
}
