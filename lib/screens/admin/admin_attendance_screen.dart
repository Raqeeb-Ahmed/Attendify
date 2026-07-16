import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/pdf_generator_service.dart';

class AdminAttendanceScreen extends StatefulWidget {
  final String selectedDate;
  final bool isMobile;
  final VoidCallback? onMenuPressed;
  const AdminAttendanceScreen({
    super.key,
    required this.selectedDate,
    this.isMobile = false,
    this.onMenuPressed,
  });

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  late String _selectedDate;
  String _searchQuery = '';
  String _filterStatus = 'All';

  final List<String> _statusFilters = [
    'All',
    'present',
    'late',
    'outside',
    'pending',
  ];

  // Employee history tab variables
  int _selectedTab = 0; // 0: Daily Roster, 1: Employee History
  String? _selectedUid;
  int _auditDaysLimit = 4;
  DateTime _employeeCalendarMonth = DateTime.now();
  DateTime? _auditStartDate;
  DateTime? _auditEndDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_selectedDate),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF6366F1)),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted)
      setState(() => _selectedDate = DateFormat('yyyy-MM-dd').format(picked));
  }

  Widget _buildTabSelector(bool isMobile) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedTab == 0 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _selectedTab == 0
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'Daily Roster',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _selectedTab == 0
                          ? const Color(0xFF4F46E5)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = 1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedTab == 1 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _selectedTab == 1
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'Employee History',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _selectedTab == 1
                          ? const Color(0xFF4F46E5)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localIsMobile = MediaQuery.of(context).size.width < 768;
    final isMobile = widget.isMobile || localIsMobile;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(isMobile),
            _buildTabSelector(isMobile),
            Expanded(
              child: _selectedTab == 0
                  ? Column(
                      children: [
                        _buildFilterRow(isMobile),
                        Expanded(
                          child: StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('attendance')
                                .where('date', isEqualTo: _selectedDate)
                                .snapshots(),
                            builder: (context, attSnap) {
                              return StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('users')
                                    .snapshots(),
                                builder: (context, usersSnap) {
                                  final attDocs = attSnap.data?.docs ?? [];
                                  final userDocs = usersSnap.data?.docs ?? [];

                                  final userMap =
                                      <String, Map<String, dynamic>>{};
                                  for (var u in userDocs) {
                                    userMap[u.id] =
                                        u.data() as Map<String, dynamic>;
                                  }

                                  final checkedInIds = attDocs
                                      .map(
                                        (d) =>
                                            (d.data()
                                                    as Map<
                                                      String,
                                                      dynamic
                                                    >)['userId']
                                                as String? ??
                                            '',
                                      )
                                      .toSet();
                                  final pendingUsers = userDocs
                                      .where(
                                        (u) =>
                                            (u.data()
                                                    as Map<
                                                      String,
                                                      dynamic
                                                    >)['role'] !=
                                                'admin' &&
                                            !checkedInIds.contains(u.id),
                                      )
                                      .toList();

                                  final allRecords = [
                                    ...attDocs.map((doc) {
                                      final d =
                                          doc.data() as Map<String, dynamic>;
                                      return {'type': 'att', 'data': d};
                                    }),
                                    ...pendingUsers.map((u) {
                                      final d =
                                          u.data() as Map<String, dynamic>;
                                      return {
                                        'type': 'pending',
                                        'data': {
                                          'userId': u.id,
                                          'userName': d['name'] ?? '',
                                          'email': d['email'] ?? '',
                                          'status': 'pending',
                                        },
                                      };
                                    }),
                                  ];

                                  final filtered = allRecords.where((rec) {
                                    final d =
                                        rec['data'] as Map<String, dynamic>;
                                    final name =
                                        (d['userName'] as String? ?? '')
                                            .toLowerCase();
                                    final email = (d['email'] as String? ?? '')
                                        .toLowerCase();
                                    final status =
                                        d['status'] as String? ?? 'pending';
                                    final matchSearch =
                                        name.contains(
                                          _searchQuery.toLowerCase(),
                                        ) ||
                                        email.contains(
                                          _searchQuery.toLowerCase(),
                                        );
                                    final matchStatus =
                                        _filterStatus == 'All' ||
                                        status == _filterStatus;
                                    return matchSearch && matchStatus;
                                  }).toList();

                                  if (attSnap.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF6366F1),
                                      ),
                                    );
                                  }

                                  if (filtered.isEmpty) {
                                    return Center(
                                      child: Text(
                                        'No records found',
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                    );
                                  }

                                  return ListView.builder(
                                    padding: EdgeInsets.all(isMobile ? 16 : 24),
                                    itemCount: filtered.length,
                                    itemBuilder: (ctx, i) =>
                                        _buildAttendanceCard(
                                          filtered[i]['data']
                                              as Map<String, dynamic>,
                                        ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    )
                  : _buildEmployeeHistoryTab(isMobile),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isMobile) {
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
          if (isMobile && widget.onMenuPressed != null)
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: widget.onMenuPressed,
            ),
          const Icon(
            Icons.calendar_month_rounded,
            color: Color(0xFF6366F1),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daily Attendance',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  'Check-in status and time logs',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          if (!isMobile)
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Text(
                      DateFormat(
                        'dd MMM yyyy',
                      ).format(DateTime.parse(_selectedDate)),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
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
            ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(bool isMobile) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      color: Colors.white,
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search by name or email...',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              prefixIcon: Icon(
                Icons.search,
                color: Colors.grey.shade400,
                size: 20,
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide(color: Color(0xFF6366F1)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _statusFilters.map((s) {
                final isActive = _filterStatus == s;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filterStatus = s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF6366F1)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        s == 'All'
                            ? 'All'
                            : s[0].toUpperCase() + s.substring(1),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isActive ? Colors.white : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard(Map<String, dynamic> d) {
    final name = d['userName'] as String? ?? d['name'] as String? ?? 'Unknown';
    final email = d['email'] as String? ?? '';
    final status = d['status'] as String? ?? 'pending';
    final checkIn = d['checkInTime'] as String?;
    final checkOut = d['checkOutTime'] as String?;
    final insideTime = (d['insideTime'] as num?)?.toInt() ?? 0;
    final outsideTime = (d['outsideTime'] as num?)?.toInt() ?? 0;
    final totalHours = (d['totalHours'] as num?)?.toDouble() ?? 0.0;
    final atOffice = d['atOffice'] as bool? ?? false;
    final userId = d['userId'] as String? ?? '';

    final sessionStatus = d['sessionStatus'] as String? ?? '';
    final extraHours = (d['extraHours'] as num?)?.toInt() ?? 0;

    Color statusColor;
    Color statusBg;
    String statusLabel;
    switch (status) {
      case 'present':
        statusColor = const Color(0xFF16A34A);
        statusBg = const Color(0xFFDCFCE7);
        statusLabel = 'Present';
        break;
      case 'late':
        statusColor = const Color(0xFFCA8A04);
        statusBg = const Color(0xFFFEF9C3);
        statusLabel = 'Late';
        break;
      case 'outside':
        statusColor = const Color(0xFFEA580C);
        statusBg = const Color(0xFFFFEDD5);
        statusLabel = 'Out of System';
        break;
      default:
        statusColor = const Color(0xFF64748B);
        statusBg = const Color(0xFFF1F5F9);
        statusLabel = 'Pending';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: statusColor, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
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
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
                if (userId.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _showEmployeeCalendar(userId, name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_month,
                            size: 14,
                            color: Color(0xFF6366F1),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'View',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (checkIn != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  _attStat(
                    'Check In',
                    DateFormat(
                      'hh:mm a',
                    ).format(DateTime.parse(checkIn).toLocal()),
                    const Color(0xFF22C55E),
                  ),
                  const SizedBox(width: 20),
                  _attStat(
                    'Check Out',
                    checkOut != null
                        ? DateFormat(
                            'hh:mm a',
                          ).format(DateTime.parse(checkOut).toLocal())
                        : 'Active',
                    const Color(0xFFF97316),
                  ),
                  const SizedBox(width: 20),
                  _attStat(
                    'Total Hours',
                    '${totalHours.toStringAsFixed(1)}h',
                    const Color(0xFF6366F1),
                  ),
                  const Spacer(),
                  if (atOffice)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'IN OFFICE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _timePill(
                    'Inside',
                    '${insideTime ~/ 60}h ${insideTime % 60}m',
                    const Color(0xFF22C55E),
                  ),
                  const SizedBox(width: 8),
                  _timePill(
                    'Outside',
                    '${outsideTime ~/ 60}h ${outsideTime % 60}m',
                    const Color(0xFFF97316),
                  ),
                  if (extraHours > 0) ...[
                    const SizedBox(width: 8),
                    _timePill(
                      'Overtime',
                      '${extraHours ~/ 60}h ${extraHours % 60}m',
                      const Color(0xFF8B5CF6),
                    ),
                  ],
                ],
              ),
              if (sessionStatus == 'auto-checkout')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 10,
                              color: Color(0xFF6366F1),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'AUTO-CHECKOUT 6 PM',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6366F1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _attStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade400,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _timePill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  /// Show monthly calendar dialog for an employee
  // ─── Employee History & Range Audit Helpers ──────────────────────────────

  List<DateTime> _getDaysInMonth() {
    final firstDay = DateTime(
      _employeeCalendarMonth.year,
      _employeeCalendarMonth.month,
      1,
    );
    final lastDay = DateTime(
      _employeeCalendarMonth.year,
      _employeeCalendarMonth.month + 1,
      0,
    );
    final daysBefore = firstDay.weekday % 7;

    final days = <DateTime>[];
    for (int i = daysBefore - 1; i >= 0; i--) {
      days.add(firstDay.subtract(Duration(days: i + 1)));
    }
    for (int i = 0; i < lastDay.day; i++) {
      days.add(
        DateTime(
          _employeeCalendarMonth.year,
          _employeeCalendarMonth.month,
          i + 1,
        ),
      );
    }
    final remaining = 42 - days.length;
    for (int i = 1; i <= remaining; i++) {
      days.add(lastDay.add(Duration(days: i)));
    }
    return days;
  }

  /// Generate attendance history PDF for the selected employee
  Future<void> _generateEmployeePDF(
    List<QueryDocumentSnapshot> users,
    Map<String, Map<String, dynamic>> monthData,
  ) async {
    if (_selectedUid == null) return;

    // Find the selected user document
    QueryDocumentSnapshot? userDoc;
    for (final u in users) {
      if (u.id == _selectedUid) {
        userDoc = u;
        break;
      }
    }
    if (userDoc == null) return;
    final userData = userDoc.data() as Map<String, dynamic>;
    final employeeName = userData['name'] as String? ?? 'Unknown';
    final employeeEmail = userData['email'] as String? ?? '';
    final department = userData['department'] as String? ?? '';
    final designation = userData['designation'] as String? ?? '';
    final reportMonthYear = DateFormat(
      'MMMM yyyy',
    ).format(_employeeCalendarMonth);

    // Helper to extract time from ISO string
    String formatTime(String? isoStr) {
      if (isoStr == null || isoStr.isEmpty) return 'N/A';
      try {
        final dt = DateTime.parse(isoStr);
        return DateFormat('hh:mm a').format(dt);
      } catch (_) {
        return isoStr;
      }
    }

    // Generate ALL days in the month, not just recorded days
    final firstDay = DateTime(
      _employeeCalendarMonth.year,
      _employeeCalendarMonth.month,
      1,
    );
    final lastDay = DateTime(
      _employeeCalendarMonth.year,
      _employeeCalendarMonth.month + 1,
      0,
    );

    final attendanceRecords = <Map<String, dynamic>>[];
    for (int i = 0; i < lastDay.day; i++) {
      final day = DateTime(firstDay.year, firstDay.month, i + 1);
      // Skip future dates
      if (day.isAfter(DateTime.now())) break;
      final dateStr = DateFormat('yyyy-MM-dd').format(day);
      final data = monthData[dateStr];
      if (data != null) {
        attendanceRecords.add(<String, dynamic>{
          'date': DateFormat('MMM dd, yyyy').format(day),
          'checkIn': formatTime(data['checkInTime'] as String?),
          'checkOut': formatTime(data['checkOutTime'] as String?),
          'status': data['status'] as String? ?? 'N/A',
          'insideRadius': data['atOffice'] ?? false,
        });
      } else {
        attendanceRecords.add(<String, dynamic>{
          'date': DateFormat('MMM dd, yyyy').format(day),
          'checkIn': '--',
          'checkOut': '--',
          'status': 'Absent',
          'insideRadius': false,
        });
      }
    }

    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final pdfService = PDFGeneratorService();
      await pdfService.generateAttendanceHistoryPDF(
        employeeName: employeeName,
        employeeEmail: employeeEmail,
        department: department,
        designation: designation,
        attendanceRecords: attendanceRecords,
        reportMonthYear: reportMonthYear,
      );

      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'PDF generated for $employeeName ($reportMonthYear)',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF22C55E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Failed to generate PDF: $e',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Generate PDF for audit date range data
  Future<void> _generateAuditPDF(
    List<QueryDocumentSnapshot> users,
    Map<String, Map<String, dynamic>> recordMap,
    String startStr,
    String endStr,
  ) async {
    if (_selectedUid == null) return;

    // Find the selected user document
    QueryDocumentSnapshot? userDoc;
    for (final u in users) {
      if (u.id == _selectedUid) {
        userDoc = u;
        break;
      }
    }
    if (userDoc == null) return;

    final userData = userDoc.data() as Map<String, dynamic>;
    final employeeName = userData['name'] as String? ?? 'Unknown';
    final employeeEmail = userData['email'] as String? ?? '';
    final department = userData['department'] as String? ?? '';
    final designation = userData['designation'] as String? ?? '';
    final reportPeriod =
        '${DateFormat('MMM d, yyyy').format(DateTime.parse(startStr))} - ${DateFormat('MMM d, yyyy').format(DateTime.parse(endStr))}';

    // Helper to extract time from ISO string
    String formatTime(String? isoStr) {
      if (isoStr == null || isoStr.isEmpty) return 'N/A';
      try {
        final dt = DateTime.parse(isoStr);
        return DateFormat('hh:mm a').format(dt);
      } catch (_) {
        return isoStr;
      }
    }

    // Generate ALL days in the audit range, not just recorded days
    final rangeStart = DateTime.parse(startStr);
    final rangeEnd = DateTime.parse(endStr);
    final totalDays = rangeEnd.difference(rangeStart).inDays + 1;

    final attendanceRecords = <Map<String, dynamic>>[];
    for (int i = 0; i < totalDays; i++) {
      final day = rangeStart.add(Duration(days: i));
      // Skip future dates
      if (day.isAfter(DateTime.now())) break;
      final dateStr = DateFormat('yyyy-MM-dd').format(day);
      final data = recordMap[dateStr];
      if (data != null) {
        attendanceRecords.add(<String, dynamic>{
          'date': DateFormat('MMM dd, yyyy').format(day),
          'checkIn': formatTime(data['checkInTime'] as String?),
          'checkOut': formatTime(data['checkOutTime'] as String?),
          'status': data['status'] as String? ?? 'N/A',
          'insideRadius': data['atOffice'] ?? false,
        });
      } else {
        attendanceRecords.add(<String, dynamic>{
          'date': DateFormat('MMM dd, yyyy').format(day),
          'checkIn': '--',
          'checkOut': '--',
          'status': 'Absent',
          'insideRadius': false,
        });
      }
    }

    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final pdfService = PDFGeneratorService();
      await pdfService.generateAttendanceHistoryPDF(
        employeeName: employeeName,
        employeeEmail: employeeEmail,
        department: department,
        designation: designation,
        attendanceRecords: attendanceRecords,
        reportMonthYear: reportPeriod,
      );

      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Audit PDF generated for $employeeName',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF22C55E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Failed to generate PDF: $e',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
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

  Widget _buildSummaryCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCalendarGrid(
    List<DateTime> days,
    Map<String, Map<String, dynamic>> monthData,
    List<QueryDocumentSnapshot> approvedLeaves,
  ) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: MediaQuery.of(context).size.width < 400 ? 0.75 : 1.0,
      ),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        final dateStr = DateFormat('yyyy-MM-dd').format(day);
        final record = monthData[dateStr];
        final hasRecord = record != null;
        final isCurrentMonth = day.month == _employeeCalendarMonth.month;
        final isToday =
            DateFormat('yyyy-MM-dd').format(day) ==
            DateFormat('yyyy-MM-dd').format(DateTime.now());

        bool isLeaveDay = false;
        if (isCurrentMonth) {
          final dayStr = DateFormat('yyyy-MM-dd').format(day);
          for (var doc in approvedLeaves) {
            final data = doc.data() as Map<String, dynamic>;
            final start = data['startDate'] as String?;
            final end = data['endDate'] as String?;
            if (start != null && end != null) {
              if (dayStr.compareTo(start) >= 0 && dayStr.compareTo(end) <= 0) {
                isLeaveDay = true;
                break;
              }
            }
          }
        }

        Color? bgColor;
        Color? borderColor;
        String? statusLabel;

        if (isLeaveDay) {
          bgColor = const Color(0xFFFAF5FF);
          borderColor = const Color(0xFFD8B4FE);
          statusLabel = 'LV';
        } else if (hasRecord && isCurrentMonth) {
          final status = (record['status'] as String?)?.toUpperCase() ?? '';
          if (status == 'PRESENT') {
            bgColor = const Color(0xFFF0FDF4);
            borderColor = const Color(0xFF22C55E);
            statusLabel = 'P';
          } else if (status == 'LATE') {
            bgColor = const Color(0xFFFEF3C7);
            borderColor = const Color(0xFFF59E0B);
            statusLabel = 'L';
          } else if (status == 'OUTSIDE') {
            bgColor = const Color(0xFFFFF7ED);
            borderColor = const Color(0xFFF97316);
            statusLabel = 'O';
          }
        }

        return InkWell(
          onTap: hasRecord && isCurrentMonth
              ? () => _showDateDetails(day, record)
              : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color:
                  bgColor ??
                  (isCurrentMonth ? Colors.white : const Color(0xFFF8FAFC)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isToday
                    ? const Color(0xFF6366F1)
                    : borderColor ?? const Color(0xFFE2E8F0),
                width: isToday ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isCurrentMonth
                        ? const Color(0xFF1E293B)
                        : const Color(0xFF94A3B8),
                  ),
                ),
                if (statusLabel != null)
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: statusLabel == 'LV'
                          ? const Color(0xFFA855F7)
                          : borderColor,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAuditDateRange() async {
    final DateTimeRange? initialRange;
    if (_auditStartDate != null && _auditEndDate != null) {
      initialRange = DateTimeRange(
        start: _auditStartDate!,
        end: _auditEndDate!,
      );
    } else {
      // Align initial picker viewport to the currently selected month
      final year = _employeeCalendarMonth.year;
      final month = _employeeCalendarMonth.month;
      final today = DateTime.now();
      // If selected month is current month, start selection from today going back 6 days, otherwise use first 7 days
      if (year == today.year && month == today.month) {
        initialRange = DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: today,
        );
      } else {
        initialRange = DateTimeRange(
          start: DateTime(year, month, 1),
          end: DateTime(year, month, 7),
        );
      }
    }

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      initialDateRange: initialRange,
      builder: (ctx, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF6366F1),
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF1E293B),
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        _auditStartDate = picked.start;
        _auditEndDate = picked.end;
      });
    }
  }

  Widget _buildDateRangeAudit(String uid, List<QueryDocumentSnapshot> users) {
    final String startStr;
    final String endStr;
    final List<DateTime> dates;

    if (_auditStartDate != null && _auditEndDate != null) {
      startStr = DateFormat('yyyy-MM-dd').format(_auditStartDate!);
      endStr = DateFormat('yyyy-MM-dd').format(_auditEndDate!);
      final difference = _auditEndDate!.difference(_auditStartDate!).inDays;
      dates = List.generate(difference + 1, (index) {
        return _auditEndDate!.subtract(Duration(days: index));
      });
    } else {
      final DateTime refDate;
      final now = DateTime.now();
      if (_employeeCalendarMonth.year == now.year &&
          _employeeCalendarMonth.month == now.month) {
        refDate = DateTime(now.year, now.month, now.day);
      } else {
        refDate = DateTime(
          _employeeCalendarMonth.year,
          _employeeCalendarMonth.month + 1,
          0,
        );
      }
      final startDay = refDate.subtract(Duration(days: _auditDaysLimit - 1));
      startStr = DateFormat('yyyy-MM-dd').format(startDay);
      endStr = DateFormat('yyyy-MM-dd').format(refDate);
      dates = List.generate(_auditDaysLimit, (index) {
        return refDate.subtract(Duration(days: index));
      });
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('attendance')
          .where('userId', isEqualTo: uid)
          .where('date', isGreaterThanOrEqualTo: startStr)
          .where('date', isLessThanOrEqualTo: endStr)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF6366F1)),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final recordMap = <String, Map<String, dynamic>>{};
        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['date'] != null) {
            recordMap[data['date'] as String] = data;
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.manage_search_rounded,
                          color: Color(0xFF6366F1),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Date Range Audit',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.picture_as_pdf_rounded,
                          color: Color(0xFF6366F1),
                          size: 22,
                        ),
                        tooltip: 'Download Audit PDF',
                        onPressed: () => _generateAuditPDF(
                          users,
                          recordMap,
                          startStr,
                          endStr,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'Range:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ...[4, 7, 15, 30].map((days) {
                                final isActive =
                                    _auditDaysLimit == days &&
                                    _auditStartDate == null;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(
                                      '$days Days',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isActive
                                            ? Colors.white
                                            : const Color(0xFF475569),
                                      ),
                                    ),
                                    selected: isActive,
                                    onSelected: (val) {
                                      if (val) {
                                        setState(() {
                                          _auditDaysLimit = days;
                                          _auditStartDate = null;
                                          _auditEndDate = null;
                                        });
                                      }
                                    },
                                    selectedColor: const Color(0xFF6366F1),
                                    backgroundColor: const Color(0xFFF1F5F9),
                                    showCheckmark: false,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                  ),
                                );
                              }),
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.calendar_month_outlined,
                                        size: 13,
                                        color:
                                            (_auditStartDate != null &&
                                                _auditEndDate != null)
                                            ? Colors.white
                                            : const Color(0xFF475569),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _auditStartDate != null &&
                                                _auditEndDate != null
                                            ? '${DateFormat('MMM d').format(_auditStartDate!)} - ${DateFormat('MMM d').format(_auditEndDate!)}'
                                            : 'Custom Range',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              (_auditStartDate != null &&
                                                  _auditEndDate != null)
                                              ? Colors.white
                                              : const Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                  ),
                                  selected:
                                      _auditStartDate != null &&
                                      _auditEndDate != null,
                                  onSelected: (val) {
                                    _pickAuditDateRange();
                                  },
                                  selectedColor: const Color(0xFF6366F1),
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  showCheckmark: false,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: dates.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final day = dates[index];
                      final dateStr = DateFormat('yyyy-MM-dd').format(day);
                      final record = recordMap[dateStr];

                      return _buildAuditDayRow(day, record);
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAuditDayRow(DateTime day, Map<String, dynamic>? record) {
    final isWeekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    final dateStr = DateFormat('EEEE, MMM d').format(day);

    if (record == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                  ),
                ),
                Text(
                  isWeekend ? 'Weekend' : 'Weekday',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isWeekend
                    ? const Color(0xFFF1F5F9)
                    : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isWeekend ? 'OFF' : 'ABSENT',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: isWeekend
                      ? const Color(0xFF64748B)
                      : const Color(0xFFEF4444),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final status = record['status'] as String? ?? 'pending';
    final checkIn = record['checkInTime'] as String?;
    final checkOut = record['checkOutTime'] as String?;
    final insideTime = (record['insideTime'] as num?)?.toInt() ?? 0;
    final outsideTime = (record['outsideTime'] as num?)?.toInt() ?? 0;
    final offlineTime = (record['offlineTime'] as num?)?.toInt() ?? 0;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'present':
        statusColor = const Color(0xFF22C55E);
        statusLabel = 'Present';
        break;
      case 'late':
        statusColor = const Color(0xFFF59E0B);
        statusLabel = 'Late';
        break;
      case 'outside':
        statusColor = const Color(0xFFF97316);
        statusLabel = 'Outside';
        break;
      default:
        statusColor = const Color(0xFF64748B);
        statusLabel = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.login, size: 12, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Text(
                checkIn != null
                    ? DateFormat(
                        'hh:mm a',
                      ).format(DateTime.parse(checkIn).toLocal())
                    : '--:--',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.logout, size: 12, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Text(
                checkOut != null
                    ? DateFormat(
                        'hh:mm a',
                      ).format(DateTime.parse(checkOut).toLocal())
                    : 'Active',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: checkOut != null
                      ? const Color(0xFF475569)
                      : const Color(0xFF6366F1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildAuditTimeLabel(
                'Inside',
                insideTime,
                const Color(0xFF22C55E),
              ),
              _buildAuditTimeLabel(
                'Outside',
                outsideTime,
                const Color(0xFFF97316),
              ),
              _buildAuditTimeLabel(
                'Offline',
                offlineTime,
                const Color(0xFF64748B),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAuditTimeLabel(String label, int mins, Color color) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
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

  Widget _buildEmployeeHistoryTab(bool isMobile) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: const ['employee', 'manager'])
          .snapshots(),
      builder: (context, usersSnap) {
        if (!usersSnap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF6366F1)),
          );
        }

        final users = usersSnap.data!.docs;

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

        if (_selectedUid == null) {
          return const Center(
            child: Text(
              'No employees found',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          );
        }

        final startDate = DateTime(
          _employeeCalendarMonth.year,
          _employeeCalendarMonth.month,
          1,
        );
        final endDate = DateTime(
          _employeeCalendarMonth.year,
          _employeeCalendarMonth.month + 1,
          0,
        );
        final startStr = DateFormat('yyyy-MM-dd').format(startDate);
        final endStr = DateFormat('yyyy-MM-dd').format(endDate);

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('leaves')
              .where('userId', isEqualTo: _selectedUid)
              .where('status', isEqualTo: 'approved')
              .snapshots(),
          builder: (context, leavesSnap) {
            final approvedLeaves = leavesSnap.data?.docs ?? [];

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('attendance')
                  .where('userId', isEqualTo: _selectedUid)
                  .where('date', isGreaterThanOrEqualTo: startStr)
                  .where('date', isLessThanOrEqualTo: endStr)
                  .snapshots(),
              builder: (context, attendanceSnap) {
            final docs = attendanceSnap.data?.docs ?? [];
            final monthData = <String, Map<String, dynamic>>{};

            int present = 0, late = 0, outside = 0;
            for (var doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              if (data['date'] != null) {
                monthData[data['date'] as String] = data;
                final status = (data['status'] as String?)?.toUpperCase() ?? '';
                if (status == 'PRESENT') {
                  present++;
                } else if (status == 'LATE') {
                  late++;
                } else if (status == 'OUTSIDE') {
                  outside++;
                }
              }
            }
            final totalRecords = present + late + outside;
            final days = _getDaysInMonth();

            return SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select Employee',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        dropdownWidget,
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: isMobile ? 2 : 4,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: isMobile ? 2.0 : 1.25,
                    children: [
                      _buildSummaryCard(
                        'Present',
                        '$present',
                        Icons.check_circle,
                        const Color(0xFF22C55E),
                      ),
                      _buildSummaryCard(
                        'Late',
                        '$late',
                        Icons.warning_amber,
                        const Color(0xFFF59E0B),
                      ),
                      _buildSummaryCard(
                        'Outside',
                        '$outside',
                        Icons.cancel,
                        const Color(0xFFF97316),
                      ),
                      _buildSummaryCard(
                        'Rate',
                        totalRecords > 0
                            ? '${(((present + late) / totalRecords) * 100).round()}%'
                            : '0%',
                        Icons.trending_up,
                        const Color(0xFF6366F1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.calendar_today,
                                  color: Color(0xFF6366F1),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Attendance Calendar',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1E293B),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.chevron_left, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _employeeCalendarMonth = DateTime(
                                      _employeeCalendarMonth.year,
                                      _employeeCalendarMonth.month - 1,
                                    );
                                  });
                                },
                              ),
                              Text(
                                DateFormat(
                                  'MMM yyyy',
                                ).format(_employeeCalendarMonth),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.chevron_right, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _employeeCalendarMonth = DateTime(
                                      _employeeCalendarMonth.year,
                                      _employeeCalendarMonth.month + 1,
                                    );
                                  });
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(
                                  Icons.picture_as_pdf_rounded,
                                  color: Color(0xFF6366F1),
                                  size: 22,
                                ),
                                tooltip: 'Download PDF',
                                onPressed: () =>
                                    _generateEmployeePDF(users, monthData),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Row(
                                children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                                    .map((day) {
                                      return Expanded(
                                        child: Center(
                                          child: Text(
                                            day,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF94A3B8),
                                            ),
                                          ),
                                        ),
                                      );
                                    })
                                    .toList(),
                              ),
                              const SizedBox(height: 12),
                              attendanceSnap.connectionState ==
                                      ConnectionState.waiting
                                  ? const SizedBox(
                                      height: 220,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: Color(0xFF6366F1),
                                        ),
                                      ),
                                    )
                                  : _buildEmployeeCalendarGrid(days, monthData, approvedLeaves),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(16),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildLegendItem(
                                'P',
                                'Present',
                                const Color(0xFF22C55E),
                              ),
                              _buildLegendItem(
                                'L',
                                'Late',
                                const Color(0xFFF59E0B),
                              ),
                              _buildLegendItem(
                                'O',
                                'Outside',
                                const Color(0xFFF97316),
                              ),
                              _buildLegendItem(
                                'LV',
                                'Leave',
                                const Color(0xFFA855F7),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildDateRangeAudit(_selectedUid!, users),
                ],
              ),
            );
          },
        );
      },
    );
  },
);
}

  void _showDateDetails(DateTime day, Map<String, dynamic> record) {
    final checkIn = record['checkInTime'] as String?;
    final checkOut = record['checkOutTime'] as String?;
    final status = record['status'] as String? ?? 'pending';
    final insideTimeVal = (record['insideTime'] as num?)?.toInt() ?? 0;
    final outsideTime = (record['outsideTime'] as num?)?.toInt() ?? 0;
    final offlineTime = (record['offlineTime'] as num?)?.toInt() ?? 0;
    final insideTime = insideTimeVal + offlineTime;
    final totalHours = (record['totalHours'] as num?)?.toDouble() ?? 0.0;
    final atOffice = record['atOffice'] as bool? ?? false;
    final checkInMethod = record['checkInMethod'] as String? ?? 'manual';
    final autoCheckedIn = record['autoCheckedIn'] as bool? ?? false;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'present':
        statusColor = const Color(0xFF22C55E);
        statusLabel = 'Present';
        break;
      case 'late':
        statusColor = const Color(0xFFF59E0B);
        statusLabel = 'Late';
        break;
      case 'outside':
        statusColor = const Color(0xFFF97316);
        statusLabel = 'Outside';
        break;
      default:
        statusColor = const Color(0xFF64748B);
        statusLabel = 'Pending';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.event_note,
                        color: statusColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('EEEE, MMMM d').format(day),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: statusColor),
                            ),
                            child: Text(
                              statusLabel.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                if (checkIn != null) ...[
                  _buildDetailRow(
                    Icons.login,
                    const Color(0xFF22C55E),
                    'Check In',
                    DateFormat(
                      'hh:mm a',
                    ).format(DateTime.parse(checkIn).toLocal()),
                  ),
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    Icons.logout,
                    const Color(0xFFF97316),
                    'Check Out',
                    checkOut != null
                        ? DateFormat(
                            'hh:mm a',
                          ).format(DateTime.parse(checkOut).toLocal())
                        : 'Active',
                  ),
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    Icons.timelapse,
                    const Color(0xFF6366F1),
                    'Total Hours',
                    '${totalHours.toStringAsFixed(1)} hrs',
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 12),
                ],
                _buildDetailRow(
                  atOffice ? Icons.location_on : Icons.location_off,
                  atOffice ? const Color(0xFF22C55E) : const Color(0xFFF97316),
                  'Location',
                  atOffice ? 'In Office' : 'Out of Office',
                ),
                const SizedBox(height: 12),
                if (insideTime > 0 || outsideTime > 0 || offlineTime > 0) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 12),
                  const Text(
                    'Time Breakdown',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (insideTime > 0)
                    _buildTimePill(
                      'Inside Office',
                      '${insideTime ~/ 60}h ${insideTime % 60}m',
                      const Color(0xFF22C55E),
                    ),
                  if (outsideTime > 0) ...[
                    const SizedBox(height: 8),
                    _buildTimePill(
                      'Outside Office',
                      '${outsideTime ~/ 60}h ${outsideTime % 60}m',
                      const Color(0xFFF97316),
                    ),
                  ],
                  if (offlineTime > 0) ...[
                    const SizedBox(height: 8),
                    _buildTimePill(
                      'Offline',
                      '${offlineTime ~/ 60}h ${offlineTime % 60}m',
                      const Color(0xFF64748B),
                    ),
                  ],
                ],
                if (autoCheckedIn) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.auto_fix_high,
                          size: 16,
                          color: Color(0xFF6366F1),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Auto Check-in via ${checkInMethod.replaceAll('_', ' ').toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6366F1),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    Color color,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimePill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _showEmployeeCalendar(String userId, String userName) {
    showDialog(
      context: context,
      builder: (context) =>
          _EmployeeCalendarDialog(userId: userId, userName: userName),
    );
  }
}

