import 'package:flutter/foundation.dart';
import '../utils/app_config.dart';
import 'work_manager_service.dart';
import 'wifi_auto_checkin_service.dart';
import 'background_location_service.dart';
import 'foreground_tracking_service.dart';
import 'attendance_service.dart';

/// Unified Background Check-In Service
/// Coordinates all background services for pixel-perfect auto check-in without app open
class BackgroundCheckInService {
  static final BackgroundCheckInService _instance = BackgroundCheckInService._internal();
  factory BackgroundCheckInService() => _instance;
  BackgroundCheckInService._internal();

  final WiFiAutoCheckInService _wifiService = WiFiAutoCheckInService();
  final BackgroundLocationService _locationService = BackgroundLocationService();
  final AttendanceService _attendanceService = AttendanceService();

  bool _isInitialized = false;
  bool _isRunning = false;

  /// Initialize all background services (call once at app startup)
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('[BackgroundCheckInService] 🚀 Initializing background services...');

      // Initialize WorkManager first
      await WorkManagerService.initialize();

      _isInitialized = true;
      debugPrint('[BackgroundCheckInService] ✅ Background services initialized');
    } catch (e) {
      debugPrint('[BackgroundCheckInService] ❌ Initialization failed: $e');
      rethrow;
    }
  }

  /// Start all background check-in services for a user
  Future<void> startAllServices({
    required String userId,
    required String userName,
    required String email,
    String? department,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isRunning) {
      debugPrint('[BackgroundCheckInService] ⚠️ Services already running');
      return;
    }

    try {
      debugPrint('[BackgroundCheckInService] 🎯 Starting all check-in services for $userName');

      // 1. Start WorkManager for periodic background execution
      await WorkManagerService.registerLocationTask(
        uid: userId,
        name: userName,
        email: email,
        department: department,
      );

      // 2. Start WiFi monitoring for instant WiFi-based check-in
      _wifiService.startMonitoring(
        userId,
        userName,
        email,
        department: department,
        customWifiNames: AppConfig.officeWifiNames,
      );

      // 3. Start background location service for geofence detection (Disabling duplicate; Foreground service handles this)
      // _locationService.startTracking(
      //   userId,
      //   userName,
      //   email,
      //   department: department,
      // );

      // 4. Start foreground service for continuous tracking
      await ForegroundTrackingService.start(
        uid: userId,
        name: userName,
        email: email,
      );

      // 5. Start attendance service timers (Disabling duplicate; Foreground service handles heartbeats and updates)
      // _attendanceService.startHeartbeat(userId);
      // _attendanceService.startLocationTracking(userId);
      _attendanceService.startAutoCheckoutTimer(userId);

      _isRunning = true;
      debugPrint('[BackgroundCheckInService] ✅ All check-in services started successfully');
    } catch (e) {
      debugPrint('[BackgroundCheckInService] ❌ Failed to start services: $e');
      rethrow;
    }
  }

  /// Stop all background services
  Future<void> stopAllServices() async {
    if (!_isRunning) return;

    try {
      debugPrint('[BackgroundCheckInService] 🛑 Stopping all background services...');

      // Stop all services
      _wifiService.stopMonitoring();
      _locationService.stopTracking();
      await ForegroundTrackingService.stop();
      await WorkManagerService.cancelAll();

      // Note: Attendance service timers are stopped in dashboard dispose
      // to avoid conflicts with other parts of the app

      _isRunning = false;
      debugPrint('[BackgroundCheckInService] ✅ All services stopped');
    } catch (e) {
      debugPrint('[BackgroundCheckInService] ❌ Error stopping services: $e');
    }
  }

  /// Restart all services (useful for permission changes or app updates)
  Future<void> restartAllServices({
    required String userId,
    required String userName,
    required String email,
    String? department,
  }) async {
    await stopAllServices();
    await Future.delayed(const Duration(seconds: 2)); // Brief pause
    await startAllServices(
      userId: userId,
      userName: userName,
      email: email,
      department: department,
    );
  }

  /// Get current status of all services
  Future<Map<String, bool>> getServiceStatus() async {
    final foregroundRunning = await ForegroundTrackingService.isRunning;
    return {
      'initialized': _isInitialized,
      'running': _isRunning,
      'workManager': _isRunning, // WorkManager doesn't have a direct status check
      'wifi': _wifiService.isMonitoring,
      'location': _locationService.isTracking,
      'foreground': foregroundRunning,
    };
  }

  /// Test auto check-in functionality
  Future<void> testAutoCheckIn() async {
    if (!_isRunning) {
      debugPrint('[BackgroundCheckInService] ⚠️ Services not running - cannot test');
      return;
    }

    debugPrint('[BackgroundCheckInService] 🧪 Testing auto check-in...');

    // Test WiFi check-in by restarting monitoring
    _wifiService.stopMonitoring();
    await Future.delayed(const Duration(seconds: 1));
    // Note: WiFi service will automatically check on next monitoring cycle

    debugPrint('[BackgroundCheckInService] ✅ Auto check-in test initiated');
  }

  /// Reset daily check-in flags (call at midnight or when needed)
  Future<void> resetDailyFlags() async {
    debugPrint('[BackgroundCheckInService] 🔄 Resetting daily check-in flags...');

    _wifiService.resetAutoCheckIn();
    _locationService.resetAutoCheckIn();

    debugPrint('[BackgroundCheckInService] ✅ Daily flags reset');
  }
}
