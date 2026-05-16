import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../utils/app_config.dart';
import 'package:intl/intl.dart';

class PastAttendanceScreen extends StatefulWidget {
  const PastAttendanceScreen({super.key});

  @override
  State<PastAttendanceScreen> createState() => _PastAttendanceScreenState();
}

class _PastAttendanceScreenState extends State<PastAttendanceScreen> {
  final user = FirebaseAuth.instance.currentUser;
  
  DateTime _currentMonth = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  
  List<Map<String, dynamic>> _attendanceRecords = [];
  List<Map<String, dynamic>> _dayLocations = [];
  
  bool _isLoading = true;
  bool _isLoadingLocations = false;

  late final double _officeLat;
  late final double _officeLng;

  @override
  void initState() {
    super.initState();
    _officeLat = AppConfig.officeLat;
    _officeLng = AppConfig.officeLng;
    _fetchMonthData();
    _fetchDayLocations();
  }

  Future<void> _fetchMonthData() async {
    if (user == null) return;
    
    setState(() => _isLoading = true);
    try {
      final startDate = DateTime(_currentMonth.year, _currentMonth.month, 1);
      final endDate = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
      
      final snapshot = await FirebaseFirestore.instance
          .collection('attendance')
          .where('userId', isEqualTo: user!.uid)
          .where('date', isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(startDate))
          .where('date', isLessThanOrEqualTo: DateFormat('yyyy-MM-dd').format(endDate))
          .get();
      
      setState(() {
        _attendanceRecords = snapshot.docs.map((doc) => {
          'id': doc.id,
          ...doc.data(),
        }).toList();
      });
    } catch (e) {
      debugPrint('Error fetching attendance: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchDayLocations() async {
    if (user == null) return;
    
    setState(() => _isLoadingLocations = true);
    try {
      final dayStr = DateFormat('yyyy-MM-dd').format(_selectedDay);
      final startTime = '${dayStr}T00:00:00.000Z';
      final endTime = '${dayStr}T23:59:59.999Z';
      
      final snapshot = await FirebaseFirestore.instance
          .collection('locations')
          .where('userId', isEqualTo: user!.uid)
          .where('timestamp', isGreaterThanOrEqualTo: startTime)
          .where('timestamp', isLessThanOrEqualTo: endTime)
          .orderBy('timestamp', descending: false)
          .get();
      
      setState(() {
        _dayLocations = snapshot.docs.map((doc) => {
          'id': doc.id,
          ...doc.data(),
        }).toList();
      });
    } catch (e) {
      debugPrint('Error fetching locations: $e');
    } finally {
      setState(() => _isLoadingLocations = false);
    }
  }

  List<DateTime> _getDaysInMonth() {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    
    // Start from the first day of the week containing the first day of month
    final startDate = firstDay.subtract(Duration(days: firstDay.weekday % 7));
    
    // End at the last day of the week containing the last day of month
    final endDate = lastDay.add(Duration(days: 6 - lastDay.weekday % 7));
    
    final days = <DateTime>[];
    for (var date = startDate; date.isBefore(endDate) || date.isAtSameMomentAs(endDate); date = date.add(const Duration(days: 1))) {
      days.add(date);
    }
    return days;
  }

  Map<String, dynamic>? _getRecordForDay(DateTime day) {
    final dayStr = DateFormat('yyyy-MM-dd').format(day);
    return _attendanceRecords.firstWhere(
      (record) => record['date'] == dayStr,
      orElse: () => {},
    );
  }

  int get _totalPresent => _attendanceRecords.where((r) => r['status'] == 'PRESENT' || r['status'] == 'present').length;
  int get _totalLate => _attendanceRecords.where((r) => r['status'] == 'LATE' || r['status'] == 'late').length;
  int get _totalOutside => _attendanceRecords.where((r) => r['status'] == 'OUTSIDE' || r['status'] == 'outside').length;
  int get _totalRecords => _attendanceRecords.length;

  @override
  Widget build(BuildContext context) {
    final selectedRecord = _getRecordForDay(_selectedDay);
    final hasRecord = selectedRecord != null && selectedRecord.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.04),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Menu',
        ),
        title: const Text(
          'Past Attendance',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Month Selector
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'View your attendance history',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left, size: 20),
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
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_right, size: 20),
                              onPressed: () {
                                setState(() {
                                  _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
                                });
                                _fetchMonthData();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Monthly Summary
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 4,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.2,
                    children: [
                      _buildSummaryCard('Present', _totalPresent.toString(), Icons.check_circle, const Color(0xFF22C55E)),
                      _buildSummaryCard('Late', _totalLate.toString(), Icons.warning_amber, const Color(0xFFF59E0B)),
                      _buildSummaryCard('Outside', _totalOutside.toString(), Icons.cancel, const Color(0xFFF97316)),
                      _buildSummaryCard('Rate', _totalRecords > 0 ? '${(((_totalPresent + _totalLate) / _totalRecords) * 100).round()}%' : '0%', Icons.trending_up, const Color(0xFF6366F1)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Calendar
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
                                child: const Icon(Icons.calendar_today, color: Color(0xFF6366F1), size: 18),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Attendance Calendar',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              // Day headers
                              Row(
                                children: ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((day) {
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
                                }).toList(),
                              ),
                              const SizedBox(height: 12),
                              // Calendar grid
                              _buildCalendarGrid(),
                            ],
                          ),
                        ),
                        // Legend
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildLegendItem('P', 'Present', const Color(0xFF22C55E)),
                              _buildLegendItem('L', 'Late', const Color(0xFFF59E0B)),
                              _buildLegendItem('O', 'Outside', const Color(0xFFF97316)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Day Details
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
                                child: const Icon(Icons.access_time, color: Color(0xFF6366F1), size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  DateFormat('EEEE, MMMM d, yyyy').format(_selectedDay),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              if (hasRecord)
                                _buildStatusBadge(selectedRecord['status'] ?? ''),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: hasRecord
                              ? Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildDetailCard(
                                            'Check-in',
                                            selectedRecord['checkInTime'] != null
                                                ? DateFormat('hh:mm a').format(DateTime.parse(selectedRecord['checkInTime'] as String).toLocal())
                                                : '--:--',
                                            Icons.login,
                                            const Color(0xFF6366F1),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _buildDetailCard(
                                            'Check-out',
                                            selectedRecord['checkOutTime'] != null
                                                ? DateFormat('hh:mm a').format(DateTime.parse(selectedRecord['checkOutTime'] as String).toLocal())
                                                : selectedRecord['sessionStatus'] == 'active' ? 'Active' : 'Auto 6 PM',
                                            Icons.logout_rounded,
                                            const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    _buildTimeAllocation(selectedRecord),
                                    const SizedBox(height: 16),
                                    _buildLocationMap(),
                                  ],
                                )
                              : Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(40),
                                    child: Column(
                                      children: [
                                        Icon(Icons.event_busy, size: 48, color: Colors.grey.shade300),
                                        const SizedBox(height: 12),
                                        Text(
                                          'No attendance record for this date',
                                          style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                                        ),
                                      ],
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
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF94A3B8),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final days = _getDaysInMonth();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        final record = _getRecordForDay(day);
        final hasRecord = record != null && record.isNotEmpty;
        final isCurrentMonth = day.month == _currentMonth.month;
        final isSelected = DateFormat('yyyy-MM-dd').format(day) == DateFormat('yyyy-MM-dd').format(_selectedDay);
        final isToday = DateFormat('yyyy-MM-dd').format(day) == DateFormat('yyyy-MM-dd').format(DateTime.now());
        final isFuture = day.isAfter(DateTime.now());

        Color? bgColor;
        Color? borderColor;
        String? statusLabel;

        if (hasRecord && isCurrentMonth && !isFuture) {
          final status = record['status']?.toString().toUpperCase() ?? '';
          if (status == 'PRESENT') {
            bgColor = const Color(0xFFF0FDF4);
            borderColor = const Color(0xFF86EFAC);
            statusLabel = 'P';
          } else if (status == 'LATE') {
            bgColor = const Color(0xFFFEF3C7);
            borderColor = const Color(0xFFFDE047);
            statusLabel = 'L';
          } else if (status == 'OUTSIDE') {
            bgColor = const Color(0xFFFFF7ED);
            borderColor = const Color(0xFFFED7AA);
            statusLabel = 'O';
          }
        }

        return InkWell(
          onTap: isFuture ? null : () {
            setState(() => _selectedDay = day);
            _fetchDayLocations();
          },
          child: Container(
            decoration: BoxDecoration(
              color: bgColor ?? (isCurrentMonth ? Colors.white : const Color(0xFFF8FAFC)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF6366F1)
                    : isToday
                        ? const Color(0xFF6366F1).withValues(alpha: 0.5)
                        : borderColor ?? const Color(0xFFE2E8F0),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isCurrentMonth ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                  ),
                ),
                if (statusLabel != null)
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusLabel == 'P'
                          ? const Color(0xFF22C55E)
                          : statusLabel == 'L'
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFFF97316),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLegendItem(String label, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status.toUpperCase()) {
      case 'PRESENT':
        bgColor = const Color(0xFFF0FDF4);
        textColor = const Color(0xFF16A34A);
        label = 'PRESENT';
        break;
      case 'LATE':
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFFF59E0B);
        label = 'LATE';
        break;
      case 'OUTSIDE':
        bgColor = const Color(0xFFFFF7ED);
        textColor = const Color(0xFFF97316);
        label = 'OUTSIDE';
        break;
      case 'AUTO-CHECKOUT':
        bgColor = const Color(0xFFEEF2FF);
        textColor = const Color(0xFF6366F1);
        label = 'AUTO-CHECKOUT';
        break;
      default:
        bgColor = const Color(0xFFF1F5F9);
        textColor = const Color(0xFF64748B);
        label = status.isEmpty ? 'PENDING' : status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }

  String _fmtMins(dynamic val) {
    final m = (val is num) ? val.toInt() : 0;
    return '${m ~/ 60}h ${m % 60}m';
  }

  Widget _buildTimeAllocation(Map<String, dynamic> record) {
    final insideTime = record['insideTime'];
    final outsideTime = record['outsideTime'];
    final offlineTime = record['offlineTime'];
    final extraHours = record['extraHours'];
    final totalHours = (record['totalHours'] as num?)?.toDouble() ?? 0.0;

    if (insideTime == null && outsideTime == null && extraHours == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('TIME ALLOCATION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 1)),
              const Spacer(),
              Text('Total: ${totalHours.toStringAsFixed(1)}h', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6366F1))),
            ],
          ),
          const SizedBox(height: 12),
          _timeAllocationRow('Inside Office', _fmtMins(insideTime), const Color(0xFF22C55E)),
          _timeAllocationRow('Outside Office', _fmtMins(outsideTime), const Color(0xFFF97316)),
          _timeAllocationRow('Offline / Idle', _fmtMins(offlineTime), const Color(0xFF94A3B8)),
          if ((extraHours is num) && extraHours > 0)
            _timeAllocationRow('Overtime', _fmtMins(extraHours), const Color(0xFF8B5CF6)),
        ],
      ),
    );
  }

  Widget _timeAllocationRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF475569), fontWeight: FontWeight.w500))),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildDetailCard(String label, String value, IconData icon, Color color) {
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
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationMap() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.map, size: 18, color: Color(0xFF6366F1)),
            const SizedBox(width: 8),
            const Text(
              'Location Trail',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_dayLocations.length} GPS points',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _isLoadingLocations
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
                : _dayLocations.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_off, size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              'No location data for this day',
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(_dayLocations[0]['lat'], _dayLocations[0]['lng']),
                          initialZoom: 15.0,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.attendo.app',
                          ),
                          // Office marker
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(_officeLat, _officeLng),
                                width: 40,
                                height: 40,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6366F1),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 3),
                                  ),
                                  child: const Icon(Icons.business, color: Colors.white, size: 20),
                                ),
                              ),
                              // Start point
                              if (_dayLocations.isNotEmpty)
                                Marker(
                                  point: LatLng(_dayLocations.first['lat'], _dayLocations.first['lng']),
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22C55E),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 3),
                                    ),
                                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                                  ),
                                ),
                              // End point
                              if (_dayLocations.length > 1)
                                Marker(
                                  point: LatLng(_dayLocations.last['lat'], _dayLocations.last['lng']),
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 3),
                                    ),
                                    child: const Icon(Icons.stop, color: Colors.white, size: 20),
                                  ),
                                ),
                            ],
                          ),
                          // Trail polyline
                          if (_dayLocations.length > 1)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _dayLocations.map((loc) => LatLng(loc['lat'] as double, loc['lng'] as double)).toList(),
                                  color: const Color(0xFF6366F1),
                                  strokeWidth: 3,
                                ),
                              ],
                            ),
                        ],
                      ),
          ),
        ),
      ],
    );
  }
}
