package com.addvalue.crewclock

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class AlarmAlertActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreen()
        setContentView(buildContent())
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        setContentView(buildContent())
    }

    private fun showOverLockScreen() {
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
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON,
        )
    }

    private fun buildContent(): LinearLayout {
        val label = intent.getStringExtra("label")?.takeIf { it.isNotBlank() }
            ?: "CrewClock Alarm"
        val route = buildRouteText()
        val alarmTime = formatAlarmTime(intent.getStringExtra("time").orEmpty())

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(26), dp(30), dp(26), dp(30))
            background = verticalGradient(0xffe9f6ff.toInt(), 0xfff7fbff.toInt())

            addView(
                TextView(this@AlarmAlertActivity).apply {
                    text = "CREW CLOCK"
                    gravity = Gravity.CENTER
                    setTextColor(0xff17324a.toInt())
                    textSize = 26f
                    letterSpacing = 0.18f
                    typeface = Typeface.DEFAULT_BOLD
                },
                fullWidthWrap(),
            )

            addView(
                TextView(this@AlarmAlertActivity).apply {
                    text = "FLIGHT ALARM"
                    gravity = Gravity.CENTER
                    setTextColor(0xff7da8c4.toInt())
                    textSize = 12f
                    letterSpacing = 0.22f
                    typeface = Typeface.DEFAULT_BOLD
                },
                fullWidthWrap().apply { topMargin = dp(8) },
            )

            addView(Space(this@AlarmAlertActivity), fullWidthFixed(28))

            addView(
                LinearLayout(this@AlarmAlertActivity).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER
                    setPadding(dp(22), dp(26), dp(22), dp(26))
                    background = roundedFill(0xffffffff.toInt(), dp(24), 0x22000000)

                    addView(
                        TextView(this@AlarmAlertActivity).apply {
                            text = alarmTime
                            gravity = Gravity.CENTER
                            setTextColor(0xff2f7fbd.toInt())
                            textSize = 44f
                            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
                        },
                        fullWidthWrap(),
                    )

                    addView(
                        TextView(this@AlarmAlertActivity).apply {
                            text = label
                            gravity = Gravity.CENTER
                            setTextColor(0xff172d42.toInt())
                            textSize = 22f
                            typeface = Typeface.DEFAULT_BOLD
                            maxLines = 2
                        },
                        fullWidthWrap().apply { topMargin = dp(18) },
                    )

                    if (route.isNotBlank()) {
                        addView(
                            TextView(this@AlarmAlertActivity).apply {
                                text = route
                                gravity = Gravity.CENTER
                                setTextColor(0xff55748d.toInt())
                                textSize = 15f
                                typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
                            },
                            fullWidthWrap().apply { topMargin = dp(8) },
                        )
                    }
                },
                fullWidthWrap(),
            )

            addView(Space(this@AlarmAlertActivity), fullWidthFixed(30))

            addView(
                primaryButton("Dismiss Alarm") {
                    AlarmRingingService.stop(this@AlarmAlertActivity)
                    finishAndRemoveTaskCompat()
                },
                fullWidthFixed(60),
            )

            addView(
                secondaryButton("Snooze 5 min") {
                    NativeAlarmScheduler.scheduleSnooze(this@AlarmAlertActivity, intent, 5)
                    AlarmRingingService.stop(this@AlarmAlertActivity)
                    finishAndRemoveTaskCompat()
                },
                fullWidthFixed(54).apply { topMargin = dp(12) },
            )

            addView(
                secondaryButton("Open App") {
                    startActivity(
                        Intent(this@AlarmAlertActivity, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP
                        },
                    )
                },
                fullWidthFixed(50).apply { topMargin = dp(6) },
            )
        }
    }

    private fun primaryButton(textValue: String, action: () -> Unit): Button {
        return Button(this).apply {
            text = textValue
            textSize = 19f
            isAllCaps = false
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            background = roundedFill(0xff2f7fbd.toInt(), dp(16), 0)
            setOnClickListener { action() }
        }
    }

    private fun secondaryButton(textValue: String, action: () -> Unit): Button {
        return Button(this).apply {
            text = textValue
            textSize = 16f
            isAllCaps = false
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(0xff2f7fbd.toInt())
            background = roundedStroke(0x00ffffff, dp(15), 0xff9dc7df.toInt(), dp(1))
            setOnClickListener { action() }
        }
    }

    private fun buildRouteText(): String {
        val fnum = intent.getStringExtra("fnum").orEmpty()
        val dep = intent.getStringExtra("depApt").orEmpty()
        val arr = intent.getStringExtra("arrApt").orEmpty()
        val route = listOf(dep, arr).filter { it.isNotBlank() && it != "???" }
            .joinToString(" -> ")
        return listOf(fnum, route).filter { it.isNotBlank() }.joinToString(" ")
    }

    private fun formatAlarmTime(raw: String): String {
        return runCatching {
            val local = Instant.parse(raw).atZone(ZoneId.systemDefault())
            DateTimeFormatter.ofPattern("HH:mm").format(local)
        }.getOrDefault("--:--")
    }

    private fun roundedFill(color: Int, radius: Int, shadowColor: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(color)
            cornerRadius = radius.toFloat()
            if (shadowColor != 0) setStroke(dp(1), 0x11000000)
        }
    }

    private fun roundedStroke(
        color: Int,
        radius: Int,
        strokeColor: Int,
        strokeWidth: Int,
    ): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(color)
            cornerRadius = radius.toFloat()
            setStroke(strokeWidth, strokeColor)
        }
    }

    private fun verticalGradient(top: Int, bottom: Int): GradientDrawable {
        return GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(top, bottom),
        )
    }

    private fun fullWidthWrap(): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
    }

    private fun fullWidthFixed(height: Int): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(height),
        )
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private fun finishAndRemoveTaskCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            finishAndRemoveTask()
        } else {
            finish()
        }
    }
}
