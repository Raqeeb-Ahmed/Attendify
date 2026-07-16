import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/app_config.dart';
import 'attendance_service.dart';

/// WiFi Auto Check-in Service
/// Monitors WiFi connection state and automatically checks in when connected to office WiFi
/// Works alongside GPS geofencing for redundant check-in detection
class WiFiAutoCheckInService {
  static final WiFiAutoCheckInService _instance = WiFiAutoCheckInService._internal();
  factory WiFiAutoCheckInService() => _instance;
  WiFiAutoCheckInService._internal();

  final NetworkInfo _networkInfo = NetworkInfo();
  final AttendanceService _attendanceService = AttendanceService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _wifiCheckTimer;

  String? _currentUid;
  String? _currentName;
  String? _currentEmail;
  String? _currentDepartment;

  bool get isMonitoring => _isMonitoring;
  bool _isMonitoring = false;
  bool _hasAutoCheckedIn = false;
  String? _lastKnownWifiName;
  bool _isCheckingIn = false;

  /// Office WiFi identifiers - can be SSID name or BSSID (MAC address)
  /// Uses configured office WiFi names from AppConfig
  static List<String> get _officeWifiIdentifiers => AppConfig.officeWifiNames;

  /// Start monitoring WiFi connection for auto check-in
  void startMonitoring(
    String uid,
    String name,
    String email, {
    String? department,
    List<String>? customWifiNames,
  }) {
    if (_isMonitoring) return;
    _isMonitoring = true;

    _currentUid = uid;
    _currentName = name;
    _currentEmail = email;
    _currentDepartment = department;
    _hasAutoCheckedIn = false;

    // Add custom WiFi names from config if provided
    final wifiNames = <String>[..._officeWifiIdentifiers];
    if (customWifiNames != null) {
      wifiNames.addAll(customWifiNames);
    }

    debugPrint('[WiFiAutoCheckInService] Started monitoring for $name');
    debugPrint('[WiFiAutoCheckInService] Watching for WiFi: $wifiNames');

    // Listen to connectivity changes for real-time detection
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      _onConnectivityChanged(results, wifiNames);
    });

    // Check more frequently for faster detection (every 10 seconds)
    // _wifiCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
    //   await _checkWifiAndAutoCheckIn(wifiNames);
    // });

    _wifiCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
          (_) async {
        if (!_isCheckingIn) {
          await _checkWifiAndAutoCheckIn(wifiNames);
        }
      },
    );

    // Immediate first check
    _checkWifiAndAutoCheckIn(wifiNames);
  }

  /// Stop monitoring
  void stopMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _wifiCheckTimer?.cancel();
    _wifiCheckTimer = null;
    _isMonitoring = false;
    _currentUid = null;
    _currentName = null;
    _currentEmail = null;
    _currentDepartment = null;
    _hasAutoCheckedIn = false;
    _lastKnownWifiName = null;
    debugPrint('[WiFiAutoCheckInService] Stopped monitoring');
  }

  /// Handle connectivity change events
  Future<void> _onConnectivityChanged(
    List<ConnectivityResult> results,
    List<String> wifiNames,
  ) async {
    // Check if connected to WiFi
    final isWifi = results.contains(ConnectivityResult.wifi);

    if (isWifi) {
      // Small delay to ensure WiFi info is available
      await Future.delayed(const Duration(seconds: 2));
      await _checkWifiAndAutoCheckIn(wifiNames);
    } else {
      debugPrint('[WiFiAutoCheckInService] Disconnected from WiFi');
      _lastKnownWifiName = null;
    }
  }

  /// Core WiFi check and auto check-in logic
  Future<void> _checkWifiAndAutoCheckIn(List<String> officeWifiNames) async {
    if (_currentUid == null) return;

    if (_hasAutoCheckedIn) {
      debugPrint("[WiFiAutoCheckInService] Already auto checked in.");
      return;
    }

    if (_isCheckingIn) {
      debugPrint("[WiFiAutoCheckInService] Check-in already in progress...");
      return;
    }

    try {
      // Get current WiFi info
      final wifiName = await _networkInfo.getWifiName();
      final bssid = await _networkInfo.getWifiBSSID();

      debugPrint('[WiFiAutoCheckInService] Current WiFi: $wifiName (BSSID: $bssid)');

      // Check if this is office WiFi
      final isOfficeWifi = _isOfficeWifi(wifiName, bssid, officeWifiNames);

      if (isOfficeWifi && !_hasAutoCheckedIn) {
        // AND Condition: Must also be within GPS radius of the office
        try {
          // Check location permission first
          final permission = await Geolocator.checkPermission();
          debugPrint("Permission = $permission");
          if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
            debugPrint('[WiFiAutoCheckInService] Location permission denied. Cannot verify geofence proximity.');
            return;
          }

          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          );

          if (position.accuracy > 150) {
            debugPrint('[WiFiAutoCheckInService] Low accuracy (${position.accuracy}m). Ignoring.');
            return;
          }

          final distance = _attendanceService.getDistanceFromLatLonInM(
            AppConfig.officeLat,
            AppConfig.officeLng,
            position.latitude,
            position.longitude,
          );

          debugPrint("============== GPS DEBUG ==============");
          debugPrint("Office Lat : ${AppConfig.officeLat}");
          debugPrint("Office Lng : ${AppConfig.officeLng}");

          debugPrint("Current Lat : ${position.latitude}");
          debugPrint("Current Lng : ${position.longitude}");

          debugPrint("Accuracy : ${position.accuracy}");

          debugPrint("Distance : ${distance.round()} meters");
          debugPrint("=======================================");


          final isInsideRadius = distance <= 100;

          if (!isInsideRadius) {
            debugPrint('[WiFiAutoCheckInService] Connected to office WiFi but outside geofence radius (${distance.round()}m). Skipping check-in.');
            return;
          }
        } catch (gpsError) {
          debugPrint('[WiFiAutoCheckInService] Error fetching GPS location for WiFi check-in: $gpsError');
          return; // Skip check-in if GPS verification fails
        }

        // Check if already checked in today
        final hasCheckedIn = await _hasAlreadyCheckedIn();

        if (!hasCheckedIn) {
          await _performAutoCheckIn(wifiName, bssid);
        } else {
          debugPrint('[WiFiAutoCheckInService] Already checked in today');
          _hasAutoCheckedIn = true; // Mark as done to prevent further checks
        }
      }

      _lastKnownWifiName = wifiName;
    } catch (e) {
      debugPrint('[WiFiAutoCheckInService] Error checking WiFi: $e');
    }
  }

  /// Check if current WiFi is office WiFi
  bool _isOfficeWifi(String? wifiName, String? bssid, List<String> officeWifiNames) {
    if (wifiName == null && bssid == null) return false;

    // Remove quotes from WiFi name (some devices return quoted SSID)
    final cleanName = wifiName?.replaceAll('"', '').toLowerCase().trim();
    final cleanBssid = bssid?.toLowerCase().replaceAll(':', '').trim();

    for (final officeName in officeWifiNames) {
      final cleanOfficeName = officeName.toLowerCase().trim();

      // Match by SSID name
      if (cleanName != null && cleanName.contains(cleanOfficeName)) {
        debugPrint("✅ Office WiFi Matched");
        debugPrint('[WiFiAutoCheckInService] Matched WiFi by SSID: $wifiName');
        return true;
      }

      // Match by exact SSID
      if (cleanName == cleanOfficeName) {
        debugPrint('[WiFiAutoCheckInService] Exact WiFi SSID match: $wifiName');
        return true;
      }

      // Match by BSSID (MAC address) - useful for hidden networks
      if (cleanBssid != null && cleanBssid == cleanOfficeName.replaceAll(':', '')) {
        debugPrint('[WiFiAutoCheckInService] WiFi BSSID match: $bssid');
        return true;
      }
    }

    return false;
  }

  /// Check if user already checked in today
  // Future<bool> _hasAlreadyCheckedIn() async {
  //   if (_currentUid == null) return false;
  //
  //   try {
  //     final today = DateTime.now();
  //     final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  //     final docId = '${_currentUid}_$dateStr';
  //
  //     final doc = await _db.collection('attendance').doc(docId).get();
  //     return doc.exists && doc.data()?['checkInTime'] != null;
  //   } catch (e) {
  //     debugPrint('[WiFiAutoCheckInService] Error checking attendance: $e');
  //     return false;
  //   }
  // }


  Future<bool> _hasAlreadyCheckedIn() async {

    if (_hasAutoCheckedIn) {
      return true;
    }

    if (_currentUid == null) {
      return false;
    }

    try {

      final today = DateTime.now();

      final dateStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final docId = '${_currentUid}_$dateStr';

      final doc =
      await _db.collection('attendance').doc(docId).get();

      if (doc.exists && doc.data()?['checkInTime'] != null) {

        _hasAutoCheckedIn = true;

        return true;
      }

      return false;

    } catch (e) {

      debugPrint(e.toString());

      return false;
    }
  }
  /// Perform auto check-in via WiFi detection
  //


  Future<void> _performAutoCheckIn(String? wifiName, String? bssid) async {
    if (_currentUid == null) return;

    if (_isCheckingIn) {
      debugPrint("[WiFiAutoCheckInService] Another check-in request is already running.");
      return;
    }

    _isCheckingIn = true;

    try {
      debugPrint("==================================");
      debugPrint("AUTO CHECK-IN STARTED");
      debugPrint("User : $_currentUid");
      debugPrint("Time : ${DateTime.now()}");
      debugPrint("==================================");

      final result = await _attendanceService.checkIn(
        _currentUid!,
        _currentName!,
        _currentDepartment,
        _currentEmail!,
      );

      if (result != null) {
        _hasAutoCheckedIn = true;

        final today = DateTime.now();

        final dateStr =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

        final docId = '${_currentUid}_$dateStr';

        await _db.collection('attendance').doc(docId).update({
          'wifiAutoCheckIn': true,
          'wifiName': wifiName,
          'wifiBssid': bssid,
          'checkInMethod': 'wifi',
        });

        debugPrint("✅ AUTO CHECK-IN SUCCESS");

        // _attendanceService.startHeartbeat(_currentUid!);
        // _attendanceService.startLocationTracking(_currentUid!);
        _attendanceService.startAutoCheckoutTimer(_currentUid!);
      } else {
        debugPrint("⚠ AttendanceService returned NULL");
      }
    } catch (e, stack) {
      debugPrint("========== AUTO CHECK IN ERROR ==========");
      debugPrint(e.toString());
      debugPrint(stack.toString());
      debugPrint("========================================");
    } finally {
      _isCheckingIn = false;
    }
  }


  /// Reset auto check-in status (for new day or testing)
  void resetAutoCheckIn() {
    _hasAutoCheckedIn = false;
    debugPrint('[WiFiAutoCheckInService] Reset auto check-in status');
  }

  /// Check if auto check-in has occurred
  bool get hasAutoCheckedIn => _hasAutoCheckedIn;

  /// Get last known WiFi name
  String? get lastKnownWifiName => _lastKnownWifiName;

  /// Manual check - useful for testing
  Future<bool> isConnectedToOfficeWifi(List<String> officeWifiNames) async {
    try {
      final wifiName = await _networkInfo.getWifiName();
      final bssid = await _networkInfo.getWifiBSSID();
      return _isOfficeWifi(wifiName, bssid, officeWifiNames);
    } catch (e) {
      return false;
    }
  }
}
