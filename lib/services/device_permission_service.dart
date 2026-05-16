import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

/// Reads the device's current permission states and persists them to the
/// `users/{uid}` document under the `devicePermissions` sub-map so the admin
/// can see each employee's tracking health at a glance.
///
/// Schema written to Firestore:
/// ```
/// users/{uid}.devicePermissions = {
///   'location':    'always' | 'whileInUse' | 'denied' | 'deniedForever',
///   'notification': true | false,
///   'battery':      true | false,
///   'lastUpdated':  ISO-8601 string,
/// }
/// ```
class DevicePermissionService {
  static final _db = FirebaseFirestore.instance;

  /// Check all permission states and write them to Firestore.
  /// Call this:
  ///   - After each permission dialog is resolved (first run)
  ///   - On app resume (AppLifecycleState.resumed)
  static Future<void> syncToFirestore(String uid) async {
    try {
      final location = await _locationStatus();
      final isPrecise = await _isPreciseLocation();
      final notification = await _notificationStatus();
      final battery = await _batteryStatus();

      await _db.collection('users').doc(uid).update({
        'devicePermissions': {
          'location': location,
          'isPreciseLocation': isPrecise,
          'notification': notification,
          'battery': battery,
          'lastUpdated': DateTime.now().toIso8601String(),
        },
      });

      debugPrint('[DevicePermissionService] Synced: loc=$location precise=$isPrecise notif=$notification battery=$battery');
    } catch (e) {
      debugPrint('[DevicePermissionService] Sync failed: $e');
    }
  }

  /// Human-readable location permission string.
  static Future<String> _locationStatus() async {
    try {
      final perm = await Geolocator.checkPermission();
      switch (perm) {
        case LocationPermission.always:
          return 'always';
        case LocationPermission.whileInUse:
          return 'whileInUse';
        case LocationPermission.denied:
          return 'denied';
        case LocationPermission.deniedForever:
          return 'deniedForever';
        default:
          return 'unknown';
      }
    } catch (_) {
      return 'unknown';
    }
  }

  /// Returns true if notification permission is granted (Android 13+).
  static Future<bool> _notificationStatus() async {
    try {
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      return perm == NotificationPermission.granted;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if battery optimizations are disabled (i.e. app is exempt).
  static Future<bool> _batteryStatus() async {
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return false;
    }
  }

  /// Check if precise location is enabled by attempting to get high accuracy position
  /// Note: This is a heuristic - even with precise permission, indoor GPS can be poor
  static Future<bool> _isPreciseLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      // If we got a position with reasonable accuracy, consider it precise
      // Relaxed threshold to 50m to account for indoor GPS limitations
      final isPrecise = position.accuracy > 0 && position.accuracy <= 50;
      debugPrint('[DevicePermissionService] Location accuracy: ${position.accuracy.toStringAsFixed(1)}m -> precise=$isPrecise');
      return isPrecise;
    } on TimeoutException {
      // Timed out - might be approximate location or poor GPS signal
      debugPrint('[DevicePermissionService] Location timed out - likely approximate or indoor');
      return false;
    } catch (e) {
      debugPrint('[DevicePermissionService] Error checking precise location: $e');
      return false;
    }
  }

  /// Public method to check if user should be prompted about approximate location
  /// Returns true if permission is acceptable but location is approximate
  static Future<bool> shouldPromptForPreciseLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      // Has "Always" permission but might be approximate
      if (permission == LocationPermission.always) {
        final isPrecise = await _isPreciseLocation();
        return !isPrecise; // Should prompt if not precise
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
