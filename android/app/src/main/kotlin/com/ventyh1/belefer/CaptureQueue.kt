package com.ventyh1.belefer

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Az automatikus rögzítésre váró Revolut-értesítések sora (az alkalmazás
 * saját, privát tárolójában), amíg a Belefér meg nem nyílik és fel nem
 * dolgozza őket.
 */
object CaptureQueue {
    private const val PREFS = "belefer_capture"
    private const val KEY_QUEUE = "queue"
    private const val KEY_SEEN = "seen"
    const val KEY_ENABLED = "revolut_enabled"
    private const val MAX_QUEUE = 200
    private const val MAX_SEEN = 150

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_ENABLED, enabled).apply()
        if (!enabled) clear(context)
    }

    @Synchronized
    fun add(context: Context, event: JSONObject) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val id = event.optString("id")
        val seen = JSONArray(prefs.getString(KEY_SEEN, "[]"))
        for (i in 0 until seen.length()) {
            if (seen.optString(i) == id) return
        }
        seen.put(id)
        while (seen.length() > MAX_SEEN) seen.remove(0)
        val queue = JSONArray(prefs.getString(KEY_QUEUE, "[]"))
        queue.put(event)
        while (queue.length() > MAX_QUEUE) queue.remove(0)
        prefs.edit()
            .putString(KEY_SEEN, seen.toString())
            .putString(KEY_QUEUE, queue.toString())
            .apply()
    }

    /** A sor tartalma (és a sor ürítése). */
    @Synchronized
    fun drain(context: Context): List<Map<String, Any?>> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val queue = JSONArray(prefs.getString(KEY_QUEUE, "[]"))
        prefs.edit().putString(KEY_QUEUE, "[]").apply()
        val result = mutableListOf<Map<String, Any?>>()
        for (i in 0 until queue.length()) {
            val item = queue.optJSONObject(i) ?: continue
            val map = mutableMapOf<String, Any?>()
            for (key in item.keys()) map[key] = item.get(key)
            result.add(map)
        }
        return result
    }

    @Synchronized
    private fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_QUEUE, "[]").apply()
    }
}
