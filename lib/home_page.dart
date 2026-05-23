import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:auto_start_flutter/auto_start_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:strict/watched_users_page.dart';
import 'monitor_service.dart';
import 'profile.dart';
import 'you_watch.dart';
import 'requests.dart';
import 'my_requests.dart';
import 'watch_you.dart';
import 'main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _isMonitoring = false;
  bool _isLoading = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkServiceStatus();
    MonitorService.listenToEvents(_onServiceEvent);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      OneSignal.login(uid);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkServiceStatus();
    }
  }

  void _onServiceEvent(String event) {
    if (!mounted) return;
    if (event == 'started') {
      _pollTimer?.cancel();
      setState(() {
        _isMonitoring = true;
        _isLoading = false;
      });
    } else if (event == 'stopped' || event == 'cancelled') {
      _pollTimer?.cancel();
      setState(() {
        _isMonitoring = false;
        _isLoading = false;
      });
    } else if (event == 'single_app_selected') {
      _pollTimer?.cancel();
      setState(() {
        _isMonitoring = false;
        _isLoading = false;
      });
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('wrong_selection'.tr()),
          content: Text('wrong_selection_content'.tr()),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('ok'.tr()),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _checkServiceStatus() async {
    final running = await MonitorService.isServiceRunning();
    if (!mounted) return;
    setState(() {
      _isMonitoring = running;
      if (!running) _isLoading = false;
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    int attempts = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      attempts++;
      final running = await MonitorService.isServiceRunning();
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (running) {
        timer.cancel();
        setState(() {
          _isMonitoring = true;
          _isLoading = false;
        });
      } else if (attempts >= 15) {
        timer.cancel();
        setState(() {
          _isMonitoring = false;
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _toggleMonitoring() async {
    if (_isLoading) return;

    if (_isMonitoring) {
      setState(() => _isLoading = true);
      await MonitorService.stopCapture();
      if (mounted) {
        setState(() {
          _isMonitoring = false;
          _isLoading = false;
        });
      }
      return;
    }

    if (Platform.isAndroid) {
      final hasUsage = await MonitorService.hasUsagePermission();
      if (!hasUsage) {
        await _showInfoDialog(
          icon: Icons.bar_chart,
          title: 'usage_access'.tr(),
          content: 'usage_access_content'.tr(),
          buttonLabel: 'open_settings'.tr(),
          onButton: () => MonitorService.openUsageSettings(),
        );
        return;
      }
    }

    if (Platform.isAndroid) {
      final notifStatus = await Permission.notification.status;
      if (!notifStatus.isGranted) {
        if (notifStatus.isPermanentlyDenied) {
          await _showInfoDialog(
            icon: Icons.notifications_off,
            title: 'notification_permission'.tr(),
            content: 'notification_required'.tr(),
            buttonLabel: 'open_settings'.tr(),
            onButton: () => openAppSettings(),
          );
          return;
        } else {
          final result = await Permission.notification.request();
          if (!result.isGranted) {
            if (!mounted) return;
            await _showInfoDialog(
              icon: Icons.notifications_off,
              title: 'notification_permission'.tr(),
              content: 'notification_allow'.tr(),
              buttonLabel: 'try_again'.tr(),
              onButton: () => Permission.notification.request(),
            );
            return;
          }
        }
      }
    }

    if (Platform.isAndroid) {
      final isIgnoring =
          await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (!isIgnoring) {
        await _showInfoDialog(
          icon: Icons.battery_charging_full,
          title: 'battery_optimization'.tr(),
          content: 'battery_content'.tr(),
          buttonLabel: 'continue_btn'.tr(),
          onButton: () =>
              FlutterForegroundTask.requestIgnoreBatteryOptimization(),
        );
        return;
      }
    }

    if (Platform.isAndroid) {
      final alreadyDone = await MonitorService.isLaunchSettingsDone();

      if (!alreadyDone) {
        bool? shouldProceed;

        try {
          final isAvailable = await isAutoStartAvailable ?? false;

          if (isAvailable) {
            shouldProceed = await _showAutoStartDialog(
              onOpenSettings: () async {
                await getAutoStartPermission();
                await MonitorService.setLaunchSettingsDone();
              },
            );
          } else {
            final couldOpen = await MonitorService.openAppLaunchSettings();
            if (couldOpen) {
              shouldProceed = await _showAutoStartDialog(
                onOpenSettings: () async {
                  await MonitorService.openAppLaunchSettings();
                  await MonitorService.setLaunchSettingsDone();
                },
              );
            }
          }
        } catch (_) {}

        if (shouldProceed == false) return;
      }
    }

    final confirmed = await _showConfirmDialog();
    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    await MonitorService.startCapture();
    _startPolling();
  }

  Future<bool?> _showAutoStartDialog({
    required Future<void> Function() onOpenSettings,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.play_circle_outline,
          size: 40,
          color: Colors.orange,
        ),
        title: Text('background_launch'.tr(), textAlign: TextAlign.center),
        content: Text('background_launch_content'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('later'.tr()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx, true);
              onOpenSettings();
            },
            child: Text('open_settings'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _showInfoDialog({
    required IconData icon,
    required String title,
    required String content,
    required String buttonLabel,
    required VoidCallback onButton,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon, size: 40, color: Colors.orange),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('later'.tr()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onButton();
            },
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('start_monitoring_title'.tr()),
        content: Text('start_monitoring_content'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('start'.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: Drawer(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              Text(
                'menu'.tr(),
                style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),

              _drawerItem(
                context,
                icon: Icons.remove_red_eye,
                title: 'you_watch'.tr(),
                badgeStream: FirebaseFirestore.instance
                    .collection('monitoring_requests')
                    .where(
                      'fromUserId',
                      isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '',
                    )
                    .where('status', isEqualTo: 'accepted')
                    .where('seenByFrom', isEqualTo: false)
                    .snapshots(),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const YouWatchPage()),
                  );
                },
              ),

              _drawerItem(
                context,
                icon: Icons.shield_outlined,
                title: 'watch_you'.tr(),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WatchYouPage()),
                  );
                },
              ),

              _drawerItem(
                context,
                icon: Icons.move_to_inbox,
                title: 'requests'.tr(),
                badgeStream: FirebaseFirestore.instance
                    .collection('monitoring_requests')
                    .where(
                      'toUserId',
                      isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '',
                    )
                    .where('seenByTo', isEqualTo: false)
                    .snapshots(),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MonitoringRequestsPage(),
                    ),
                  );
                },
              ),

              _drawerItem(
                context,
                icon: Icons.send,
                title: 'my_requests'.tr(),
                badgeStream: FirebaseFirestore.instance
                    .collection('monitoring_requests')
                    .where(
                      'fromUserId',
                      isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '',
                    )
                    .where('status', isEqualTo: 'rejected')
                    .where('seenByFrom', isEqualTo: false)
                    .snapshots(),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MyMonitoringRequestsPage(),
                    ),
                  );
                },
              ),

              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: GestureDetector(
                  onTap: _isLoading ? null : _toggleMonitoring,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _isLoading
                          ? Colors.grey
                          : (_isMonitoring ? Colors.redAccent : Colors.green),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: (_isMonitoring ? Colors.red : Colors.green)
                              // ignore: deprecated_member_use
                              .withOpacity(0.4),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isLoading)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        else
                          Icon(
                            _isMonitoring ? Icons.stop : Icons.play_arrow,
                            color: Colors.white,
                          ),
                        const SizedBox(width: 10),
                        Text(
                          _isLoading
                              ? 'starting'.tr()
                              : (_isMonitoring
                                    ? 'stop_monitoring'.tr()
                                    : 'start_monitoring'.tr()),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _isMonitoring ? 'service_running'.tr() : 'service_idle'.tr(),
                  style: TextStyle(
                    color: _isMonitoring ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),

              _languageSwitch(context),
              _themeSwitch(context),
            ],
          ),
        ),
      ),

      appBar: AppBar(
        elevation: 0,
        leadingWidth: 96,
        leading: Row(
          children: [
            Builder(
              builder: (ctx) => StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('monitoring_requests')
                    .where(
                      'toUserId',
                      isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '',
                    )
                    .where('seenByTo', isEqualTo: false)
                    .snapshots(),
                builder: (context, incomingSnap) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('monitoring_requests')
                        .where(
                          'fromUserId',
                          isEqualTo:
                              FirebaseAuth.instance.currentUser?.uid ?? '',
                        )
                        .where('status', isEqualTo: 'accepted')
                        .where('seenByFrom', isEqualTo: false)
                        .snapshots(),
                    builder: (context, acceptedSnap) {
                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('monitoring_requests')
                            .where(
                              'fromUserId',
                              isEqualTo:
                                  FirebaseAuth.instance.currentUser?.uid ?? '',
                            )
                            .where('status', isEqualTo: 'rejected')
                            .where('seenByFrom', isEqualTo: false)
                            .snapshots(),
                        builder: (context, rejectedSnap) {
                          final total =
                              (incomingSnap.data?.docs.length ?? 0) +
                              (acceptedSnap.data?.docs.length ?? 0) +
                              (rejectedSnap.data?.docs.length ?? 0);

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.menu, size: 27),
                                onPressed: () => Scaffold.of(ctx).openDrawer(),
                              ),
                              if (total > 0)
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    child: Text(
                                      '$total',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            IconButton(
              icon: Stack(
                children: [
                  Icon(
                    Icons.remove_red_eye,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 24,
                  ),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Icon(Icons.add, color: Colors.green, size: 18),
                  ),
                ],
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchUserPage()),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser?.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final avatarIndex = snapshot.data?.get('avatarIndex') ?? 2;
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProfilePage()),
                    );
                  },
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage: AssetImage(
                      'assets/images/profile/$avatarIndex.jpg',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),

      body: const WatchedUsersPage(),
    );
  }

  Widget _languageSwitch(BuildContext context) {
    final isEnglish = context.locale.languageCode == 'en';

    return ListTile(
      leading: const Icon(Icons.language),
      title: Text('language'.tr()),
      trailing: SizedBox(
        width: 90,
        height: 36,
        child: Stack(
          children: [
            // Background container
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),

            // Animated indicator
            AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: isEnglish
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Container(
                width: 45,
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),

            // AR / EN buttons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      context.setLocale(const Locale('ar'));
                      SharedPreferences.getInstance().then(
                        (p) => p.setString('app_locale', 'ar'),
                      );
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(FirebaseAuth.instance.currentUser?.uid)
                          .update({'appLocale': 'ar'});
                    },
                    child: Center(
                      child: Text(
                        'AR',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: !isEnglish ? Colors.white : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      context.setLocale(const Locale('en'));
                      SharedPreferences.getInstance().then(
                        (p) => p.setString('app_locale', 'en'),
                      );
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(FirebaseAuth.instance.currentUser?.uid)
                          .update({'appLocale': 'en'});
                    },
                    child: Center(
                      child: Text(
                        'EN',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isEnglish ? Colors.white : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // وأضف الدالة دي
  Widget _themeSwitch(BuildContext context) {
    final appState = MyApp.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
      title: Text('theme'.tr()),
      trailing: SizedBox(
        width: 90,
        height: 36,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: isDark ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                width: 45,
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => appState?.setThemeMode(ThemeMode.dark),
                    child: Center(
                      child: Icon(
                        Icons.dark_mode,
                        size: 16,
                        color: isDark ? Colors.white : Colors.grey,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => appState?.setThemeMode(ThemeMode.light),
                    child: Center(
                      child: Icon(
                        Icons.light_mode,
                        size: 16,
                        color: !isDark ? Colors.white : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    VoidCallback? onTap,
    Stream<QuerySnapshot>? badgeStream,
  }) {
    return ListTile(
      leading: badgeStream != null ? _badgeIcon(icon, badgeStream) : Icon(icon),
      title: Text(title),
      onTap: onTap,
    );
  }

  // ── helper عشان يعمل badge ──
  Widget _badgeIcon(IconData icon, Stream<QuerySnapshot> countStream) {
    return StreamBuilder<QuerySnapshot>(
      stream: countStream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon),
            if (count > 0)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
