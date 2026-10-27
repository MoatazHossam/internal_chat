package com.example.internal_chat

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** A notification tapped before Dart asked for it (cold start). */
    private var pendingRoom: String? = null
    private var dartReady = false
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PushNotifications.CHANNEL)
        this.channel = channel
        PushNotifications.tokenListener = { token ->
            runOnUiThread { channel.invokeMethod("tokenChanged", tokenArguments(token)) }
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> requestPermission(result)
                "getToken" -> getToken(result)
                "takeOpenedRoom" -> {
                    dartReady = true
                    result.success(pendingRoom)
                    pendingRoom = null
                }
                "clearDelivered" -> {
                    PushNotifications.clear(this)
                    result.success(null)
                }
                "setAlertText" -> {
                    PushNotifications.setAlertText(this, call.argument<String>("text"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleNotificationTap(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNotificationTap(intent)
    }

    override fun onResume() {
        super.onResume()
        PushNotifications.appVisible = true
    }

    override fun onPause() {
        PushNotifications.appVisible = false
        super.onPause()
    }

    override fun onDestroy() {
        PushNotifications.tokenListener = null
        super.onDestroy()
    }

    private fun handleNotificationTap(intent: Intent?) {
        val room = intent?.getStringExtra(PushNotifications.EXTRA_ROOM_ID) ?: return
        intent.removeExtra(PushNotifications.EXTRA_ROOM_ID)
        if (dartReady) {
            channel?.invokeMethod("opened", room)
        } else {
            pendingRoom = room
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        val needsRuntimePermission = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        if (!needsRuntimePermission) {
            // Also false when the user turned notifications off in the settings.
            result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
            return
        }
        if (permissionResult != null) {
            // A request is already showing.
            result.success(false)
            return
        }
        permissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATIONS,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_NOTIFICATIONS) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        permissionResult?.success(granted)
        permissionResult = null
    }

    private fun getToken(result: MethodChannel.Result) {
        // Built without android/app/google-services.json: no Firebase, no push.
        if (FirebaseApp.getApps(this).isEmpty()) {
            result.success(null)
            return
        }
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            val token = if (task.isSuccessful) task.result else null
            if (token.isNullOrEmpty()) {
                result.error("token_unavailable", null, null)
            } else {
                result.success(tokenArguments(token))
            }
        }
    }

    private fun tokenArguments(token: String) = mapOf("service" to "fcm", "token" to token)

    companion object {
        private const val REQUEST_NOTIFICATIONS = 4101
    }
}
