import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../utils/app_config.dart';

// ─── Top-level entry point (required — must be a top-level function) ─────────

@pragma('vm:entry-point')
void startForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_LocationTaskHandler());
}

// ─── Task handler ─────────────────────────────────────────────────────────────

class _LocationTaskHandler extends TaskHandler {
  static const int _radiusMeters = 100;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ForegroundTask] Started');
    await _runUpdate();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _runUpdate();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ForegroundTask] Destroyed (timeout=$isTimeout)');
  }

  Future<void> _runUpdate() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final uid = await FlutterForegroundTask.getData<String>(key: 'uid');
      if (uid == null || uid.isEmpty) return;

      final name = await FlutterForegroundTask.getData<String>(key: 'name') ?? '';
      final email = await FlutterForegroundTask.getData<String>(key: 'email') ?? '';

      final db = FirebaseFirestore.instance;
      final now = DateTime.now();
      final nowIso = now.toIso8601String();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Heartbeat
      await db.collection('heartbeats').doc(uid).set({
        'userId': uid,
        'userName': name,
        'email': email,
        'lastSeen': nowIso,
        'online': true,
      }, SetOptions(merge: true));

      // Location permission check - REQUIRES "Always" for background tracking
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always) {
        debugPrint('[ForegroundTask] Location permission is not "Always". Skipping update.');
        return;
      }

      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } catch (_) {
        return;
      }

      final distance = _haversine(
        position.latitude, position.longitude,
        AppConfig.officeLat, AppConfig.officeLng,
      );
      final isInside = distance <= _radiusMeters;
      final status = isInside ? 'present' : 'outside';

      final locationData = {
        'userId': uid,
        'userName': name,
        'email': email,
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': nowIso,
        'status': status,
        'insideRadius': isInside,
        'distanceFromOffice': distance.round(),
      };

      // Overwrite latest doc (admin live view reads this)
      await db.collection('locations').doc('${uid}_latest').set(locationData);

      // Append to history (admin timeline reads this)
      await db.collection('locations').add(locationData);

      // Update today's attendance with current status
      final attDoc = await db.collection('attendance').doc('${uid}_$today').get();
      if (attDoc.exists &&
          attDoc.data()?['checkInTime'] != null &&
          attDoc.data()?['checkOutTime'] == null) {
        await db.collection('attendance').doc('${uid}_$today').update({
          'currentStatus': status,
          'lastLocationUpdate': nowIso,
          'atOffice': isInside,
        });
      }

      // Update notification text with neutral wording
      final notifText = isInside ? 'You are at the office' : 'You are away';
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Work session active',
        notificationText: notifText,
      );

      debugPrint('[ForegroundTask] $status (${distance.round()}m)');
    } catch (e) {
      debugPrint('[ForegroundTask] Error: $e');
    }
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371e3;
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLon = (lon2 - lon1) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}

// ─── Public service API ───────────────────────────────────────────────────────

class ForegroundTrackingService {
  /// Call once from main() before runApp
  static void initialize() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'attendance_session',
        channelName: 'Attendance',
        channelDescription: 'Keeps your work session active',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        showBadge: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // repeat every 60 000 ms = 60 seconds
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Request battery optimization exemption (shows system dialog like WhatsApp)
  static Future<void> requestBatteryExemption() async {
    try {
      final isIgnoring = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (!isIgnoring) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (e) {
      debugPrint('[ForegroundTrackingService] Battery exemption request failed: $e');
    }
  }

  /// Request notification permission (Android 13+)
  static Future<void> requestPermissions() async {
    try {
      await FlutterForegroundTask.requestNotificationPermission();
    } catch (e) {
      debugPrint('[ForegroundTrackingService] Notification permission request failed: $e');
    }
  }

  /// Start the foreground tracking service
  static Future<void> start({
    required String uid,
    required String name,
    required String email,
    String? department,
  }) async {
    // Save user data — readable by the task handler isolate via SharedPreferences
    await FlutterForegroundTask.saveData(key: 'uid', value: uid);
    await FlutterForegroundTask.saveData(key: 'name', value: name);
    await FlutterForegroundTask.saveData(key: 'email', value: email);
    await FlutterForegroundTask.saveData(key: 'department', value: department ?? '');

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      await FlutterForegroundTask.restartService();
      debugPrint('[ForegroundTrackingService] Restarted for $name');
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: 1001,
      notificationTitle: 'Work session active',
      notificationText: 'Attendance enabled',
      callback: startForegroundTaskCallback,
    );
    debugPrint('[ForegroundTrackingService] Started for $name');
  }

  /// Stop the foreground tracking service
  static Future<void> stop() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      await FlutterForegroundTask.stopService();
      debugPrint('[ForegroundTrackingService] Stopped');
    }
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;
}
