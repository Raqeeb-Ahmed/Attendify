import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class MonthlyProgressWidget extends StatefulWidget {
  final String userId;
  final DateTime selectedMonth;

  const MonthlyProgressWidget({
    super.key,
    required this.userId,
    required this.selectedMonth,
  });

  @override
  State<MonthlyProgressWidget> createState() => _MonthlyProgressWidgetState();
}

class _MonthlyProgressWidgetState extends State<MonthlyProgressWidget> {
  bool _isLoading = true;
  Map<String, dynamic> _monthlyStats = {};

  @override
  void initState() {
    super.initState();
    _fetchMonthlyStats();
  }

  @override
  void didUpdateWidget(MonthlyProgressWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedMonth != widget.selectedMonth) {
      _fetchMonthlyStats();
    }
  }

  Future<void> _fetchMonthlyStats() async {
    setState(() => _isLoading = true);
    
    try {
      final startDate = DateTime(widget.selectedMonth.year, widget.selectedMonth.month, 1);
      final endDate = DateTime(widget.selectedMonth.year, widget.selectedMonth.month + 1, 0);
      
      final snapshot = await FirebaseFirestore.instance
          .collection('attendance')
          .where('userId', isEqualTo: widget.userId)
          .where('date', isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(startDate))
          .where('date', isLessThanOrEqualTo: DateFormat('yyyy-MM-dd').format(endDate))
          .get();
      
      final stats = _calculateMonthlyStats(snapshot.docs);
      setState(() {
        _monthlyStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching monthly stats: $e');
      setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _calculateMonthlyStats(List<DocumentSnapshot> docs) {
    int totalDays = 0;
    int presentDays = 0;
    int lateDays = 0;
    int absentDays = 0;
    int outsideDays = 0;
    double totalLateMinutes = 0;
    double totalExtraMinutes = 0;
    double totalWorkMinutes = 0;
    double totalInsideMinutes = 0;
    double totalOutsideMinutes = 0;

    final workingDaysInMonth = _getWorkingDaysInMonth(widget.selectedMonth);

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = (data['status'] as String?)?.toUpperCase() ?? 'PENDING';
      
      totalDays++;
      
      switch (status) {
        case 'PRESENT':
          presentDays++;
          break;
        case 'LATE':
          lateDays++;
          break;
        case 'OUTSIDE':
          outsideDays++;
          break;
        case 'ABSENT':
          absentDays++;
          break;
      }

      // Calculate time-based metrics
      final insideTime = (data['insideTime'] as num?)?.toDouble() ?? 0;
      final outsideTime = (data['outsideTime'] as num?)?.toDouble() ?? 0;
      final extraHours = (data['extraHours'] as num?)?.toDouble() ?? 0;
      final totalHours = (data['totalHours'] as num?)?.toDouble() ?? 0;

      totalInsideMinutes += insideTime;
      totalOutsideMinutes += outsideTime;
      totalExtraMinutes += extraHours;
      totalWorkMinutes += totalHours * 60;

      // Calculate late minutes (simplified - assumes 9:45 AM start time)
      if (status == 'LATE' && data['checkInTime'] != null) {
        final checkInTime = DateTime.parse(data['checkInTime'] as String).toLocal();
        final officeStartTime = DateTime(checkInTime.year, checkInTime.month, checkInTime.day, 9, 45);
        if (checkInTime.isAfter(officeStartTime)) {
          totalLateMinutes += checkInTime.difference(officeStartTime).inMinutes;
        }
      }
    }

    // Calculate absent days (working days - total recorded days)
    absentDays = workingDaysInMonth - totalDays;

    final attendanceRate = workingDaysInMonth > 0 
        ? ((presentDays + lateDays) / workingDaysInMonth) * 100 
        : 0.0;

    return {
      'totalDays': totalDays,
      'presentDays': presentDays,
      'lateDays': lateDays,
      'absentDays': absentDays,
      'outsideDays': outsideDays,
      'workingDaysInMonth': workingDaysInMonth,
      'totalLateMinutes': totalLateMinutes,
      'totalExtraMinutes': totalExtraMinutes,
      'totalWorkMinutes': totalWorkMinutes,
      'totalInsideMinutes': totalInsideMinutes,
      'totalOutsideMinutes': totalOutsideMinutes,
      'attendanceRate': attendanceRate,
    };
  }

  int _getWorkingDaysInMonth(DateTime month) {
    int workingDays = 0;
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    
    for (DateTime day = firstDay; day.isBefore(lastDay.add(const Duration(days: 1))); day = day.add(const Duration(days: 1))) {
      // Skip only Sundays (Sunday = 7). Saturday is a working day.
      if (day.weekday < 7) {
        workingDays++;
      }
    }
    return workingDays;
  }

  String _formatDuration(double minutes) {
    final hours = minutes ~/ 60;
    final mins = (minutes % 60).round();
    return '${hours}h ${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1))),
      );
    }

    return Container(
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
          // Header
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
                  child: const Icon(Icons.analytics, color: Color(0xFF6366F1), size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Monthly Progress',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        DateFormat('MMMM yyyy').format(widget.selectedMonth),
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
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          
          // Stats Grid
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Attendance Overview
                _buildAttendanceOverview(),
                const SizedBox(height: 24),
                
                // Time Metrics
                _buildTimeMetrics(),
                const SizedBox(height: 24),
                
                // Progress Bars
                _buildProgressBars(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ATTENDANCE OVERVIEW',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildStatCard('Present', '${_monthlyStats['presentDays']}', Icons.check_circle, const Color(0xFF22C55E))),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard('Late', '${_monthlyStats['lateDays']}', Icons.warning_amber, const Color(0xFFF59E0B))),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard('Absent', '${_monthlyStats['absentDays']}', Icons.cancel, const Color(0xFFEF4444))),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard('Outside', '${_monthlyStats['outsideDays']}', Icons.location_off, const Color(0xFFF97316))),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeMetrics() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TIME METRICS',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildTimeCard('Late Hours', _formatDuration(_monthlyStats['totalLateMinutes'] ?? 0), Icons.schedule, const Color(0xFFF59E0B))),
            const SizedBox(width: 12),
            Expanded(child: _buildTimeCard('Extra Hours', _formatDuration(_monthlyStats['totalExtraMinutes'] ?? 0), Icons.access_time, const Color(0xFF8B5CF6))),
            const SizedBox(width: 12),
            Expanded(child: _buildTimeCard('Total Work', _formatDuration(_monthlyStats['totalWorkMinutes'] ?? 0), Icons.work, const Color(0xFF6366F1))),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressBars() {
    final attendanceRate = (_monthlyStats['attendanceRate'] as double?) ?? 0.0;
    final workingDays = (_monthlyStats['workingDaysInMonth'] as int?) ?? 1;
    final presentDays = (_monthlyStats['presentDays'] as int?) ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PERFORMANCE INDICATORS',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        
        // Attendance Rate Progress
        _buildProgressBar(
          'Attendance Rate',
          '${attendanceRate.toStringAsFixed(1)}%',
          attendanceRate / 100,
          const Color(0xFF22C55E),
        ),
        const SizedBox(height: 16),
        
        // Punctuality Progress
        _buildProgressBar(
          'Punctuality Rate',
          '${(workingDays > 0 ? (presentDays / workingDays) * 100 : 0.0).toStringAsFixed(1)}%',
          (workingDays > 0 ? (presentDays / workingDays) * 100 : 0.0) / 100,
          const Color(0xFF6366F1),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(String label, String value, double progress, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
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
        const SizedBox(height: 8),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
