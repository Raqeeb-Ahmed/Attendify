import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../utils/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../utils/firebase_exception_handler.dart';

/// Unified Attendance Service - Matches Web App Schema
/// Office hours: 9:45 AM - 5:45 PM
class AttendanceService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  // Office Configuration
  double get officeLat => AppConfig.officeLat;
  double get officeLng => AppConfig.officeLng;
  String get officeIP => AppConfig.officeIP;
  static const int radiusMeters = 100;
  static const int officeStartMinutes = 9 * 60 + 45; // 9:45 AM
  static const int officeEndMinutes = 17 * 60 + 45; // 5:45 PM

  // Intervals
  static const Duration heartbeatInterval = Duration(seconds: 60);
  static const Duration locationInterval = Duration(seconds: 120);
  static const Duration staleSessionGrace = Duration(minutes: 2);

  Timer? _heartbeatTimer;
  Timer? _locationTimer;
  Timer? _autoCheckoutTimer;

  // Auto-checkout time: 6:00 PM
  static const int autoCheckoutHour = 18; // 6 PM
  static const int autoCheckoutMinute = 0;

  // ── Haversine Formula ──
  double getDistanceFromLatLonInM(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371e3;
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLon = (lon2 - lon1) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  // ── Attendance ID (one per user per day) ──
  String getTodayAttendanceId(String userId) {
    final today = _formatDate(DateTime.now());
    return '${userId}_$today';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // ── Fetch Today's Attendance ──
  Future<Map<String, dynamic>?> fetchTodayAttendance(String userId) async {
    try {
      final attendanceId = getTodayAttendanceId(userId);
      final docSnap = await _db.collection('attendance').doc(attendanceId).get();
      if (docSnap.exists) {
        return {'id': docSnap.id, ...docSnap.data()!};
      }
      return null;
    } catch (e) {
      throw AppException(getFirebaseErrorMessage(e));
    }
  }

  // ── Check In ──
  Future<Map<String, dynamic>?> checkIn(String userId, String userName, String? department, String email) async {
    try {
      final attendanceId = getTodayAttendanceId(userId);
      final today = _formatDate(DateTime.now());
      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      // Close any previous unclosed sessions first
      await _closeStaleSession(userId);

      // Fetch user's IP
      String userIp = '';
      try {
        final response = await http.get(Uri.parse('https://api.ipify.org?format=json'));
        if (response.statusCode == 200) {
          userIp = _parseIpResponse(response.body);
        }
      } catch (err) {
        debugPrint("Failed to fetch IP: $err");
      }

      // Get location
      Position? position;
      bool isLocationValid = false;
      double? lat, lng, distance;

      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission != LocationPermission.deniedForever) {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          );
          lat = position.latitude;
          lng = position.longitude;
          distance = getDistanceFromLatLonInM(officeLat, officeLng, lat, lng);
          isLocationValid = distance <= radiusMeters;
        }
      } catch (e) {
        debugPrint("Location error: $e");
      }

      final isIpValid = userIp == officeIP && officeIP.isNotEmpty;
      final isAtOffice = isLocationValid || isIpValid;

      return _processCheckInWithTransaction(
        userId: userId,
        userName: userName,
        department: department ?? 'N/A',
        email: email,
        attendanceId: attendanceId,
        isAtOffice: isAtOffice,
        ipAddress: userIp,
        location: lat != null && lng != null && distance != null
            ? {'lat': lat, 'lng': lng, 'distanceFromOffice': distance.round()}
            : null,
        dateStr: today,
        nowIso: nowIso,
      );
    } catch (e) {
      throw AppException(getFirebaseErrorMessage(e));
    }
  }

  // ── Process Check-In with Transaction (Race Condition Safe) ──
  Future<Map<String, dynamic>?> _processCheckInWithTransaction({
    required String userId,
    required String userName,
    required String department,
    required String email,
    required String attendanceId,
    required bool isAtOffice,
    required String ipAddress,
    required Map<String, dynamic>? location,
    required String dateStr,
    required String nowIso,
  }) async {
    return await _db.runTransaction<Map<String, dynamic>?>((transaction) async {
      final docRef = _db.collection('attendance').doc(attendanceId);
      final docSnap = await transaction.get(docRef);

      // Check if already exists (duplicate prevention)
      if (docSnap.exists) {
        return {'id': docSnap.id, ...docSnap.data()!};
      }

      final now = DateTime.now();
      final currentMinutes = now.hour * 60 + now.minute;

      // Determine status: present (before 9:45) or late (after 9:45)
      String finalStatus = 'outside';
      if (isAtOffice) {
        finalStatus = currentMinutes <= officeStartMinutes ? 'present' : 'late';
      }

      final data = {
        'userId': userId,
        'userName': userName,
        'email': email,
        'department': department,
        'date': dateStr,
        'checkInTime': nowIso,
        'checkOutTime': null,
        'status': finalStatus,
        'sessionStatus': 'active',
        'ipAddress': ipAddress,
        'location': location,
        'atOffice': isAtOffice,
        'insideTime': 0,
        'outsideTime': 0,
        'extraHours': 0,
        'offlineTime': 0,
        'insideOfficeTime': 0,
        'totalHours': 0.0,
        'lastActive': nowIso,
      };

      transaction.set(docRef, data);

      // Store initial location in same transaction for consistency
      if (location != null) {
        final locationRef = _db.collection('locations').doc();
        transaction.set(locationRef, {
          'userId': userId,
          'lat': location['lat'],
          'lng': location['lng'],
          'distanceFromOffice': location['distanceFromOffice'] ?? 0,
          'timestamp': nowIso,
          'status': finalStatus,
          'insideRadius': isAtOffice,
        });
      }

      return data;
    });
  }

  
  String _parseIpResponse(String body) {
    try {
      final start = body.indexOf('"ip":"') + 6;
      final end = body.indexOf('"', start);
      return body.substring(start, end);
    } catch (e) {
      return '';
    }
  }

  // ── Check Out ──
  Future<Map<String, dynamic>?> checkOut(String userId) async {
    try {
      final attendanceId = getTodayAttendanceId(userId);
      final docRef = _db.collection('attendance').doc(attendanceId);
      final docSnap = await docRef.get();

      if (!docSnap.exists) return null;

      final attData = docSnap.data()!;
      if (attData['checkOutTime'] != null) return attData;

      final nowIso = DateTime.now().toIso8601String();
      final totalHours = _computeTotalHours(attData['checkInTime'], nowIso);
      final insideOfficeMs = (attData['insideTime'] ?? 0) * 60 * 1000;

      await docRef.update({
        'checkOutTime': nowIso,
        'lastActive': nowIso,
        'sessionStatus': 'ended',
        'totalHours': totalHours,
        'insideOfficeTime': insideOfficeMs,
      });

      // Mark presence offline in RTDB
      try {
        final presenceRef = _rtdb.ref('presence/$userId');
        await presenceRef.set({'online': false, 'lastSeen': nowIso});
      } catch (e) {
        debugPrint("RTDB presence update failed: $e");
      }

      // Note: Location tracking continues even after check-out for continuous monitoring
      // Only heartbeat is stopped, location tracking keeps running via foreground service
      
      return fetchTodayAttendance(userId);
    } catch (e) {
      throw AppException(getFirebaseErrorMessage(e));
    }
  }

  // ── Close Stale Sessions ──
  Future<void> _closeStaleSession(String userId) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayStr = _formatDate(yesterday);
    final yesterdayId = '${userId}_$yesterdayStr';

    final docRef = _db.collection('attendance').doc(yesterdayId);
    final docSnap = await docRef.get();

    if (docSnap.exists) {
      final data = docSnap.data()!;
      if (data['checkOutTime'] == null && data['sessionStatus'] == 'active') {
        final lastActive = data['lastActive'];
        final closeTime = lastActive != null
            ? DateTime.parse(lastActive).add(staleSessionGrace).toIso8601String()
            : data['checkInTime'];
        final totalHours = _computeTotalHours(data['checkInTime'], closeTime);
        final insideOfficeMs = (data['insideTime'] ?? 0) * 60 * 1000;

        await docRef.update({
          'checkOutTime': closeTime,
          'sessionStatus': 'auto-closed',
          'totalHours': totalHours,
          'insideOfficeTime': insideOfficeMs,
        });
      }
    }
  }

  double _computeTotalHours(String? checkInIso, String? checkOutIso) {
    if (checkInIso == null || checkOutIso == null) return 0.0;
    final diffMs = DateTime.parse(checkOutIso).difference(DateTime.parse(checkInIso)).inMilliseconds;
    return double.parse((diffMs / (1000 * 60 * 60)).toStringAsFixed(2));
  }

  // ── Start Heartbeat ──
  void startHeartbeat(String userId) {
    if (_heartbeatTimer != null) return;

    _sendHeartbeat(userId);
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => _sendHeartbeat(userId));

    // Setup RTDB presence
    _setupPresence(userId);
  }

  Future<void> _sendHeartbeat(String userId) async {
    try {
      final nowIso = DateTime.now().toIso8601String();

      // Write heartbeat directly to Realtime Database to save Firestore requests
      await _rtdb.ref('presence/$userId').set({
        'userId': userId,
        'lastSeen': nowIso,
        'online': true,
      });
    } catch (e) {
      debugPrint("Heartbeat failed: $e");
    }
  }

  void _setupPresence(String userId) {
    try {
      final presenceRef = _rtdb.ref('presence/$userId');
      final connectedRef = _rtdb.ref('.info/connected');

      connectedRef.onValue.listen((event) {
        if (event.snapshot.value == true) {
          presenceRef.onDisconnect().set({
            'userId': userId,
            'online': false,
            'lastSeen': DateTime.now().toIso8601String(),
          }).then((_) {
            presenceRef.set({
              'userId': userId,
              'online': true,
              'lastSeen': DateTime.now().toIso8601String(),
            });
          });
        }
      });
    } catch (e) {
      debugPrint("RTDB presence setup failed: $e");
    }
  }

  // ── Stop Heartbeat ──
  void stopHeartbeat(String userId) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    // Disabling Firestore heartbeats write to save writes
    // _db.collection('heartbeats').doc(userId).set({...});

    try {
      final presenceRef = _rtdb.ref('presence/$userId');
      presenceRef.set({
        'userId': userId,
        'online': false,
        'lastSeen': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint("RTDB presence update failed: $e");
    }
  }

  // ── Auto Checkout at 6 PM ──
  /// Schedules a one-shot timer that fires at 6:00 PM today (or immediately
  /// if already past 6 PM and session is still active).
  void startAutoCheckoutTimer(String userId) {
    _autoCheckoutTimer?.cancel();

    final now = DateTime.now();
    final todayCheckout = DateTime(now.year, now.month, now.day, autoCheckoutHour, autoCheckoutMinute);

    // If already past 6 PM today, run immediately
    final delay = todayCheckout.isAfter(now) ? todayCheckout.difference(now) : Duration.zero;

    debugPrint('[AutoCheckout] Scheduled in ${delay.inMinutes} minutes');

    _autoCheckoutTimer = Timer(delay, () => autoCheckout(userId));
  }

  void cancelAutoCheckoutTimer() {
    _autoCheckoutTimer?.cancel();
    _autoCheckoutTimer = null;
  }

  /// Performs checkout at 6 PM, calculates overtime beyond 5:45 PM.
  /// Uses a Firestore transaction to prevent race conditions when the Timer
  /// and ForegroundService both fire around the same time.
  Future<void> autoCheckout(String userId) async {
    try {
      final attendanceId = getTodayAttendanceId(userId);
      final docRef = _db.collection('attendance').doc(attendanceId);
      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      bool didCheckout = false;

      await _db.runTransaction((tx) async {
        final docSnap = await tx.get(docRef);
        if (!docSnap.exists) return;
        final attData = docSnap.data()!;
        if (attData['checkOutTime'] != null) return; // Already checked out

        final totalHours = _computeTotalHours(attData['checkInTime'], nowIso);
        final insideOfficeMs = (attData['insideTime'] ?? 0) * 60 * 1000;
        final checkoutMins = now.hour * 60 + now.minute;
        final overtimeMins = checkoutMins > officeEndMinutes ? checkoutMins - officeEndMinutes : 0;

        tx.update(docRef, {
          'checkOutTime': nowIso,
          'lastActive': nowIso,
          'sessionStatus': 'auto-checkout',
          'totalHours': totalHours,
          'insideOfficeTime': insideOfficeMs,
          'extraHours': (attData['extraHours'] ?? 0) + overtimeMins,
        });
        didCheckout = true;
      });

      if (!didCheckout) return;

      // Mark presence offline
      try {
        final presenceRef = _rtdb.ref('presence/$userId');
        await presenceRef.set({'online': false, 'lastSeen': nowIso});
      } catch (e) {
        debugPrint("RTDB presence update failed: $e");
      }

      // Stop heartbeat; keep location tracking for overtime (ForegroundService handles post-checkout)
      stopHeartbeat(userId);
      cancelAutoCheckoutTimer();

      debugPrint('[AutoCheckout] User $userId auto-checked out at $nowIso');
    } catch (e) {
      debugPrint('[AutoCheckout] Error: $e');
    }
  }

  // ── Track Location ──
  void startLocationTracking(String userId) {
    if (_locationTimer != null) return;

    _sendLocation(userId);
    _locationTimer = Timer.periodic(locationInterval, (_) => _sendLocation(userId));
  }

  void stopLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  double? _lastLat;
  double? _lastLng;

  Future<void> _sendLocation(String userId) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final latitude = position.latitude;
      final longitude = position.longitude;

      // Skip if position hasn't changed significantly (< 5m)
      if (_lastLat != null && _lastLng != null) {
        final distance = getDistanceFromLatLonInM(_lastLat!, _lastLng!, latitude, longitude);
        if (distance < 5) return;
      }

      _lastLat = latitude;
      _lastLng = longitude;

      final distFromOffice = getDistanceFromLatLonInM(officeLat, officeLng, latitude, longitude);
      final isInside = distFromOffice <= radiusMeters;
      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      // Store location
      await _db.collection('locations').add({
        'userId': userId,
        'timestamp': nowIso,
        'lat': latitude,
        'lng': longitude,
        'distanceFromOffice': distFromOffice.round(),
        'insideRadius': isInside,
      });

      // Update time tracking on attendance
      await _updateTimeTrackingInternal(userId, now, isInside, nowIso);
    } catch (e) {
      debugPrint("Location tracking error: $e");
    }
  }

  /// Public method for external services to update time tracking.
  /// Called by BackgroundLocationService, ForegroundTrackingService, WorkManager,
  /// and OfflineLocationService (for chronological offline playback).
  ///
  /// [overrideAttendanceDate] – optional date string (yyyy-MM-dd) to target
  /// a specific day's attendance document (used when replaying cached offline
  /// locations that may belong to a previous day).
  Future<void> updateTimeTracking(String userId, DateTime now, bool isInside, String nowIso, {String? overrideAttendanceDate}) async {
    return _updateTimeTrackingInternal(userId, now, isInside, nowIso, overrideAttendanceDate: overrideAttendanceDate);
  }

  /// ─── Centralised Time-Tracking State Machine ─────────────────────────────
  /// ALL time-tracking arithmetic lives here. No other file should duplicate
  /// these calculations. Both the ForegroundTrackingService isolate and the
  /// WorkManager isolate call this method via [updateTimeTracking].
  ///
  /// Metric definitions (all stored in minutes except totalHours):
  /// • totalHours   – frozen at checkout (checkOutTime − checkInTime).
  ///                  While active: now − checkInTime (in decimal hours).
  /// • insideTime   – minutes inside the 100 m geofence during work hours
  ///                  OR before 9:45 AM (early arrivals count).
  /// • outsideTime  – minutes outside the geofence before 5:45 PM while
  ///                  the session is still active (not checked out).
  /// • extraHours   – overtime minutes. Accumulated when the user is inside
  ///                  the geofence AFTER 5:45 PM, or when they remain inside
  ///                  the geofence AFTER checking out.
  /// • offlineTime  – tracking gaps ≥ 20 minutes (unified threshold).
  Future<void> _updateTimeTrackingInternal(String userId, DateTime now, bool isInside, String nowIso, {String? overrideAttendanceDate}) async {
    // Resolve the correct attendance document
    final String attendanceId;

    if (overrideAttendanceDate != null) {
      attendanceId = '${userId}_$overrideAttendanceDate';
    } else {
      attendanceId = getTodayAttendanceId(userId);
    }

    final attRef = _db.collection('attendance').doc(attendanceId);
    final attSnap = await attRef.get();

    if (!attSnap.exists) return;

    final attData = attSnap.data()!;
    // If there is no checkInTime yet, nothing to track against.
    if (attData['checkInTime'] == null) return;


    final alreadyCheckedOut = attData['checkOutTime'] != null;
    final currentMinutes = now.hour * 60 + now.minute;
    final updates = <String, dynamic>{};

    debugPrint("CheckOut : ${attData['checkOutTime']}");
    debugPrint("Status : ${attData['sessionStatus']}");
    debugPrint("Inside : $isInside");
    debugPrint("LastActive : ${attData['lastActive']}");
    debugPrint("Now : $nowIso");
    debugPrint("Current Minutes : $currentMinutes");
    debugPrint("Office End : $officeEndMinutes");

    // ── Interval-based metric accumulation ──────────────────────────────────
    if (attData['lastActive'] != null) {
      final lastDate = DateTime.parse(attData['lastActive']);
      final diffMins = now.difference(lastDate).inMinutes;

      debugPrint("Diff Minutes : $diffMins");

      debugPrint("Last Active : ${attData['lastActive']}");
      debugPrint("Now : $nowIso");
      debugPrint("Difference : $diffMins");

      if (diffMins > 0 && diffMins < 20) {
        // ── Active tracking interval (< 20 min gap) ───────────────────────
        if (isInside) {
          if (alreadyCheckedOut || currentMinutes > officeEndMinutes) {
            // Inside geofence + (checked out OR after 5:45 PM) → overtime
            updates['extraHours'] = (attData['extraHours'] ?? 0) + diffMins;
          } else {
            // Inside geofence during or before office hours → insideTime
            // This intentionally includes early arrivals (before 9:45 AM)
            updates['insideTime'] = (attData['insideTime'] ?? 0) + diffMins;
          }
        } else {
          // Outside geofence
          if (!alreadyCheckedOut && currentMinutes <= officeEndMinutes) {
            // Outside during active session within work hours → outsideTime
            updates['outsideTime'] = (attData['outsideTime'] ?? 0) + diffMins;
          }
          // Outside after checkout or after 5:45 PM → not counted at all
        }
      } else if (diffMins >= 20) {
        // ── Offline gap (≥ 20 minutes) ─────────────────────────────────────
        updates['offlineTime'] = (attData['offlineTime'] ?? 0) + diffMins;
      }
      // diffMins == 0 → duplicate timestamp, skip silently
    }

    // ── Recalculate derived fields ──────────────────────────────────────────
    final newInsideTime = updates['insideTime'] ?? attData['insideTime'] ?? 0;
    updates['insideOfficeTime'] = (newInsideTime as int) * 60 * 1000; // ms

    // totalHours: freeze after checkout — use checkOutTime, not nowIso
    if (alreadyCheckedOut) {
      updates['totalHours'] = _computeTotalHours(attData['checkInTime'], attData['checkOutTime']);
    } else {
      updates['totalHours'] = _computeTotalHours(attData['checkInTime'], nowIso);
    }

    // Update location status metadata
    updates['currentStatus'] = isInside ? 'present' : 'outside';
    updates['atOffice'] = isInside;
    updates['lastLocationUpdate'] = nowIso;
    updates['lastActive'] = nowIso;

    await attRef.update(updates);
  }

  // ── Stream Attendance History ──
  Stream<QuerySnapshot> getAttendanceHistory(String userId, {int limit = 30}) {
    return _db
        .collection('attendance')
        .where('userId', isEqualTo: userId)
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots();
  }

  // ── Stream All Attendance for Date (Admin) ──
  Stream<QuerySnapshot> getAllAttendanceForDate(String date) {
    return _db
        .collection('attendance')
        .where('date', isEqualTo: date)
        .snapshots();
  }

  // ── Stream Heartbeats (Admin) ──
  Stream<DatabaseEvent> getHeartbeats() {
    return _rtdb.ref('presence').onValue;
  }

  // ── Stream Locations (Admin) ──
  Stream<QuerySnapshot> getLocations() {
    return _db
        .collection('locations')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // ── Get Latest Location per User ──
  Future<List<Map<String, dynamic>>> getLatestLocations(String date) async {
    try {
      final snapshot = await _db
          .collection('locations')
          .where('timestamp', isGreaterThanOrEqualTo: '${date}T00:00:00')
          .where('timestamp', isLessThanOrEqualTo: '${date}T23:59:59')
          .orderBy('timestamp', descending: true)
          .get();

      final latestLocs = <String, Map<String, dynamic>>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final userId = data['userId'] as String?;
        if (userId != null && !latestLocs.containsKey(userId)) {
          latestLocs[userId] = {'id': doc.id, ...data};
        }
      }
      return latestLocs.values.toList();
    } catch (e) {
      throw AppException(getFirebaseErrorMessage(e));
    }
  }

  // ── Get User Data (for role) ──
  Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      return doc.exists ? {'id': doc.id, ...doc.data()!} : null;
    } catch (e) {
      throw AppException(getFirebaseErrorMessage(e));
    }
  }

  // ── Format Minutes to Hours/Minutes ──
  String formatMinutes(int? mins) {
    if (mins == null || mins == 0) return '0h 0m';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h}h ${m}m';
  }
}
