import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../widgets/app_shimmer.dart';

class HRAnalyticsScreen extends StatefulWidget {
  final bool isMobile;
  final VoidCallback? onMenuPressed;
  const HRAnalyticsScreen({
    super.key,
    this.isMobile = false,
    this.onMenuPressed,
  });

  @override
  State<HRAnalyticsScreen> createState() => _HRAnalyticsScreenState();
}

class _HRAnalyticsScreenState extends State<HRAnalyticsScreen> {
  late Stream<QuerySnapshot> _usersStream;
  late Stream<QuerySnapshot> _attendanceStream;
  late Stream<QuerySnapshot> _leavesStream;
  late Stream<QuerySnapshot> _expensesStream;

  @override
  void initState() {
    super.initState();
    _usersStream = FirebaseFirestore.instance
        .collection('users')
        .where('role', whereIn: const ['employee', 'manager'])
        .snapshots();
    _attendanceStream = FirebaseFirestore.instance
        .collection('attendance')
        .where(
          'date',
          isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(
            DateTime.now().subtract(const Duration(days: 30)),
          ),
        )
        .limit(300)
        .snapshots();
    _leavesStream = FirebaseFirestore.instance
        .collection('leaves')
        .where('status', isEqualTo: 'approved')
        .limit(50)
        .snapshots();
    _expensesStream = FirebaseFirestore.instance
        .collection('expenses')
        .where('status', isEqualTo: 'approved')
        .limit(50)
        .snapshots();
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
            _buildTopBar(isMobile, widget.onMenuPressed),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _usersStream,
                builder: (ctx, usersSnap) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: _attendanceStream,
                    builder: (ctx, attSnap) {
                      return StreamBuilder<QuerySnapshot>(
                        stream: _leavesStream,
                        builder: (ctx, leavesSnap) {
                          return StreamBuilder<QuerySnapshot>(
                            stream: _expensesStream,
                            builder: (ctx, expSnap) {
                              if (usersSnap.connectionState ==
                                      ConnectionState.waiting ||
                                  attSnap.connectionState ==
                                      ConnectionState.waiting ||
                                  leavesSnap.connectionState ==
                                      ConnectionState.waiting ||
                                  expSnap.connectionState ==
                                      ConnectionState.waiting) {
                                return Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: AppShimmer.metricsGrid(count: 4),
                                );
                              }

                              final totalEmp = usersSnap.data?.docs.length ?? 0;
                              final attDocs = attSnap.data?.docs ?? [];
                              final leaveDocs = leavesSnap.data?.docs ?? [];
                              final expDocs = expSnap.data?.docs ?? [];

                              int presentToday = 0;
                              int lateToday = 0;
                              int outsideToday = 0;
                              final today = DateFormat(
                                'yyyy-MM-dd',
                              ).format(DateTime.now());

                              final deptMap = <String, int>{};
                              final deptLate = <String, int>{};

                              for (var doc in attDocs) {
                                final d = doc.data() as Map<String, dynamic>;
                                final dept =
                                    d['department'] as String? ?? 'Unknown';
                                if (d['date'] == today) {
                                  final s = d['status'] as String? ?? '';
                                  if (s == 'present') {
                                    presentToday++;
                                  } else if (s == 'late') {
                                    lateToday++;
                                    deptLate[dept] = (deptLate[dept] ?? 0) + 1;
                                  } else if (s == 'outside') {
                                    outsideToday++;
                                  }
                                }
                                deptMap[dept] = (deptMap[dept] ?? 0) + 1;
                              }

                              double totalExpenses = 0;
                              for (var doc in expDocs) {
                                totalExpenses +=
                                    ((doc.data()
                                                as Map<
                                                  String,
                                                  dynamic
                                                >)['amount']
                                            as num?)
                                        ?.toDouble() ??
                                    0;
                              }

                              final fmt = NumberFormat('#,##0', 'en_US');

                              return SingleChildScrollView(
                                padding: EdgeInsets.all(isMobile ? 16 : 24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // KPI Cards
                                    _sectionTitle('Today\'s Overview'),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 14,
                                      runSpacing: 14,
                                      children: [
                                        _kpiCard(
                                          'Total Employees',
                                          '$totalEmp',
                                          Icons.people_rounded,
                                          const Color(0xFF6366F1),
                                          const Color(0xFFEEF2FF),
                                        ),
                                        _kpiCard(
                                          'Present Today',
                                          '$presentToday',
                                          Icons.check_circle_rounded,
                                          const Color(0xFF22C55E),
                                          const Color(0xFFF0FDF4),
                                        ),
                                        _kpiCard(
                                          'Late Today',
                                          '$lateToday',
                                          Icons.warning_amber_rounded,
                                          const Color(0xFFF59E0B),
                                          const Color(0xFFFEF3C7),
                                        ),
                                        _kpiCard(
                                          'Out of System',
                                          '$outsideToday',
                                          Icons.logout_rounded,
                                          const Color(0xFFF97316),
                                          const Color(0xFFFFF7ED),
                                        ),
                                        _kpiCard(
                                          'Approved Leaves',
                                          '${leaveDocs.length}',
                                          Icons.beach_access_rounded,
                                          const Color(0xFF06B6D4),
                                          const Color(0xFFECFEFF),
                                        ),
                                        _kpiCard(
                                          'Total Expenses',
                                          'PKR ${fmt.format(totalExpenses)}',
                                          Icons.account_balance_wallet_rounded,
                                          const Color(0xFF8B5CF6),
                                          const Color(0xFFF5F3FF),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),

                                    // Attendance trend
                                    _sectionTitle('Attendance Rate'),
                                    const SizedBox(height: 12),
                                    _buildAttendanceRateCard(
                                      totalEmp,
                                      presentToday,
                                      lateToday,
                                      outsideToday,
                                    ),
                                    const SizedBox(height: 24),

                                    // Department breakdown
                                    if (deptMap.isNotEmpty) ...[
                                      _sectionTitle('Activity by Department'),
                                      const SizedBox(height: 12),
                                      _buildDeptBreakdown(deptMap, deptLate),
                                      const SizedBox(height: 24),
                                    ],

                                    // Recent attendance list
                                    _sectionTitle('Recent Attendance (Today)'),
                                    const SizedBox(height: 12),
                                    _buildRecentAttendance(attDocs, today),
                                  ],
                                ),
                              );
                            },
                          );
                        },
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

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1E293B),
      ),
    );
  }

  Widget _buildTopBar(bool isMobile, VoidCallback? onMenuPressed) {
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
          if (isMobile && onMenuPressed != null)
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: onMenuPressed,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          if (isMobile && onMenuPressed != null) const SizedBox(width: 8),
          const Icon(
            Icons.bar_chart_rounded,
            color: Color(0xFF6366F1),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HR Analytics',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                Text(
                  'Workforce insights and KPIs',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isMobile ? 10 : 12,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(
    String label,
    String value,
    IconData icon,
    Color color,
    Color bg,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final cardWidth = isMobile ? (screenWidth - 32 - 14) / 2 : 170.0;
    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceRateCard(
    int total,
    int present,
    int late,
    int outside,
  ) {
    final rate = total > 0 ? ((present + late) / total * 100).round() : 0;
    final pendingCount = total - present - late - outside;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$rate%',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: rate >= 80
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attendance Rate',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Text(
                      '$total total employees',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (present > 0)
                    Expanded(
                      flex: present,
                      child: Container(color: const Color(0xFF22C55E)),
                    ),
                  if (late > 0)
                    Expanded(
                      flex: late,
                      child: Container(color: const Color(0xFFF59E0B)),
                    ),
                  if (outside > 0)
                    Expanded(
                      flex: outside,
                      child: Container(color: const Color(0xFFF97316)),
                    ),
                  if (pendingCount > 0)
                    Expanded(
                      flex: pendingCount,
                      child: Container(color: const Color(0xFFCBD5E1)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _legendItem(const Color(0xFF22C55E), 'Present: $present'),
              _legendItem(const Color(0xFFF59E0B), 'Late: $late'),
              _legendItem(const Color(0xFFF97316), 'Outside: $outside'),
              _legendItem(const Color(0xFFCBD5E1), 'Pending: $pendingCount'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
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
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDeptBreakdown(
    Map<String, int> deptMap,
    Map<String, int> deptLate,
  ) {
    final sorted = deptMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.isEmpty) return const SizedBox.shrink();
    final max = sorted.first.value;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: sorted.map((entry) {
          final lateCount = deptLate[entry.key] ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: MediaQuery.of(context).size.width < 450 ? 80 : 110,
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: entry.value / max,
                      minHeight: 8,
                      backgroundColor: const Color(0xFFEEF2FF),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF6366F1),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 30,
                  child: Text(
                    '${entry.value}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                if (lateCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF9C3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$lateCount late',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFCA8A04),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRecentAttendance(
    List<QueryDocumentSnapshot> docs,
    String today,
  ) {
    final todayDocs = docs
        .where((d) => (d.data() as Map<String, dynamic>)['date'] == today)
        .take(10)
        .toList();

    if (todayDocs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            'No attendance records for today',
            style: TextStyle(color: Colors.grey.shade400),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: todayDocs.map((doc) {
          final d = doc.data() as Map<String, dynamic>;
          final name = d['userName'] as String? ?? 'Unknown';
          final status = d['status'] as String? ?? 'pending';
          final checkIn = d['checkInTime'] as String?;
          final checkInStr = checkIn != null
              ? DateFormat('hh:mm a').format(DateTime.parse(checkIn).toLocal())
              : '--';

          Color statusColor;
          Color statusBg;
          switch (status) {
            case 'present':
              statusColor = const Color(0xFF16A34A);
              statusBg = const Color(0xFFDCFCE7);
              break;
            case 'late':
              statusColor = const Color(0xFFCA8A04);
              statusBg = const Color(0xFFFEF9C3);
              break;
            case 'outside':
              statusColor = const Color(0xFFEA580C);
              statusBg = const Color(0xFFFFEDD5);
              break;
            default:
              statusColor = const Color(0xFF64748B);
              statusBg = const Color(0xFFF1F5F9);
          }

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                Text(
                  checkInStr,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status[0].toUpperCase() + status.substring(1),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
