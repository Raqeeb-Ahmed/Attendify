import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/work_manager_service.dart';
import '../../utils/app_config.dart';
import 'package:intl/intl.dart';
import '../../services/attendance_service.dart';
import '../../services/location_service.dart';
import '../../services/background_location_service.dart';
import '../../services/foreground_tracking_service.dart';
import '../../services/device_permission_service.dart';
import '../../services/wifi_auto_checkin_service.dart';
import '../../services/location_permission_service.dart';
import '../../services/background_checkin_service.dart';
import '../../services/offline_location_service.dart';
import '../../utils/firebase_exception_handler.dart';
import 'employee_sidebar.dart';
import '../common/notifications_screen.dart';
import '../../services/notification_service.dart';
import 'past_attendance_screen.dart';
import 'leave_management_screen.dart';
import 'payslips_screen.dart';
import 'performance_screen.dart';
import 'expenses_screen.dart';
import 'my_learning_screen.dart';
import 'my_documents_screen.dart';
import 'my_profile_screen.dart';
import '../../widgets/monthly_progress_widget.dart';
import '../admin/announcements_screen.dart';
import 'my_assets_screen.dart';

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({super.key});

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard>
    with WidgetsBindingObserver {
  final AttendanceService _attendanceService = AttendanceService();
  final LocationService _locationService = LocationService();
  final BackgroundCheckInService _backgroundService =
      BackgroundCheckInService();
  final user = FirebaseAuth.instance.currentUser;

  int _selectedNavIndex = 0;
  Map<String, dynamic>? _todayData;
  double? _currentLat;
  double? _distanceFromOffice;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final double _officeLat;
  late final double _officeLng;

  int _offlineCount = 0;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeBackgroundServices();
    });
    WidgetsBinding.instance.addObserver(this);
    _officeLat = AppConfig.officeLat;
    _officeLng = AppConfig.officeLng;
    _loadTodayData();
    _loadCurrentLocation();
    _startBackgroundTracking();
    _checkAndSyncOfflineLocations();
  }

  Future<void> _initializeBackgroundServices() async {
    await WorkManagerService.initialize();
    ForegroundTrackingService.initialize();
  }

  Future<void> _checkAndSyncOfflineLocations() async {
    if (user == null) return;
    try {
      final count = await OfflineLocationService().getCachedLocationsCount();
      if (mounted) {
        setState(() {
          _offlineCount = count;
        });
      }
      if (count > 0 && !_isSyncing) {
        if (mounted) {
          setState(() {
            _isSyncing = true;
          });
        }
        await OfflineLocationService().syncCachedLocations(user!.uid);
        final newCount = await OfflineLocationService()
            .getCachedLocationsCount();
        if (mounted) {
          setState(() {
            _offlineCount = newCount;
            _isSyncing = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[Dashboard] Error checking/syncing offline locations: $e');
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && user != null) {
      DevicePermissionService.syncToFirestore(user!.uid);
      _checkAndSyncOfflineLocations();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BackgroundLocationService().stopTracking();
    WiFiAutoCheckInService().stopMonitoring();
    if (user != null) {
      // Only stop heartbeat and auto-checkout timer, but keep location tracking active
      _attendanceService.stopHeartbeat(user!.uid);
      _attendanceService.cancelAutoCheckoutTimer();
    }
    // Note: ForegroundTrackingService keeps running after dispose (by design)
    // Location tracking continues even after check-out for continuous monitoring
    super.dispose();
  }

  void _startBackgroundTracking() async {
    if (user == null) return;

    try {
      // Step 1: Check and enforce Always + Precise location permission
      final permissionStatus =
          await LocationPermissionService.checkPermissionStatus();
      debugPrint('[Dashboard] Initial permission status: $permissionStatus');

      if (!LocationPermissionService.isPermissionAcceptable(permissionStatus)) {
        // Request permission with enforcement
        if (mounted) {
          final newStatus = await LocationPermissionService.requestPermission(
            context: context,
            forceAlways: true,
            forcePrecise: true,
          );
          debugPrint('[Dashboard] After request permission status: $newStatus');

          if (!LocationPermissionService.isPermissionAcceptable(newStatus)) {
            // Permission still not acceptable - show warning
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Location permission is required for auto check-in. Please enable "Always" location permission.',
                  ),
                  duration: Duration(seconds: 5),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }
        }
      }

      // Step 2: Start unified background check-in service
      debugPrint('[Dashboard] Starting unified background check-in service...');

      await _backgroundService.startAllServices(
        userId: user!.uid,
        userName: user!.displayName ?? 'Employee',
        email: user!.email ?? '',
        department: 'N/A', // You can get this from user profile if needed
      );

      debugPrint(
        '[Dashboard] Unified background check-in service started successfully',
      );

      // Step 3: Additional setup
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) await ForegroundTrackingService.requestBatteryExemption();
      await DevicePermissionService.syncToFirestore(user!.uid);

      // Step 4: Check for approximate location and prompt user if needed
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        final needsPrecisePrompt =
            await DevicePermissionService.shouldPromptForPreciseLocation();
        if (needsPrecisePrompt && mounted) {
          _showApproximateLocationDialog();
        }
      }

      debugPrint('[Dashboard] Background tracking initialized successfully');
    } catch (e) {
      debugPrint('Background tracking error: ${getFirebaseErrorMessage(e)}');
    }
  }

  Future<void> _loadTodayData() async {
    if (user == null) return;
    final data = await _attendanceService.fetchTodayAttendance(user!.uid);
    debugPrint("============= TODAY DATA =============");
    debugPrint(data.toString());

    debugPrint(
      "Inside : ${data?['insideTime']}  ${data?['insideTime'].runtimeType}",
    );

    debugPrint(
      "Outside : ${data?['outsideTime']}  ${data?['outsideTime'].runtimeType}",
    );

    debugPrint(
      "Offline : ${data?['offlineTime']}  ${data?['offlineTime'].runtimeType}",
    );

    debugPrint(
      "Extra : ${data?['extraHours']}  ${data?['extraHours'].runtimeType}",
    );

    debugPrint("====================================");

    if (mounted) setState(() => _todayData = data);
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final pos = await _locationService.getCurrentLocation();
      if (mounted) {
        final dist = _haversine(
          pos.latitude,
          pos.longitude,
          _officeLat,
          _officeLng,
        );
        setState(() {
          _currentLat = pos.latitude;
          _distanceFromOffice = dist;
        });
      }
      await _checkAndSyncOfflineLocations();
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371e3;
    final dLat = (lat2 - lat1) * (3.141592653589793 / 180);
    final dLon = (lon2 - lon1) * (3.141592653589793 / 180);
    final a =
        (dLat / 2) * (dLat / 2) +
        (lat1 * 3.141592653589793 / 180).abs() *
            (lat2 * 3.141592653589793 / 180).abs() *
            (dLon / 2) *
            (dLon / 2);
    return R * 2 * (a < 1 ? a : 1);
  }

  /// Show dialog prompting user to enable precise location
  void _showApproximateLocationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.gps_off, color: Colors.orange),
            SizedBox(width: 8),
            Text('Approximate Location Detected'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your location permission is set to "Approximate" which may cause inaccurate attendance tracking.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 12),
            Text('Please enable "Use precise location" in settings for:'),
            SizedBox(height: 8),
            Text('• Accurate office entry detection'),
            Text('• Reliable distance calculations'),
            Text('• Better attendance tracking'),
            SizedBox(height: 12),
            Text(
              'Settings → Apps → Attendo → Permissions → Location → Use precise location',
              style: TextStyle(color: Colors.blue, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              LocationPermissionService.openAppSettings();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Helper to format minutes into display string
  String formatMins(dynamic val) {
    final minutes = (val as num?)?.round() ?? 0;

    final hours = minutes ~/ 60;
    final mins = minutes % 60;

    return '${hours}h ${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(now);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final isTablet = screenWidth >= 768 && screenWidth < 1100;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8F9FC),
      drawer: isMobile
          ? Drawer(
              child: EmployeeSidebar(
                selectedIndex: _selectedNavIndex,
                onItemSelected: (i) {
                  setState(() => _selectedNavIndex = i);
                },
                userName: user?.displayName ?? 'Employee',
              ),
            )
          : null,
      body: SafeArea(
        child: Row(
          children: [
            if (!isMobile)
              EmployeeSidebar(
                selectedIndex: _selectedNavIndex,
                onItemSelected: (i) => setState(() => _selectedNavIndex = i),
                userName: user?.displayName ?? 'Employee',
              ),
            Expanded(child: _buildPageForIndex(dateStr, isMobile, isTablet)),
          ],
        ),
      ),
    );
  }

  Widget _buildPageForIndex(String dateStr, bool isMobile, bool isTablet) {
    Widget page;
    switch (_selectedNavIndex) {
      case 1:
        page = const PastAttendanceScreen();
        break;
      case 2:
        page = const LeaveManagementScreen();
        break;
      case 3:
        page = const PayslipsScreen();
        break;
      case 4:
        page = const PerformanceScreen();
        break;
      case 5:
        page = const ExpensesScreen();
        break;
      case 6:
        page = const MyLearningScreen();
        break;
      case 7:
        page = const MyDocumentsScreen();
        break;
      case 8:
        page = const MyProfileScreen();
        break;
      case 9:
        page = const AnnouncementsScreen();
        break;
      case 10:
        page = const MyAssetsScreen();
        break;
      default:
        return Column(
          children: [
            _buildTopBar(dateStr, isMobile),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isMobile ? 16 : 24),
                child: isMobile || isTablet
                    ? _buildMobileLayout()
                    : _buildDesktopLayout(),
              ),
            ),
          ],
        );
    }

    // On mobile, sub-screens don't have drawer access — overlay a menu button
    if (isMobile) {
      return Stack(
        children: [
          page,
          Positioned(
            top: 8,
            left: 4,
            child: SafeArea(
              child: Material(
                color: Colors.transparent,
                child: IconButton(
                  icon: const Icon(
                    Icons.menu_rounded,
                    color: Color(0xFF475569),
                  ),
                  // tooltip: 'Menu',
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return page;
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Column(
            children: [
              _buildTodaySummary(),
              const SizedBox(height: 20),
              _buildTrackingStatus(),
              const SizedBox(height: 20),
              MonthlyProgressWidget(
                userId: user!.uid,
                selectedMonth: DateTime.now(),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(flex: 6, child: _buildAttendanceLog()),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildTodaySummary(),
        const SizedBox(height: 16),
        _buildTrackingStatus(),
        const SizedBox(height: 16),
        MonthlyProgressWidget(userId: user!.uid, selectedMonth: DateTime.now()),
        const SizedBox(height: 16),
        _buildAttendanceLog(),
      ],
    );
  }

  Widget _buildTopBar(String dateStr, bool isMobile) {
    final bool isCheckedIn =
        _todayData != null && _todayData!['checkInTime'] != null;
    final bool isCheckedOut =
        _todayData != null && _todayData!['checkOutTime'] != null;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
        vertical: 16,
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
      child: Row(
        children: [
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attendance Dashboard',
                  style: TextStyle(
                    fontSize: isMobile ? 18 : 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: isMobile ? 11 : 13,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
                if (isMobile) ...[
                  const SizedBox(height: 8),
                  _buildStatusBadge(isCheckedIn, isCheckedOut),
                ],
              ],
            ),
          ),
          _buildSyncBadge(),
          const SizedBox(width: 8),
          // Notification bell with unread badge
          if (user != null)
            StreamBuilder<int>(
              stream: NotificationService().streamUnreadCount(user!.uid),
              builder: (ctx, snap) {
                final count = snap.data ?? 0;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      ),
                      icon: const Icon(
                        Icons.notifications_outlined,
                        color: Color(0xFF475569),
                      ),
                      // tooltip: 'Notifications',
                    ),
                    if (count > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          if (!isMobile) ...[
            const SizedBox(width: 12),
            _buildStatusBadge(isCheckedIn, isCheckedOut),
          ],
        ],
      ),
    );
  }

  Widget _buildSyncBadge() {
    if (_offlineCount > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 14, color: Color(0xFFEF4444)),
            const SizedBox(width: 4),
            Text(
              '$_offlineCount Unsynced',
              style: const TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else if (_isSyncing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFC7D2FE)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Color(0xFF6366F1),
              ),
            ),
            SizedBox(width: 6),
            Text(
              'Syncing...',
              style: TextStyle(
                color: Color(0xFF6366F1),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_done, size: 14, color: Color(0xFF22C55E)),
            SizedBox(width: 4),
            Text(
              'Synced',
              style: TextStyle(
                color: Color(0xFF22C55E),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildStatusBadge(bool isCheckedIn, bool isCheckedOut) {
    if (!isCheckedIn) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFDBA74), width: 1.5),
        ),
        child: const Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            Icon(Icons.wifi_rounded, size: 16, color: Color(0xFFEA580C)),
            Text(
              'Auto check-in on WiFi',
              style: TextStyle(
                color: Color(0xFFEA580C),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    } else if (!isCheckedOut) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
        ),
        child: const Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF16A34A)),
            Text(
              'Auto checkout 6 PM',
              style: TextStyle(
                color: Color(0xFF16A34A),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
        ),
        child: const Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            Icon(Icons.check_circle, size: 16, color: Color(0xFF16A34A)),
            Text(
              'Completed',
              style: TextStyle(
                color: Color(0xFF16A34A),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildTodaySummary() {
    final checkInTime = _todayData?['checkInTime'] as String?;
    final checkOutTime = _todayData?['checkOutTime'] as String?;
    final status = _todayData?['status'] ?? 'pending';
    final checkInStr = checkInTime != null
        ? _formatIsoTime(checkInTime)
        : '--:--';
    final checkOutStr = checkOutTime != null
        ? _formatIsoTime(checkOutTime)
        : '--:--';

    debugPrint(
      "Inside : ${_todayData?['insideTime']} "
      "${_todayData?['insideTime'].runtimeType}",
    );

    debugPrint(
      "Outside : ${_todayData?['outsideTime']} "
      "${_todayData?['outsideTime'].runtimeType}",
    );

    debugPrint(
      "Offline : ${_todayData?['offlineTime']} "
      "${_todayData?['offlineTime'].runtimeType}",
    );

    debugPrint(
      "Extra : ${_todayData?['extraHours']} "
      "${_todayData?['extraHours'].runtimeType}",
    );
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's Summary",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _summaryBlock(
                  'CHECK IN',
                  checkInStr,
                  const Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _summaryBlock(
                  'CHECK OUT',
                  checkOutStr,
                  const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text(
                'Status',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const Spacer(),
              _statusBadge(status),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
          ),
          const Text(
            'TIME ALLOCATION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          _timeRow(
            'Inside Office',
            formatMins((_todayData?['insideTime'] ?? 0) + (_todayData?['offlineTime'] ?? 0)),
            const Color(0xFF22C55E),
          ),
          _timeRow(
            'Outside',
            formatMins(_todayData?['outsideTime'] ?? 0),
            const Color(0xFFF97316),
          ),
          _timeRow(
            'Offline/Idle',
            formatMins(_todayData?['offlineTime'] ?? 0),
            const Color(0xFF94A3B8),
          ),
          _timeRow(
            'Extra Hours',
            formatMins(_todayData?['extraHours'] ?? 0),
            const Color(0xFF6366F1),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final lowerStatus = status.toLowerCase();
    Color bg, fg;
    if (lowerStatus == 'present') {
      bg = const Color(0xFFF0FDF4);
      fg = const Color(0xFF16A34A);
    } else if (lowerStatus == 'late') {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFD97706);
    } else if (lowerStatus == 'outside') {
      bg = const Color(0xFFFEF2F2);
      fg = const Color(0xFFDC2626);
    } else {
      bg = const Color(0xFFF1F5F9);
      fg = const Color(0xFF64748B);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  String _formatIsoTime(String isoTime) {
    try {
      final dateTime = DateTime.parse(isoTime);
      return DateFormat('hh:mm a').format(dateTime);
    } catch (e) {
      return '--:--';
    }
  }

  Widget _summaryBlock(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeRow(String label, String display, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF475569),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            display,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingStatus() {
    final isCheckedIn =
        _todayData != null && _todayData!['checkInTime'] != null;
    final isCheckedOut =
        _todayData != null && _todayData!['checkOutTime'] != null;
    final isActive = isCheckedIn && !isCheckedOut;

    final dist = _distanceFromOffice;
    final isAtOffice = dist != null && dist <= 100;

    Color dotColor;
    String statusLabel;
    String subLabel;
    Color cardBg;

    final isAutoCheckedOut =
        _todayData != null && _todayData!['sessionStatus'] == 'auto-checkout';

    if (isAutoCheckedOut) {
      dotColor = const Color(0xFF8B5CF6);
      statusLabel = 'Session ended';
      subLabel = 'Auto checked-out at 6 PM';
      cardBg = const Color(0xFFF5F3FF);
    } else if (!isActive) {
      dotColor = const Color(0xFF94A3B8);
      statusLabel = 'Awaiting check-in';
      subLabel = 'Will auto check-in when you reach office WiFi';
      cardBg = const Color(0xFFF8FAFC);
    } else if (isAtOffice) {
      dotColor = const Color(0xFF22C55E);
      statusLabel = 'At the office';
      subLabel = '${dist.round()}m from office';
      cardBg = const Color(0xFFF0FDF4);
    } else {
      dotColor = const Color(0xFFF97316);
      statusLabel = 'Outside office';
      subLabel = dist != null ? '${dist.round()}m from office' : 'Locating...';
      cardBg = const Color(0xFFFFF7ED);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dotColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dotColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isAutoCheckedOut
                  ? Icons.check_circle_rounded
                  : isActive
                  ? (isAtOffice
                        ? Icons.domain_verification_rounded
                        : Icons.directions_walk_rounded)
                  : Icons.wifi_rounded,
              color: dotColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: dotColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.shield_rounded,
                        size: 13,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Session running in background',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_offlineCount > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        _isSyncing ? Icons.sync : Icons.cloud_off,
                        size: 13,
                        color: _isSyncing
                            ? const Color(0xFF6366F1)
                            : const Color(0xFFEF4444),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isSyncing
                            ? 'Syncing $_offlineCount offline locations...'
                            : '$_offlineCount locations cached offline',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _isSyncing
                              ? const Color(0xFF6366F1)
                              : const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ] else if (_isSyncing) ...[
                  const SizedBox(height: 6),
                  const Row(
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Syncing offline locations...',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (_currentLat != null)
            IconButton(
              icon: const Icon(
                Icons.refresh_rounded,
                size: 20,
                color: Color(0xFF6366F1),
              ),
              // tooltip: 'Refresh location',
              onPressed: _loadCurrentLocation,
            ),
        ],
      ),
    );
  }

  Widget _buildAttendanceLog() {
    if (user == null) return const Center(child: Text('Not logged in'));
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.access_time,
                      color: Color(0xFF6366F1),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Attendance Log',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFFFAFAFA),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('MMMM yyyy').format(DateTime.now()),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: Color(0xFF94A3B8),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (!isMobile) _logHeaderRow(),
          if (!isMobile) const Divider(height: 1, color: Color(0xFFE2E8F0)),
          StreamBuilder<QuerySnapshot>(
            stream: _attendanceService.getAttendanceHistory(user!.uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.event_note,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No records yet',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: snapshot.data!.docs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  return isMobile ? _logRowMobile(d) : _logRow(d);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _logHeaderRow() {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: Color(0xFF94A3B8),
      letterSpacing: 0.5,
    );
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('DATE', style: style)),
          Expanded(flex: 2, child: Text('IN', style: style)),
          Expanded(flex: 2, child: Text('OUT', style: style)),
          Expanded(flex: 2, child: Text('INSIDE', style: style)),
          Expanded(flex: 2, child: Text('OUTSIDE', style: style)),
          Expanded(flex: 2, child: Text('OFFLINE', style: style)),
          Expanded(flex: 2, child: Text('EXTRA', style: style)),
          Expanded(flex: 1, child: Text('STATUS', style: style)),
        ],
      ),
    );
  }

  Widget _logRow(Map<String, dynamic> d) {
    final checkInTime = d['checkInTime'] as String?;
    final checkOutTime = d['checkOutTime'] as String?;
    final dateStr = d['date'] ?? '--';
    final inStr = checkInTime != null ? _formatIsoTime(checkInTime) : '--';
    final outStr = checkOutTime != null ? _formatIsoTime(checkOutTime) : '--';
    final status = d['status'] ?? 'pending';
    const cellStyle = TextStyle(fontSize: 12, color: Color(0xFF475569));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(dateStr, style: cellStyle)),
          Expanded(flex: 2, child: Text(inStr, style: cellStyle)),
          Expanded(flex: 2, child: Text(outStr, style: cellStyle)),
          Expanded(
            flex: 2,
            child: Text(
              formatMins(((d['insideTime'] as num?)?.toInt() ?? 0) + ((d['offlineTime'] as num?)?.toInt() ?? 0)),
              style: cellStyle.copyWith(color: const Color(0xFF22C55E)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatMins(d['outsideTime']),
              style: cellStyle.copyWith(color: const Color(0xFFF97316)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(formatMins(d['offlineTime']), style: cellStyle),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatMins(d['extraHours']),
              style: cellStyle.copyWith(color: const Color(0xFFEF4444)),
            ),
          ),
          Expanded(flex: 1, child: _statusBadge(status)),
        ],
      ),
    );
  }

  Widget _logRowMobile(Map<String, dynamic> d) {
    final checkInTime = d['checkInTime'] as String?;
    final checkOutTime = d['checkOutTime'] as String?;
    final dateStr = d['date'] ?? '--';
    final inStr = checkInTime != null ? _formatIsoTime(checkInTime) : '--';
    final outStr = checkOutTime != null ? _formatIsoTime(checkOutTime) : '--';
    final status = d['status'] ?? 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateStr,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              _statusBadge(status),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _mobileLogItem('In', inStr),
              _mobileLogItem('Out', outStr),
              _mobileLogItem('Inside', formatMins(((d['insideTime'] as num?)?.toInt() ?? 0) + ((d['offlineTime'] as num?)?.toInt() ?? 0))),
              _mobileLogItem('Outside', formatMins(d['outsideTime'])),
              if ((d['extraHours'] is num) && (d['extraHours'] as num) > 0)
                _mobileLogItem('Extra', formatMins(d['extraHours'])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mobileLogItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }
}
