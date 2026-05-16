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
}
