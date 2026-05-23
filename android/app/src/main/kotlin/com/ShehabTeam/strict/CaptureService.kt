package com.ShehabTeam.strict

import androidx.work.*
import android.app.Activity
import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat
import android.graphics.Bitmap
import android.graphics.PixelFormat
import org.tensorflow.lite.Interpreter
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.text.SimpleDateFormat
import java.util.*

class CaptureService : Service() {

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var handlerThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private var tfliteInterpreter: Interpreter? = null
    private var wakeLock: PowerManager.WakeLock? = null
    

    private var isScreenOn = true
    private var lastKnownApp = "Unknown"
    private var currentUid = "unknown"
    private var consecutiveNsfwCount = 0
    private var nsfwNotificationSent = false

    private enum class StopReason { USER, EXTERNAL, UNEXPECTED, LOGOUT }
    private var stopReason = StopReason.UNEXPECTED

    private val MODEL_INPUT_SIZE = 224
    private val MODEL_INPUT_CHANNELS = 3
    private val PREFS_NAME = "app_prefs"


    private val REPORT_MARKER = "==="

    companion object {
        var instance: CaptureService? = null
            private set

        fun triggerCapture() {
            instance?.saveFrameAndAnalyze()
        }

        fun stopByUser() {
            instance?.let {
                it.stopReason = StopReason.USER
                it.stopSelf()
            }
        }
        fun stopByLogout() {
    instance?.let { it.stopReason = StopReason.LOGOUT; it.stopSelf() }
}
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> isScreenOn = false
                Intent.ACTION_SCREEN_ON  -> isScreenOn = true
                Intent.ACTION_SHUTDOWN   -> writeLogEntry("SYSTEM", "Device shutting down")
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SHUTDOWN)
        }
        registerReceiver(screenReceiver, filter)
        loadModel()

        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "CaptureService::WakeLock")
        wakeLock?.acquire(24 * 60 * 60 * 1000L)

        
    }
