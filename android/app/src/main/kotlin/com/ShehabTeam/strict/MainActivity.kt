package com.ShehabTeam.strict

import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        var savedResultCode: Int = Activity.RESULT_CANCELED
        var savedData: Intent? = null
        var eventSink: EventChannel.EventSink? = null
        var isServiceRunning: Boolean = false
        var savedUid: String = "unknown"  // ─── جديد ───

        fun sendEvent(event: String) {
            val sink = eventSink ?: run {
                
                return
            }
            Handler(Looper.getMainLooper()).post { sink.success(event) }
        }
    }

    private val CHANNEL = "com.ShehabTeam.strict/channel"
    private val EVENT_CHANNEL = "com.ShehabTeam.strict/events"
    private val PREFS_NAME = "app_prefs"
    private val KEY_LAUNCH_DONE = "launch_settings_done"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "startCapture" -> {

                        savedUid = call.argument<String>("uid") ?: "unknown"
                        

                        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val config = android.media.projection.MediaProjectionConfig.createConfigForDefaultDisplay()
                            startActivityForResult(manager.createScreenCaptureIntent(config), 1001)
                        } else {
                            startActivityForResult(manager.createScreenCaptureIntent(), 1001)
                        }
                        result.success("pending")
                    }

                    "stopCapture" -> {
                        CaptureService.stopByUser()
                        savedResultCode = Activity.RESULT_CANCELED
                        savedData = null
                        isServiceRunning = false
                        result.success("stopped")
                    }


                    "stopCaptureByLogout" -> {
                        CaptureService.stopByLogout()
                        savedResultCode = Activity.RESULT_CANCELED
                        savedData = null
                        isServiceRunning = false
                        savedUid = "unknown"
                        result.success("stopped")
                    }

                    "isServiceRunning" -> result.success(isServiceRunning)

                    "getBattery" -> {
                        val bm = getSystemService(BATTERY_SERVICE) as BatteryManager
                        result.success(bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY))
                    }

                    "getForegroundApp" -> result.success(getForegroundApp())

                    "getLogsDir" -> {
                        val logsDir = java.io.File(filesDir, "logs/$savedUid")
                        if (!logsDir.exists()) logsDir.mkdirs()
                        result.success(logsDir.absolutePath)
                    }

                    "hasUsagePermission" -> {
                        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
                        val mode = appOps.checkOpNoThrow(
                            AppOpsManager.OPSTR_GET_USAGE_STATS,
                            Process.myUid(), packageName
                        )
                        result.success(mode == AppOpsManager.MODE_ALLOWED)
                    }

                    "openUsageSettings" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(null)
                    }

                    "openAppLaunchSettings" -> {
                        result.success(openAppLaunchSettings())
                    }

                    "isLaunchSettingsDone" -> {
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        result.success(prefs.getBoolean(KEY_LAUNCH_DONE, false))
                    }

                    "setLaunchSettingsDone" -> {
                        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                            .edit().putBoolean(KEY_LAUNCH_DONE, true).apply()
                        result.success(null)
                    }

                    "getCompletedDir" -> {
                        val completedDir = java.io.File(filesDir, "logs/$savedUid/Completed")
                        if (!completedDir.exists()) completedDir.mkdirs()
                        result.success(completedDir.absolutePath)
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    private fun openAppLaunchSettings(): Boolean {
        val intentsToTry = listOf(
            Intent("com.huawei.systemmanager.startupmgr.ui.StartupAppDetailActivity").apply {
                putExtra("package_name", packageName)
            },
            Intent("com.hihonor.systemmanager.startupmgr.ui.StartupAppDetailActivity").apply {
                putExtra("package_name", packageName)
            },
            Intent("com.huawei.systemmanager.power.ui.HwPowerUsageDetailActivity").apply {
                putExtra("package_name", packageName)
            },
            Intent("com.hihonor.systemmanager.power.ui.HwPowerUsageDetailActivity").apply {
                putExtra("package_name", packageName)
            },
            Intent().apply {
                setClassName("com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")
            },
            Intent().apply {
                setClassName("com.hihonor.systemmanager",
                    "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity")
            },
            Intent().apply {
                setClassName("com.samsung.android.lool",
                    "com.samsung.android.sm.battery.ui.BatteryActivity")
            },
            Intent().apply {
                setClassName("com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity")
            },
            Intent().apply {
                setClassName("com.coloros.safecenter",
                    "com.coloros.privacypermissionsentry.PermissionTopActivity")
            },
            Intent().apply {
                setClassName("com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")
            },
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
            }
        )

        for (intent in intentsToTry) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                
                return true
            } catch (e: Exception) {
                
            }
        }
        return false
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 1001) return

        

        if (resultCode != Activity.RESULT_OK || data == null) {
            
            sendEvent("cancelled")
            return
        }

        savedResultCode = resultCode
        savedData = data

        try {

            val intent = Intent(applicationContext, CaptureService::class.java).apply {
                putExtra("uid", savedUid)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            isServiceRunning = true
            sendEvent("started")
            
        } catch (e: Exception) {
            
            sendEvent("cancelled")
        }
    }

    private fun getForegroundApp(): String {
        return try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val time = System.currentTimeMillis()
            val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, time - 60_000, time)
            stats?.maxByOrNull { it.lastTimeUsed }?.packageName ?: "Unknown"
        } catch (e: Exception) { "Unknown" }
    }
}