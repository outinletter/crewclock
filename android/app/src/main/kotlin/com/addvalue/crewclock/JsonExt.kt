package com.addvalue.crewclock

import org.json.JSONObject

fun JSONObject.optBooleanCompat(name: String): Boolean {
    val value = opt(name) ?: return false
    return when (value) {
        is Boolean -> value
        is Number -> value.toInt() != 0
        is String -> value == "1" || value.equals("true", ignoreCase = true)
        else -> false
    }
}

