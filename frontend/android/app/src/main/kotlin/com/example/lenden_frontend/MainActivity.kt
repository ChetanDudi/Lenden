package com.example.lenden_frontend

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "lenden_notifications"
            val channel = NotificationChannel(
                channelId,
                "LenDen Notifications",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "LenDen payment and transaction alerts"
                enableVibration(true)
                val soundUri = Uri.parse(
                    "android.resource://${packageName}/raw/notification_sound"
                )
                setSound(
                    soundUri,
                    AudioAttributes.Builder()
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .build()
                )
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }
}
