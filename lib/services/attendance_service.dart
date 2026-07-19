import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../utils/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../utils/firebase_exception_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Unified Attendance Service - Matches Web App Schema
/// Office hours: 9:45 AM - 5:45 PM
class AttendanceService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  static final Map<String, DateTime> _lastSyncTimes = {};
  static final Map<String, String> _lastStatuses = {};
  static final Map<String, DateTime> _lastFirestoreSyncTimes = {};
  static DateTime? _lastHistoryWriteTime;

  // Office Configuration
  double get officeLat => AppConfig.officeLat;
  double get officeLng => AppConfig.officeLng;
  String get officeIP => AppConfig.officeIP;
  static const int radiusMeters = 100;
  static const int officeStartMinutes = 9 * 60; // 9:00 AM
  static const int officeEndMinutes = 18 * 60; // 6:00 PM

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

  AttendanceService() {
    forceAutoCheckoutAllPastDue();
  }

  // ── Haversine Formula ──
  double getDistanceFromLatLonInM(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371e3;
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLon = (lon2 - lon1) * (pi / 180);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) *
            cos(lat2 * (pi / 180)) *
            sin(dLon / 2) *
            sin(dLon / 2);
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
      await checkAndForceAutoCheckout(userId);
      final docSnap = await _db
          .collection('attendance')
          .doc(attendanceId)
          .get();
      if (docSnap.exists) {
        return {'id': docSnap.id, ...docSnap.data()!};
      }
      return null;
    } catch (e) {
      throw AppException(getFirebaseErrorMessage(e));
    }
  }

  // ── Check In ──
  Future<Map<String, dynamic>?> checkIn(
    String userId,
    String userName,
    String? department,
    String email,
  ) async {
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
        final response = await http.get(
          Uri.parse('https://api.ipify.org?format=json'),
        );
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
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
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

      Map<String, dynamic>? attData;
      final rtdbRef = _rtdb.ref('attendance/$attendanceId');
      try {
        final rtdbSnap = await rtdbRef.get();
        if (rtdbSnap.exists) {
          attData = Map<String, dynamic>.from(rtdbSnap.value as Map);
        }
      } catch (_) {}

      if (attData == null) {
        final docSnap = await docRef.get();
        if (!docSnap.exists) return null;
        attData = docSnap.data()!;
      }

      if (attData['checkOutTime'] != null) return attData;

      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      final finalSegmentUpdates = _accumulateFinalSegment(attData, now);
      final insideTime =
          finalSegmentUpdates['insideTime'] ?? attData['insideTime'] ?? 0;
      final offlineTime =
          finalSegmentUpdates['offlineTime'] ?? attData['offlineTime'] ?? 0;
      final outsideTime =
          finalSegmentUpdates['outsideTime'] ?? attData['outsideTime'] ?? 0;
      final extraHours =
          finalSegmentUpdates['extraHours'] ?? attData['extraHours'] ?? 0;

      final totalHours = _computeTotalHours(attData['checkInTime'], nowIso);
      final insideOfficeMs = (insideTime + offlineTime) * 60 * 1000;

      final updates = {
        'checkOutTime': nowIso,
        'lastActive': nowIso,
        'sessionStatus': 'ended',
        'totalHours': totalHours,
        'insideOfficeTime': insideOfficeMs,
        'insideTime': insideTime,
        'offlineTime': offlineTime,
        'outsideTime': outsideTime,
        'extraHours': extraHours,
      };

      await docRef.update(updates);

      // Also update RTDB
      try {
        await rtdbRef.update(updates);
      } catch (_) {}

      // Clear memory cache
      _lastSyncTimes.remove(attendanceId);
      _lastStatuses.remove(attendanceId);
      _lastFirestoreSyncTimes.remove(attendanceId);

      // Clear local tracking cache for today
      try {
        await FlutterForegroundTask.saveData(
          key: 'attendance_last_sync_$attendanceId',
          value: '',
        );
        await FlutterForegroundTask.saveData(
          key: 'attendance_last_status_$attendanceId',
          value: '',
        );
      } catch (_) {}

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
            ? DateTime.parse(
                lastActive,
              ).add(staleSessionGrace).toIso8601String()
            : data['checkInTime'];
        final totalHours = _computeTotalHours(data['checkInTime'], closeTime);
        final insideOfficeMs =
            ((data['insideTime'] ?? 0) + (data['offlineTime'] ?? 0)) *
            60 *
            1000;

        await docRef.update({
          'checkOutTime': closeTime,
          'sessionStatus': 'auto-closed',
          'totalHours': totalHours,
          'insideOfficeTime': insideOfficeMs,
        });
      }
    }
  }

  /// Accumulates final tracking metrics between the last update and the checkout time
  Map<String, int> _accumulateFinalSegment(
    Map<String, dynamic> attData,
    DateTime now,
  ) {
    final updates = <String, int>{};
    if (attData['lastActive'] == null) return updates;

    try {
      final lastDate = DateTime.parse(attData['lastActive'] as String);
      final diffMins = now.difference(lastDate).inMinutes;

      if (diffMins > 0) {
        // Construct office boundary dates for the segment's day
        final dayStart = DateTime(
          lastDate.year,
          lastDate.month,
          lastDate.day,
          9,
          0,
        );
        final dayEnd = DateTime(
          lastDate.year,
          lastDate.month,
          lastDate.day,
          18,
          0,
        );

        final officeStartOverlap = lastDate.isAfter(dayStart)
            ? lastDate
            : dayStart;
        final officeEndOverlap = now.isBefore(dayEnd) ? now : dayEnd;
        final officeMins = officeEndOverlap.isAfter(officeStartOverlap)
            ? officeEndOverlap.difference(officeStartOverlap).inMinutes
            : 0;

        final overtimeStartOverlap = lastDate.isAfter(dayEnd)
            ? lastDate
            : dayEnd;
        final overtimeEndOverlap = now;
        final overtimeMins = overtimeEndOverlap.isAfter(overtimeStartOverlap)
            ? overtimeEndOverlap.difference(overtimeStartOverlap).inMinutes
            : 0;

        if (diffMins < 20) {
          // Active tracking interval (< 20 min gap)
          // Default to inside office unless explicitly outside
          final wasInside = attData['currentStatus'] != 'outside';
          if (wasInside) {
            if (officeMins > 0) {
              updates['insideTime'] =
                  ((attData['insideTime'] as num?)?.toInt() ?? 0) + officeMins;
            }
            if (overtimeMins > 0) {
              updates['extraHours'] =
                  ((attData['extraHours'] as num?)?.toInt() ?? 0) +
                  overtimeMins;
            }
          } else {
            if (officeMins > 0) {
              updates['outsideTime'] =
                  ((attData['outsideTime'] as num?)?.toInt() ?? 0) + officeMins;
            }
          }
        } else {
          // Offline gap (≥ 20 minutes)
          // As requested, offline/killed time is treated as inside office time!
          if (officeMins > 0) {
            updates['offlineTime'] =
                ((attData['offlineTime'] as num?)?.toInt() ?? 0) + officeMins;
            updates['insideTime'] =
                ((attData['insideTime'] as num?)?.toInt() ?? 0) + officeMins;
          }
        }
      }
    } catch (_) {}
    return updates;
  }

  /// Checks and forcefully check out a specific user if it's past 6:00 PM
  Future<void> checkAndForceAutoCheckout(
    String userId, {
    String? targetDate,
  }) async {
    try {
      final attendanceId = targetDate != null
          ? '${userId}_$targetDate'
          : getTodayAttendanceId(userId);
      final docRef = _db.collection('attendance').doc(attendanceId);

      // Get cached data from RTDB first (most recent)
      Map<String, dynamic>? attData;
      final rtdbRef = _rtdb.ref('attendance/$attendanceId');
      try {
        final rtdbSnap = await rtdbRef.get();
        if (rtdbSnap.exists) {
          attData = Map<String, dynamic>.from(rtdbSnap.value as Map);
        }
      } catch (_) {}

      if (attData == null) {
        final docSnap = await docRef.get();
        if (docSnap.exists) {
          attData = docSnap.data();
        }
      }

      if (attData == null) return;

      // Check if checked in, but not checked out, and current time is past 6:00 PM of that day
      if (attData['checkInTime'] != null && attData['checkOutTime'] == null) {
        final checkInDateTime = DateTime.parse(
          attData['checkInTime'] as String,
        );
        final now = DateTime.now();

        // Construct 6 PM time of that attendance day
        final autoCheckoutTime = DateTime(
          checkInDateTime.year,
          checkInDateTime.month,
          checkInDateTime.day,
          18,
          0,
        );

        if (now.isAfter(autoCheckoutTime)) {
          debugPrint(
            '[AttendanceService] Forcefully auto-checking out $userId at 6 PM',
          );
          final nowIso = autoCheckoutTime.toIso8601String();

          final finalSegmentUpdates = _accumulateFinalSegment(
            attData,
            autoCheckoutTime,
          );
          final insideTime =
              finalSegmentUpdates['insideTime'] ??
              (attData['insideTime'] as num?)?.toInt() ??
              0;
          final offlineTime =
              finalSegmentUpdates['offlineTime'] ??
              (attData['offlineTime'] as num?)?.toInt() ??
              0;
          final outsideTime =
              finalSegmentUpdates['outsideTime'] ??
              (attData['outsideTime'] as num?)?.toInt() ??
              0;
          final extraHours =
              finalSegmentUpdates['extraHours'] ??
              (attData['extraHours'] as num?)?.toInt() ??
              0;

          final totalHours = _computeTotalHours(
            attData['checkInTime'] as String?,
            nowIso,
          );
          final insideOfficeMs = (insideTime + offlineTime) * 60 * 1000;

          final updates = {
            'checkOutTime': nowIso,
            'lastActive': nowIso,
            'sessionStatus': 'auto-checkout',
            'totalHours': totalHours,
            'insideOfficeTime': insideOfficeMs,
            'insideTime': insideTime,
            'offlineTime': offlineTime,
            'outsideTime': outsideTime,
            'extraHours': extraHours,
          };

          await docRef.update(updates);

          try {
            await rtdbRef.update(updates);
          } catch (_) {}

          // Clear caches
          _lastSyncTimes.remove(attendanceId);
          _lastStatuses.remove(attendanceId);
          _lastFirestoreSyncTimes.remove(attendanceId);
        }
      }
    } catch (e) {
      debugPrint('[AttendanceService] Error in checkAndForceAutoCheckout: $e');
    }
  }

  /// Forcefully checkout all active sessions that are past 6 PM (both past days and today)
  Future<void> forceAutoCheckoutAllPastDue() async {
    try {
      final now = DateTime.now();
      final todayStr = _formatDate(now);

      // Query all documents that are currently active
      final querySnap = await _db
          .collection('attendance')
          .where('sessionStatus', isEqualTo: 'active')
          .get();

      for (var doc in querySnap.docs) {
        final data = doc.data();
        final dateStr = data['date'] as String?;
        if (dateStr == null) continue;

        final isPastDay = dateStr.compareTo(todayStr) < 0;
        final isTodayPast6PM = dateStr == todayStr && now.hour >= 18;

        if (isPastDay || isTodayPast6PM) {
          final userId = data['userId'] as String?;
          if (userId == null) continue;

          final attendanceId = doc.id;

          // Construct 6 PM time of that day
          final parts = dateStr.split('-');
          if (parts.length != 3) continue;
          final yr = int.parse(parts[0]);
          final mon = int.parse(parts[1]);
          final dy = int.parse(parts[2]);
          final autoCheckoutTime = DateTime(yr, mon, dy, 18, 0);
          final nowIso = autoCheckoutTime.toIso8601String();

          // Get RTDB cache first
          Map<String, dynamic>? cachedData;
          final rtdbRef = _rtdb.ref('attendance/$attendanceId');
          try {
            final rtdbSnap = await rtdbRef.get();
            if (rtdbSnap.exists) {
              cachedData = Map<String, dynamic>.from(rtdbSnap.value as Map);
            }
          } catch (_) {}

          final mergedData = {...data, if (cachedData != null) ...cachedData};

          final finalSegmentUpdates = _accumulateFinalSegment(
            mergedData,
            autoCheckoutTime,
          );
          final insideTime =
              finalSegmentUpdates['insideTime'] ??
              (mergedData['insideTime'] as num?)?.toInt() ??
              0;
          final offlineTime =
              finalSegmentUpdates['offlineTime'] ??
              (mergedData['offlineTime'] as num?)?.toInt() ??
              0;
          final outsideTime =
              finalSegmentUpdates['outsideTime'] ??
              (mergedData['outsideTime'] as num?)?.toInt() ??
              0;
          final extraHours =
              finalSegmentUpdates['extraHours'] ??
              (mergedData['extraHours'] as num?)?.toInt() ??
              0;

          final totalHours = _computeTotalHours(
            data['checkInTime'] as String?,
            nowIso,
          );
          final insideOfficeMs = (insideTime + offlineTime) * 60 * 1000;

          final updates = {
            'checkOutTime': nowIso,
            'lastActive': nowIso,
            'sessionStatus': 'auto-checkout',
            'totalHours': totalHours,
            'insideOfficeTime': insideOfficeMs,
            'insideTime': insideTime,
            'offlineTime': offlineTime,
            'outsideTime': outsideTime,
            'extraHours': extraHours,
          };

          await _db.collection('attendance').doc(attendanceId).update(updates);

          try {
            await rtdbRef.update(updates);
          } catch (_) {}

          // Clear caches
          _lastSyncTimes.remove(attendanceId);
          _lastStatuses.remove(attendanceId);
          _lastFirestoreSyncTimes.remove(attendanceId);

          debugPrint(
            '[AttendanceService] Forcefully checked out stale user $userId for day $dateStr',
          );
        }
      }
    } catch (e) {
      debugPrint('[AttendanceService] Error forcing auto-checkouts: $e');
    }
  }

  double _computeTotalHours(String? checkInIso, String? checkOutIso) {
    if (checkInIso == null || checkOutIso == null) return 0.0;
    final diffMs = DateTime.parse(
      checkOutIso,
    ).difference(DateTime.parse(checkInIso)).inMilliseconds;
    return double.parse((diffMs / (1000 * 60 * 60)).toStringAsFixed(2));
  }

  // ── Start Heartbeat ──
  void startHeartbeat(String userId) {
    if (_heartbeatTimer != null) return;

    _sendHeartbeat(userId);
    _heartbeatTimer = Timer.periodic(
      heartbeatInterval,
      (_) => _sendHeartbeat(userId),
    );

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
          presenceRef
              .onDisconnect()
              .set({
                'userId': userId,
                'online': false,
                'lastSeen': DateTime.now().toIso8601String(),
              })
              .then((_) {
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
    final todayCheckout = DateTime(
      now.year,
      now.month,
      now.day,
      autoCheckoutHour,
      autoCheckoutMinute,
    );

    // If already past 6 PM today, run immediately
    final delay = todayCheckout.isAfter(now)
        ? todayCheckout.difference(now)
        : Duration.zero;

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

      Map<String, dynamic>? cachedData;
      final rtdbRef = _rtdb.ref('attendance/$attendanceId');
      try {
        final rtdbSnap = await rtdbRef.get();
        if (rtdbSnap.exists) {
          cachedData = Map<String, dynamic>.from(rtdbSnap.value as Map);
        }
      } catch (_) {}

      bool didCheckout = false;

      await _db.runTransaction((tx) async {
        final docSnap = await tx.get(docRef);
        if (!docSnap.exists) return;
        final attData = docSnap.data()!;
        if (attData['checkOutTime'] != null) return; // Already checked out

        final mergedData = {...attData, if (cachedData != null) ...cachedData};

        final finalSegmentUpdates = _accumulateFinalSegment(mergedData, now);
        final insideTime =
            (finalSegmentUpdates['insideTime'] as num?)?.toInt() ??
            (mergedData['insideTime'] as num?)?.toInt() ??
            0;
        final offlineTime =
            (finalSegmentUpdates['offlineTime'] as num?)?.toInt() ??
            (mergedData['offlineTime'] as num?)?.toInt() ??
            0;
        final outsideTime =
            (finalSegmentUpdates['outsideTime'] as num?)?.toInt() ??
            (mergedData['outsideTime'] as num?)?.toInt() ??
            0;
        final extraHours =
            (finalSegmentUpdates['extraHours'] as num?)?.toInt() ??
            (mergedData['extraHours'] as num?)?.toInt() ??
            0;

        final totalHours = _computeTotalHours(attData['checkInTime'], nowIso);
        final insideOfficeMs = (insideTime + offlineTime) * 60 * 1000;
        final checkoutMins = now.hour * 60 + now.minute;
        final overtimeMins = checkoutMins > officeEndMinutes
            ? checkoutMins - officeEndMinutes
            : 0;

        final updates = {
          'checkOutTime': nowIso,
          'lastActive': nowIso,
          'sessionStatus': 'auto-checkout',
          'totalHours': totalHours,
          'insideOfficeTime': insideOfficeMs,
          'insideTime': insideTime,
          'offlineTime': offlineTime,
          'outsideTime': outsideTime,
          'extraHours': extraHours + overtimeMins,
        };

        tx.update(docRef, updates);

        // Also update RTDB
        try {
          rtdbRef.update(updates);
        } catch (_) {}

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
    _locationTimer = Timer.periodic(
      locationInterval,
      (_) => _sendLocation(userId),
    );
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final latitude = position.latitude;
      final longitude = position.longitude;

      // Skip if position hasn't changed significantly (< 5m)
      if (_lastLat != null && _lastLng != null) {
        final distance = getDistanceFromLatLonInM(
          _lastLat!,
          _lastLng!,
          latitude,
          longitude,
        );
        if (distance < 5) return;
      }

      _lastLat = latitude;
      _lastLng = longitude;

      final distFromOffice = getDistanceFromLatLonInM(
        officeLat,
        officeLng,
        latitude,
        longitude,
      );
      final isInside = distFromOffice <= radiusMeters;
      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      final nowTime = DateTime.now();
      bool shouldLogHistory = false;
      if (_lastHistoryWriteTime == null ||
          nowTime.difference(_lastHistoryWriteTime!).inMinutes >= 10) {
        shouldLogHistory = true;
      }

      if (shouldLogHistory) {
        // Store location
        await _db.collection('locations').add({
          'userId': userId,
          'timestamp': nowIso,
          'lat': latitude,
          'lng': longitude,
          'distanceFromOffice': distFromOffice.round(),
          'insideRadius': isInside,
        });
        _lastHistoryWriteTime = nowTime;
      }

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
  Future<void> updateTimeTracking(
    String userId,
    DateTime now,
    bool isInside,
    String nowIso, {
    String? overrideAttendanceDate,
    bool forceWrite = false,
  }) async {
    return _updateTimeTrackingInternal(
      userId,
      now,
      isInside,
      nowIso,
      overrideAttendanceDate: overrideAttendanceDate,
      forceWrite: forceWrite,
    );
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
  Future<void> _updateTimeTrackingInternal(
    String userId,
    DateTime now,
    bool isInside,
    String nowIso, {
    String? overrideAttendanceDate,
    bool forceWrite = false,
  }) async {
    // Resolve the correct attendance document
    final String attendanceId;

    if (overrideAttendanceDate != null) {
      attendanceId = '${userId}_$overrideAttendanceDate';
    } else {
      attendanceId = getTodayAttendanceId(userId);
    }

    // Throttling logic to save Firestore read/write quota
    bool shouldWrite = false;
    final currentStatus = isInside ? 'present' : 'outside';

    if (forceWrite) {
      shouldWrite = true;
    } else {
      final lastSync = _lastSyncTimes[attendanceId];
      final lastStatus = _lastStatuses[attendanceId];

      if (lastSync == null || lastStatus == null) {
        shouldWrite = true;
      } else {
        final elapsedMins = now.difference(lastSync).inMinutes;

        if (currentStatus != lastStatus) {
          shouldWrite = true; // status transition
        } else if (elapsedMins >= 5) {
          shouldWrite = true; // 5-minute timeout boundary reached
        }
      }
    }

    if (shouldWrite) {
      _lastSyncTimes[attendanceId] = now;
      _lastStatuses[attendanceId] = currentStatus;
    }

    if (!shouldWrite) {
      debugPrint(
        '[AttendanceService] Quota Saved: Throttling Firestore update for $userId',
      );
      return;
    }

    final attRef = _db.collection('attendance').doc(attendanceId);
    Map<String, dynamic>? attData;

    final rtdbRef = _rtdb.ref('attendance/$attendanceId');
    try {
      final rtdbSnap = await rtdbRef.get();
      if (rtdbSnap.exists) {
        attData = Map<String, dynamic>.from(rtdbSnap.value as Map);
      } else {
        final attSnap = await attRef.get();
        if (attSnap.exists) {
          attData = attSnap.data();
          if (attData != null) {
            // Initialize RTDB cache
            await rtdbRef.set(attData);
          }
        }
      }
    } catch (e) {
      debugPrint('[AttendanceService] RTDB cache read error: $e');
      final attSnap = await attRef.get();
      if (attSnap.exists) {
        attData = attSnap.data();
      }
    }

    if (attData == null) return;
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

      if (diffMins > 0) {
        // Construct office boundary dates for the segment's day
        final dayStart = DateTime(
          lastDate.year,
          lastDate.month,
          lastDate.day,
          9,
          0,
        );
        final dayEnd = DateTime(
          lastDate.year,
          lastDate.month,
          lastDate.day,
          18,
          0,
        );

        // Segment's overlap with standard office hours (9:45 AM to 5:45 PM)
        final officeStartOverlap = lastDate.isAfter(dayStart)
            ? lastDate
            : dayStart;
        final officeEndOverlap = now.isBefore(dayEnd) ? now : dayEnd;
        final officeMins = officeEndOverlap.isAfter(officeStartOverlap)
            ? officeEndOverlap.difference(officeStartOverlap).inMinutes
            : 0;

        // Segment's overlap with overtime hours (after 5:45 PM)
        final overtimeStartOverlap = lastDate.isAfter(dayEnd)
            ? lastDate
            : dayEnd;
        final overtimeEndOverlap = now;
        final overtimeMins = overtimeEndOverlap.isAfter(overtimeStartOverlap)
            ? overtimeEndOverlap.difference(overtimeStartOverlap).inMinutes
            : 0;

        if (diffMins < 20) {
          // ── Active tracking interval (< 20 min gap) ───────────────────────
          final wasInside =
              attData['currentStatus'] == 'present' ||
              attData['atOffice'] == true ||
              (attData['currentStatus'] == null && isInside);

          if (wasInside) {
            if (officeMins > 0) {
              updates['insideTime'] = (attData['insideTime'] ?? 0) + officeMins;
            }
            if (overtimeMins > 0) {
              updates['extraHours'] =
                  (attData['extraHours'] ?? 0) + overtimeMins;
            }
          } else {
            // Outside geofence
            if (officeMins > 0 && !alreadyCheckedOut) {
              updates['outsideTime'] =
                  (attData['outsideTime'] ?? 0) + officeMins;
            }
          }
        } else {
          // ── Offline gap (≥ 20 minutes) ─────────────────────────────────────
          // Only count the offline gap that fell within office hours
          if (officeMins > 0) {
            updates['offlineTime'] = (attData['offlineTime'] ?? 0) + officeMins;
            updates['insideTime'] = (attData['insideTime'] ?? 0) + officeMins;
          }
        }
      }
    }

    // ── Recalculate derived fields ──────────────────────────────────────────
    final currentInside = updates['insideTime'] ?? attData['insideTime'] ?? 0;
    final currentOffline =
        updates['offlineTime'] ?? attData['offlineTime'] ?? 0;
    updates['insideOfficeTime'] =
        (currentInside + currentOffline) * 60 * 1000; // ms

    if (alreadyCheckedOut) {
      updates['totalHours'] = _computeTotalHours(
        attData['checkInTime'],
        attData['checkOutTime'],
      );
    } else {
      updates['totalHours'] = _computeTotalHours(
        attData['checkInTime'],
        nowIso,
      );
    }

    updates['currentStatus'] = isInside ? 'present' : 'outside';
    updates['atOffice'] = isInside;
    updates['lastLocationUpdate'] = nowIso;
    updates['lastActive'] = nowIso;

    // Save to RTDB Cache (Free writes)
    try {
      await rtdbRef.update(updates);
    } catch (e) {
      debugPrint('[AttendanceService] RTDB cache write error: $e');
    }

    // Dual-Write Strategy: Determine if we should also sync to Firestore
    bool syncToFirestore = false;
    if (forceWrite ||
        updates['currentStatus'] != attData['currentStatus'] ||
        alreadyCheckedOut) {
      syncToFirestore = true;
    } else {
      final lastSync = _lastFirestoreSyncTimes[attendanceId];
      if (lastSync == null || now.difference(lastSync).inMinutes >= 30) {
        syncToFirestore = true;
      }
    }

    if (syncToFirestore) {
      await attRef.update(updates);
      _lastFirestoreSyncTimes[attendanceId] = now;
      debugPrint(
        '[AttendanceService] Syncing time tracking to Firestore (Quota Throttled)',
      );
    } else {
      debugPrint(
        '[AttendanceService] Time tracking updated in RTDB cache only',
      );
    }
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
      final ref = _rtdb.ref('locations');
      final event = await ref.get();
      final data = event.value as Map<dynamic, dynamic>? ?? {};

      final latestLocs = <String, Map<String, dynamic>>{};
      data.forEach((key, val) {
        if (val != null) {
          final map = Map<String, dynamic>.from(val as Map);
          final userId = map['userId'] as String?;
          final timestamp = map['timestamp'] as String?;
          if (userId != null &&
              timestamp != null &&
              timestamp.startsWith(date)) {
            latestLocs[userId] = map;
          }
        }
      });
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
