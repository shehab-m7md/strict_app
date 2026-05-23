package com.ShehabTeam.strict

import android.content.Context
import android.util.Log
import androidx.work.*
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.tasks.await
import java.io.File
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody

class UploadReportWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    private val prefs = applicationContext
        .getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
    private val db   = FirebaseFirestore.getInstance()
    private val auth = FirebaseAuth.getInstance()

    override suspend fun doWork(): Result {
        return try {
            val uid = prefs.getString("current_uid", null) ?: return Result.retry()

            val reportedDir = File(applicationContext.filesDir, "logs/$uid/Reported")
            if (!reportedDir.exists()) return Result.success()

            val files = reportedDir.listFiles()
                ?.filter  { it.isFile && it.name.startsWith("log_") }
                ?.sortedBy { it.name }
                ?: return Result.success()

            if (files.isEmpty()) return Result.success()

            for (file in files) {
                val date = file.name.removePrefix("log_").removeSuffix(".txt")
                if (prefs.getString("report_flag_$date", "pending") == "sent") continue
                val result = processFile(file, date)
                if (result is Result.Retry) return Result.retry()
            }

            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }

    private suspend fun processFile(file: File, date: String): Result {
        val flagKey     = "report_flag_$date"
        val urlKey      = "report_logfile_id_$date"
        val watchersKey = "report_watchers_done_$date"

        val reportText = extractReportText(file) ?: run {
            markSent(flagKey, urlKey, watchersKey, file)
            return Result.success()
        }

        val targetUid = auth.currentUser?.uid
            ?: prefs.getString("current_uid", null)
            ?: return Result.retry()

        val targetCustomId = getCustomId(targetUid) ?: return Result.retry()

        // ── Log file ID ثابت = targetCustomId_date ──
        val logDocId = "${targetCustomId}_$date"
        var logFileId = prefs.getString(urlKey, null)

        if (logFileId == null) {
            logFileId = uploadLogFile(file, targetUid, date, logDocId)
                ?: return Result.retry()

            prefs.edit()
                .putString(urlKey,  logFileId)
                .putString(flagKey, "pending_storage_done")
                .apply()
        }

        val watchers = getWatchers(targetUid)

        if (watchers.isEmpty()) {
            markSent(flagKey, urlKey, watchersKey, file)
            return Result.success()
        }

        val doneWatchers = prefs.getString(watchersKey, "")
            ?.split(",")
            ?.filter  { it.isNotEmpty() }
            ?.toMutableSet()
            ?: mutableSetOf()

        for (watcherId in watchers) {
            if (doneWatchers.contains(watcherId)) continue

            val success = writeReport(
                watcherId      = watcherId,
                targetCustomId = targetCustomId,
                reportText     = reportText,
                logFileId      = logFileId,
                date           = date
            )

            if (!success) {
                prefs.edit()
                    .putString(watchersKey, doneWatchers.joinToString(","))
                    .apply()
                return Result.retry()
            }

            doneWatchers.add(watcherId)
        }

        markSent(flagKey, urlKey, watchersKey, file)
        return Result.success()
    }

    private suspend fun uploadLogFile(
        file: File,
        targetUid: String,
        date: String,
        docId: String
    ): String? {
        return try {
            val docRef = db.collection("log_files").document(docId)

            // ── check قبل الرفع ──
            val existing = docRef.get().await()
            if (existing.exists()) return docId

            docRef.set(mapOf(
                "content"    to file.readText(),
                "uploadedBy" to targetUid,
                "date"       to date,
                "createdAt"  to FieldValue.serverTimestamp()
            )).await()
            docId
        } catch (e: Exception) {
            null
        }
    }

    private suspend fun writeReport(
        watcherId: String,
        targetCustomId: String,
        reportText: String,
        logFileId: String,
        date: String
    ): Boolean {
        return try {
            val docId = "${targetCustomId}_$date"
            val docRef = db.collection("users")
                .document(watcherId)
                .collection("reports")
                .document(docId)

            // ── check قبل الرفع ──
            val existing = docRef.get().await()
            if (existing.exists()) return true

            docRef.set(mapOf(
                "targetCustomId" to targetCustomId,
                "reportText"     to reportText,
                "logFileId"      to logFileId,
                "reportDate"     to date,
                "createdAt"      to FieldValue.serverTimestamp()
            )).await()
            true
        } catch (e: Exception) {
            Log.e("UPLOAD", "writeReport error: ${e.message}")
            false
        }.also {
            if (it) {
                try { sendNotificationToWatcher(watcherId, targetCustomId) } catch (e: Exception) {}
            }
        }
    }

    private fun sendNotificationToWatcher(watcherId: String, targetCustomId: String) {
        try {
            val client = okhttp3.OkHttpClient()
            val jsonBody = org.json.JSONObject().apply {
                put("app_id", "5580a780-3024-4e2c-b3fe-3206be81c4fe")
                put("include_aliases", org.json.JSONObject().apply {
                    put("external_id", org.json.JSONArray().apply { put(watcherId) })
                })
                put("target_channel", "push")
                put("headings", org.json.JSONObject().apply {
                    put("en", "New Report Ready")
                    put("ar", "تقرير جديد متاح")
                })
                put("contents", org.json.JSONObject().apply {
                    put("en", "A new monitoring report for $targetCustomId is available")
                    put("ar", "يوجد تقرير مراقبة جديد لـ $targetCustomId")
                })
            }

            val request = okhttp3.Request.Builder()
                .url("https://onesignal.com/api/v1/notifications")
                .post(jsonBody.toString().toRequestBody("application/json".toMediaType()))
                .addHeader("Authorization", "Basic os_v2_app_kwakpabqerhczm76gidl5aoe734h5svggy5uzevvchxj2md7a5gjwovttl6sypjisjonbu3evpvhjcajzmga4wfs2rj52ngnjdjm6gi")
                .addHeader("Content-Type", "application/json")
                .build()

            client.newCall(request).execute()
        } catch (e: Exception) {
            Log.e("NOTIFY", "❌ Error: ${e.message}")
        }
    }

    private suspend fun getWatchers(targetUid: String): List<String> {
        return try {
            db.collection("monitoring_relations")
                .whereEqualTo("toUserId", targetUid)
                .get().await()
                .documents
                .mapNotNull { it.getString("fromUserId") }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private suspend fun getCustomId(uid: String): String? {
        return try {
            db.collection("users")
                .document(uid)
                .get().await()
                .getString("customId")
        } catch (e: Exception) {
            null
        }
    }

    private fun extractReportText(file: File): String? {
        return try {
            val content = file.readText()
            val parts   = content.split("===")
            if (parts.size >= 3) parts[1].trim() else null
        } catch (e: Exception) {
            null
        }
    }

    private fun markSent(
        flagKey: String,
        urlKey: String,
        watchersKey: String,
        file: File
    ) {
        prefs.edit()
            .putString(flagKey, "sent")
            .remove(urlKey)
            .remove(watchersKey)
            .apply()
        file.delete()
    }
}