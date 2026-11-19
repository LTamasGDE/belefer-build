package com.ventyh1.belefer

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject

/**
 * Csak a Revolut alkalmazás értesítéseit veszi figyelembe.
 *
 * Az Android az értesítés-hozzáférést rendszerszinten adja meg; ez a
 * szolgáltatás az első lépésben eldobja minden más alkalmazás értesítését,
 * azok tartalmát nem olvassa és nem tárolja.
 */
class BeleferNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName != REVOLUT_PACKAGE) return
        if (!CaptureQueue.isEnabled(this)) return
        val notification = sbn.notification ?: return
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (notification.flags and Notification.FLAG_ONGOING_EVENT != 0) return
        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)
            )?.toString().orEmpty()
        if (title.isBlank() && text.isBlank()) return
        val event = JSONObject()
            .put("id", "${sbn.key}|${(title + "\n" + text).hashCode()}")
            .put("source", "revolut")
            .put("time", sbn.postTime)
            .put("title", title)
            .put("text", text)
        CaptureQueue.add(this, event)
    }

    companion object {
        const val REVOLUT_PACKAGE = "com.revolut.revolut"
    }
}
