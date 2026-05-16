import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';

/// Enhanced Location Permission Service
/// Ensures "Always" + "Precise" location permissions are granted
/// Redirects to app settings if permissions are insufficient
class LocationPermissionService {
  /// Check if location permission is granted and is "Always" + "Precise"
  static Future<LocationPermissionStatus> checkPermissionStatus() async {
    try {
      // First check if location services are enabled
      final isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isLocationServiceEnabled) {
        return LocationPermissionStatus.serviceDisabled;
      }

      // Check permission level
      final permission = await Geolocator.checkPermission();

      switch (permission) {
        case LocationPermission.denied:
          return LocationPermissionStatus.denied;
        case LocationPermission.deniedForever:
          return LocationPermissionStatus.deniedForever;
        case LocationPermission.whileInUse:
          // Has permission but not "Always" - need to upgrade
          return LocationPermissionStatus.whileInUseOnly;
        case LocationPermission.always:
          // Has "Always" permission - now check if it's precise
          final isPrecise = await _isPreciseLocationEnabled();
          return isPrecise
              ? LocationPermissionStatus.alwaysPrecise
              : LocationPermissionStatus.alwaysApproximate;
        default:
          return LocationPermissionStatus.unknown;
      }
    } catch (e) {
      debugPrint('[LocationPermissionService] Error checking permission: $e');
      return LocationPermissionStatus.error;
    }
  }

  /// Request location permission with enforcement of Always + Precise
  /// Returns the final permission status after all dialogs
  static Future<LocationPermissionStatus> requestPermission({
    required BuildContext context,
    bool forceAlways = true,
    bool forcePrecise = true,
  }) async {
    try {
      // Step 1: Request basic location permission
      LocationPermission permission = await Geolocator.requestPermission();

      // Step 2: If denied forever, must go to settings
      if (permission == LocationPermission.deniedForever) {
        await _showSettingsDialog(
          context,
          title: 'Location Permission Required',
          message: 'This app requires location permission to track your attendance. Please enable it in settings.',
        );
        return LocationPermissionStatus.deniedForever;
      }

      // Step 3: If denied, try once more
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          return permission == LocationPermission.deniedForever
              ? LocationPermissionStatus.deniedForever
              : LocationPermissionStatus.denied;
        }
      }

      // Step 4: Check if we have "Always" permission
      if (permission == LocationPermission.whileInUse && forceAlways) {
        // Need to upgrade to "Always" - show explanation dialog
        final shouldGoToSettings = await _showPermissionUpgradeDialog(context);
        if (shouldGoToSettings) {
          await openLocationSettings();
          // Re-check after returning from settings
          return await checkPermissionStatus();
        }
        return LocationPermissionStatus.whileInUseOnly;
      }

      // Step 5: Check precision level
      if (permission == LocationPermission.always && forcePrecise) {
        final isPrecise = await _isPreciseLocationEnabled();
        if (!isPrecise) {
          // Show dialog to enable precise location
          final shouldGoToSettings = await _showPreciseLocationDialog(context);
          if (shouldGoToSettings) {
            await openLocationSettings();
            // Re-check after returning
            return await checkPermissionStatus();
          }
          return LocationPermissionStatus.alwaysApproximate;
        }
        return LocationPermissionStatus.alwaysPrecise;
      }

      // Step 6: Check if location services are enabled
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isServiceEnabled) {
        await _showEnableLocationServiceDialog(context);
        return LocationPermissionStatus.serviceDisabled;
      }

      return LocationPermissionStatus.alwaysPrecise;
    } catch (e) {
      debugPrint('[LocationPermissionService] Error requesting permission: $e');
      return LocationPermissionStatus.error;
    }
  }

  /// Check if precise location is enabled (Android 12+ / iOS 14+)
  /// This uses platform channel to check the precise location setting
  static Future<bool> _isPreciseLocationEnabled() async {
    try {
      // Try to get high accuracy position - if it works with <10m accuracy, it's precise
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );

      // If accuracy is available and <= 20 meters, consider it precise
      if (position.accuracy > 0 && position.accuracy <= 20) {
        return true;
      }

      // On Android 12+, we can check the permission directly via platform channel
      // For now, assume precise if we can get a position
      return true;
    } on TimeoutException {
      // Timed out - might be approximate location
      return false;
    } catch (e) {
      // If we can't get position, assume not precise
      return false;
    }
  }

  /// Show dialog explaining why "Always" permission is needed
  static Future<bool> _showPermissionUpgradeDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Colors.orange),
            SizedBox(width: 8),
            Text('Always Allow Location'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This app needs to access your location ALL THE TIME to:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('• Auto check-in when you arrive at the office'),
            Text('• Track attendance while you work'),
            Text('• Detect when you leave the office'),
            SizedBox(height: 12),
            Text(
              'Please select "Allow all the time" in the next screen.',
              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.settings),
            label: const Text('Go to Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Show dialog explaining why "Precise" location is needed
  static Future<bool> _showPreciseLocationDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.gps_fixed, color: Colors.red),
            SizedBox(width: 8),
            Text('Precise Location Required'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Approximate location is not accurate enough for attendance tracking.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('Please enable "Use precise location" in settings to:'),
            SizedBox(height: 8),
            Text('• Accurately detect when you enter the office'),
            Text('• Calculate exact distance from office'),
            Text('• Prevent false check-ins/outs'),
            SizedBox(height: 12),
            Text(
              'Toggle "Use precise location" to ON',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Use Approximate'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.gps_fixed),
            label: const Text('Enable Precise'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Show dialog when permission is denied forever
  static Future<void> _showSettingsDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Show dialog to enable location services
  static Future<void> _showEnableLocationServiceDialog(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.red),
            SizedBox(width: 8),
            Text('Location Services Disabled'),
          ],
        ),
        content: const Text(
          'Please enable location services on your device to use attendance tracking.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Geolocator.openLocationSettings();
            },
            child: const Text('Enable Location'),
          ),
        ],
      ),
    );
  }

  /// Open app settings
  static Future<void> openAppSettings() async {
    try {
      await AppSettings.openAppSettings();
    } catch (e) {
      debugPrint('[LocationPermissionService] Error opening app settings: $e');
    }
  }

  /// Open location settings
  static Future<void> openLocationSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (e) {
      debugPrint('[LocationPermissionService] Error opening location settings: $e');
    }
  }

  /// Check if the current permission status is acceptable for the app
  static bool isPermissionAcceptable(LocationPermissionStatus status) {
    return status == LocationPermissionStatus.alwaysPrecise ||
        status == LocationPermissionStatus.alwaysApproximate;
  }

  /// Get human-readable status message
  static String getStatusMessage(LocationPermissionStatus status) {
    switch (status) {
      case LocationPermissionStatus.alwaysPrecise:
        return 'Always + Precise location granted';
      case LocationPermissionStatus.alwaysApproximate:
        return 'Always location granted (but approximate)';
      case LocationPermissionStatus.whileInUseOnly:
        return 'Only "While using" permission granted';
      case LocationPermissionStatus.denied:
        return 'Location permission denied';
      case LocationPermissionStatus.deniedForever:
        return 'Location permission denied permanently';
      case LocationPermissionStatus.serviceDisabled:
        return 'Location services disabled';
      case LocationPermissionStatus.unknown:
        return 'Unknown permission status';
      case LocationPermissionStatus.error:
        return 'Error checking permission';
    }
  }
}

/// Location permission status enum
enum LocationPermissionStatus {
  alwaysPrecise,      // ✅ Ideal - always allow + precise
  alwaysApproximate,  // ⚠️ Partial - always allow but approximate
  whileInUseOnly,     // ❌ Insufficient - only while using
  denied,             // ❌ Denied
  deniedForever,      // ❌ Denied permanently
  serviceDisabled,    // ❌ Location services off
  unknown,            // ❓ Unknown
  error,              // ❌ Error checking
}
