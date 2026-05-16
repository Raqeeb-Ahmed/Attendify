import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
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

  // Auto check-in logic
  final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final attDoc = await db.collection('attendance').doc('${uid}_$today').get();
  final hasCheckedIn = attDoc.exists && attDoc.data()?['checkInTime'] != null;

  if (isInside && !hasCheckedIn) {
    // Perform auto check-in — schema matches attendance_service.checkIn()
    await db.collection('attendance').doc('${uid}_$today').set({
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
      'ipAddress': '',
      'insideTime': 0,
      'outsideTime': 0,
      'offlineTime': 0,
      'extraHours': 0,
      'insideOfficeTime': 0,
      'totalHours': 0.0,
      'lastActive': nowIso,
    }, SetOptions(merge: false));

    // Show local notification to inform user
    await _showAutoCheckInNotification(name);
  }
}

bool _isLateCheckIn(DateTime now) {
  final officeStart = DateTime(now.year, now.month, now.day, 9, 45);
  return now.isAfter(officeStart);
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

Future<void> _showAutoCheckInNotification(String name) async {
  final plugin = FlutterLocalNotificationsPlugin();

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));

  const channel = AndroidNotificationDetails(
    'auto_checkin_channel',
    'Auto Check-In',
    channelDescription: 'Notifies when automatic check-in occurs',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );

  await plugin.show(
    1001,
    'Auto Check-In',
    'You have been automatically checked in at the office.',
    const NotificationDetails(android: channel),
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
