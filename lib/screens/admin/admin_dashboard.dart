import 'package:attendenceapp/screens/admin/announcements_screen.dart';
import 'package:attendenceapp/screens/admin/assets_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/app_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../../services/attendance_service.dart';
import '../../services/work_manager_service.dart';
import '../../services/foreground_tracking_service.dart';
import '../../services/background_checkin_service.dart';
import '../../services/device_permission_service.dart';
import 'admin_sidebar.dart';
import 'employee_list_panel.dart';
import 'leave_management_screen.dart';
import 'stats_cards_row.dart';
import 'employee_management_screen.dart';
import 'admin_attendance_screen.dart';
import 'payroll_screen.dart';
import 'performance_management_screen.dart';
import 'document_management_screen.dart';
import 'expense_management_screen.dart';
import 'hr_analytics_screen.dart';
import 'location_monitor_screen.dart';
import '../common/notifications_screen.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedNavIndex = 0;
  final MapController _mapController = MapController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AttendanceService _attendanceService = AttendanceService();
  final NotificationService _notificationService = NotificationService();

  String _userRole = 'admin';

  late final double _officeLat;
  late final double _officeLng;
  late String _selectedDate;

  @override
  void initState() {
    super.initState();
    _officeLat = AppConfig.officeLat;
    _officeLng = AppConfig.officeLng;
    _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (doc.exists && mounted) {
        final role = doc.data()?['role'] ?? 'admin';
        setState(() {
          _userRole = role;
        });
        if (role == 'manager') {
          _startManagerBackgroundTracking();
        }
      }
    }
  }

  Future<void> _startManagerBackgroundTracking() async {
    if (kIsWeb) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await WorkManagerService.initialize();
      ForegroundTrackingService.initialize();

      final backgroundService = BackgroundCheckInService();
      await backgroundService.startAllServices(
        userId: user.uid,
        userName: user.displayName ?? 'Manager',
        email: user.email ?? '',
        department: 'Management',
      );

      await DevicePermissionService.syncToFirestore(user.uid);
      _attendanceService.startHeartbeat(user.uid);

      debugPrint(
        '[Manager Dashboard] Silence background attendance tracking initialized successfully',
      );
    } catch (e) {
      debugPrint('[Manager Dashboard] Silence background tracking error: $e');
    }
  }

  @override
  void dispose() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && _userRole == 'manager') {
      _attendanceService.stopHeartbeat(uid);
      _attendanceService.cancelAutoCheckoutTimer();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_selectedDate),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF6366F1)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDate = DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  static const int _notificationsIndex = 10;
  int _prevNavIndex = 0;

  void _openNotifications() {
    _prevNavIndex = _selectedNavIndex;
    setState(() => _selectedNavIndex = _notificationsIndex);
  }

  void _closeNotifications() {
    setState(() => _selectedNavIndex = _prevNavIndex);
  }

  Widget _buildScreenForIndex(bool isMobile) {
    final safeIndex = _selectedNavIndex >= 13 ? 0 : _selectedNavIndex;
    return IndexedStack(
      index: safeIndex,
      children: [
        _AdminDashboardHome(
          selectedDate: _selectedDate,
          officeLat: _officeLat,
          officeLng: _officeLng,
          mapController: _mapController,
          attendanceService: _attendanceService,
          isMobile: isMobile,
          onMenuPressed: _openDrawer,
          notificationService: _notificationService,
          onDatePick: _pickDate,
          onBroadcast: _showBroadcastDialog,
          onExportCSV: _exportCSV,
          scaffoldKey: _scaffoldKey,
          onOpenNotifications: _openNotifications,
          onNavigate: (index) => setState(() => _selectedNavIndex = index),
          userRole: _userRole,
        ),
        _userRole == 'manager'
            ? const SizedBox.shrink()
            : LocationMonitorScreen(
                isMobile: isMobile,
                onMenuPressed: _openDrawer,
              ),
        EmployeeManagementScreen(
          isMobile: isMobile,
          onMenuPressed: _openDrawer,
        ),
        AdminAttendanceScreen(
          selectedDate: _selectedDate,
          isMobile: isMobile,
          onMenuPressed: _openDrawer,
        ),
        LeaveManagementScreen(isMobile: isMobile, onMenuPressed: _openDrawer),
        PayrollScreen(isMobile: isMobile, onMenuPressed: _openDrawer),
        PerformanceManagementScreen(
          isMobile: isMobile,
          onMenuPressed: _openDrawer,
        ),
        DocumentManagementScreen(
          isMobile: isMobile,
          onMenuPressed: _openDrawer,
        ),
        ExpenseManagementScreen(isMobile: isMobile, onMenuPressed: _openDrawer),
        HRAnalyticsScreen(isMobile: isMobile, onMenuPressed: _openDrawer),
        NotificationsScreen(onBack: _closeNotifications),
        AnnouncementsScreen(isMobile: isMobile, onMenuPressed: _openDrawer),
        AssetsManagementScreen(isMobile: isMobile, onMenuPressed: _openDrawer),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    return PopScope(
      canPop: _selectedNavIndex != _notificationsIndex,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedNavIndex == _notificationsIndex) {
          _closeNotifications();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFF8F9FC),
        drawer: isMobile
            ? Drawer(
                child: AdminSidebar(
                  selectedIndex: _selectedNavIndex,
                  onItemSelected: (i) {
                    setState(() => _selectedNavIndex = i);
                    Navigator.pop(context);
                  },
                  userRole: _userRole,
                ),
              )
            : null,
        body: SafeArea(
          child: Row(
            children: [
              if (!isMobile)
                AdminSidebar(
                  selectedIndex: _selectedNavIndex,
                  onItemSelected: (index) =>
                      setState(() => _selectedNavIndex = index),
                  userRole: _userRole,
                ),
              Expanded(
                child: Stack(
                  children: [
                    _buildScreenForIndex(isMobile),
                    if (isMobile &&
                        _selectedNavIndex != 0 &&
                        _selectedNavIndex != _notificationsIndex)
                      Positioned(
                        bottom: 20,
                        left: 20,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF6366F1,
                                ).withValues(alpha: 0.3),
                                blurRadius: 12,
                                spreadRadius: 2,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Material(
                              color: const Color(0xFF6366F1),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedNavIndex = 0;
                                  });
                                },
                                child: const SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Icon(
                                    Icons.home_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showBroadcastDialog() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String selectedType = 'announcement';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text(
            'Broadcast Notification',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Type',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  items: const [
                    DropdownMenuItem(
                      value: 'announcement',
                      child: Text(
                        'Announcement',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'attendance',
                      child: Text('Attendance', style: TextStyle(fontSize: 13)),
                    ),
                    DropdownMenuItem(
                      value: 'payroll',
                      child: Text('Payroll', style: TextStyle(fontSize: 13)),
                    ),
                    DropdownMenuItem(
                      value: 'warning',
                      child: Text('Warning', style: TextStyle(fontSize: 13)),
                    ),
                    DropdownMenuItem(
                      value: 'general',
                      child: Text('General', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                  onChanged: (v) => setS(() => selectedType = v!),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      borderSide: BorderSide(color: Color(0xFF6366F1)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Title',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    hintText: 'Notification title...',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      borderSide: BorderSide(color: Color(0xFF6366F1)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Message',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: bodyCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Message body...',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      borderSide: BorderSide(color: Color(0xFF6366F1)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
              ),
              icon: const Icon(
                Icons.send_rounded,
                size: 16,
                color: Colors.white,
              ),
              label: const Text(
                'Broadcast',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                await NotificationService().broadcastToAll(
                  title: titleCtrl.text.trim(),
                  body: bodyCtrl.text.trim(),
                  type: selectedType,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Broadcast sent to all users'),
                      backgroundColor: Color(0xFF22C55E),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCSV() async {
    try {
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: const ['employee', 'manager'])
          .get();
      final attSnap = await FirebaseFirestore.instance
          .collection('attendance')
          .where('date', isEqualTo: _selectedDate)
          .get();
      // Filter locations query by selected date in Firestore to save reads
      final locSnap = await FirebaseFirestore.instance
          .collection('locations')
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: '${_selectedDate}T00:00:00',
          )
          .where('timestamp', isLessThanOrEqualTo: '${_selectedDate}T23:59:59')
          .get();

      // Read heartbeats (presence) from Realtime Database to save Firestore reads
      final hbSnap = await FirebaseDatabase.instance.ref('presence').get();
      final hbData = hbSnap.value as Map<dynamic, dynamic>? ?? {};

      final attMap = <String, Map<String, dynamic>>{};
      for (var doc in attSnap.docs) {
        final d = doc.data();
        attMap[d['userId'] as String? ?? ''] = d;
      }
      final locMap = <String, Map<String, dynamic>>{};
      for (var doc in locSnap.docs) {
        final d = doc.data();
        final uid = d['userId'] as String? ?? '';
        if (!locMap.containsKey(uid)) locMap[uid] = d;
      }
      final hbMap = <String, Map<String, dynamic>>{};
      hbData.forEach((key, val) {
        if (val != null) {
          final d = Map<String, dynamic>.from(val as Map);
          hbMap[key.toString()] = d;
        }
      });

      final buffer = StringBuffer();
      buffer.writeln(
        'Name,Email,Status,Online,Check-In,Check-Out,Inside(min),Outside(min),Offline(min),Extra(min),Lat,Lng',
      );

      for (var userDoc in usersSnap.docs) {
        final u = userDoc.data();
        final uid = userDoc.id;
        final att = attMap[uid];
        final loc = locMap[uid];
        final hb = hbMap[uid];

        final name = (u['name'] as String? ?? '').replaceAll(',', '');
        final email = u['email'] as String? ?? '';
        final status = att?['status'] as String? ?? 'pending';
        final online = hb?['online'] == true ? 'Yes' : 'No';
        final checkIn = att?['checkInTime'] as String? ?? '';
        final checkOut = att?['checkOutTime'] as String? ?? '';
        final inside = att?['insideTime']?.toString() ?? '0';
        final outside = att?['outsideTime']?.toString() ?? '0';
        final offline = att?['offlineTime']?.toString() ?? '0';
        final extra = att?['extraHours']?.toString() ?? '0';
        final lat = loc?['lat']?.toString() ?? '';
        final lng = loc?['lng']?.toString() ?? '';

        buffer.writeln(
          '"$name","$email","$status","$online","$checkIn","$checkOut",$inside,$outside,$offline,$extra,"$lat","$lng"',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'CSV data ready for $_selectedDate (${usersSnap.docs.length} employees)',
            ),
            backgroundColor: const Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _AdminDashboardHome extends StatefulWidget {
  final String selectedDate;
  final double officeLat;
  final double officeLng;
  final MapController mapController;
  final AttendanceService attendanceService;
  final bool isMobile;
  final VoidCallback? onMenuPressed;
  final NotificationService notificationService;
  final VoidCallback onDatePick;
  final VoidCallback onBroadcast;
  final VoidCallback onExportCSV;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final VoidCallback onOpenNotifications;
  final ValueChanged<int> onNavigate;
  final String userRole;

  const _AdminDashboardHome({
    required this.selectedDate,
    required this.officeLat,
    required this.officeLng,
    required this.mapController,
    required this.attendanceService,
    required this.isMobile,
    this.onMenuPressed,
    required this.notificationService,
    required this.onDatePick,
    required this.onBroadcast,
    required this.onExportCSV,
    required this.onOpenNotifications,
    required this.scaffoldKey,
    required this.onNavigate,
    required this.userRole,
  });

  @override
  State<_AdminDashboardHome> createState() => _AdminDashboardHomeState();
}

class _AdminDashboardHomeState extends State<_AdminDashboardHome>
    with AutomaticKeepAliveClientMixin {
  String _selectedFilter = 'ALL';
  EmployeeMapData? _selectedMarkerEmployee;
  final Map<String, bool> _updatingLeaves = {};
  final Map<String, bool> _updatingUsers = {};

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: const ['employee', 'manager'])
          .snapshots(),
      builder: (context, usersSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('attendance')
              .where('date', isEqualTo: widget.selectedDate)
              .snapshots(),
          builder: (context, attendanceSnap) {
            return StreamBuilder<DatabaseEvent>(
              stream: widget.attendanceService.getHeartbeats(),
              builder: (context, heartbeatSnapshot) {
                return StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance.ref('locations').onValue,
                  builder: (context, locationsSnapshot) {
                    return Column(
                      children: [
                        _buildTopBar(),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.all(widget.isMobile ? 16 : 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                StatsCardsRow(
                                  isMobile: widget.isMobile,
                                  selectedDate: widget.selectedDate,
                                  selectedFilter: _selectedFilter,
                                  onFilterChanged: (filter) {
                                    setState(() {
                                      _selectedFilter = filter;
                                    });
                                  },
                                  usersSnapshot: usersSnap.data,
                                  heartbeatSnapshot: heartbeatSnapshot.data,
                                  attendanceSnapshot: attendanceSnap.data,
                                ),
                                const SizedBox(height: 24),
                                if (widget.userRole == 'manager') ...[
                                  _buildManagerPersonalTrackingCard(),
                                ],
                                _buildQuickAccess(),
                                const SizedBox(height: 24),
                                _buildWorkforceHealth(usersSnap.data, attendanceSnap.data),
                                _buildPendingUserApprovals(),
                                _buildPendingLeavesApprovals(),
                                const SizedBox(height: 24),
                                _buildMainContent(
                                  usersSnap.data,
                                  attendanceSnap.data,
                                  heartbeatSnapshot.data,
                                  locationsSnapshot.data,
                                ),
                              ],
                            ),
                          ),
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
  }

  Widget _buildQuickAccess() {
    final items = [
      if (widget.userRole != 'manager')
        {
          'icon': Icons.location_on_rounded,
          'title': 'Location Monitor',
          'subtitle': 'Live tracking map',
          'color': const Color(0xFF6366F1),
          'index': 1,
        },
      {
        'icon': Icons.people_rounded,
        'title': 'Employees',
        'subtitle': 'Staff directory',
        'color': const Color(0xFF10B981),
        'index': 2,
      },
      {
        'icon': Icons.event_note_rounded,
        'title': 'Attendance Logs',
        'subtitle': 'Timesheets & lates',
        'color': const Color(0xFFF59E0B),
        'index': 3,
      },
      {
        'icon': Icons.check_circle_outline,
        'title': 'Leave Approvals',
        'subtitle': 'Review requests',
        'color': const Color(0xFFEC4899),
        'index': 4,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Navigation',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 600;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isNarrow ? 2 : items.length,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: isNarrow ? 1.45 : 1.75,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final color = item['color'] as Color;
                return InkWell(
                  onTap: () => widget.onNavigate(item['index'] as int),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            item['icon'] as IconData,
                            color: color,
                            size: 20,
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title'] as String,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item['subtitle'] as String,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF94A3B8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    final isMobile = widget.isMobile;
    final selectedDate = widget.selectedDate;
    final isToday =
        selectedDate == DateFormat('yyyy-MM-dd').format(DateTime.now());
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 32,
        vertical: isMobile ? 12 : 16,
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
              onPressed: () => widget.scaffoldKey.currentState?.openDrawer(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          if (isMobile) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        widget.userRole == 'manager'
                            ? 'Manager Dashboard'
                            : 'Admin Dashboard',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isMobile ? 16 : 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                      ),
                    ],
                    if (widget.userRole == 'manager') ...[
                      const SizedBox(width: 8),
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('attendance')
                            .doc(
                              '${FirebaseAuth.instance.currentUser?.uid}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                            )
                            .snapshots(),
                        builder: (context, snap) {
                          if (!snap.hasData || !snap.data!.exists) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFFCA5A5),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.login_rounded,
                                    size: 10,
                                    color: Color(0xFFEF4444),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'NOT CHECKED IN',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          final data =
                              snap.data!.data() as Map<String, dynamic>?;
                          final checkIn = data?['checkInTime'] as String?;
                          final checkOut = data?['checkOutTime'] as String?;

                          String statusStr = 'CHECKED IN';
                          Color statusColor = const Color(0xFF16A34A);
                          Color bgColor = const Color(0xFFF0FDF4);
                          Color borderColor = const Color(0xFF86EFAC);
                          IconData statusIcon = Icons.login_rounded;

                          if (checkIn != null) {
                            try {
                              final dt = DateTime.parse(checkIn).toLocal();
                              statusStr =
                                  'IN: ${DateFormat('hh:mm a').format(dt)}';
                            } catch (_) {}
                          }

                          if (checkOut != null) {
                            try {
                              final dt = DateTime.parse(checkOut).toLocal();
                              statusStr =
                                  'OUT: ${DateFormat('hh:mm a').format(dt)}';
                            } catch (_) {}
                            statusColor = const Color(0xFFF97316);
                            bgColor = const Color(0xFFFFF7ED);
                            borderColor = const Color(0xFFFED7AA);
                            statusIcon = Icons.logout_rounded;
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: 10, color: statusColor),
                                const SizedBox(width: 4),
                                Text(
                                  statusStr,
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
                if (!isMobile) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Real-time workforce monitoring & location tracking',
                    style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  ),
                ],
              ],
            ),
          ),
          if (!isMobile) ...[
            OutlinedButton.icon(
              onPressed: widget.onExportCSV,
              icon: const Icon(Icons.download, size: 16),
              label: const Text(
                'Export CSV',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6366F1),
                side: const BorderSide(color: Color(0xFF6366F1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: widget.onBroadcast,
              icon: const Icon(
                Icons.campaign_rounded,
                color: Color(0xFF6366F1),
              ),
            ),
            const SizedBox(width: 4),
          ],
          RepaintBoundary(
            child: StreamBuilder<int>(
              stream: widget.notificationService.streamUnreadCount(
                FirebaseAuth.instance.currentUser?.uid ?? 'admin',
              ),
              builder: (ctx, snap) {
                final count = snap.data ?? 0;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      onPressed: widget.onOpenNotifications,
                      icon: const Icon(
                        Icons.notifications_outlined,
                        color: Color(0xFF475569),
                      ),
                      padding: isMobile
                          ? EdgeInsets.zero
                          : const EdgeInsets.all(8),
                      constraints: isMobile ? const BoxConstraints() : null,
                    ),
                    if (count > 0)
                      Positioned(
                        right: isMobile ? -4 : 6,
                        top: isMobile ? -4 : 6,
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
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onDatePick,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 8 : 14,
                vertical: isMobile ? 8 : 10,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10),
                color: Colors.white,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isMobile
                        ? DateFormat(
                            'dd MMM',
                          ).format(DateTime.parse(widget.selectedDate))
                        : DateFormat(
                            'dd MMM yyyy',
                          ).format(DateTime.parse(widget.selectedDate)),
                    style: TextStyle(
                      fontSize: isMobile ? 12 : 13,
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.calendar_today_rounded,
                    size: isMobile ? 12 : 14,
                    color: const Color(0xFF6366F1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManagerPersonalTrackingCard() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('attendance')
          .doc('${uid}_$todayStr')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final exists = snap.data!.exists;
        final data = exists ? snap.data!.data() as Map<String, dynamic>? : null;

        final checkIn = data?['checkInTime'] as String?;
        final checkOut = data?['checkOutTime'] as String?;
        final status = (data?['status'] as String? ?? 'N/A').toUpperCase();

        final insideMinsVal = (data?['insideTime'] as num?)?.toInt() ?? 0;
        final outsideMins = (data?['outsideTime'] as num?)?.toInt() ?? 0;
        final offlineMins = (data?['offlineTime'] as num?)?.toInt() ?? 0;
        final insideMins = insideMinsVal + offlineMins;
        final totalHours = (data?['totalHours'] as num?)?.toDouble() ?? 0.0;

        String checkInText = '--:--';
        if (checkIn != null) {
          try {
            final dt = DateTime.parse(checkIn).toLocal();
            checkInText = DateFormat('hh:mm a').format(dt);
          } catch (_) {}
        }

        String checkOutText = '--:--';
        if (checkOut != null) {
          try {
            final dt = DateTime.parse(checkOut).toLocal();
            checkOutText = DateFormat('hh:mm a').format(dt);
          } catch (_) {}
        }

        Color statusColor = const Color(0xFF94A3B8);
        Color statusBg = const Color(0xFFF1F5F9);
        if (status == 'PRESENT') {
          statusColor = const Color(0xFF16A34A);
          statusBg = const Color(0xFFF0FDF4);
        } else if (status == 'LATE') {
          statusColor = const Color(0xFFD97706);
          statusBg = const Color(0xFFFFFBEB);
        } else if (status == 'OUTSIDE') {
          statusColor = const Color(0xFFEA580C);
          statusBg = const Color(0xFFFFF5F1);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFEEF2FF)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.badge_rounded,
                        color: Color(0xFF6366F1),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'My Attendance Tracking Today',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      exists ? status : 'NOT LOGGED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final tileList = [
                    _buildTrackingStatTile(
                      Icons.login_rounded,
                      'Check In',
                      checkInText,
                      const Color(0xFF10B981),
                    ),
                    _buildTrackingStatTile(
                      Icons.logout_rounded,
                      'Check Out',
                      checkOutText,
                      const Color(0xFFF59E0B),
                    ),
                    _buildTrackingStatTile(
                      Icons.work_history_rounded,
                      'Working Hours',
                      '${totalHours.toStringAsFixed(1)} hrs',
                      const Color(0xFF6366F1),
                    ),
                  ];

                  final isNarrow = constraints.maxWidth < 480;

                  if (isNarrow) {
                    return Column(
                      children: [
                        tileList[0],
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        const SizedBox(height: 12),
                        tileList[1],
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        const SizedBox(height: 12),
                        tileList[2],
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: tileList[0]),
                      Container(
                        height: 32,
                        width: 1,
                        color: const Color(0xFFE2E8F0),
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      Expanded(child: tileList[1]),
                      Container(
                        height: 32,
                        width: 1,
                        color: const Color(0xFFE2E8F0),
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      Expanded(child: tileList[2]),
                    ],
                  );
                },
              ),
              if (exists) ...[
                const SizedBox(height: 18),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 14),
                const Text(
                  'Office Bound Log Summary',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _buildDurationLabel(
                      'Office Boundary',
                      insideMins,
                      const Color(0xFF10B981),
                    ),
                    _buildDurationLabel(
                      'Outside Boundary',
                      outsideMins,
                      const Color(0xFFEA580C),
                    ),
                    _buildDurationLabel(
                      'Offline / Inactive',
                      offlineMins,
                      const Color(0xFF64748B),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTrackingStatTile(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDurationLabel(String label, int mins, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ${mins ~/ 60}h ${mins % 60}m',
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildWorkforceHealth(QuerySnapshot? usersSnap, QuerySnapshot? attSnap) {
    if (usersSnap == null || attSnap == null) {
      return const SizedBox.shrink();
    }
    final totalEmployees = usersSnap.docs.length;
    final attDocs = attSnap.docs;
    int presentCount = 0, lateCount = 0, outsideCount = 0;
    for (var doc in attDocs) {
      final status =
          (doc.data() as Map<String, dynamic>)['status'] as String? ??
          '';
      if (status == 'present') {
        presentCount++;
      } else if (status == 'late') {
        lateCount++;
      } else if (status == 'outside') {
        outsideCount++;
      }
    }
    final pendingCount = totalEmployees - attDocs.length;
    final inOfficePct = totalEmployees > 0
        ? (presentCount + lateCount) / totalEmployees
        : 0.0;
    final outsidePct = totalEmployees > 0
        ? outsideCount / totalEmployees
        : 0.0;
    final pendingPct = totalEmployees > 0
        ? pendingCount / totalEmployees
        : 0.0;
    final outOfSystem = outsideCount;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.isMobile) ...[
            Row(
              children: [
                const Icon(
                  Icons.bar_chart_rounded,
                  color: Color(0xFF475569),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Workforce Health',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _healthLegend(
                  const Color(0xFF22C55E),
                  'In Office ${(inOfficePct * 100).round()}%',
                ),
                _healthLegend(
                  const Color(0xFFF97316),
                  'Outside ${(outsidePct * 100).round()}%',
                ),
                _healthLegend(
                  const Color(0xFFCBD5E1),
                  'Pending ${(pendingPct * 100).round()}%',
                ),
              ],
            ),
          ] else
            Row(
              children: [
                const Icon(
                  Icons.bar_chart_rounded,
                  color: Color(0xFF475569),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Workforce Health',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Wrap(
                    spacing: 12,
                    children: [
                      _healthLegend(
                        const Color(0xFF22C55E),
                        'In Office ${(inOfficePct * 100).round()}%',
                      ),
                      _healthLegend(
                        const Color(0xFFF97316),
                        'Outside ${(outsidePct * 100).round()}%',
                      ),
                      _healthLegend(
                        const Color(0xFFCBD5E1),
                        'Pending ${(pendingPct * 100).round()}%',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  if (inOfficePct > 0)
                    Expanded(
                      flex: (inOfficePct * 100).round(),
                      child: Container(color: const Color(0xFF22C55E)),
                    ),
                  if (outsidePct > 0)
                    Expanded(
                      flex: (outsidePct * 100).round(),
                      child: Container(color: const Color(0xFFF97316)),
                    ),
                  if (pendingPct > 0)
                    Expanded(
                      flex: (pendingPct * 100).round(),
                      child: Container(color: const Color(0xFFCBD5E1)),
                    ),
                  if (inOfficePct == 0 &&
                      outsidePct == 0 &&
                      pendingPct == 0)
                    Expanded(
                      child: Container(color: const Color(0xFFCBD5E1)),
                    ),
                ],
              ),
            ),
          ),
          if (outOfSystem > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: Color(0xFFEA580C),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$outOfSystem employee(s) are active online but outside the office.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFEA580C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _healthLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildPendingUserApprovals() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('approved', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint(
            'Firestore error loading pending user approvals: ${snapshot.error}',
          );
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Error loading pending approvals: ${snapshot.error}',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(
                  Icons.person_add_rounded,
                  color: Color(0xFF6366F1),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Pending Account Approvals',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${docs.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFD97706),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final docId = doc.id;
                final name = data['name'] ?? 'Unknown';
                final email = data['email'] ?? '';

                return Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  color: Colors.white,
                  child: InkWell(
                    onTap: () => widget.onNavigate(
                      2,
                    ), // Redirects to Employee Management
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(
                              0xFF6366F1,
                            ).withValues(alpha: 0.1),
                            child: Text(
                              _getInitials(name),
                              style: const TextStyle(
                                color: Color(0xFF6366F1),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  email,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _updatingUsers[docId] == true && _updatingUsers[docId + '_rejected'] == true
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFEF4444),
                                      ),
                                    )
                                  : IconButton(
                                      onPressed: _updatingUsers[docId] == true
                                          ? null
                                          : () => _rejectUser(docId, name),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        color: Color(0xFFEF4444),
                                      ),
                                      style: IconButton.styleFrom(
                                        backgroundColor: const Color(0xFFFEF2F2),
                                        padding: const EdgeInsets.all(8),
                                      ),
                                    ),
                              const SizedBox(width: 8),
                              _updatingUsers[docId] == true && _updatingUsers[docId + '_approved'] == true
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF22C55E),
                                      ),
                                    )
                                  : IconButton(
                                      onPressed: _updatingUsers[docId] == true
                                          ? null
                                          : () => _approveUser(docId, name),
                                      icon: const Icon(
                                        Icons.check_rounded,
                                        color: Color(0xFF22C55E),
                                      ),
                                      style: IconButton.styleFrom(
                                        backgroundColor: const Color(0xFFF0FDF4),
                                        padding: const EdgeInsets.all(8),
                                      ),
                                    ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildPendingLeavesApprovals() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('leaves')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(
                  Icons.beach_access_rounded,
                  color: Color(0xFF6366F1),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Pending Leave Requests',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${docs.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFD97706),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final docId = doc.id;
                final employeeName = data['employeeName'] ?? 'Unknown';
                final leaveType = data['leaveType'] ?? 'Leave';
                final days = data['days'] ?? 1;
                final reason = data['reason'] ?? 'No reason';
                final startDate = _formatDate(data['startDate']);
                final endDate = _formatDate(data['endDate']);

                return Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  color: Colors.white,
                  child: InkWell(
                    onTap: () => widget.onNavigate(4),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(
                              0xFF6366F1,
                            ).withValues(alpha: 0.1),
                            child: Text(
                              _getInitials(employeeName),
                              style: const TextStyle(
                                color: Color(0xFF6366F1),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  employeeName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$leaveType • $days ${days == 1 ? 'day' : 'days'} ($startDate - $endDate)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Reason: $reason',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF475569),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _updatingLeaves[docId] == true && _updatingLeaves[docId + '_rejected'] == true
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFEF4444),
                                      ),
                                    )
                                  : IconButton(
                                      onPressed: _updatingLeaves[docId] == true
                                          ? null
                                          : () => _updateLeaveStatus(docId, 'rejected'),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        color: Color(0xFFEF4444),
                                      ),
                                      style: IconButton.styleFrom(
                                        backgroundColor: const Color(0xFFFEF2F2),
                                        padding: const EdgeInsets.all(8),
                                      ),
                                    ),
                              const SizedBox(width: 8),
                              _updatingLeaves[docId] == true && _updatingLeaves[docId + '_approved'] == true
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF22C55E),
                                      ),
                                    )
                                  : IconButton(
                                      onPressed: _updatingLeaves[docId] == true
                                          ? null
                                          : () => _updateLeaveStatus(docId, 'approved'),
                                      icon: const Icon(
                                        Icons.check_rounded,
                                        color: Color(0xFF22C55E),
                                      ),
                                      style: IconButton.styleFrom(
                                        backgroundColor: const Color(0xFFF0FDF4),
                                        padding: const EdgeInsets.all(8),
                                      ),
                                    ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
  }

  String _formatDate(dynamic date) {
    if (date == null) return '--';
    if (date is Timestamp) return DateFormat('MMM d').format(date.toDate());
    if (date is String) {
      try {
        return DateFormat('MMM d').format(DateTime.parse(date));
      } catch (_) {
        return date;
      }
    }
    return '--';
  }

  Future<void> _updateLeaveStatus(String docId, String status) async {
    if (_updatingLeaves[docId] == true) return;
    setState(() {
      _updatingLeaves[docId] = true;
      _updatingLeaves[docId + '_' + status] = true;
    });
    try {
      await FirebaseFirestore.instance.collection('leaves').doc(docId).update({
        'status': status,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      // Fetch recipient details to send push notification
      final leaveSnap = await FirebaseFirestore.instance
          .collection('leaves')
          .doc(docId)
          .get();
      if (leaveSnap.exists) {
        final leaveData = leaveSnap.data();
        final userId = leaveData?['userId'] as String?;
        if (userId != null) {
          final userSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();
          if (userSnap.exists) {
            final userData = userSnap.data();
            final tokens = List<String>.from(userData?['fcmTokens'] ?? []);
            if (tokens.isNotEmpty) {
              await PushNotificationService.instance.sendPushNotification(
                recipientTokens: tokens,
                title: 'Leave Request Update',
                body: 'Your leave request has been $status.',
              );
            }
          }

          // Save in notifications collection in database
          await FirebaseFirestore.instance.collection('notifications').add({
            'userId': userId,
            'title': 'Leave Request Update',
            'body': 'Your leave request has been $status.',
            'type': 'leave',
            'data': {'leaveId': docId},
            'read': false,
            'createdAt': DateTime.now().toIso8601String(),
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Leave $status'),
            backgroundColor: status == 'approved'
                ? const Color(0xFF22C55E)
                : const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update leave: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _updatingLeaves[docId] = false;
          _updatingLeaves[docId + '_' + status] = false;
        });
      }
    }
  }

  Future<void> _approveUser(String docId, String name) async {
    if (_updatingUsers[docId] == true) return;
    setState(() {
      _updatingUsers[docId] = true;
      _updatingUsers[docId + '_approved'] = true;
    });
    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'approved': true,
      });

      // Send approval notification
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(docId)
          .get();
      if (userSnap.exists) {
        final userData = userSnap.data();
        final tokens = List<String>.from(userData?['fcmTokens'] ?? []);
        if (tokens.isNotEmpty) {
          await PushNotificationService.instance.sendPushNotification(
            recipientTokens: tokens,
            title: 'Account Approved',
            body:
                'Congratulations! Your account has been approved by the Admin.',
          );
        }

        // Save in notifications collection in database
        await FirebaseFirestore.instance.collection('notifications').add({
          'userId': docId,
          'title': 'Account Approved',
          'body':
              'Congratulations! Your account has been approved by the Admin.',
          'type': 'approval',
          'data': {},
          'read': false,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name approved successfully!'),
            backgroundColor: const Color(0xFF22C55E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Approval failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _updatingUsers[docId] = false;
          _updatingUsers[docId + '_approved'] = false;
        });
      }
    }
  }

  Future<void> _rejectUser(String docId, String name) async {
    if (_updatingUsers[docId] == true) return;
    setState(() {
      _updatingUsers[docId] = true;
      _updatingUsers[docId + '_rejected'] = true;
    });
    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name registration rejected & deleted!'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rejection failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _updatingUsers[docId] = false;
          _updatingUsers[docId + '_rejected'] = false;
        });
      }
    }
  }

  Widget _buildMainContent(
    QuerySnapshot? usersSnap,
    QuerySnapshot? attendanceSnap,
    DatabaseEvent? heartbeatSnapshot,
    DatabaseEvent? locationsSnapshot,
  ) {
    final List<EmployeeMapData> employees = [];
    final colors = [
      const Color(0xFF8B5CF6),
      const Color(0xFF14B8A6),
      const Color(0xFF6366F1),
      const Color(0xFFF97316),
      const Color(0xFFEC4899),
      const Color(0xFF06B6D4),
      const Color(0xFF10B981),
      const Color(0xFFF43F5E),
    ];
    final userDocs = usersSnap?.docs ?? [];
    
    final locData = locationsSnapshot?.snapshot.value as Map<dynamic, dynamic>? ?? {};
    final List<Map<String, dynamic>> locations = [];
    locData.forEach((key, val) {
      if (val != null) {
        final map = Map<String, dynamic>.from(val as Map);
        final timestamp = map['timestamp'] as String?;
        if (timestamp != null && timestamp.startsWith(widget.selectedDate)) {
          locations.add(map);
        }
      }
    });

    final hbData =
        heartbeatSnapshot?.snapshot.value
            as Map<dynamic, dynamic>? ??
        {};
    final hbMap = <String, Map<String, dynamic>>{};
    hbData.forEach((key, val) {
      if (val != null) {
        hbMap[key.toString()] = Map<String, dynamic>.from(
          val as Map,
        );
      }
    });
    final locMap = <String, Map<String, dynamic>>{};
    for (var loc in locations) {
      final userId = loc['userId'] as String?;
      if (userId != null) locMap[userId] = loc;
    }

    // Build attendance status map from Firestore check-in documents
    final attDocs = attendanceSnap?.docs ?? [];
    final attMap = <String, String>{};
    for (var doc in attDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final uId = data['userId'] as String?;
      final stat = data['status'] as String?;
      if (uId != null && stat != null) {
        attMap[uId] = stat;
      }
    }

    int i = 0;
    for (var userDoc in userDocs) {
      final userData = userDoc.data() as Map<String, dynamic>;
      final userId = userDoc.id;
      final hb = hbMap[userId];
      final loc = locMap[userId];
      final isOnline = hb?['online'] == true;
      final checkInStatus = attMap[userId];

      employees.add(
        EmployeeMapData(
          name: userData['name'] as String? ?? 'Unknown',
          email: userData['email'] as String? ?? '',
          lat:
              (loc?['lat'] as num?)?.toDouble() ??
              widget.officeLat,
          lng:
              (loc?['lng'] as num?)?.toDouble() ??
              widget.officeLng,
          status: _mapStatus(
            checkInStatus,
            isOnline,
            loc?['insideRadius'],
          ),
          avatarColor: colors[i % colors.length],
          isOnline: isOnline,
          distance: (loc?['distanceFromOffice'] as num?)
              ?.toInt(),
          userId: userId,
        ),
      );
      i++;
    }

    final List<EmployeeMapData> filteredEmployees;
    switch (_selectedFilter) {
      case 'PRESENT':
        filteredEmployees = employees
            .where((e) => e.status == EmployeeStatus.present)
            .toList();
        break;
      case 'LATE':
        filteredEmployees = employees
            .where((e) => e.status == EmployeeStatus.late_)
            .toList();
        break;
      case 'OUT_OF_SYSTEM':
        filteredEmployees = employees
            .where((e) => e.status == EmployeeStatus.outside)
            .toList();
        break;
      case 'OFFLINE':
        filteredEmployees = employees
            .where(
              (e) =>
                  !e.isOnline ||
                  (e.status != EmployeeStatus.present &&
                      e.status != EmployeeStatus.late_),
            )
            .toList();
        break;
      case 'ONLINE':
        filteredEmployees = employees
            .where(
              (e) =>
                  e.isOnline &&
                  (e.status == EmployeeStatus.present ||
                      e.status == EmployeeStatus.late_),
            )
            .toList();
        break;
      case 'IN_OFFICE':
        filteredEmployees = employees
            .where(
              (e) =>
                  e.status == EmployeeStatus.present ||
                  (e.status == EmployeeStatus.late_ &&
                      e.distance != null &&
                      e.distance! <= 100),
            )
            .toList();
        break;
      default:
        filteredEmployees = employees;
        break;
    }

    final bool isManager = widget.userRole == 'manager';

    if (widget.isMobile) {
      return Column(
        children: [
          EmployeeListPanel(
            employees: employees,
            selectedDate: widget.selectedDate,
            activeFilter: _selectedFilter,
            onFilterChanged: (filter) {
              setState(() {
                _selectedFilter = filter;
              });
            },
          ),
          const SizedBox(height: 16),
          _buildLiveMap(filteredEmployees, 300),
        ],
      );
    }

    if (isManager) {
      return EmployeeListPanel(
        employees: employees,
        selectedDate: widget.selectedDate,
        activeFilter: _selectedFilter,
        onFilterChanged: (filter) {
          setState(() {
            _selectedFilter = filter;
          });
        },
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 380,
          child: EmployeeListPanel(
            employees: employees,
            selectedDate: widget.selectedDate,
            activeFilter: _selectedFilter,
            onFilterChanged: (filter) {
              setState(() {
                _selectedFilter = filter;
              });
            },
          ),
        ),
        const SizedBox(width: 24),
        Expanded(child: _buildLiveMap(filteredEmployees, 520)),
      ],
    );
  }

  EmployeeStatus _mapStatus(
    dynamic status,
    bool isOnline,
    dynamic insideRadius,
  ) {
    if (!isOnline) return EmployeeStatus.offline;
    final lowerStatus = (status as String?)?.toLowerCase() ?? '';
    if (lowerStatus == 'late') return EmployeeStatus.late_;
    if (lowerStatus == 'present' || insideRadius == true)
      return EmployeeStatus.present;
    if (lowerStatus == 'outside' || insideRadius == false)
      return EmployeeStatus.outside;
    return EmployeeStatus.pending;
  }

  Widget _buildLiveMap(List<EmployeeMapData> employees, double height) {
    final online = employees.where((e) => e.isOnline).length;
    final inOffice = employees
        .where((e) => e.status == EmployeeStatus.present)
        .length;
    return Container(
      height: height,
      decoration: _cardDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.map_rounded,
                      color: Color(0xFF6366F1),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Live Location Map',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          '${employees.length} employees · $online online · $inOffice in office',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _mapDot(const Color(0xFF22C55E), 'Present'),
                  const SizedBox(width: 10),
                  _mapDot(const Color(0xFFF97316), 'Outside'),
                  const SizedBox(width: 10),
                  _mapDot(const Color(0xFF94A3B8), 'Offline'),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  RepaintBoundary(
                    child: FlutterMap(
                      mapController: widget.mapController,
                      options: MapOptions(
                        initialCenter: LatLng(
                          widget.officeLat,
                          widget.officeLng,
                        ),
                        initialZoom: 15.0,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.attendo.attendance',
                        ),
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: LatLng(widget.officeLat, widget.officeLng),
                              radius: 100,
                              useRadiusInMeter: true,
                              color: const Color(
                                0xFF6366F1,
                              ).withValues(alpha: 0.08),
                              borderColor: const Color(
                                0xFF6366F1,
                              ).withValues(alpha: 0.35),
                              borderStrokeWidth: 2,
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(widget.officeLat, widget.officeLng),
                              width: 44,
                              height: 44,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF6366F1,
                                      ).withValues(alpha: 0.35),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.business,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                            ...employees.map((emp) {
                              final markerColor =
                                  emp.status == EmployeeStatus.present
                                  ? const Color(0xFF22C55E)
                                  : emp.status == EmployeeStatus.late_
                                  ? const Color(0xFFF59E0B)
                                  : emp.status == EmployeeStatus.outside
                                  ? const Color(0xFFF97316)
                                  : const Color(0xFF94A3B8);
                              return Marker(
                                point: LatLng(emp.lat, emp.lng),
                                width: 40,
                                height: 40,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedMarkerEmployee = emp;
                                    });
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: emp.avatarColor,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: markerColor.withValues(
                                            alpha: 0.4,
                                          ),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: Stack(
                                      children: [
                                        Center(
                                          child: Text(
                                            emp.initials,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: emp.isOnline
                                                  ? const Color(0xFF22C55E)
                                                  : const Color(0xFF94A3B8),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_selectedMarkerEmployee != null)
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  _selectedMarkerEmployee!.avatarColor,
                              child: Text(
                                _selectedMarkerEmployee!.initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _selectedMarkerEmployee!.name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color:
                                              _selectedMarkerEmployee!.isOnline
                                              ? const Color(0xFF22C55E)
                                              : const Color(0xFF94A3B8),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _selectedMarkerEmployee!.isOnline
                                            ? 'Online'
                                            : 'Offline',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              _selectedMarkerEmployee!.isOnline
                                              ? const Color(0xFF22C55E)
                                              : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                      if (_selectedMarkerEmployee!.distance !=
                                          null) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          '· ${_selectedMarkerEmployee!.distance}m',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Color(0xFF94A3B8),
                              ),
                              onPressed: () {
                                setState(() {
                                  _selectedMarkerEmployee = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapDot(Color c, String l) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        l,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );

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

enum EmployeeStatus { present, late_, outside, pending, offline }

class EmployeeMapData {
  final String name;
  final String email;
  final double lat;
  final double lng;
  final EmployeeStatus status;
  final Color avatarColor;
  final bool isOnline;
  final int? distance;
  final String userId;

  EmployeeMapData({
    required this.name,
    required this.email,
    required this.lat,
    required this.lng,
    required this.status,
    required this.avatarColor,
    this.isOnline = false,
    this.distance,
    required this.userId,
  });

  String get initials {
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.length >= 2
        ? name.substring(0, 2).toUpperCase()
        : name.toUpperCase();
  }
}