private fun createNotification(): Notification {
    val channelId = "monitor_channel"
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val chan = NotificationChannel(
            channelId, "Monitoring", NotificationManager.IMPORTANCE_LOW
        )
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(chan)
    }

    val isArabic = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        .getString("flutter.app_locale", "en") == "ar"

    return NotificationCompat.Builder(this, channelId)
        .setSmallIcon(android.R.drawable.ic_menu_camera)
        .setContentTitle(if (isArabic) "المراقبة" else "Monitoring")
        .setContentText(if (isArabic) "تعمل في الخلفية..." else "Running in background...")
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .setOngoing(true)
        .build()
}
    private fun loadModel() {
        try {
            val modelFile = copyAssetToCache("nsfw_inference.tflite")
            tfliteInterpreter = Interpreter(modelFile, Interpreter.Options().apply { setNumThreads(2) })
            
        } catch (e: Exception) {
            
        }
    }

    private fun copyAssetToCache(assetName: String): File {
        val cacheFile = File(cacheDir, assetName)
        if (cacheFile.exists() && cacheFile.length() > 0) {
            return cacheFile
        }
        assets.open(assetName).use { input ->
            FileOutputStream(cacheFile).use { output ->
                input.copyTo(output)
            }
        }
        
        return cacheFile
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stopReason = StopReason.UNEXPECTED
        currentUid = intent?.getStringExtra("uid") ?: "unknown"

 getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    .edit()
    .putString("current_uid", currentUid)
    .apply()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1, createNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(1, createNotification())
        }

        handlerThread = HandlerThread("CaptureThread")
        handlerThread?.start()
        backgroundHandler = Handler(handlerThread!!.looper)

        val resultCode = MainActivity.savedResultCode
        val data = MainActivity.savedData

        if (resultCode != Activity.RESULT_OK || data == null) {
            
            stopSelf()
            return START_NOT_STICKY
        }

        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = manager.getMediaProjection(resultCode, data)

        if (mediaProjection == null) {
            
            stopSelf()
            return START_NOT_STICKY
        }

        writeBootTimeIfNeeded()


        markOldLogsAsComplete()

        setupCapture()
        backgroundHandler?.postDelayed({ saveFrameAndAnalyze() }, 2_000L)
        AlarmScheduler.schedule(this)
        writeLogEntry("SYSTEM", "Service started")

        return START_STICKY
    }
    private fun getLogsDir(): File {
    val dir = File(filesDir, "logs/$currentUid")
    if (!dir.exists()) dir.mkdirs()
    return dir
    }

    private fun writeBootTimeIfNeeded() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val bootTimesStr = prefs.getString("boot_times_list", "") ?: ""
        if (bootTimesStr.isEmpty()) return

        val fileFormat = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
        val logFormat  = SimpleDateFormat("dd/MM/yy HH:mm:ss", Locale.getDefault())

        try {
            val logDir = getLogsDir()
            if (!logDir.exists()) logDir.mkdirs()

            bootTimesStr.split(",").forEach { tsStr ->
                val ts = tsStr.trim().toLongOrNull() ?: return@forEach
                val bootDate = Date(ts)
                val logFile = File(logDir, "log_${fileFormat.format(bootDate)}.txt")
                logFile.appendText("${logFormat.format(bootDate)} | Battery: -- | App: SYSTEM | Device started after reboot\n")
                
            }
        } catch (e: Exception) {
            
        }

        prefs.edit().remove("boot_times_list").apply()
    }


    private fun markOldLogsAsComplete() {
        try {
            val logDir = getLogsDir()
            if (!logDir.exists()) return

            val completedDir = File(logDir, "Completed")
            if (!completedDir.exists()) completedDir.mkdirs()

            val fileFormat = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
            val todayName = "log_${fileFormat.format(Date())}.txt"

            logDir.listFiles()
                ?.filter { it.isFile && it.name.startsWith("log_") && it.name != todayName }
                ?.sortedBy { it.name }
                ?.forEach { file ->
                    val dest = File(completedDir, file.name)
                    if (file.renameTo(dest)) {
                        
                    }
                }

        } catch (e: Exception) {
            
        }


        startReportThread()
        enqueueUpload()
    }


    private fun startReportThread() {
        Thread {
            try {
                val logDir = getLogsDir()
                val completedDir = File(logDir, "Completed")
                val reportedDir  = File(logDir, "Reported")

                if (!completedDir.exists()) return@Thread
                if (!reportedDir.exists()) reportedDir.mkdirs()


                val files = completedDir.listFiles()
                    ?.filter { it.isFile && it.name.startsWith("log_") }
                    ?.sortedBy { it.name }
                    ?: return@Thread

                if (files.isEmpty()) {
                    
                    return@Thread
                }

                for (file in files) {
                    
                    processFileReport(file, reportedDir)
                }

            } catch (e: Exception) {
                
            }
        }.start()
    }


    private fun processFileReport(file: File, reportedDir: File) {
        try {
            var content = file.readText()


            val markerCount = content.split(REPORT_MARKER).size - 1

            when {

                markerCount >= 6 -> {
                val dest = File(reportedDir, file.name)
                if (file.renameTo(dest)) {
                enqueueUpload()
                }
                return
                }
                markerCount in 1..5 -> {
                    
                    val firstMarker = content.indexOf(REPORT_MARKER)
                    content = content.substring(0, firstMarker).trimEnd()
                    file.writeText(content + "\n")
                }

                else -> {
                    
                }
            }


            val reportText = buildReport(content, file.name)


            file.appendText("\n$REPORT_MARKER\n$reportText\n$REPORT_MARKER\n")


            val dest = File(reportedDir, file.name)
            if (file.renameTo(dest)) {
                
                    enqueueUpload()

            }

        } catch (e: Exception) {
            
        }
    }


    private fun getAppUsageForDate(dateStr: String): Map<String, Long> {
     return try {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
        val date = sdf.parse(dateStr) ?: return emptyMap()
        val cal = Calendar.getInstance().apply { time = date }

        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        val startTime = cal.timeInMillis
        val endTime = startTime + 24 * 60 * 60 * 1000L

        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
        val stats = usm.queryUsageStats(
            android.app.usage.UsageStatsManager.INTERVAL_DAILY,
            startTime,
            endTime
        )

        stats
            ?.filter { it.totalTimeInForeground > 60_000L } // أكتر من دقيقة بس
            ?.associate { it.packageName to it.totalTimeInForeground }
            ?: emptyMap()

     } catch (e: Exception) { emptyMap() }
    }



    private fun buildReport(content: String, fileName: String): String {
    val lines = content.lines().filter { it.isNotBlank() }
    if (lines.isEmpty()) return "No data found."

    val report = StringBuilder()

    val dateStr = fileName.removePrefix("log_").removeSuffix(".txt")
    val deviceInfo = "${Build.MANUFACTURER} ${Build.MODEL} (Android ${Build.VERSION.RELEASE})"

    report.appendLine("Date: $dateStr")
    report.appendLine("Device: $deviceInfo")
    report.appendLine("─────────────────────────────")

    data class LogEntry(
        val timeStr: String,
        val battery: String,
        val app: String,
        val result: String,
        val timeMs: Long
    )

 fun parseTime(timeStr: String): Long {
        return try {
            val sdf = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
            sdf.parse(timeStr)?.time ?: -1L
        } catch (e: Exception) { -1L }
    }

    val entries = mutableListOf<LogEntry>()
    for (line in lines) {
        val parts = line.split(" | ")
        if (parts.size < 4) continue
        val timeStr = parts[0].trim()
        val battery = parts[1].trim().removePrefix("Battery:").trim().removeSuffix("%")
        val app     = parts[2].trim().removePrefix("App:").trim()
        val result  = parts.drop(3).joinToString(" | ").trim()
        val timeMs  = parseTime(timeStr)
        if (timeMs < 0) continue
        entries.add(LogEntry(timeStr, battery, app, result, timeMs))
    }

    if (entries.isEmpty()) return "No valid entries found."

    val startOfDay = parseTime("00:00:00")
    val endOfDay   = parseTime("23:59:59")
    val twoMinutes = 2 * 60 * 1000L

    // ═══════════════════════════════════════════════
    // 1. الغيابات
    // ═══════════════════════════════════════════════
    val gaps = StringBuilder()

    val firstEntry = entries.first()
    val gapFromStart = firstEntry.timeMs - startOfDay
    if (gapFromStart > twoMinutes) {
        gaps.appendLine("• Gap at start of day: 00:00:00 → ${firstEntry.timeStr} (${formatDuration(gapFromStart)})")
    }

    val lastEntry = entries.last()
    val gapToEnd = endOfDay - lastEntry.timeMs
    if (gapToEnd > twoMinutes) {
        gaps.appendLine("• Gap at end of day: ${lastEntry.timeStr} → 23:59:59 (${formatDuration(gapToEnd)})")
    }

    for (i in 0 until entries.size - 1) {
        val curr = entries[i]
        val next = entries[i + 1]
        val diff = next.timeMs - curr.timeMs

        val isStopEntry = curr.result.contains("stopped by user from app") ||
                          curr.result.contains("stopped by user (recording revoked)") ||
                          curr.result.contains("stopped (system kill or force stop)")

        if (isStopEntry) {
            val nextStart = entries.drop(i + 1).firstOrNull { it.result == "Service started" }
            if (nextStart != null) {
                val stopDuration = nextStart.timeMs - curr.timeMs
                val reason = when {
                    curr.result.contains("stopped by user from app") -> "Stopped by user"
                    curr.result.contains("recording revoked")        -> "Recording revoked"
                    else                                              -> "System kill / Force stop"
                }
                gaps.appendLine("• $reason: ${curr.timeStr} → ${nextStart.timeStr} (${formatDuration(stopDuration)})")
            } else {
                gaps.appendLine("• ${curr.result} at ${curr.timeStr} — service did not restart")
            }
            continue
        }

        if (curr.result.contains("Device started after reboot")) {
            val nextStart = entries.drop(i + 1).firstOrNull { it.result == "Service started" }
            if (nextStart != null) {
                val rebootDuration = nextStart.timeMs - curr.timeMs
                if (rebootDuration > twoMinutes) {
                    gaps.appendLine("• Reboot: ${curr.timeStr} → ${nextStart.timeStr} (${formatDuration(rebootDuration)})")
                }
            }
            continue
        }

        if (diff > twoMinutes) {
            val batteryVal = curr.battery.toIntOrNull()
            if (batteryVal != null && batteryVal <= 2) continue
            val isNextStart = next.result == "Service started"
            val gapLabel = if (isNextStart) "Unexplained gap (possible kill/force stop)" else "Unexplained gap"
            gaps.appendLine("• $gapLabel: ${curr.timeStr} → ${next.timeStr} (${formatDuration(diff)})")
        }
    }

    if (gaps.isNotEmpty()) {
        report.appendLine("⚠️ Gaps:")
        report.append(gaps)
        report.appendLine("─────────────────────────────")
    }

    // ═══════════════════════════════════════════════
    // 2. NSFW
    // ═══════════════════════════════════════════════
    val nsfwEvents = StringBuilder()
    var i = 0
    while (i < entries.size) {
        val entry = entries[i]
        if (entry.result.startsWith("NSFW")) {
            var j = i + 1
            while (j < entries.size && entries[j].result.startsWith("NSFW")) { j++ }
            val chainLength = j - i
            if (chainLength >= 2) {
                val start = entries[i]
                val end   = entries[j - 1]
                val duration = end.timeMs - start.timeMs + 15_000L
                nsfwEvents.appendLine("• NSFW on [${start.app}]: ${start.timeStr} → ${end.timeStr} (${formatDuration(duration)})")
            }
            i = j
        } else { i++ }
    }

    if (nsfwEvents.isNotEmpty()) {
        report.appendLine("🔴 NSFW sequences:")
        report.append(nsfwEvents)
        report.appendLine("─────────────────────────────")
    }

    // ═══════════════════════════════════════════════
    // 3. PROTECTED
    // ═══════════════════════════════════════════════
    val protectedEvents = StringBuilder()
    i = 0
    while (i < entries.size) {
        val entry = entries[i]
        if (entry.result == "PROTECTED") {
            var j = i + 1
            while (j < entries.size && entries[j].result == "PROTECTED") { j++ }
            val chainLength = j - i
            if (chainLength >= 2) {
                val start = entries[i]
                val end   = entries[j - 1]
                val duration = end.timeMs - start.timeMs + 15_000L
                protectedEvents.appendLine("• Protected content on [${start.app}]: ${start.timeStr} → ${end.timeStr} (${formatDuration(duration)})")
            }
            i = j
        } else { i++ }
    }

    if (protectedEvents.isNotEmpty()) {
        report.appendLine("🔒 Protected sequences:")
        report.append(protectedEvents)
        report.appendLine("─────────────────────────────")
    }

    if (gaps.isEmpty() && nsfwEvents.isEmpty() && protectedEvents.isEmpty()) {
        report.appendLine("✅ No issues found.")
    }
// ═══════════════════════════════════════════════
// 4. App usage من UsageStats
// ═══════════════════════════════════════════════
report.appendLine("─────────────────────────────")
report.appendLine("App usage:")

val appUsage = getAppUsageForDate(dateStr)
if (appUsage.isEmpty()) {
    report.appendLine("• No usage data available")
} else {
    val totalMs = appUsage.values.sum()
    if (totalMs > 0) {
        report.appendLine("• Total screen time: ${formatDuration(totalMs)}")
    }
    appUsage.entries
        .sortedByDescending { it.value }
        .take(15)
        .forEach { (pkg, ms) ->
            val appName = try {
                packageManager.getApplicationLabel(
                    packageManager.getApplicationInfo(pkg, 0)
                ).toString()
            } catch (e: Exception) { pkg }
            report.appendLine("• $appName: ${formatDuration(ms)}")
        }
}

return report.toString().trimEnd()
}
    private fun formatDuration(ms: Long): String {
        val totalSeconds = ms / 1000
        val hours   = totalSeconds / 3600
        val minutes = (totalSeconds % 3600) / 60
        val seconds = totalSeconds % 60
        return when {
            hours > 0   -> "${hours}h ${minutes}m"
            minutes > 0 -> "${minutes}m ${seconds}s"
            else        -> "${seconds}s"
        }
    }

    private fun setupCapture() {
        val metrics = resources.displayMetrics

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    
                    if (stopReason != StopReason.USER) {
                        stopReason = StopReason.EXTERNAL
                    }
                    stopSelf()
                }
            }, backgroundHandler)
        }

        val minHeight = MODEL_INPUT_SIZE * 3
        val scale = maxOf(0.5f, minHeight.toFloat() / metrics.heightPixels)
        val captureWidth = (metrics.widthPixels * scale).toInt()
        val captureHeight = (metrics.heightPixels * scale).toInt()

        

        imageReader = ImageReader.newInstance(captureWidth, captureHeight, PixelFormat.RGBA_8888, 2)

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "ScreenCapture",
            captureWidth,
            captureHeight,
            metrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface,
            null,
            backgroundHandler
        )

        
    }

    fun saveFrameAndAnalyze() {
    if (!isScreenOn) {
        writeLogEntry(getForegroundApp(), "SCREEN_OFF - SKIPPED")
        return
    }

    val image = try {
        imageReader?.acquireLatestImage()
    } catch (e: Exception) {
        null
    } ?: run {
        writeLogEntry(getForegroundApp(), "NO_FRAME")
        return
    }

    try {
        val plane = image.planes[0]
        val buffer = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * image.width

        val fullBitmap = Bitmap.createBitmap(
            image.width + rowPadding / pixelStride,
            image.height,
            Bitmap.Config.ARGB_8888
        )
        fullBitmap.copyPixelsFromBuffer(buffer)

        val bitmap = Bitmap.createBitmap(fullBitmap, 0, 0, image.width, image.height)
        fullBitmap.recycle()

        if (isBlackOrProtected(bitmap)) {
            bitmap.recycle()
            writeLogEntry(getForegroundApp(), "PROTECTED")
            consecutiveNsfwCount = 0
            nsfwNotificationSent = false
            return
        }

        val appName = getForegroundApp()
        val analysisResult = analyzeNSFW(bitmap)
        bitmap.recycle()

        writeLogEntry(appName, analysisResult)

        // ── NSFW notification logic ──
        if (analysisResult.startsWith("NSFW")) {
            consecutiveNsfwCount++
            if (consecutiveNsfwCount >= 2 && !nsfwNotificationSent) {
                nsfwNotificationSent = true
                sendNsfwWarningNotification()
            }
        } else {
            consecutiveNsfwCount = 0
            nsfwNotificationSent = false
        }
        // ─────────────────────────────

        MainActivity.sendEvent("result:$appName|$analysisResult")

    } catch (e: Exception) {
        writeLogEntry(getForegroundApp(), "FAILED")
    } finally {
        image.close()
    }
}

