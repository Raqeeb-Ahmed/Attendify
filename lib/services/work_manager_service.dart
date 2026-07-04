import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:http/http.dart' as http;
import '../utils/app_config.dart';
import 'offline_location_service.dart';
import 'attendance_service.dart';

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

  // Get location - Accept "Always" or "While in use" for background tracking
  bool locationGranted = false;
  try {
    final permission = await Geolocator.checkPermission();
    // Accept both "Always" and "While in use" permissions
    locationGranted = permission == LocationPermission.always || 
                    permission == LocationPermission.whileInUse;
    
    if (!locationGranted) {
      debugPrint('[WorkManager] Location permission denied. Current: $permission');
      return;
    }
  } catch (e) {
    debugPrint('[WorkManager] Error checking location permission: $e');
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

  final Map<String, dynamic> locationData = {
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

  // Check internet connectivity
  bool isOnline = false;
  try {
    final response = await http
        .get(Uri.parse('https://www.google.com'))
        .timeout(const Duration(seconds: 5));
    isOnline = response.statusCode == 200;
  } catch (_) {
    isOnline = false;
  }

  if (!isOnline) {
    debugPrint('[WorkManager] Device offline - Caching location locally');
    await OfflineLocationService().cacheLocation(locationData);
    return;
  }

  // Online: Sync any cached offline locations first
  await OfflineLocationService().syncCachedLocations(uid);

  // Update heartbeat
  await db.collection('heartbeats').doc(uid).set({
    'userId': uid,
    'userName': name,
    'email': email,
    'lastSeen': nowIso,
    'online': true,
  }, SetOptions(merge: true));

  // Update live location
  await db.collection('locations').doc('${uid}_latest').set(locationData);

  // Add to locations log history
  await db.collection('locations').add(locationData);

  // Auto check-in logic - Check via GPS
  final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final attendanceId = '${uid}_$today';
  final attRef = db.collection('attendance').doc(attendanceId);

  // Check WiFi only if inside office geofence
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

      // Check WiFi if inside
      if (isInside) {
        isWifiCheckIn = await _checkWifiAndAutoCheckIn(uid, name, email, department, now, nowIso);
      }

      // Determine if we should check in - strict WiFi + GPS AND logic
      final shouldCheckIn = isInside && isWifiCheckIn;
      if (!shouldCheckIn) {
        return false; // Not at office or not connected to WiFi, abort
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
        'checkInMethod': 'wifi_gps_workmanager',
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
    debugPrint('[WorkManager] ✅ Auto check-in successful via WiFi & GPS');
  } else {
    // ── Auto-checkout at 6:00 PM ──────────────────────────────────────────
    final attDoc = await attRef.get();
    if (attDoc.exists && attDoc.data()?['checkInTime'] != null) {
      final attData = attDoc.data()!;
      final alreadyCheckedOut = attData['checkOutTime'] != null;
      final autoCheckoutTime = DateTime(now.year, now.month, now.day, 18, 0);

      if (!alreadyCheckedOut && now.isAfter(autoCheckoutTime)) {
        final totalHours = _computeTotalHoursLocal(attData['checkInTime'], nowIso);
        final insideOfficeMs = (attData['insideTime'] ?? 0) * 60 * 1000;
        const officeEndMins = 17 * 60 + 45;
        final nowMins = now.hour * 60 + now.minute;
        final overtimeMins = nowMins > officeEndMins ? nowMins - officeEndMins : 0;

        await attRef.update({
          'checkOutTime': nowIso,
          'lastActive': nowIso,
          'sessionStatus': 'auto-checkout',
          'totalHours': totalHours,
          'insideOfficeTime': insideOfficeMs,
          'extraHours': (attData['extraHours'] ?? 0) + overtimeMins,
        });
        debugPrint('[WorkManager] Auto-checkout done. Overtime: ${overtimeMins}m');
      } else {
        // ── Delegate ALL time-tracking arithmetic to the centralized service ──
        await AttendanceService().updateTimeTracking(uid, now, isInside, nowIso);
        debugPrint('[WorkManager] Delegated time tracking to centralized service');
      }
    }
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

    print("SSID = $wifiName");
    print("BSSID = $bssid");
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

/// Local helper used ONLY for the auto-checkout snapshot calculation.
/// All ongoing metric tracking is handled by AttendanceService.
double _computeTotalHoursLocal(String? checkInIso, String? checkOutIso) {
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
    
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode,
      );
      _initialized = true;
      debugPrint('[WorkManagerService] ✅ Initialized successfully');
    } catch (e) {
      debugPrint('[WorkManagerService] ❌ Initialization failed: $e');
      rethrow;
    }
  }

  /// Register periodic location tracking (every 15 min — Android minimum)
  static Future<void> registerLocationTask({
    required String uid,
    required String name,
    required String email,
    String? department,
  }) async {
    if (!_initialized) {
      debugPrint('[WorkManagerService] ⚠️ Not initialized, call initialize() first');
      return;
    }

    try {
      // Cancel existing tasks first to prevent duplicates
      await Workmanager().cancelByUniqueName(_locationTaskName);
      
      await Workmanager().registerPeriodicTask(
        _locationTaskName,
        _locationTaskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.notRequired,
          requiresCharging: false, // Allow even when not charging
          requiresDeviceIdle: false, // Allow even when device is in use
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
        initialDelay: const Duration(minutes: 1), // Start after 1 minute
      );
      
      debugPrint('[WorkManagerService] ✅ Location task registered for $name');
    } catch (e) {
      debugPrint('[WorkManagerService] ❌ Failed to register location task: $e');
    }
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
