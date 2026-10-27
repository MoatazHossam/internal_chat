package com.example.internal_chat

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Receives FCM data messages from the push gateway (Sygnal, format
 * `event_id_only`). Runs even when the app is not open.
 */
class PushMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val roomId = data["room_id"]
        // Updates without an event (for example the unread count after a
        // message was read on another device) show nothing.
        if (data["event_id"].isNullOrEmpty() || roomId.isNullOrEmpty()) return
        PushNotifications.showNewMessage(applicationContext, roomId)
    }

    override fun onNewToken(token: String) {
        PushNotifications.tokenListener?.invoke(token)
    }
}
