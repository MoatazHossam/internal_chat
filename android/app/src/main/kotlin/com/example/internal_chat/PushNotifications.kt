package com.example.internal_chat

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Shows push notifications. The text is always the generic "New message"
 * in the app's language: pushes carry only the room ID, the event ID and
 * counts, and nothing here reads message content or the sender.
 */
object PushNotifications {
    const val CHANNEL = "internal_chat/push"
    const val EXTRA_ROOM_ID = "internal_chat.room_id"
    private const val MESSAGES_CHANNEL_ID = "messages"
    private const val PREFERENCES = "internal_chat_push"
    private const val KEY_ALERT_TEXT = "alert_text"

    /** While the app is on screen the conversation list updates live. */
    @Volatile
    var appVisible = false

    @Volatile
    var tokenListener: ((String) -> Unit)? = null

    fun setAlertText(context: Context, text: String?) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_ALERT_TEXT, text)
            .apply()
    }

    @SuppressLint("MissingPermission")
    fun showNewMessage(context: Context, roomId: String) {
        if (appVisible) return
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return
        manager.createNotificationChannel(
            NotificationChannelCompat.Builder(
                MESSAGES_CHANNEL_ID,
                NotificationManagerCompat.IMPORTANCE_HIGH,
            ).setName(context.getString(R.string.push_channel_messages)).build(),
        )
        val text = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getString(KEY_ALERT_TEXT, null)
            ?: context.getString(R.string.push_new_message)
        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_ROOM_ID, roomId)
        }
        val tap = PendingIntent.getActivity(
            context,
            roomId.hashCode(),
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, MESSAGES_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_message)
            .setContentTitle(text)
            .setContentIntent(tap)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            // The text is generic, so it may show on the lock screen.
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
        // One notification per conversation; a newer message replaces it.
        try {
            manager.notify(roomId.hashCode(), notification)
        } catch (_: SecurityException) {
            // Permission withdrawn meanwhile.
        }
    }

    fun clear(context: Context) {
        NotificationManagerCompat.from(context).cancelAll()
    }
}