private fun sendNsfwWarningNotification() {
    val channelId = "nsfw_alert_channel"
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val chan = NotificationChannel(
            channelId, "NSFW Alerts", NotificationManager.IMPORTANCE_HIGH
        )
        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(chan)
    }

    val isArabic = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    .getString("flutter.app_locale", "en") == "ar"

    // ── غير النص هنا لو عايز ──
    val title = if (isArabic) "تحذير" else "Warning"
    val text  = if (isArabic) "تم رصد محتوى غير لائق" else "NSFW content detected"
    // ──────────────────────────

    val notification = NotificationCompat.Builder(this, channelId)
        .setSmallIcon(android.R.drawable.ic_dialog_alert)
        .setContentTitle(title)
        .setContentText(text)
        .setPriority(NotificationCompat.PRIORITY_HIGH)
        .setAutoCancel(true)
        .build()

    getSystemService(NotificationManager::class.java)?.notify(999, notification)
}

    private fun isBlackOrProtected(bitmap: Bitmap): Boolean {
        val total = bitmap.width * bitmap.height
        var i = 0
        while (i < total) {
            val x = i % bitmap.width
            val y = i / bitmap.width
            val pixel = bitmap.getPixel(x, y)
            val sum = android.graphics.Color.red(pixel) + android.graphics.Color.green(pixel) + android.graphics.Color.blue(pixel)
            if (sum > 0) return false
            i++
        }
        return true
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

    val isArabic = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
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

    private fun analyzeNSFW(originalBitmap: Bitmap): String {
        val interpreter = tfliteInterpreter ?: return "FAILED"

        try {
            val height = originalBitmap.height
            val third = height / 3

            val sections = listOf(
                Bitmap.createBitmap(originalBitmap, 0, 0, originalBitmap.width, third),
                Bitmap.createBitmap(originalBitmap, 0, third, originalBitmap.width, third),
                Bitmap.createBitmap(originalBitmap, 0, third * 2, originalBitmap.width, height - third * 2)
            )

            var maxNSFW = 0f

            for (section in sections) {
                val resized = Bitmap.createScaledBitmap(section, MODEL_INPUT_SIZE, MODEL_INPUT_SIZE, true)
                section.recycle()

                val inputBuffer = bitmapToByteBuffer(resized)
                resized.recycle()

                val output = Array(1) { FloatArray(2) }
                interpreter.run(inputBuffer, output)

                val probNSFW = output[0][1]
                if (probNSFW > maxNSFW) maxNSFW = probNSFW
            }

            return if (maxNSFW >= 0.75f) {
                "NSFW ${String.format("%.1f", maxNSFW * 100)}%"
            } else {
                "NORMAL"
            }

        } catch (e: Exception) {
            
            return "FAILED"
        }
    }

    private fun bitmapToByteBuffer(bitmap: Bitmap): ByteBuffer {
        val byteBuffer = ByteBuffer.allocateDirect(4 * MODEL_INPUT_SIZE * MODEL_INPUT_SIZE * MODEL_INPUT_CHANNELS)
        byteBuffer.order(ByteOrder.nativeOrder())
        val pixels = IntArray(MODEL_INPUT_SIZE * MODEL_INPUT_SIZE)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        for (pixel in pixels) {
            byteBuffer.putFloat(android.graphics.Color.red(pixel).toFloat())
            byteBuffer.putFloat(android.graphics.Color.green(pixel).toFloat())
            byteBuffer.putFloat(android.graphics.Color.blue(pixel).toFloat())
        }
        return byteBuffer
    }

    fun writeLogEntry(appName: String, analysis: String) {
        try {
            val fileFormat = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
            val logFormat = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
            val now = Date()
            val today = fileFormat.format(now)

            val logDir = getLogsDir()
            if (!logDir.exists()) logDir.mkdirs()
            val logFile = File(logDir, "log_${today}.txt")


            if (!logFile.exists() || logFile.length() == 0L) {
                markOldLogsAsComplete()
            }

            val battery = getBatteryLevel()
            logFile.appendText("${logFormat.format(now)} | Battery: $battery% | App: $appName | $analysis\n")
        } catch (e: Exception) {
            
        }
    }

    private fun getBatteryLevel(): Int {
        val bm = getSystemService(BATTERY_SERVICE) as android.os.BatteryManager
        return bm.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
    }

    private fun getForegroundApp(): String {
        val app = tryGetForegroundApp()
        if (app != "Unknown") lastKnownApp = app
        return lastKnownApp
    }

    private fun tryGetForegroundApp(): String {
        return try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
            val time = System.currentTimeMillis()
            val stats = usm.queryUsageStats(android.app.usage.UsageStatsManager.INTERVAL_DAILY, time - 60_000, time)
            stats?.maxByOrNull { it.lastTimeUsed }?.packageName ?: "Unknown"
        } catch (e: Exception) { "Unknown" }
    }

    private fun enqueueUpload() {
     val constraints = Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED)
        .build()
     val request = OneTimeWorkRequestBuilder<UploadReportWorker>()
        .setConstraints(constraints)
        .setBackoffCriteria(
            BackoffPolicy.EXPONENTIAL,
            WorkRequest.MIN_BACKOFF_MILLIS,
            java.util.concurrent.TimeUnit.MILLISECONDS
        )
        .build()
     WorkManager.getInstance(applicationContext)
        .enqueueUniqueWork(
            "upload_reports",
            ExistingWorkPolicy.REPLACE,
            request
        )
    }
    override fun onDestroy() {
        super.onDestroy()
        MainActivity.isServiceRunning = false

        when (stopReason) {
            StopReason.USER       -> writeLogEntry("SYSTEM", "stopped by user from app")
            StopReason.EXTERNAL   -> writeLogEntry("SYSTEM", "stopped by user (recording revoked)")
            StopReason.UNEXPECTED -> writeLogEntry("SYSTEM", "stopped (system kill or force stop)")
            StopReason.LOGOUT -> writeLogEntry("SYSTEM", "stopped by user logout")
        }

        MainActivity.sendEvent("stopped")

        AlarmScheduler.cancel(this)
        try { unregisterReceiver(screenReceiver) } catch (e: Exception) {}
        tfliteInterpreter?.close()
        if (wakeLock?.isHeld == true) wakeLock?.release()
        handlerThread?.quitSafely()
        virtualDisplay?.release()
        imageReader?.close()
        mediaProjection?.stop()

        instance = null
        
    }

    override fun onBind(intent: Intent?) = null
}