/// Monthly calendar dialog for viewing employee attendance
class _EmployeeCalendarDialog extends StatefulWidget {
  final String userId;
  final String userName;

  const _EmployeeCalendarDialog({required this.userId, required this.userName});

  @override
  State<_EmployeeCalendarDialog> createState() =>
      _EmployeeCalendarDialogState();
}

class _EmployeeCalendarDialogState extends State<_EmployeeCalendarDialog> {
  DateTime _currentMonth = DateTime.now();
  Map<String, Map<String, dynamic>> _attendanceData = {};
  List<QueryDocumentSnapshot> _approvedLeaves = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMonthData();
  }

  Future<void> _fetchMonthData() async {
    setState(() => _isLoading = true);
    try {
      final startDate = DateTime(_currentMonth.year, _currentMonth.month, 1);
      final endDate = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);

      final snapshot = await FirebaseFirestore.instance
          .collection('attendance')
          .where('userId', isEqualTo: widget.userId)
          .where(
            'date',
            isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(startDate),
          )
          .where(
            'date',
            isLessThanOrEqualTo: DateFormat('yyyy-MM-dd').format(endDate),
          )
          .get();

      final data = <String, Map<String, dynamic>>{};
      for (var doc in snapshot.docs) {
        final d = doc.data();
        data[d['date'] as String] = d;
      }

      final leavesSnapshot = await FirebaseFirestore.instance
          .collection('leaves')
          .where('userId', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'approved')
          .get();

      setState(() {
        _attendanceData = data;
        _approvedLeaves = leavesSnapshot.docs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error fetching attendance: $e');
    }
  }

  List<DateTime> _getDaysInMonth() {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final daysBefore = firstDay.weekday % 7;

    final days = <DateTime>[];
    // Previous month days
    for (int i = daysBefore - 1; i >= 0; i--) {
      days.add(firstDay.subtract(Duration(days: i + 1)));
    }
    // Current month days
    for (int i = 0; i < lastDay.day; i++) {
      days.add(DateTime(_currentMonth.year, _currentMonth.month, i + 1));
    }
    // Next month days to fill grid
    final remaining = 42 - days.length;
    for (int i = 1; i <= remaining; i++) {
      days.add(lastDay.add(Duration(days: i)));
    }
    return days;
  }

  Map<String, dynamic>? _getRecordForDay(DateTime day) {
    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    return _attendanceData[dateStr];
  }

  @override
  Widget build(BuildContext context) {
    final days = _getDaysInMonth();

    // Calculate stats
    int present = 0, late = 0, outside = 0;
    for (var data in _attendanceData.values) {
      final status = (data['status'] as String?)?.toUpperCase() ?? '';
      if (status == 'PRESENT') {
        present++;
      } else if (status == 'LATE') {
        late++;
      } else if (status == 'OUTSIDE') {
        outside++;
      }
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width > 600
            ? 500
            : MediaQuery.of(context).size.width * 0.9,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Color(0xFF6366F1),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.userName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const Text(
                        'Monthly Attendance',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Month selector
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() {
                      _currentMonth = DateTime(
                        _currentMonth.year,
                        _currentMonth.month - 1,
                      );
                    });
                    _fetchMonthData();
                  },
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_currentMonth),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() {
                      _currentMonth = DateTime(
                        _currentMonth.year,
                        _currentMonth.month + 1,
                      );
                    });
                    _fetchMonthData();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatChip('Present', present, const Color(0xFF22C55E)),
                _buildStatChip('Late', late, const Color(0xFFF59E0B)),
                _buildStatChip('Outside', outside, const Color(0xFFF97316)),
              ],
            ),
            const SizedBox(height: 20),

            // Day headers
            Row(
              children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                  .map(
                    (day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),

            // Calendar grid
            _isLoading
                ? const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : SizedBox(
                    height: 240,
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                      itemCount: days.length,
                      itemBuilder: (context, index) {
                        final day = days[index];
                        final record = _getRecordForDay(day);
                        final hasRecord = record != null;
                        final isCurrentMonth = day.month == _currentMonth.month;
                        final isToday =
                            DateFormat('yyyy-MM-dd').format(day) ==
                            DateFormat('yyyy-MM-dd').format(DateTime.now());

                        bool isLeaveDay = false;
                        if (isCurrentMonth) {
                          final dayStr = DateFormat('yyyy-MM-dd').format(day);
                          for (var doc in _approvedLeaves) {
                            final data = doc.data() as Map<String, dynamic>;
                            final start = data['startDate'] as String?;
                            final end = data['endDate'] as String?;
                            if (start != null && end != null) {
                              if (dayStr.compareTo(start) >= 0 && dayStr.compareTo(end) <= 0) {
                                isLeaveDay = true;
                                break;
                              }
                            }
                          }
                        }

                        Color? bgColor;
                        Color? borderColor;
                        String? statusLabel;

                        if (isLeaveDay) {
                          bgColor = const Color(0xFFFAF5FF);
                          borderColor = const Color(0xFFD8B4FE);
                          statusLabel = 'LV';
                        } else if (hasRecord && isCurrentMonth) {
                          final status =
                              (record['status'] as String?)?.toUpperCase() ??
                              '';
                          if (status == 'PRESENT') {
                            bgColor = const Color(0xFFF0FDF4);
                            borderColor = const Color(0xFF22C55E);
                            statusLabel = 'P';
                          } else if (status == 'LATE') {
                            bgColor = const Color(0xFFFEF3C7);
                            borderColor = const Color(0xFFF59E0B);
                            statusLabel = 'L';
                          } else if (status == 'OUTSIDE') {
                            bgColor = const Color(0xFFFFF7ED);
                            borderColor = const Color(0xFFF97316);
                            statusLabel = 'O';
                          }
                        }

                        return InkWell(
                          onTap: hasRecord && isCurrentMonth
                              ? () => _showDateDetails(day, record)
                              : null,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            decoration: BoxDecoration(
                              color:
                                  bgColor ??
                                  (isCurrentMonth
                                      ? Colors.white
                                      : Colors.grey.shade50),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isToday
                                    ? const Color(0xFF6366F1)
                                    : borderColor ?? Colors.grey.shade200,
                                width: isToday ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${day.day}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isCurrentMonth
                                        ? const Color(0xFF1E293B)
                                        : Colors.grey.shade400,
                                  ),
                                ),
                                if (statusLabel != null)
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: statusLabel == 'LV'
                                          ? const Color(0xFFA855F7)
                                          : borderColor,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

            // Legend
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('P', 'Present', const Color(0xFF22C55E)),
                const SizedBox(width: 12),
                _buildLegendItem('L', 'Late', const Color(0xFFF59E0B)),
                const SizedBox(width: 12),
                _buildLegendItem('O', 'Outside', const Color(0xFFF97316)),
                const SizedBox(width: 12),
                _buildLegendItem('LV', 'Leave', const Color(0xFFA855F7)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  void _showDateDetails(DateTime day, Map<String, dynamic> record) {
    final checkIn = record['checkInTime'] as String?;
    final checkOut = record['checkOutTime'] as String?;
    final status = record['status'] as String? ?? 'pending';
    final insideTimeVal = (record['insideTime'] as num?)?.toInt() ?? 0;
    final outsideTime = (record['outsideTime'] as num?)?.toInt() ?? 0;
    final offlineTime = (record['offlineTime'] as num?)?.toInt() ?? 0;
    final insideTime = insideTimeVal + offlineTime;
    final totalHours = (record['totalHours'] as num?)?.toDouble() ?? 0.0;
    final atOffice = record['atOffice'] as bool? ?? false;
    final checkInMethod = record['checkInMethod'] as String? ?? 'manual';
    final autoCheckedIn = record['autoCheckedIn'] as bool? ?? false;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'present':
        statusColor = const Color(0xFF22C55E);
        statusLabel = 'Present';
        break;
      case 'late':
        statusColor = const Color(0xFFF59E0B);
        statusLabel = 'Late';
        break;
      case 'outside':
        statusColor = const Color(0xFFF97316);
        statusLabel = 'Outside';
        break;
      default:
        statusColor = const Color(0xFF64748B);
        statusLabel = 'Pending';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.event_note,
                        color: statusColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('EEEE, MMMM d').format(day),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: statusColor),
                            ),
                            child: Text(
                              statusLabel.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),

                // Time details
                if (checkIn != null) ...[
                  _buildDetailRow(
                    Icons.login,
                    const Color(0xFF22C55E),
                    'Check In',
                    DateFormat(
                      'hh:mm a',
                    ).format(DateTime.parse(checkIn).toLocal()),
                  ),
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    Icons.logout,
                    const Color(0xFFF97316),
                    'Check Out',
                    checkOut != null
                        ? DateFormat(
                            'hh:mm a',
                          ).format(DateTime.parse(checkOut).toLocal())
                        : 'Active',
                  ),
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    Icons.timelapse,
                    const Color(0xFF6366F1),
                    'Total Hours',
                    '${totalHours.toStringAsFixed(1)} hrs',
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 12),
                ],

                // Location status
                _buildDetailRow(
                  atOffice ? Icons.location_on : Icons.location_off,
                  atOffice ? const Color(0xFF22C55E) : const Color(0xFFF97316),
                  'Location',
                  atOffice ? 'In Office' : 'Out of Office',
                ),
                const SizedBox(height: 12),

                // Time breakdown
                if (insideTime > 0 || outsideTime > 0 || offlineTime > 0) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 12),
                  const Text(
                    'Time Breakdown',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (insideTime > 0)
                    _buildTimePill(
                      'Inside Office',
                      '${insideTime ~/ 60}h ${insideTime % 60}m',
                      const Color(0xFF22C55E),
                    ),
                  if (outsideTime > 0) ...[
                    const SizedBox(height: 8),
                    _buildTimePill(
                      'Outside Office',
                      '${outsideTime ~/ 60}h ${outsideTime % 60}m',
                      const Color(0xFFF97316),
                    ),
                  ],
                  if (offlineTime > 0) ...[
                    const SizedBox(height: 8),
                    _buildTimePill(
                      'Offline',
                      '${offlineTime ~/ 60}h ${offlineTime % 60}m',
                      const Color(0xFF64748B),
                    ),
                  ],
                ],

                // Auto check-in indicator
                if (autoCheckedIn) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.auto_fix_high,
                          size: 16,
                          color: Color(0xFF6366F1),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Auto Check-in via ${checkInMethod.replaceAll('_', ' ').toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6366F1),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    Color color,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimePill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

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
