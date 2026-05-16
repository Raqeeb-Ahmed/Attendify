import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminAttendanceScreen extends StatefulWidget {
  final String selectedDate;
  final bool isMobile;
  final VoidCallback? onMenuPressed;
  const AdminAttendanceScreen({super.key, required this.selectedDate, this.isMobile = false, this.onMenuPressed});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  late String _selectedDate;
  String _searchQuery = '';
  String _filterStatus = 'All';

  final List<String> _statusFilters = ['All', 'present', 'late', 'outside', 'pending'];

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
        data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6366F1))),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = DateFormat('yyyy-MM-dd').format(picked));
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
            _buildFilterRow(isMobile),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('attendance')
                    .where('date', isEqualTo: _selectedDate)
                    .snapshots(),
                builder: (context, attSnap) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('users').snapshots(),
                    builder: (context, usersSnap) {
                      final attDocs = attSnap.data?.docs ?? [];
                      final userDocs = usersSnap.data?.docs ?? [];

                      final userMap = <String, Map<String, dynamic>>{};
                      for (var u in userDocs) { userMap[u.id] = u.data() as Map<String, dynamic>; }

                      final checkedInIds = attDocs.map((d) => (d.data() as Map<String, dynamic>)['userId'] as String? ?? '').toSet();
                      final pendingUsers = userDocs
                          .where((u) => (u.data() as Map<String, dynamic>)['role'] != 'admin' && !checkedInIds.contains(u.id))
                          .toList();

                      final allRecords = [
                        ...attDocs.map((doc) {
                          final d = doc.data() as Map<String, dynamic>;
                          return {'type': 'att', 'data': d};
                        }),
                        ...pendingUsers.map((u) {
                          final d = u.data() as Map<String, dynamic>;
                          return {
                            'type': 'pending',
                            'data': {'userId': u.id, 'userName': d['name'] ?? '', 'email': d['email'] ?? '', 'status': 'pending'}
                          };
                        }),
                      ];

                      final filtered = allRecords.where((rec) {
                        final d = rec['data'] as Map<String, dynamic>;
                        final name = (d['userName'] as String? ?? '').toLowerCase();
                        final email = (d['email'] as String? ?? '').toLowerCase();
                        final status = d['status'] as String? ?? 'pending';
                        final matchSearch = name.contains(_searchQuery.toLowerCase()) || email.contains(_searchQuery.toLowerCase());
                        final matchStatus = _filterStatus == 'All' || status == _filterStatus;
                        return matchSearch && matchStatus;
                      }).toList();

                      if (attSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));
                      }

                      if (filtered.isEmpty) {
                        return Center(child: Text('No records found', style: TextStyle(color: Colors.grey.shade400)));
                      }

                      return ListView.builder(
                        padding: EdgeInsets.all(isMobile ? 16 : 24),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) => _buildAttendanceCard(filtered[i]['data'] as Map<String, dynamic>),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          if (isMobile && widget.onMenuPressed != null)
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: widget.onMenuPressed,
            ),
          const Icon(Icons.calendar_month_rounded, color: Color(0xFF6366F1), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Daily Attendance',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                Text('Check-in status and time logs',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              ],
            ),
          ),
          if (!isMobile)
            GestureDetector(
              onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text(DateFormat('dd MMM yyyy').format(DateTime.parse(_selectedDate)),
                      style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
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
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: Color(0xFF6366F1))),
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
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFF6366F1) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        s == 'All' ? 'All' : s[0].toUpperCase() + s.substring(1),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isActive ? Colors.white : Colors.grey.shade600),
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

    Color statusColor;
    Color statusBg;
    String statusLabel;
    switch (status) {
      case 'present':
        statusColor = const Color(0xFF16A34A); statusBg = const Color(0xFFDCFCE7); statusLabel = 'Present';
        break;
      case 'late':
        statusColor = const Color(0xFFCA8A04); statusBg = const Color(0xFFFEF9C3); statusLabel = 'Late';
        break;
      case 'outside':
        statusColor = const Color(0xFFEA580C); statusBg = const Color(0xFFFFEDD5); statusLabel = 'Out of System';
        break;
      default:
        statusColor = const Color(0xFF64748B); statusBg = const Color(0xFFF1F5F9); statusLabel = 'Pending';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: statusColor, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
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
                      Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                      Text(email, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(10)),
                  child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                ),
                if (userId.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _showEmployeeCalendar(userId, name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_month, size: 14, color: Color(0xFF6366F1)),
                          SizedBox(width: 4),
                          Text('View', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF6366F1))),
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
                  _attStat('Check In', DateFormat('hh:mm a').format(DateTime.parse(checkIn).toLocal()), const Color(0xFF22C55E)),
                  const SizedBox(width: 20),
                  _attStat('Check Out', checkOut != null ? DateFormat('hh:mm a').format(DateTime.parse(checkOut).toLocal()) : 'Active', const Color(0xFFF97316)),
                  const SizedBox(width: 20),
                  _attStat('Total Hours', '${totalHours.toStringAsFixed(1)}h', const Color(0xFF6366F1)),
                  const Spacer(),
                  if (atOffice)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(8)),
                      child: const Text('IN OFFICE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _timePill('Inside', '${insideTime ~/ 60}h ${insideTime % 60}m', const Color(0xFF22C55E)),
                  const SizedBox(width: 8),
                  _timePill('Outside', '${outsideTime ~/ 60}h ${outsideTime % 60}m', const Color(0xFFF97316)),
                ],
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
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w600)),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
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
      child: Text('$label: $value',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  /// Show monthly calendar dialog for an employee
  void _showEmployeeCalendar(String userId, String userName) {
    showDialog(
      context: context,
      builder: (context) => _EmployeeCalendarDialog(
        userId: userId,
        userName: userName,
      ),
    );
  }
}

