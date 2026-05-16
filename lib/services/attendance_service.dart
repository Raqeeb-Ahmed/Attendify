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

      // Prevent duplicate check-in
      final existing = await _db.collection('attendance').doc(attendanceId).get();
      if (existing.exists) {
        return {'id': existing.id, ...existing.data()!};
      }

      // Close any previous unclosed sessions
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

      return _processCheckIn(
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

  // ── Process Check-In ──
  Future<Map<String, dynamic>> _processCheckIn({
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

    await _db.collection('attendance').doc(attendanceId).set(data);

    // Store initial location
    if (location != null) {
      await _db.collection('locations').add({
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

      // Only write the lightweight heartbeats doc — attendance lastActive
      // is updated by the location tracker (every 120s) which already does
      // a read+write there, avoiding a duplicate read here every 60s.
      await _db.collection('heartbeats').doc(userId).set({
        'userId': userId,
        'lastSeen': nowIso,
        'online': true,
      }, SetOptions(merge: true));
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
            'online': false,
            'lastSeen': DateTime.now().toIso8601String(),
          }).then((_) {
            presenceRef.set({
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

    // Mark offline
    _db.collection('heartbeats').doc(userId).set({
      'userId': userId,
      'lastSeen': DateTime.now().toIso8601String(),
      'online': false,
    });

    try {
      final presenceRef = _rtdb.ref('presence/$userId');
      presenceRef.set({'online': false, 'lastSeen': DateTime.now().toIso8601String()});
    } catch (e) {
      debugPrint("RTDB presence update failed: $e");
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

  /// Public method for external services to update time tracking
  /// Called by BackgroundLocationService, ForegroundTrackingService, WorkManager
  Future<void> updateTimeTracking(String userId, DateTime now, bool isInside, String nowIso) async {
    return _updateTimeTrackingInternal(userId, now, isInside, nowIso);
  }

  Future<void> _updateTimeTrackingInternal(String userId, DateTime now, bool isInside, String nowIso) async {
    final attendanceId = getTodayAttendanceId(userId);
    final attRef = _db.collection('attendance').doc(attendanceId);
    final attSnap = await attRef.get();

    if (!attSnap.exists) return;

    final attData = attSnap.data()!;
    if (attData['checkOutTime'] != null || attData['sessionStatus'] != 'active') return;

    final currentMinutes = now.hour * 60 + now.minute;
    final updates = <String, dynamic>{};

    if (attData['lastActive'] != null) {
      final lastDate = DateTime.parse(attData['lastActive']);
      final diffMins = now.difference(lastDate).inMinutes;

      // Only add if reasonable (< 15 mins gap means user was active)
      if (diffMins > 0 && diffMins < 15) {
        if (currentMinutes > officeEndMinutes) {
          // After 5:45 PM = extra hours
          updates['extraHours'] = (attData['extraHours'] ?? 0) + diffMins;
        } else if (currentMinutes >= officeStartMinutes && currentMinutes <= officeEndMinutes) {
          // Office hours: track inside/outside
          if (isInside) {
            updates['insideTime'] = (attData['insideTime'] ?? 0) + diffMins;
          } else {
            updates['outsideTime'] = (attData['outsideTime'] ?? 0) + diffMins;
          }
        } else if (currentMinutes < officeStartMinutes) {
          // Before 9:45 AM = outside time
          updates['outsideTime'] = (attData['outsideTime'] ?? 0) + diffMins;
        }
      } else if (diffMins >= 15) {
        // Gap > 15 mins = offline time
        updates['offlineTime'] = (attData['offlineTime'] ?? 0) + diffMins;
      }
    }

    // Recalculate derived fields
    final newInsideTime = updates['insideTime'] ?? attData['insideTime'] ?? 0;
    updates['insideOfficeTime'] = (newInsideTime as int) * 60 * 1000; // ms
    updates['totalHours'] = _computeTotalHours(attData['checkInTime'], nowIso);
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
  Stream<QuerySnapshot> getHeartbeats() {
    return _db.collection('heartbeats').snapshots();
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
