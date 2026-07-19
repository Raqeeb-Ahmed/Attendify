import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../../utils/app_config.dart';

class LocationMonitorScreen extends StatefulWidget {
  final bool isMobile;
  final VoidCallback? onMenuPressed;
  const LocationMonitorScreen({
    super.key,
    this.isMobile = false,
    this.onMenuPressed,
  });

  @override
  State<LocationMonitorScreen> createState() => _LocationMonitorScreenState();
}

class _LocationMonitorScreenState extends State<LocationMonitorScreen> {
  String? _selectedUid;
  final _db = FirebaseFirestore.instance;
  String _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_selectedDate),
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('users')
          .where('role', whereIn: const ['employee', 'manager'])
          .snapshots(),
      builder: (context, usersSnap) {
        final users = usersSnap.data?.docs ?? [];

        // Auto-select first user if selection is null or not found in list anymore
        if (_selectedUid == null && users.isNotEmpty) {
          _selectedUid = users.first.id;
        } else if (_selectedUid != null &&
            users.isNotEmpty &&
            !users.any((u) => u.id == _selectedUid)) {
          _selectedUid = users.first.id;
        }

        final dropdownWidget = SearchableDropdown(
          users: users,
          selectedUid: _selectedUid,
          onChanged: (val) {
            setState(() {
              _selectedUid = val;
            });
          },
          initialsHelper: _initials,
        );

        final datePickerButton = InkWell(
          onTap: () => _selectDate(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('dd MMM yyyy').format(DateTime.parse(_selectedDate)),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: Color(0xFF6366F1),
                ),
              ],
            ),
          ),
        );

        return Column(
          children: [
            _buildHeader(isMobile, widget.onMenuPressed, dropdownWidget, datePickerButton),
            Expanded(
              child: _selectedUid == null
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_alt_rounded,
                            size: 48,
                            color: Color(0xFF94A3B8),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No employees found',
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    )
                  : _ActiveEmployeeTrackerView(
                      uid: _selectedUid!,
                      today: _selectedDate,
                      isMobile: isMobile,
                    ),
            ),
          ],
        );
      },
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }

  Widget _buildHeader(
    bool isMobile,
    VoidCallback? onMenuPressed,
    Widget dropdownWidget,
    Widget datePickerButton,
  ) {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isToday = _selectedDate == todayStr;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (onMenuPressed != null)
                      IconButton(
                        icon: const Icon(Icons.menu_rounded),
                        onPressed: onMenuPressed,
                      ),
                    const Text(
                      'Location Monitor',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const Spacer(),
                    _buildStatusBadge(isToday),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: dropdownWidget),
                    const SizedBox(width: 8),
                    datePickerButton,
                  ],
                ),
              ],
            )
          : Row(
              children: [
                if (onMenuPressed != null) ...[
                  IconButton(
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: onMenuPressed,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Location Monitor',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Employee geofence status & movement history',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF94A3B8),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                datePickerButton,
                const SizedBox(width: 16),
                Container(width: 240, child: dropdownWidget),
                const SizedBox(width: 16),
                _buildStatusBadge(isToday),
              ],
            ),
    );
  }

  Widget _buildStatusBadge(bool isToday) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: isToday ? const Color(0xFFF0FDF4) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isToday ? const Color(0xFF86EFAC) : const Color(0xFF93C5FD)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: isToday ? const Color(0xFF22C55E) : const Color(0xFF3B82F6)),
          const SizedBox(width: 6),
          Text(
            isToday ? 'LIVE' : 'HISTORY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isToday ? const Color(0xFF16A34A) : const Color(0xFF1D4ED8),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Active Employee Tracker View ──────────────────────────────────────────

class _ActiveEmployeeTrackerView extends StatefulWidget {
  final String uid;
  final String today;
  final bool isMobile;

  const _ActiveEmployeeTrackerView({
    required this.uid,
    required this.today,
    required this.isMobile,
  });

  @override
  State<_ActiveEmployeeTrackerView> createState() =>
      _ActiveEmployeeTrackerViewState();
}

class _ActiveEmployeeTrackerViewState
    extends State<_ActiveEmployeeTrackerView> {
  bool _showTimeline = true;
  List<LatLng>? _cachedRoute;
  List<LatLng>? _lastInputPoints;
  List<LatLng> _lastPoints = [];
  Future<List<LatLng>>? _routeFuture;
  List<LatLng> _routePoints = [];

  bool _isSamePoints(List<LatLng> a, List<LatLng>? b) {
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude)
        return false;
    }
    return true;
  }

  Future<List<LatLng>> _getOSRMRoute(List<LatLng> points) async {
    if (points.length < 2) return points;
    if (_cachedRoute != null && _isSamePoints(points, _lastInputPoints)) {
      return _cachedRoute!;
    }
    _lastInputPoints = List.from(points);
    final coordsString = points
        .map((p) => '${p.longitude},${p.latitude}')
        .join(';');
    final url =
        'https://router.project-osrm.org/route/v1/driving/$coordsString?overview=full&geometries=geojson';

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final geometry = routes[0]['geometry'] as Map?;
          final coordinates = geometry?['coordinates'] as List?;
          if (coordinates != null) {
            _cachedRoute = coordinates.map((c) {
              final lng = (c[0] as num).toDouble();
              final lat = (c[1] as num).toDouble();
              return LatLng(lat, lng);
            }).toList();
            return _cachedRoute!;
          }
        }
      }
    } catch (e) {
      debugPrint('OSRM routing error: $e');
    }
    // Fallback to straight lines
    return points;
  }

  void _updateRouteFuture(List<LatLng> points) {
    if (_routeFuture != null && _isSamePoints(points, _lastPoints)) {
      return;
    }
    _lastPoints = List.from(points);
    _routeFuture = _getOSRMRoute(points).then((resolvedPoints) {
      if (mounted) {
        setState(() {
          _routePoints = resolvedPoints;
        });
      }
      return resolvedPoints;
    });
  }

  @override
  void didUpdateWidget(covariant _ActiveEmployeeTrackerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid || oldWidget.today != widget.today) {
      _cachedRoute = null;
      _lastInputPoints = null;
      _lastPoints = [];
      _routePoints = [];
      _routeFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid;
    final today = widget.today;
    final isMobile = widget.isMobile;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, userSnap) {
        if (!userSnap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF6366F1)),
          );
        }
        final liveUser = userSnap.data!.data() as Map<String, dynamic>? ?? {};
        final perms = liveUser['devicePermissions'] as Map<String, dynamic>?;

        return StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance
              .ref('locations/${uid}_latest')
              .onValue,
          builder: (context, locEventSnap) {
            final locData = locEventSnap.data?.snapshot.value;
            final loc = locData != null
                ? Map<String, dynamic>.from(locData as Map)
                : null;
            final isOnline = _isOnline(loc?['timestamp'] as String?);

            return StreamBuilder<DatabaseEvent>(
              stream: FirebaseDatabase.instance.ref('presence/$uid').onValue,
              builder: (context, hbEventSnap) {
                final hbData = hbEventSnap.data?.snapshot.value;
                final hb = hbData != null
                    ? Map<String, dynamic>.from(hbData as Map)
                    : null;
                final heartOnline = hb?['online'] as bool? ?? false;
                final effectiveOnline = isOnline && heartOnline;

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('locations')
                      .where('userId', isEqualTo: uid)
                      .where(
                        'timestamp',
                        isGreaterThanOrEqualTo: '${today}T00:00:00',
                      )
                      .where(
                        'timestamp',
                        isLessThanOrEqualTo: '${today}T23:59:59',
                      )
                      .orderBy('timestamp', descending: false)
                      .snapshots(),
                  builder: (context, locationsSnap) {
                    final allDocs = locationsSnap.data?.docs ?? [];
                    final todayDocs = allDocs.where((doc) {
                      final ts =
                          (doc.data() as Map<String, dynamic>)['timestamp']
                              as String?;
                      if (ts == null) return false;
                      try {
                        return DateTime.parse(
                          ts,
                        ).toLocal().toString().startsWith(today);
                      } catch (_) {
                        return false;
                      }
                    }).toList();

                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('attendance')
                          .doc('${uid}_$today')
                          .get(),
                      builder: (context, attSnap) {
                        final att =
                            attSnap.data?.data() as Map<String, dynamic>?;
                        final checkIn = att?['checkInTime'] as String?;
                        final checkOut = att?['checkOutTime'] as String?;

                        return Stack(
                          children: [
                            // Base Layer: Map
                            _buildMapWidget(todayDocs, loc, effectiveOnline),

                            // Floating Panel Overlay
                            if (isMobile)
                              _buildMobileFloatingPanel(
                                liveUser,
                                perms,
                                effectiveOnline,
                                loc,
                                checkIn,
                                checkOut,
                                todayDocs,
                              )
                            else
                              _buildDesktopFloatingPanel(
                                liveUser,
                                perms,
                                effectiveOnline,
                                loc,
                                checkIn,
                                checkOut,
                                todayDocs,
                              ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMapWidget(
    List<QueryDocumentSnapshot> sortedDocs,
    Map<String, dynamic>? latestLoc,
    bool effectiveOnline,
  ) {
    var userLat = latestLoc?['lat'] as double?;
    var userLng = latestLoc?['lng'] as double?;

    if (userLat == null || userLng == null || userLat.isNaN || userLng.isNaN) {
      userLat = null;
      userLng = null;
    }

    final centerLat = userLat ?? AppConfig.officeLat;
    final centerLng = userLng ?? AppConfig.officeLng;

    final trailPoints = <LatLng>[];
    final userCircles = <CircleMarker>[];

    for (int i = 0; i < sortedDocs.length; i++) {
      final data = sortedDocs[i].data() as Map<String, dynamic>;
      final lat = data['lat'] as double?;
      final lng = data['lng'] as double?;
      final inside = data['insideRadius'] as bool? ?? false;

      if (lat == null || lng == null || lat.isNaN || lng.isNaN) continue;

      final point = LatLng(lat, lng);
      trailPoints.add(point);

      if (i % 3 == 0 && i < sortedDocs.length - 1) {
        userCircles.add(
          CircleMarker(
            point: point,
            radius: 4,
            color: (inside ? const Color(0xFF22C55E) : const Color(0xFFF97316))
                .withValues(alpha: 0.7),
            borderColor: Colors.white,
            borderStrokeWidth: 1.5,
            useRadiusInMeter: false,
          ),
        );
      }
    }

    _updateRouteFuture(trailPoints);

    if (userLat != null && userLng != null) {
      final point = LatLng(userLat, userLng);
      final inside = latestLoc?['insideRadius'] as bool? ?? false;
      final markerColor = inside
          ? const Color(0xFF22C55E)
          : const Color(0xFFF97316);

      userCircles.add(
        CircleMarker(
          point: point,
          radius: 14,
          color: markerColor.withValues(alpha: 0.25),
          borderColor: markerColor,
          borderStrokeWidth: 3,
          useRadiusInMeter: false,
        ),
      );
      userCircles.add(
        CircleMarker(
          point: point,
          radius: 7,
          color: markerColor,
          borderColor: Colors.white,
          borderStrokeWidth: 2,
          useRadiusInMeter: false,
        ),
      );
    }

    final hasUserLocations =
        sortedDocs.isNotEmpty || (userLat != null && userLng != null);
    final latestTs = latestLoc?['timestamp'] as String?;
    final latestTimeStr = latestTs != null ? _fmtTime(latestTs) : '';
    final latestInside = latestLoc?['insideRadius'] as bool? ?? false;

    return ClipRRect(
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(centerLat, centerLng),
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.attendance.attendo',
              ),
              if (trailPoints.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints.isNotEmpty ? _routePoints : trailPoints,
                      color: const Color(0xFF6366F1).withValues(alpha: 0.7),
                      strokeWidth: 4,
                    ),
                  ],
                ),
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _createGeofenceCircle(
                      AppConfig.officeLat,
                      AppConfig.officeLng,
                      100,
                    ),
                    color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                    borderColor: const Color(0xFF22C55E),
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              CircleLayer(circles: userCircles),
            ],
          ),
          if (hasUserLocations && latestTimeStr.isNotEmpty)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: latestInside
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFF97316),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'LATEST ACTIVE  $latestTimeStr',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopFloatingPanel(
    Map<String, dynamic> user,
    Map<String, dynamic>? perms,
    bool isOnline,
    Map<String, dynamic>? loc,
    String? checkIn,
    String? checkOut,
    List<QueryDocumentSnapshot> todayDocs,
  ) {
    final segments = _buildSegments(todayDocs);
    final locPerm = perms?['location'] as String? ?? 'unknown';
    final notifOk = perms?['notification'] as bool? ?? false;
    final batteryOk = perms?['battery'] as bool? ?? false;
    final syncedAt = _fmtSynced(perms?['lastUpdated'] as String?);

    final status = loc?['status'] as String? ?? 'offline';
    final isAtOffice = loc?['insideRadius'] as bool? ?? false;
    final dist = loc?['distanceFromOffice'] as int?;

    return Positioned(
      top: 16,
      right: 16,
      bottom: 16,
      width: 360,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(
                      0xFF6366F1,
                    ).withValues(alpha: 0.12),
                    child: Text(
                      _initials(user['name'] as String? ?? '?'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user['name'] as String? ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user['email'] as String? ?? '',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _onlineBadge(isOnline),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Current Location',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  _statusBadge(status, isAtOffice, dist),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.security,
                          size: 12,
                          color: Color(0xFF6366F1),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'PERMISSIONS',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                        const Spacer(),
                        if (syncedAt.isNotEmpty)
                          Text(
                            'synced $syncedAt',
                            style: const TextStyle(
                              fontSize: 8,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _permRow(
                          Icons.location_on_rounded,
                          'GPS',
                          _locPermLabel(locPerm),
                          _locPermOk(locPerm),
                        ),
                        const SizedBox(width: 8),
                        _permRow(
                          Icons.notifications_rounded,
                          'Notif',
                          notifOk ? 'OK' : 'Off',
                          notifOk,
                        ),
                        const SizedBox(width: 8),
                        _permRow(
                          Icons.battery_charging_full_rounded,
                          'Battery',
                          batteryOk ? 'Unres' : 'Res',
                          batteryOk,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (checkIn != null)
                    _summaryRow(
                      Icons.login_rounded,
                      'Checked in',
                      _fmtTime(checkIn),
                      const Color(0xFF22C55E),
                    ),
                  if (checkOut != null) ...[
                    const SizedBox(height: 4),
                    _summaryRow(
                      Icons.logout_rounded,
                      'Checked out',
                      _fmtTime(checkOut),
                      const Color(0xFF6366F1),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Text(
                    'MOVEMENT TIMELINE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      _showTimeline
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        setState(() => _showTimeline = !_showTimeline),
                  ),
                ],
              ),
            ),
            if (_showTimeline)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (segments.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'No location data for today',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      )
                    else
                      ...segments.asMap().entries.map((e) {
                        return _TimelineRow(
                          segment: e.value,
                          isLast: e.key == segments.length - 1,
                        );
                      }),
                  ],
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Timeline collapsed. Click arrow to expand.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileFloatingPanel(
    Map<String, dynamic> user,
    Map<String, dynamic>? perms,
    bool isOnline,
    Map<String, dynamic>? loc,
    String? checkIn,
    String? checkOut,
    List<QueryDocumentSnapshot> todayDocs,
  ) {
    final status = loc?['status'] as String? ?? 'offline';
    final isAtOffice = loc?['insideRadius'] as bool? ?? false;
    final dist = loc?['distanceFromOffice'] as int?;

    return Positioned(
      bottom: 12,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(
                    0xFF6366F1,
                  ).withValues(alpha: 0.12),
                  child: Text(
                    _initials(user['name'] as String? ?? '?'),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    user['name'] as String? ?? 'Unknown',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _onlineBadge(isOnline),
                const SizedBox(width: 8),
                _statusBadge(status, isAtOffice, dist),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (checkIn != null)
                  Text(
                    'In: ${_fmtTime(checkIn)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF475569),
                    ),
                  ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.info_outline, size: 12),
                  label: const Text(
                    'View Timeline',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    _showMobileTimelineModal(
                      context,
                      user,
                      perms,
                      isOnline,
                      loc,
                      checkIn,
                      checkOut,
                      todayDocs,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showMobileTimelineModal(
    BuildContext context,
    Map<String, dynamic> user,
    Map<String, dynamic>? perms,
    bool isOnline,
    Map<String, dynamic>? loc,
    String? checkIn,
    String? checkOut,
    List<QueryDocumentSnapshot> todayDocs,
  ) {
    final segments = _buildSegments(todayDocs);
    final locPerm = perms?['location'] as String? ?? 'unknown';
    final notifOk = perms?['notification'] as bool? ?? false;
    final batteryOk = perms?['battery'] as bool? ?? false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        user['name'] as String? ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      _onlineBadge(isOnline),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PERMISSIONS',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _permRow(
                              Icons.location_on_rounded,
                              'GPS',
                              _locPermLabel(locPerm),
                              _locPermOk(locPerm),
                            ),
                            const SizedBox(width: 8),
                            _permRow(
                              Icons.notifications_rounded,
                              'Notif',
                              notifOk ? 'OK' : 'Off',
                              notifOk,
                            ),
                            const SizedBox(width: 8),
                            _permRow(
                              Icons.battery_charging_full_rounded,
                              'Battery',
                              batteryOk ? 'Unres' : 'Res',
                              batteryOk,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'MOVEMENT TIMELINE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (segments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'No location data for today',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    )
                  else
                    ...segments.asMap().entries.map((e) {
                      return _TimelineRow(
                        segment: e.value,
                        isLast: e.key == segments.length - 1,
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── Formatting helpers ──────────────────────────────────────────

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }

  bool _isOnline(String? timestamp) {
    if (timestamp == null) {
      return false;
    }
    try {
      final t = DateTime.parse(timestamp);
      return DateTime.now().difference(t).inMinutes < 5;
    } catch (_) {
      return false;
    }
  }

  String _fmtTime(String iso) {
    try {
      return DateFormat('hh:mm a').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }

  String _fmtSynced(String? iso) {
    if (iso == null) return '';
    try {
      final t = DateTime.parse(iso).toLocal();
      return DateFormat('hh:mm a').format(t);
    } catch (_) {
      return '';
    }
  }

  // ─── Custom widget subcomponents ──────────────────────────────────────────

  Widget _onlineBadge(bool isOnline) {
    final color = isOnline ? const Color(0xFF22C55E) : const Color(0xFF94A3B8);
    final label = isOnline ? 'Online' : 'Offline';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status, bool isAtOffice, int? dist) {
    Color bg, fg;
    String label;
    IconData icon;

    if (status == 'present' || isAtOffice) {
      bg = const Color(0xFFF0FDF4);
      fg = const Color(0xFF16A34A);
      label = dist != null ? '${dist}m' : 'At office';
      icon = Icons.domain_verification_rounded;
    } else if (status == 'outside') {
      bg = const Color(0xFFFFF7ED);
      fg = const Color(0xFFEA580C);
      label = dist != null ? '${dist}m away' : 'Outside';
      icon = Icons.directions_walk_rounded;
    } else {
      bg = const Color(0xFFF1F5F9);
      fg = const Color(0xFF64748B);
      label = 'No data';
      icon = Icons.location_off_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _permRow(IconData icon, String label, String value, bool ok) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 12,
                color: ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
          ),
        ],
      ),
    );
  }

  String _locPermLabel(String perm) {
    switch (perm) {
      case 'always':
        return 'Always';
      case 'whileInUse':
        return 'In use';
      default:
        return 'Off';
    }
  }

  bool _locPermOk(String perm) => perm == 'always' || perm == 'whileInUse';

  Widget _summaryRow(IconData icon, String label, String time, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          time,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  List<LatLng> _createGeofenceCircle(
    double lat,
    double lng,
    double radiusInMeters,
  ) {
    const int points = 64;
    const double pi2 = 3.14159265359 * 2;
    const double earthRadius = 6371000;
    final List<LatLng> circlePoints = [];

    if (lat.isNaN || lng.isNaN || radiusInMeters.isNaN || radiusInMeters <= 0) {
      return [LatLng(lat, lng)];
    }

    final double radDist = radiusInMeters / earthRadius;
    final double radLat = lat * 3.14159265359 / 180;
    final double radLng = lng * 3.14159265359 / 180;

    for (int i = 0; i < points; i++) {
      final double angle = (i / points) * pi2;
      final double newRadLat = math.asin(
        math.sin(radLat) * math.cos(radDist) +
            math.cos(radLat) * math.sin(radDist) * math.cos(angle),
      );
      final double newRadLng =
          radLng +
          math.atan2(
            math.sin(angle) * math.sin(radDist) * math.cos(radLat),
            math.cos(radDist) - math.sin(radLat) * math.sin(newRadLat),
          );
      final double newLat = newRadLat * 180 / 3.14159265359;
      final double newLng = newRadLng * 180 / 3.14159265359;
      if (!newLat.isNaN && !newLng.isNaN) {
        circlePoints.add(LatLng(newLat, newLng));
      }
    }
    return circlePoints;
  }

  List<_Segment> _buildSegments(List<QueryDocumentSnapshot> docs) {
    final segments = <_Segment>[];
    if (docs.isEmpty) return segments;

    String? currentStatus;
    DateTime? segStart;
    int? lastDist;

    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      final ts = d['timestamp'] as String?;
      final status = d['status'] as String? ?? 'unknown';
      final inside = d['insideRadius'] as bool? ?? false;
      final dist = d['distanceFromOffice'] as int?;

      if (ts == null) continue;
      final time = DateTime.parse(ts).toLocal();
      final mappedStatus = (status == 'present' || inside)
          ? 'present'
          : 'outside';

      if (currentStatus == null) {
        currentStatus = mappedStatus;
        segStart = time;
        lastDist = dist;
      } else if (currentStatus != mappedStatus) {
        segments.add(
          _Segment(
            status: currentStatus,
            from: segStart!,
            to: time,
            dist: lastDist,
          ),
        );
        currentStatus = mappedStatus;
        segStart = time;
        lastDist = dist;
      }
    }

    if (currentStatus != null && segStart != null) {
      segments.add(
        _Segment(
          status: currentStatus,
          from: segStart,
          to: DateTime.now(),
          dist: lastDist,
          isOngoing: true,
        ),
      );
    }

    return segments.reversed.toList();
  }
}

// ─── Timeline helper models and widgets ──────────────────────────────────────────

class _Segment {
  final String status;
  final DateTime from;
  final DateTime to;
  final int? dist;
  final bool isOngoing;

  _Segment({
    required this.status,
    required this.from,
    required this.to,
    this.dist,
    this.isOngoing = false,
  });

  Duration get duration => to.difference(from);
}

class _TimelineRow extends StatelessWidget {
  final _Segment segment;
  final bool isLast;

  const _TimelineRow({required this.segment, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final isAtOffice = segment.status == 'present';
    final color = isAtOffice
        ? const Color(0xFF22C55E)
        : const Color(0xFFF97316);
    final bg = isAtOffice ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7ED);
    final label = isAtOffice ? 'At office' : 'Outside office';
    final icon = isAtOffice
        ? Icons.domain_verification_rounded
        : Icons.directions_walk_rounded;
    final durationStr = _fmtDur(segment.duration);
    final fromStr = DateFormat('hh:mm a').format(segment.from);
    final toStr = segment.isOngoing
        ? 'now'
        : DateFormat('hh:mm a').format(segment.to);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, size: 14, color: color),
            ),
            if (!isLast)
              Container(width: 2, height: 32, color: Colors.grey.shade200),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                          if (segment.isOngoing) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'ongoing',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$fromStr → $toStr',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  durationStr,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) {
      return '${h}h ${m}m';
    }
    if (m > 0) {
      return '${m}m';
    }
    return '<1m';
  }
}

// ─── Custom Searchable Dropdown Overlay ──────────────────────────────────────

class SearchableDropdown extends StatefulWidget {
  final List<QueryDocumentSnapshot> users;
  final String? selectedUid;
  final ValueChanged<String> onChanged;
  final String Function(String) initialsHelper;

  const SearchableDropdown({
    super.key,
    required this.users,
    required this.selectedUid,
    required this.onChanged,
    required this.initialsHelper,
  });

  @override
  State<SearchableDropdown> createState() => _SearchableDropdownState();
}

class _SearchableDropdownState extends State<SearchableDropdown> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _hideOverlay();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleOverlay() {
    if (_isOpen) {
      _hideOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            onTap: _hideOverlay,
            behavior: HitTestBehavior.translucent,
            child: Container(),
          ),
          Positioned(
            width: size.width,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(0, size.height + 4),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
                shadowColor: Colors.black.withValues(alpha: 0.1),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(this.context).size.height * 0.35,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(fontSize: 13),
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                            });
                            _overlayEntry?.markNeedsBuild();
                          },
                          decoration: InputDecoration(
                            hintText: 'Search employee...',
                            hintStyle: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                            ),
                            prefixIcon: const Icon(
                              Icons.search,
                              size: 16,
                              color: Color(0xFF64748B),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF6366F1),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      Flexible(
                        child: StatefulBuilder(
                          builder: (context, setOverlayState) {
                            final filtered = widget.users.where((u) {
                              final data = u.data() as Map<String, dynamic>;
                              final name = (data['name'] as String? ?? '')
                                  .toLowerCase();
                              final email = (data['email'] as String? ?? '')
                                  .toLowerCase();
                              return name.contains(
                                    _searchQuery.toLowerCase(),
                                  ) ||
                                  email.contains(_searchQuery.toLowerCase());
                            }).toList();

                            if (filtered.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Text(
                                  'No employees found',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              );
                            }

                            return ListView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final u = filtered[index];
                                final data = u.data() as Map<String, dynamic>;
                                final name =
                                    data['name'] as String? ?? 'Unknown';
                                final isSelected = u.id == widget.selectedUid;

                                return InkWell(
                                  onTap: () {
                                    widget.onChanged(u.id);
                                    _hideOverlay();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    color: isSelected
                                        ? const Color(0xFFEEF2FF)
                                        : Colors.transparent,
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 11,
                                          backgroundColor: isSelected
                                              ? const Color(0xFF6366F1)
                                              : const Color(
                                                  0xFF6366F1,
                                                ).withValues(alpha: 0.12),
                                          child: Text(
                                            widget.initialsHelper(name),
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected
                                                  ? Colors.white
                                                  : const Color(0xFF6366F1),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                              color: const Color(0xFF1E293B),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(
                                            Icons.check,
                                            size: 14,
                                            color: Color(0xFF6366F1),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() {
      _isOpen = true;
    });
  }

  void _hideOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
    if (mounted) {
      setState(() {
        _isOpen = false;
        _searchQuery = '';
        _searchController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String currentName = 'Select Employee';
    for (var u in widget.users) {
      if (u.id == widget.selectedUid) {
        final data = u.data() as Map<String, dynamic>;
        currentName = data['name'] as String? ?? 'Unknown';
        break;
      }
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggleOverlay,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: const Color(
                  0xFF6366F1,
                ).withValues(alpha: 0.12),
                child: Text(
                  widget.initialsHelper(currentName),
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  currentName,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1E293B),
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                _isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                color: const Color(0xFF64748B),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
