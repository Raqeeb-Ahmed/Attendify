import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'attendance_service.dart';

/// Service to handle local location caching and synchronization when offline.
/// Saves location coordinates to a local JSON file and syncs them in batches to Firestore.
/// After syncing, replays each cached record chronologically through the centralized
/// AttendanceService to reconstruct pixel-perfect inside/outside/extra/offline metrics.
class OfflineLocationService {
  static final OfflineLocationService _instance = OfflineLocationService._internal();
  factory OfflineLocationService() => _instance;
  OfflineLocationService._internal();

  static const String _cacheFileName = 'offline_locations.json';

  /// Get reference to local cache file
  Future<File> _getCacheFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_cacheFileName');
  }

  /// Check if the device is currently online
  Future<bool> _isDeviceOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return !results.contains(ConnectivityResult.none) && results.isNotEmpty;
    } catch (e) {
      debugPrint('[OfflineLocationService] Connectivity check error: $e');
      return false;
    }
  }

  /// Get the number of currently cached locations
  Future<int> getCachedLocationsCount() async {
    try {
      final file = await _getCacheFile();
      if (!await file.exists()) return 0;

      final contents = await file.readAsString();
      if (contents.trim().isEmpty) return 0;

      final List<dynamic> list = jsonDecode(contents);
      return list.length;
    } catch (e) {
      debugPrint('[OfflineLocationService] Error reading cache count: $e');
      return 0;
    }
  }

  /// Cache a single location coordinate to the local JSON file
  Future<void> cacheLocation(Map<String, dynamic> locationData) async {
    try {
      final file = await _getCacheFile();
      List<dynamic> list = [];

      if (await file.exists()) {
        final contents = await file.readAsString();
        if (contents.trim().isNotEmpty) {
          list = jsonDecode(contents);
        }
      }

      // Append new location data with an offline flag
      final Map<String, dynamic> cachedData = Map<String, dynamic>.from(locationData);
      cachedData['offlineCaptured'] = true;
      
      // Ensure the timestamp exists
      if (cachedData['timestamp'] == null) {
        cachedData['timestamp'] = DateTime.now().toIso8601String();
      }

      list.add(cachedData);

      // Write updated list back to file
      await file.writeAsString(jsonEncode(list), flush: true);
      debugPrint('[OfflineLocationService] Location cached locally. Total cached: ${list.length}');
    } catch (e) {
      debugPrint('[OfflineLocationService] Failed to cache location: $e');
    }
  }

  /// Synchronize all cached offline locations to Firestore in batches,
  /// then replay them chronologically through the centralized time-tracking
  /// service to reconstruct accurate inside/outside/extra/offline metrics.
  Future<void> syncCachedLocations(String userId) async {
    try {
      final file = await _getCacheFile();
      if (!await file.exists()) return;

      final contents = await file.readAsString();
      if (contents.trim().isEmpty) return;

      final List<dynamic> list = jsonDecode(contents);
      if (list.isEmpty) return;

      // Only proceed if online
      final bool online = await _isDeviceOnline();
      if (!online) {
        debugPrint('[OfflineLocationService] Offline - skipping batch synchronization');
        return;
      }

      debugPrint('[OfflineLocationService] 🔄 Online! Syncing ${list.length} cached location(s) to Firestore...');

      final db = FirebaseFirestore.instance;
      final collection = db.collection('locations');
      
      // Split into chunks of 400 documents to satisfy Firestore transaction limit (max 500)
      final List<List<dynamic>> chunks = [];
      for (var i = 0; i < list.length; i += 400) {
        chunks.add(list.sublist(i, i + 400 > list.length ? list.length : i + 400));
      }

      for (final chunk in chunks) {
        final batch = db.batch();

        for (final item in chunk) {
          final Map<String, dynamic> data = Map<String, dynamic>.from(item);
          // Mark as successfully synced offline location
          data['isOfflineCached'] = true;
          data['syncedAt'] = DateTime.now().toIso8601String();

          final docRef = collection.doc();
          batch.set(docRef, data);
        }

        await batch.commit();
      }

      debugPrint('[OfflineLocationService] ✅ Batch committed ${list.length} locations');

      // ── Chronological Offline Playback ────────────────────────────────────
      // Sort by original capture timestamp (ascending) so intervals are
      // reconstructed in the correct order.
      final sortedRecords = List<Map<String, dynamic>>.from(
        list.map((item) => Map<String, dynamic>.from(item)),
      );
      sortedRecords.sort((a, b) {
        final aTs = a['timestamp'] as String? ?? '';
        final bTs = b['timestamp'] as String? ?? '';
        return aTs.compareTo(bTs);
      });

      final attendanceService = AttendanceService();

      for (final record in sortedRecords) {
        try {
          final timestampStr = record['timestamp'] as String?;
          if (timestampStr == null) continue;

          final captureTime = DateTime.parse(timestampStr);
          final isInsideRadius = record['insideRadius'] as bool? ?? false;

          // Derive the attendance date from the capture timestamp (yyyy-MM-dd)
          final dateStr = '${captureTime.year}-${captureTime.month.toString().padLeft(2, '0')}-${captureTime.day.toString().padLeft(2, '0')}';

          await attendanceService.updateTimeTracking(
            userId,
            captureTime,
            isInsideRadius,
            timestampStr,
            overrideAttendanceDate: dateStr,
            forceWrite: true,
          );
        } catch (e) {
          debugPrint('[OfflineLocationService] Playback error for record: $e');
          // Continue with next record — don't break the entire playback
        }
      }

      debugPrint('[OfflineLocationService] ✅ Metrics playback complete for ${sortedRecords.length} records');

      // Clear the local cache file after successful commit and playback
      if (await file.exists()) {
        await file.delete();
      }
      
      debugPrint('[OfflineLocationService] ✅ Successfully synced ${list.length} locations to Firestore');
    } catch (e) {
      debugPrint('[OfflineLocationService] ❌ Sync failed: $e');
    }
  }

  /// Clear all cached locations manually (useful on logout)
  Future<void> clearCache() async {
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        await file.delete();
        debugPrint('[OfflineLocationService] Local cache cleared');
      }
    } catch (e) {
      debugPrint('[OfflineLocationService] Failed to clear cache: $e');
    }
  }
}
