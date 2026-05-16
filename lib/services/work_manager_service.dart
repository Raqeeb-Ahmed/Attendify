import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../utils/app_config.dart';

const String _locationTaskName = 'com.attendo.locationUpdate';
const String _heartbeatTaskName = 'com.attendo.heartbeat';

/// Top-level callback required by WorkManager - must be a static/global function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      await Firebase.initializeApp();
      final uid = inputData?['uid'] as String?;
      final name = inputData?['name'] as String?;
      final email = inputData?['email'] as String?;
      final department = inputData?['department'] as String?;

      if (uid == null || name == null || email == null) return true;

      switch (taskName) {
        case _locationTaskName:
          await _runLocationUpdate(uid, name, email, department);
          break;
        case _heartbeatTaskName:
          await _runHeartbeat(uid, name, email);
          break;
      }
    } catch (e) {
      debugPrint('[WorkManager] Task error: $e');
    }
    return true;
  });
}

Future<void> _runHeartbeat(String uid, String name, String email) async {
  final db = FirebaseFirestore.instance;
  await db.collection('heartbeats').doc(uid).set({
    'userId': uid,
    'userName': name,
    'email': email,
    'lastSeen': DateTime.now().toIso8601String(),
    'online': true,
  }, SetOptions(merge: true));
}

Future<void> _runLocationUpdate(
    String uid, String name, String email, String? department) async {
  final db = FirebaseFirestore.instance;
  final now = DateTime.now();
  final nowIso = now.toIso8601String();

  // Update heartbeat
  await db.collection('heartbeats').doc(uid).set({
    'userId': uid,
    'userName': name,
    'email': email,
    'lastSeen': nowIso,
    'online': true,
  }, SetOptions(merge: true));

  // Get location - REQUIRES "Always" permission for background tracking
  bool locationGranted = false;
  try {
    final permission = await Geolocator.checkPermission();
    // Only accept "Always" permission - "While in use" is insufficient for background
    locationGranted = permission == LocationPermission.always;
  } catch (_) {}

  if (!locationGranted) {
    debugPrint('[WorkManager] Location permission is not "Always". Skipping location update.');
    return;
  }

  Position position;
  try {
    position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
  } catch (_) {
    return;
  }

  final distance = _haversine(
    position.latitude,
    position.longitude,
    AppConfig.officeLat,
    AppConfig.officeLng,
  );
  final isInside = distance <= 100;
  final status = isInside ? 'present' : 'outside';

  // Update live location
  await db.collection('locations').doc('${uid}_latest').set({
    'userId': uid,
    'userName': name,
    'email': email,
    'lat': position.latitude,
    'lng': position.longitude,
    'timestamp': nowIso,
    'status': status,
    'insideRadius': isInside,
    'distanceFromOffice': distance.round(),
  });

  // Auto check-in logic - Check via GPS
  final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final attendanceId = '${uid}_$today';
  final attRef = db.collection('attendance').doc(attendanceId);

  // Also check via WiFi (redundant detection for reliability)
  bool isWifiCheckIn = false;

  // Use Firestore transaction for atomic check-in (prevents race conditions)
  bool didCheckIn = false;
  try {
    didCheckIn = await db.runTransaction((transaction) async {
      final attDoc = await transaction.get(attRef);
      final hasCheckedIn = attDoc.exists && (attDoc.data()?['checkInTime'] != null);

      if (hasCheckedIn) {
        debugPrint('[WorkManager] Already checked in today (transaction)');
        return false; // Already checked in, abort
      }

      // Check WiFi if not already checked in
      if (!isInside) {
        isWifiCheckIn = await _checkWifiAndAutoCheckIn(uid, name, email, department, now, nowIso);
      }

      // Determine if we should check in
      final shouldCheckIn = isInside || isWifiCheckIn;
      if (!shouldCheckIn) {
        return false; // Not at office, abort
      }

      // Atomic write - this will fail if another process writes first
      transaction.set(attRef, {
      'userId': uid,
      'userName': name,
      'email': email,
      'department': department ?? '',
      'date': today,
      'checkInTime': nowIso,
      'checkOutTime': null,
      'location': {
        'lat': position.latitude,
        'lng': position.longitude,
        'distanceFromOffice': distance.round(),
      },
      'atOffice': true,
      'status': _isLateCheckIn(now) ? 'late' : 'present',
      'sessionStatus': 'active',
      'autoCheckedIn': true,
      'checkInMethod': isWifiCheckIn ? 'wifi_workmanager' : 'geofence_workmanager',
      'ipAddress': '',
      'insideTime': 0,
      'outsideTime': 0,
      'offlineTime': 0,
      'extraHours': 0,
      'insideOfficeTime': 0,
      'totalHours': 0.0,
      'lastActive': nowIso,
    });

      return true; // Successfully checked in
    });
  } catch (e) {
    debugPrint('[WorkManager] Transaction failed (likely race condition): $e');
    didCheckIn = false;
  }

  if (didCheckIn) {
    // Show local notification to inform user
    await _showAutoCheckInNotification(name);
    debugPrint('[WorkManager] ✅ Auto check-in successful via ${isWifiCheckIn ? 'WiFi' : 'GPS'}');
  } else {
    // Update time tracking for existing session (even if not checked in via WorkManager)
    // This handles the case when app is killed but WorkManager still runs
    await _updateTimeTrackingForExistingSession(uid, name, email, isInside, now, nowIso, attRef);
  }
}

