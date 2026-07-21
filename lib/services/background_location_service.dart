import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/app_config.dart';
import 'package:http/http.dart' as http;
import 'location_service.dart';
import 'attendance_service.dart';
import 'wifi_auto_checkin_service.dart';
import 'offline_location_service.dart';
import 'package:geolocator/geolocator.dart';

/// Background location service - Web App Compatible
/// Uses locations collection (like web) with auto check-in on geofence entry
/// Runs continuously in background to keep user online
class BackgroundLocationService {
  // Singleton
  static final BackgroundLocationService _instance = BackgroundLocationService._internal();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._internal();

  Timer? _timer;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final LocationService _locationService = LocationService();
  final AttendanceService _attendanceService = AttendanceService();
  bool _isTracking = false;

  static DateTime? _lastHistoryWriteTime;

  String? _currentUid;
  String? _currentName;
  String? _currentEmail;
  String? _currentDepartment;
  bool _wasInsideRadius = false;
  bool _autoCheckedIn = false;

  late double _officeLat;
  late double _officeLng;
  static const int _radiusMeters = 100;

  /// Start periodic location tracking (every 60 seconds - matches web heartbeat)
  void startTracking(String uid, String name, String email, {String? department}) {
    if (_isTracking) return;
    _isTracking = true;

    _currentUid = uid;
    _currentName = name;
    _currentEmail = email;
    _currentDepartment = department;

    _officeLat = AppConfig.officeLat;
    _officeLng = AppConfig.officeLng;

    // Check if already checked in today
    _checkExistingAttendance();

    // Immediate first update
    _updateLocation();

    // Then every 30 seconds for faster geofence detection
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      _updateLocation();
    });

    debugPrint('[BackgroundLocationService] Tracking started for $name');
  }

  /// Stop tracking
  void stopTracking() {
    _timer?.cancel();
    _timer = null;
    _isTracking = false;
    _currentUid = null;
    _currentName = null;
    _currentEmail = null;
    _currentDepartment = null;
    _autoCheckedIn = false;
    _wasInsideRadius = false;
    debugPrint('[BackgroundLocationService] Tracking stopped');
  }

  bool get isTracking => _isTracking;

  /// Check if user already has active attendance today
  Future<void> _checkExistingAttendance() async {
    if (_currentUid == null) return;

    try {
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final docId = '${_currentUid}_$dateStr';

      final doc = await _db.collection('attendance').doc(docId).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          // Track attendance status regardless of check-out for continuous monitoring
          _autoCheckedIn = data['checkOutTime'] == null && data['sessionStatus'] == 'active';
          _wasInsideRadius = data['atOffice'] == true;
          debugPrint('[BackgroundLocationService] Found existing attendance - tracking continues regardless of check-out status');
        }
      }
    } catch (e) {
      debugPrint('[BackgroundLocationService] Error checking attendance: $e');
    }
  }

  /// Calculate distance using Haversine formula (matches web app)
  double _getDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371e3; // Earth radius in meters
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLon = (lon2 - lon1) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  /// Core update logic - Web App Compatible
  Future<void> _updateLocation() async {
    if (_currentUid == null || _currentName == null || _currentEmail == null) return;

    try {
      // Check internet connectivity
      final bool isOnline = await _checkInternet();
      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      // Get current position (can be done offline via GPS sensors)
      Position position;
      try {
        position = await _locationService.getCurrentLocation();
        if (position.accuracy > 150) {
          debugPrint('[BackgroundLocationService] Low accuracy (${position.accuracy}m). Ignoring.');
          return;
        }
      } catch (e) {
        debugPrint('[BackgroundLocationService] Error getting current position: $e');
        return;
      }

      // Calculate distance from office
      final distance = _getDistance(
        position.latitude,
        position.longitude,
        _officeLat,
        _officeLng,
      );
      final isInsideRadius = distance <= _radiusMeters;

      // Determine status (matching web app)
      String locationStatus = isInsideRadius ? 'present' : 'outside';

      final Map<String, dynamic> locationData = {
        'userId': _currentUid,
        'userName': _currentName,
        'email': _currentEmail,
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': nowIso,
        'status': locationStatus,
        'insideRadius': isInsideRadius,
        'distanceFromOffice': distance.round(),
        'isMocked': position.isMocked,
      };

      if (!isOnline) {
        debugPrint('[BackgroundLocationService] Device offline - Caching location locally');
        await OfflineLocationService().cacheLocation(locationData);
        return;
      }

      // Online: Sync any cached offline locations first
      await OfflineLocationService().syncCachedLocations(_currentUid!);

      // Update heartbeat (like web app)
      await _db.collection('heartbeats').doc(_currentUid).set({
        'userId': _currentUid,
        'userName': _currentName,
        'email': _currentEmail,
        'lastSeen': nowIso,
        'online': isOnline,
      }, SetOptions(merge: true));

      // AUTO CHECK-IN: Only between 9:00 AM and 6:00 PM, and not on Sunday
      final nowDt = DateTime.now();
      final isSunday = nowDt.weekday == DateTime.sunday;
      final currentMins = nowDt.hour * 60 + nowDt.minute;
      final isOfficeHours = !isSunday && currentMins >= 9 * 60 && currentMins < 18 * 60;

      if (isInsideRadius && !_autoCheckedIn && isOfficeHours) {
        final isOnOfficeWifi = await WiFiAutoCheckInService().isConnectedToOfficeWifi(AppConfig.officeWifiNames);
        if (isOnOfficeWifi) {
          await _performAutoCheckIn(position.latitude, position.longitude);
        } else {
          debugPrint('[BackgroundLocationService] Inside office radius but not connected to office WiFi. Skipping auto check-in.');
        }
      }

      _wasInsideRadius = isInsideRadius;

      // Update locations collection in Firestore (throttled to 10 minutes)
      final nowTime = DateTime.now();
      bool shouldLogHistory = false;
      if (_lastHistoryWriteTime == null || nowTime.difference(_lastHistoryWriteTime!).inMinutes >= 10) {
        shouldLogHistory = true;
      }

      if (shouldLogHistory) {
        await _db.collection('locations').add(locationData);
        _lastHistoryWriteTime = nowTime;
        debugPrint('[BackgroundLocationService] Logged movement coordinate to Firestore history');
      }

      // Update live latest location in Realtime Database instead of Firestore to save quota
      await FirebaseDatabase.instance.ref('locations/${_currentUid}_latest').set(locationData);

      // Update time tracking on attendance (if checked in)
      /// await _attendanceService.updateTimeTracking(_currentUid!, now, isInsideRadius, nowIso);

      debugPrint(
        '[BackgroundLocationService] Updated: $locationStatus (${distance.toStringAsFixed(0)}m)${isInsideRadius && !_autoCheckedIn ? ' - Auto check-in ready (waiting for WiFi)' : ''}',
      );
    } catch (e) {
      debugPrint('[BackgroundLocationService] Error: $e');
    }
  }

  /// Auto check-in when entering geofence
  Future<void> _performAutoCheckIn(double lat, double lng) async {
    if (_currentUid == null || _autoCheckedIn) return;

    try {
      debugPrint('[BackgroundLocationService] Auto check-in triggered!');

      final result = await _attendanceService.checkIn(
        _currentUid!,
        _currentName!,
        _currentDepartment,
        _currentEmail!,
      );

      if (result != null) {
        _autoCheckedIn = true;
        // _attendanceService.startHeartbeat(_currentUid!);
        // _attendanceService.startLocationTracking(_currentUid!);
        debugPrint('[BackgroundLocationService] Auto check-in successful!');
      }
    } catch (e) {
      debugPrint('[BackgroundLocationService] Auto check-in failed: $e');
    }
  }

  /// Check if device has internet connectivity
  Future<bool> _checkInternet() async {
    try {
      final response = await http
          .get(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Manual check-in status for UI
  bool get hasAutoCheckedIn => _autoCheckedIn;

  /// Reset auto check-in (for testing or new day)
  void resetAutoCheckIn() {
    _autoCheckedIn = false;
    _wasInsideRadius = false;
  }
}
