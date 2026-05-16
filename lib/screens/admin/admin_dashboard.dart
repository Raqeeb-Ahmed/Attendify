import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/app_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/attendance_service.dart';
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

  late final double _officeLat;
  late final double _officeLng;
  late String _selectedDate;

  @override
  void initState() {
    super.initState();
    _officeLat = AppConfig.officeLat;
    _officeLng = AppConfig.officeLng;
    _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
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

  Widget _buildScreenForIndex(bool isMobile) {
    switch (_selectedNavIndex) {
      case 1:
        return LocationMonitorScreen(isMobile: isMobile, onMenuPressed: _openDrawer);
      case 2:
        return EmployeeManagementScreen(isMobile: isMobile, onMenuPressed: _openDrawer);
      case 3:
        return AdminAttendanceScreen(selectedDate: _selectedDate, isMobile: isMobile, onMenuPressed: _openDrawer);
      case 4:
        return LeaveManagementScreen(isMobile: isMobile, onMenuPressed: _openDrawer);
      case 5:
        return PayrollScreen(isMobile: isMobile, onMenuPressed: _openDrawer);
      case 6:
        return PerformanceManagementScreen(isMobile: isMobile, onMenuPressed: _openDrawer);
      case 7:
        return DocumentManagementScreen(isMobile: isMobile, onMenuPressed: _openDrawer);
      case 8:
        return ExpenseManagementScreen(isMobile: isMobile, onMenuPressed: _openDrawer);
      case 9:
        return HRAnalyticsScreen(isMobile: isMobile, onMenuPressed: _openDrawer);
      default:
        return _buildLocationMonitor();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    return Scaffold(
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
              ),
            )
          : null,
      body: SafeArea(
        child: Row(
          children: [
            if (!isMobile)
              AdminSidebar(
                selectedIndex: _selectedNavIndex,
                onItemSelected: (index) => setState(() => _selectedNavIndex = index),
              ),
            Expanded(child: _buildScreenForIndex(isMobile)),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationMonitor() {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return Column(
      children: [
        _buildTopBar(isMobile),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatsCardsRow(isMobile: isMobile, selectedDate: _selectedDate),
                const SizedBox(height: 20),
                _buildWorkforceHealth(),
                const SizedBox(height: 20),
                _buildMainContent(isMobile),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(bool isMobile) {
    final isToday = _selectedDate == DateFormat('yyyy-MM-dd').format(DateTime.now());
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          if (isMobile)
            IconButton(icon: const Icon(Icons.menu_rounded), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text('Admin Dashboard',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: isMobile ? 18 : 24, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                    ),
                    const SizedBox(width: 12),
                    if (isToday)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 8, color: Color(0xFF22C55E)),
                            SizedBox(width: 4),
                            Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Real-time workforce monitoring & location tracking',
                    style: TextStyle(fontSize: isMobile ? 11 : 13, color: const Color(0xFF94A3B8))),
              ],
            ),
          ),
          if (!isMobile) ...[
            OutlinedButton.icon(
              onPressed: _exportCSV,
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Export CSV', style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6366F1),
                side: const BorderSide(color: Color(0xFF6366F1)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _showBroadcastDialog,
              icon: const Icon(Icons.campaign_rounded, color: Color(0xFF6366F1)),
              tooltip: 'Broadcast Notification',
            ),
            const SizedBox(width: 4),
          ],
          // Notification bell
          StreamBuilder<int>(
            stream: NotificationService().streamUnreadCount(FirebaseAuth.instance.currentUser?.uid ?? 'admin'),
            builder: (ctx, snap) {
              final count = snap.data ?? 0;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                    ),
                    icon: const Icon(Icons.notifications_outlined, color: Color(0xFF475569)),
                    tooltip: 'Notifications',
                  ),
                  if (count > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                        child: Text('$count',
                            style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
          // Date picker button
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10),
                color: Colors.white,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat('dd MMM yyyy').format(DateTime.parse(_selectedDate)),
                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF6366F1)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Dynamic workforce health bar using live Firestore data
  Widget _buildWorkforceHealth() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'employee').snapshots(),
      builder: (context, usersSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('attendance')
              .where('date', isEqualTo: _selectedDate)
              .snapshots(),
          builder: (context, attSnap) {
            final totalEmployees = usersSnap.data?.docs.length ?? 0;
            final attDocs = attSnap.data?.docs ?? [];

            int presentCount = 0;
            int lateCount = 0;
            int outsideCount = 0;

            for (var doc in attDocs) {
              final status = (doc.data() as Map<String, dynamic>)['status'] as String? ?? '';
              if (status == 'present') { presentCount++; }
              else if (status == 'late') { lateCount++; }
              else if (status == 'outside') { outsideCount++; }
            }

            final pendingCount = totalEmployees - attDocs.length;
            final inOfficePct = totalEmployees > 0 ? (presentCount + lateCount) / totalEmployees : 0.0;
            final outsidePct = totalEmployees > 0 ? outsideCount / totalEmployees : 0.0;
            final pendingPct = totalEmployees > 0 ? pendingCount / totalEmployees : 0.0;
            final outOfSystem = outsideCount;

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bar_chart_rounded, color: Color(0xFF475569), size: 20),
                      const SizedBox(width: 8),
                      const Text('Workforce Health',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                      const Spacer(),
                      Flexible(
                        child: Wrap(
                          spacing: 12,
                          children: [
                            _healthLegend(const Color(0xFF22C55E), 'In Office ${(inOfficePct * 100).round()}%'),
                            _healthLegend(const Color(0xFFF97316), 'Outside ${(outsidePct * 100).round()}%'),
                            _healthLegend(const Color(0xFFCBD5E1), 'Pending ${(pendingPct * 100).round()}%'),
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
                          if (inOfficePct == 0 && outsidePct == 0 && pendingPct == 0)
                            Expanded(child: Container(color: const Color(0xFFCBD5E1))),
                        ],
                      ),
                    ),
                  ),
                  if (outOfSystem > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFEA580C)),
                          const SizedBox(width: 6),
                          Text('$outOfSystem employee(s) are active online but outside the office.',
                              style: const TextStyle(fontSize: 12, color: Color(0xFFEA580C), fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _healthLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildMainContent(bool isMobile) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'employee').snapshots(),
      builder: (context, usersSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: _attendanceService.getHeartbeats(),
          builder: (context, heartbeatSnapshot) {
            return FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey(_selectedDate),
              future: _attendanceService.getLatestLocations(_selectedDate),
              builder: (context, latestLocsSnapshot) {
                final List<EmployeeMapData> employees = [];
                final colors = [
                  const Color(0xFF8B5CF6), const Color(0xFF14B8A6), const Color(0xFF6366F1),
                  const Color(0xFFF97316), const Color(0xFFEC4899), const Color(0xFF06B6D4),
                  const Color(0xFF10B981), const Color(0xFFF43F5E),
                ];

                final userDocs = usersSnap.data?.docs ?? [];
                final heartbeats = heartbeatSnapshot.data?.docs ?? [];
                final locations = latestLocsSnapshot.data ?? [];

                // Build lookup maps
                final hbMap = <String, Map<String, dynamic>>{};
                for (var hb in heartbeats) {
                  final d = hb.data() as Map<String, dynamic>;
                  final uid = (d['userId'] ?? hb.id) as String;
                  hbMap[uid] = d;
                }

                final locMap = <String, Map<String, dynamic>>{};
                for (var loc in locations) {
                  final userId = loc['userId'] as String?;
                  if (userId != null) locMap[userId] = loc;
                }

                // Build from ALL employees in users collection
                int i = 0;
                for (var userDoc in userDocs) {
                  final userData = userDoc.data() as Map<String, dynamic>;
                  final userId = userDoc.id;
                  final hb = hbMap[userId];
                  final loc = locMap[userId];
                  final isOnline = hb?['online'] == true;

                  employees.add(EmployeeMapData(
                    name: userData['name'] as String? ?? 'Unknown',
                    email: userData['email'] as String? ?? '',
                    lat: (loc?['lat'] as num?)?.toDouble() ?? _officeLat,
                    lng: (loc?['lng'] as num?)?.toDouble() ?? _officeLng,
                    status: _mapStatus(loc?['status'], isOnline, loc?['insideRadius']),
                    avatarColor: colors[i % colors.length],
                    isOnline: isOnline,
                    distance: (loc?['distanceFromOffice'] as num?)?.toInt(),
                    userId: userId,
                  ));
                  i++;
                }

                if (isMobile) {
                  return Column(
                    children: [
                      EmployeeListPanel(employees: employees, selectedDate: _selectedDate),
                      const SizedBox(height: 16),
                      _buildLiveMap(employees, 360),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 380, child: EmployeeListPanel(employees: employees, selectedDate: _selectedDate)),
                    const SizedBox(width: 24),
                    Expanded(child: _buildLiveMap(employees, 520)),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  EmployeeStatus _mapStatus(dynamic status, bool isOnline, dynamic insideRadius) {
    if (!isOnline) return EmployeeStatus.offline;
    final lowerStatus = (status as String?)?.toLowerCase() ?? '';
    if (lowerStatus == 'present' || insideRadius == true) return EmployeeStatus.present;
    if (lowerStatus == 'late') return EmployeeStatus.late_;
    if (lowerStatus == 'outside' || insideRadius == false) return EmployeeStatus.outside;
    return EmployeeStatus.pending;
  }

  Future<void> _showBroadcastDialog() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String selectedType = 'announcement';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Broadcast Notification', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  items: const [
                    DropdownMenuItem(value: 'announcement', child: Text('Announcement', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'attendance', child: Text('Attendance', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'payroll', child: Text('Payroll', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'warning', child: Text('Warning', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'general', child: Text('General', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (v) => setS(() => selectedType = v!),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: Color(0xFF6366F1))),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Title', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                const SizedBox(height: 6),
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    hintText: 'Notification title...',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: Color(0xFF6366F1))),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Message', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                const SizedBox(height: 6),
                TextField(
                  controller: bodyCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Message body...',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: Color(0xFF6366F1))),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
              icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
              label: const Text('Broadcast', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
                    const SnackBar(content: Text('Broadcast sent to all users'), backgroundColor: Color(0xFF22C55E)),
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
          .where('role', isEqualTo: 'employee')
          .get();
      final attSnap = await FirebaseFirestore.instance
          .collection('attendance')
          .where('date', isEqualTo: _selectedDate)
          .get();
      final locSnap = await FirebaseFirestore.instance.collection('locations').get();
      final hbSnap = await FirebaseFirestore.instance.collection('heartbeats').get();

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
      for (var doc in hbSnap.docs) {
        final d = doc.data();
        hbMap[((d['userId'] ?? doc.id) as String)] = d;
      }

      final buffer = StringBuffer();
      buffer.writeln('Name,Email,Status,Online,Check-In,Check-Out,Inside(min),Outside(min),Offline(min),Extra(min),Lat,Lng');

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

        buffer.writeln('"$name","$email","$status","$online","$checkIn","$checkOut",$inside,$outside,$offline,$extra,"$lat","$lng"');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CSV data ready for $_selectedDate (${usersSnap.docs.length} employees)'),
            backgroundColor: const Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildLiveMap(List<EmployeeMapData> employees, double height) {
    final online = employees.where((e) => e.isOnline).length;
    final inOffice = employees.where((e) => e.status == EmployeeStatus.present).length;

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
                  color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.map_rounded, color: Color(0xFF6366F1), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Live Location Map',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                        Text('${employees.length} employees · $online online · $inOffice in office',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
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
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(initialCenter: LatLng(_officeLat, _officeLng), initialZoom: 15.0),
                children: [
                  TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.attendo.app'),
                  CircleLayer(circles: [
                    CircleMarker(
                      point: LatLng(_officeLat, _officeLng),
                      radius: 100,
                      useRadiusInMeter: true,
                      color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                      borderColor: const Color(0xFF6366F1).withValues(alpha: 0.35),
                      borderStrokeWidth: 2,
                    ),
                  ]),
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(_officeLat, _officeLng),
                      width: 44,
                      height: 44,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                                blurRadius: 12,
                                spreadRadius: 2)
                          ],
                        ),
                        child: const Icon(Icons.business, color: Colors.white, size: 20),
                      ),
                    ),
                    ...employees.map((emp) {
                      final markerColor = emp.status == EmployeeStatus.present
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
                        child: Tooltip(
                          message:
                              '${emp.name}\n${emp.isOnline ? "Online" : "Offline"}${emp.distance != null ? " · ${emp.distance}m from office" : ""}',
                          child: Container(
                            decoration: BoxDecoration(
                              color: emp.avatarColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(color: markerColor.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 1)
                              ],
                            ),
                            child: Stack(
                              children: [
                                Center(
                                    child: Text(emp.initials,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: emp.isOnline ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ]),
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
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(l, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
        ],
      );

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 2)),
        BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 1)),
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
    required this.name, required this.email, required this.lat, required this.lng,
    required this.status, required this.avatarColor, this.isOnline = false, this.distance,
    required this.userId,
  });

  String get initials {
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();
  }
}