/// Monthly calendar dialog for viewing employee attendance
class _EmployeeCalendarDialog extends StatefulWidget {
  final String userId;
  final String userName;

  const _EmployeeCalendarDialog({
    required this.userId,
    required this.userName,
  });

  @override
  State<_EmployeeCalendarDialog> createState() => _EmployeeCalendarDialogState();
}

class _EmployeeCalendarDialogState extends State<_EmployeeCalendarDialog> {
  DateTime _currentMonth = DateTime.now();
  Map<String, Map<String, dynamic>> _attendanceData = {};
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
          .where('date', isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(startDate))
          .where('date', isLessThanOrEqualTo: DateFormat('yyyy-MM-dd').format(endDate))
          .get();

      final data = <String, Map<String, dynamic>>{};
      for (var doc in snapshot.docs) {
        final d = doc.data();
        data[d['date'] as String] = d;
      }

      setState(() {
        _attendanceData = data;
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
        width: MediaQuery.of(context).size.width > 600 ? 500 : MediaQuery.of(context).size.width * 0.9,
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
                  child: const Icon(Icons.person, color: Color(0xFF6366F1), size: 24),
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
                        style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
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
                      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
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
                      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
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
              children: ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((day) =>
                Expanded(
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
              ).toList(),
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
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                        final isToday = DateFormat('yyyy-MM-dd').format(day) == DateFormat('yyyy-MM-dd').format(DateTime.now());

                        Color? bgColor;
                        Color? borderColor;
                        String? statusLabel;

                        if (hasRecord && isCurrentMonth) {
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
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            decoration: BoxDecoration(
                              color: bgColor ?? (isCurrentMonth ? Colors.white : Colors.grey.shade50),
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
                                    color: isCurrentMonth ? const Color(0xFF1E293B) : Colors.grey.shade400,
                                  ),
                                ),
                                if (statusLabel != null)
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: borderColor,
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
                const SizedBox(width: 16),
                _buildLegendItem('L', 'Late', const Color(0xFFF59E0B)),
                const SizedBox(width: 16),
                _buildLegendItem('O', 'Outside', const Color(0xFFF97316)),
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
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
            ),
          ),
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
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  void _showDateDetails(DateTime day, Map<String, dynamic> record) {
    final checkIn = record['checkInTime'] as String?;
    final checkOut = record['checkOutTime'] as String?;
    final status = record['status'] as String? ?? 'pending';
    final insideTime = (record['insideTime'] as num?)?.toInt() ?? 0;
    final outsideTime = (record['outsideTime'] as num?)?.toInt() ?? 0;
    final offlineTime = (record['offlineTime'] as num?)?.toInt() ?? 0;
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
                  child: Icon(Icons.event_note, color: statusColor, size: 24),
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                DateFormat('hh:mm a').format(DateTime.parse(checkIn).toLocal()),
              ),
              const SizedBox(height: 12),
              _buildDetailRow(
                Icons.logout,
                const Color(0xFFF97316),
                'Check Out',
                checkOut != null
                    ? DateFormat('hh:mm a').format(DateTime.parse(checkOut).toLocal())
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
                _buildTimePill('Inside Office', '${insideTime ~/ 60}h ${insideTime % 60}m', const Color(0xFF22C55E)),
              if (outsideTime > 0) ...[
                const SizedBox(height: 8),
                _buildTimePill('Outside Office', '${outsideTime ~/ 60}h ${outsideTime % 60}m', const Color(0xFFF97316)),
              ],
              if (offlineTime > 0) ...[
                const SizedBox(height: 8),
                _buildTimePill('Offline', '${offlineTime ~/ 60}h ${offlineTime % 60}m', const Color(0xFF64748B)),
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
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_fix_high, size: 16, color: Color(0xFF6366F1)),
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
    ),)
  );
}

  Widget _buildDetailRow(IconData icon, Color color, String label, String value) {
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
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
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
