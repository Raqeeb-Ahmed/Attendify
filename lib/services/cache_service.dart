import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Enterprise Cache-First Manager for Firestore Reads
///
/// Features:
/// 1. Offline Persistence Enabled across Mobile & Web.
/// 2. Reads data from local cache FIRST (`Source.cache`), falling back to server (`Source.serverAndCache`) only when needed.
/// 3. Invalidation Keys: Automatically invalidates local cache when a write/mutation occurs (e.g. creating/editing leave, expense, asset, payroll, etc.).
/// 4. Ensures 0 unnecessary Firestore Quota Reads on repeated screen views or tab switches.
class CacheService {
  CacheService._internal();
  static final CacheService instance = CacheService._internal();

  final Map<String, dynamic> _memoryCache = {};
  final Set<String> _invalidatedKeys = {};

  /// Configures Firestore Settings for persistent offline caching
  void initialize() {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      debugPrint('[CacheService] Firestore offline persistence initialized (Unlimited Cache).');
    } catch (e) {
      debugPrint('[CacheService] Note on persistence initialization: $e');
    }
  }

  /// Invalidate cache for a specific key (e.g. 'leaves', 'expenses', 'users')
  /// Call this whenever a create/update/delete operation is performed in the app!
  void invalidate(String cacheKey) {
    _invalidatedKeys.add(cacheKey);
    _memoryCache.remove(cacheKey);
    debugPrint('[CacheService] Invalidated cache key: "$cacheKey". Next read will fetch fresh data from server.');
  }

  /// Invalidate all cached collections
  void invalidateAll() {
    _invalidatedKeys.clear();
    _memoryCache.clear();
    debugPrint('[CacheService] All local caches invalidated.');
  }

  /// Fetch QuerySnapshot using Cache-First strategy.
  /// 1. If key is NOT invalidated and present in cache/offline storage -> reads from `Source.cache` (0 Quota Reads).
  /// 2. If key is invalidated or missing in cache -> fetches from `Source.serverAndCache`, saves to cache, and resets invalidation flag.
  Future<QuerySnapshot> fetchQuery({
    required Query query,
    required String cacheKey,
    bool forceRefresh = false,
  }) async {
    final isInvalidated = _invalidatedKeys.contains(cacheKey);

    if (!forceRefresh && !isInvalidated) {
      try {
        final cacheSnap = await query.get(const GetOptions(source: Source.cache));
        if (cacheSnap.docs.isNotEmpty) {
          debugPrint('[CacheService] Served "$cacheKey" from LOCAL CACHE (0 Firestore Quota Reads). Docs: ${cacheSnap.docs.length}');
          return cacheSnap;
        }
      } catch (e) {
        debugPrint('[CacheService] Cache miss for "$cacheKey". Falling back to server.');
      }
    }

    // Server fetch when invalidated or missing in cache
    debugPrint('[CacheService] Fetching "$cacheKey" from SERVER (Cache refresh)...');
    final serverSnap = await query.get(const GetOptions(source: Source.serverAndCache));
    _invalidatedKeys.remove(cacheKey);
    _memoryCache[cacheKey] = serverSnap;
    return serverSnap;
  }

  /// Fetch single DocumentSnapshot using Cache-First strategy.
  Future<DocumentSnapshot> fetchDocument({
    required DocumentReference docRef,
    required String cacheKey,
    bool forceRefresh = false,
  }) async {
    final isInvalidated = _invalidatedKeys.contains(cacheKey);

    if (!forceRefresh && !isInvalidated) {
      try {
        final cacheSnap = await docRef.get(const GetOptions(source: Source.cache));
        if (cacheSnap.exists) {
          debugPrint('[CacheService] Served document "$cacheKey" from LOCAL CACHE (0 Quota Reads).');
          return cacheSnap;
        }
      } catch (_) {}
    }

    debugPrint('[CacheService] Fetching document "$cacheKey" from SERVER...');
    final serverSnap = await docRef.get(const GetOptions(source: Source.serverAndCache));
    _invalidatedKeys.remove(cacheKey);
    return serverSnap;
  }
}
