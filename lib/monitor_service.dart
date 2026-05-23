import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MonitorService {
  static const _methodChannel = MethodChannel('com.ShehabTeam.strict/channel');
  static const _eventChannel = EventChannel('com.ShehabTeam.strict/events');

  static void Function(String event)? _eventCallback;

  static void init() {
    _initForegroundTask();
    _startListening();
  }

  static void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'monitor_channel',
        channelName: 'Screen Monitor',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static void listenToEvents(void Function(String event) callback) {
    _eventCallback = callback;
  }

  static void _startListening() {
    _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is! String) return;
        _eventCallback?.call(event);   
      },
    );
  }

  static Future<bool> requestBatteryOptimizationExemption() async {
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    return true;
  }


  static Future<void> startCapture() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    await _methodChannel.invokeMethod('startCapture', {'uid': uid});
  }

  static Future<void> stopCapture() async {
    await FlutterForegroundTask.stopService();
    await _methodChannel.invokeMethod('stopCapture');
  }


  static Future<void> stopCaptureByLogout() async {
    await FlutterForegroundTask.stopService();
    await _methodChannel.invokeMethod('stopCaptureByLogout');
  }

  static Future<bool> isServiceRunning() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isServiceRunning') ?? false;
    } catch (_) { return false; }
  }

  static Future<bool> hasUsagePermission() async {
    try {
      return await _methodChannel.invokeMethod<bool>('hasUsagePermission') ?? false;
    } catch (_) { return false; }
  }

  static Future<void> openUsageSettings() async {
    try { await _methodChannel.invokeMethod('openUsageSettings'); } catch (_) {}
  }

  static Future<void> openBatterySettings() async {
    await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
  }

  static Future<bool> openAppLaunchSettings() async {
    try {
      return await _methodChannel.invokeMethod<bool>('openAppLaunchSettings') ?? false;
    } catch (_) { return false; }
  }

  static Future<bool> isLaunchSettingsDone() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isLaunchSettingsDone') ?? false;
    } catch (_) { return false; }
  }

  static Future<void> setLaunchSettingsDone() async {
    try { await _methodChannel.invokeMethod('setLaunchSettingsDone'); } catch (_) {}
  }

  static Future<String?> getCompletedDir() async {
    try {
      return await _methodChannel.invokeMethod<String>('getCompletedDir');
    } catch (_) { return null; }
  }

  static Future<String?> getLogsDir() async {
    try {
      return await _methodChannel.invokeMethod<String>('getLogsDir');
    } catch (_) { return null; }
  }
}