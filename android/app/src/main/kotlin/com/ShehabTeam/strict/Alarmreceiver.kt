package com.ShehabTeam.strict

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        

        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "AlarmReceiver::TempWakeLock"
        )
        wakeLock.acquire(30_000L)

        try {
            if (MainActivity.isServiceRunning) {

                CaptureService.triggerCapture()
            } else {



                writeLogEntry(context, "SYSTEM", "Service was killed by system")
                sendServiceKilledNotification(context)
            }
        } finally {
            if (wakeLock.isHeld) wakeLock.release()
        }


        AlarmScheduler.schedule(context)
    }

    private fun writeLogEntry(context: Context, appName: String, analysis: String) {
        try {
            val fileFormat = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
            val logFormat  = SimpleDateFormat("dd/MM/yy HH:mm:ss", Locale.getDefault())
            val now = Date()
            val logDir = File(context.getExternalFilesDir(null), "Logs")
            if (!logDir.exists()) logDir.mkdirs()
            val logFile = File(logDir, "log_${fileFormat.format(now)}.txt")
            logFile.appendText("${logFormat.format(now)} | Battery: -- | App: $appName | $analysis\n")
        } catch (e: Exception) {
            
        }
    }

    private fun sendServiceKilledNotification(context: Context) {
    val channelId = "killed_channel"
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val channel = NotificationChannel(
            channelId, "Service Alerts", NotificationManager.IMPORTANCE_HIGH
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
        .setSmallIcon(android.R.drawable.ic_dialog_alert)
        .setContentTitle(if (isArabic) "توقفت المراقبة" else "Monitoring stopped")
        .setContentText(if (isArabic) "أوقف النظام الخدمة — اضغط لإعادة التشغيل" else "System stopped the service — tap to restart it")
        .setPriority(NotificationCompat.PRIORITY_HIGH)
        .setContentIntent(openIntent)
        .setAutoCancel(true)
        .build()

    context.getSystemService(NotificationManager::class.java)?.notify(3, notification)
}
}