/// Update time tracking for existing checked-in session
/// Called when WorkManager runs but user is already checked in
Future<void> _updateTimeTrackingForExistingSession(
  String uid,
  String name,
  String email,
  bool isInside,
  DateTime now,
  String nowIso,
  DocumentReference<Map<String, dynamic>> attRef,
) async {
  try {
    final attDoc = await attRef.get();
    if (!attDoc.exists) return;

    final attData = attDoc.data()!;
    if (attData['checkOutTime'] != null || attData['sessionStatus'] != 'active') return;

    final updates = <String, dynamic>{};
    final lastActive = attData['lastActive'];

    if (lastActive != null) {
      final lastDate = DateTime.parse(lastActive);
      final diffMins = now.difference(lastDate).inMinutes;

      // WorkManager runs every 15 min, so diffMins will typically be ~15
      // Track this as offline time since we don't know where user was during this gap
      if (diffMins >= 15) {
        updates['offlineTime'] = (attData['offlineTime'] ?? 0) + diffMins;
        debugPrint('[WorkManager] Added $diffMins mins as offline time (app was killed)');
      }
    }

    // Update current status and lastActive
    updates['currentStatus'] = isInside ? 'present' : 'outside';
    updates['atOffice'] = isInside;
    updates['lastLocationUpdate'] = nowIso;
    updates['lastActive'] = nowIso;
    updates['totalHours'] = _computeTotalHours(attData['checkInTime'], nowIso);

    await attRef.update(updates);
    debugPrint('[WorkManager] Updated time tracking for existing session');
  } catch (e) {
    debugPrint('[WorkManager] Error updating time tracking: $e');
  }
}

bool _isLateCheckIn(DateTime now) {
  final officeStart = DateTime(now.year, now.month, now.day, 9, 45);
  return now.isAfter(officeStart);
}

/// Check WiFi and perform auto check-in if on office WiFi
/// Returns true if WiFi-based auto check-in was performed
Future<bool> _checkWifiAndAutoCheckIn(
  String uid,
  String name,
  String email,
  String? department,
  DateTime now,
  String nowIso,
) async {
  try {
    final networkInfo = NetworkInfo();
    final wifiName = await networkInfo.getWifiName();
    final bssid = await networkInfo.getWifiBSSID();

    debugPrint('[WorkManager] WiFi check: $wifiName (BSSID: $bssid)');

    if (wifiName == null) {
      debugPrint('[WorkManager] WiFi name is null (location permission required on Android 10+)');
      return false;
    }

    // Remove quotes and clean WiFi name
    final cleanName = wifiName.replaceAll('"', '').toLowerCase().trim();

    debugPrint('[WorkManager] Checking WiFi "$cleanName" against office list');

    // Check against configured office WiFi names
    for (final officeName in AppConfig.officeWifiNames) {
      final cleanOfficeName = officeName.toLowerCase().trim();

      if (cleanName.contains(cleanOfficeName) || cleanName == cleanOfficeName) {
        debugPrint('[WorkManager] 🎯 Office WiFi detected: $wifiName');
        return true; // Signal that we should auto check-in
      }
    }

    debugPrint('[WorkManager] WiFi "$cleanName" does not match office networks');
    return false;
  } on PlatformException catch (e) {
    // network_info_plus throws PlatformException when permission denied
    debugPrint('[WorkManager] WiFi permission denied or unavailable: $e');
    return false;
  } catch (e) {
    debugPrint('[WorkManager] WiFi check error: $e');
    return false;
  }
}

double _haversine(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371e3;
  final dLat = (lat2 - lat1) * (pi / 180);
  final dLon = (lon2 - lon1) * (pi / 180);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) * sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
}

double _computeTotalHours(String? checkInIso, String? checkOutIso) {
  if (checkInIso == null || checkOutIso == null) return 0.0;
  final diffMs = DateTime.parse(checkOutIso).difference(DateTime.parse(checkInIso)).inMilliseconds;
  return double.parse((diffMs / (1000 * 60 * 60)).toStringAsFixed(2));
}

Future<void> _showAutoCheckInNotification(String name) async {
  final plugin = FlutterLocalNotificationsPlugin();

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(
    const InitializationSettings(android: androidInit),
    onDidReceiveNotificationResponse: null,
  );

  // Create notification channel (required for Android 8+)
  const channel = AndroidNotificationChannel(
    'auto_checkin_channel',
    'Auto Check-In',
    description: 'Notifies when automatic check-in occurs',
    importance: Importance.high,
  );
  await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  const notificationDetails = AndroidNotificationDetails(
    'auto_checkin_channel',
    'Auto Check-In',
    channelDescription: 'Notifies when automatic check-in occurs',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
    ongoing: false,
    autoCancel: true,
  );

  await plugin.show(
    1001,
    'Auto Check-In',
    'You have been automatically checked in at the office.',
    const NotificationDetails(android: notificationDetails),
  );
}

/// WorkManager registration service
class WorkManagerService {
  static bool _initialized = false;

  /// Call once from main() before runApp
  static Future<void> initialize() async {
    if (_initialized) return;
    await Workmanager().initialize(callbackDispatcher);
    _initialized = true;
  }

  /// Register periodic location tracking (every 15 min — Android minimum)
  static Future<void> registerLocationTask({
    required String uid,
    required String name,
    required String email,
    String? department,
  }) async {
    await Workmanager().registerPeriodicTask(
      _locationTaskName,
      _locationTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      inputData: {
        'uid': uid,
        'name': name,
        'email': email,
        'department': department ?? '',
      },
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  /// Register a one-off heartbeat task (for immediate execution)
  static Future<void> triggerHeartbeat({
    required String uid,
    required String name,
    required String email,
  }) async {
    await Workmanager().registerOneOffTask(
      '${_heartbeatTaskName}_${DateTime.now().millisecondsSinceEpoch}',
      _heartbeatTaskName,
      inputData: {'uid': uid, 'name': name, 'email': email},
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  /// Cancel all registered tasks (call on logout)
  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}
