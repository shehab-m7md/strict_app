package com.ShehabTeam.strict

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
    val action = intent.action ?: return
    val isBootAction = action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON"
    if (!isBootAction) return

    val prefs = context.getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
    val existing = prefs.getString("boot_times_list", "") ?: ""
    val newEntry = System.currentTimeMillis().toString()
    val updated = if (existing.isEmpty()) newEntry else "$existing,$newEntry"
    prefs.edit().putString("boot_times_list", updated).apply()

        sendBootNotification(context)
    }

    private fun sendBootNotification(context: Context) {
    val channelId = "boot_channel"
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val channel = NotificationChannel(
            channelId, "Boot Notifications", NotificationManager.IMPORTANCE_HIGH
        )
        context.getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
    }

    val isArabic = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    .getString("flutter.app_locale", "en") == "ar"

    val openIntent = PendingIntent.getActivity(
        context, 0,
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    val notification = NotificationCompat.Builder(context, channelId)
        .setSmallIcon(R.mipmap.ic_launcher)
        .setContentTitle(if (isArabic) "المراقبة متوقفة" else "Monitoring is off")
        .setContentText(if (isArabic) "تم إعادة تشغيل الجهاز — اضغط لإعادة التشغيل" else "Device restarted — tap to restart it")
        .setPriority(NotificationCompat.PRIORITY_HIGH)
        .setContentIntent(openIntent)
        .setAutoCancel(true)
        .build()

    context.getSystemService(NotificationManager::class.java)?.notify(2, notification)
}
}