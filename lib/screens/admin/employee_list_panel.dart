import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'admin_dashboard.dart';

class EmployeeListPanel extends StatefulWidget {
  final List<EmployeeMapData> employees;
  final String selectedDate;

  const EmployeeListPanel({super.key, required this.employees, required this.selectedDate});

  @override
  State<EmployeeListPanel> createState() => _EmployeeListPanelState();
}

class _EmployeeListPanelState extends State<EmployeeListPanel> {
  String _searchQuery = '';
  String _activeFilter = 'All';
  String? _expandedUserId;

  final List<String> _filters = [
    'All', 'Present', 'Late', 'Outside', 'Pending', 'Online', 'Offline', 'Out of System'
  ];

  List<EmployeeMapData> get _filtered {
    return widget.employees.where((emp) {
      final matchesSearch = emp.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          emp.email.toLowerCase().contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;
      switch (_activeFilter) {
        case 'Present':
          return emp.status == EmployeeStatus.present;
        case 'Late':
          return emp.status == EmployeeStatus.late_;
        case 'Outside':
          return emp.status == EmployeeStatus.outside;
        case 'Pending':
          return emp.status == EmployeeStatus.pending;
        case 'Online':
          return emp.isOnline;
        case 'Offline':
          return !emp.isOnline;
        case 'Out of System':
          return emp.isOnline && emp.status == EmployeeStatus.outside;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('attendance')
          .where('date', isEqualTo: widget.selectedDate)
          .snapshots(),
      builder: (context, attSnap) {
        final attDocs = attSnap.data?.docs ?? [];
        final attMap = <String, Map<String, dynamic>>{};
        int insideMinutes = 0;
        int outsideMinutes = 0;
        int offlineMinutes = 0;
        int extraMinutes = 0;

        for (var doc in attDocs) {
          final data = doc.data() as Map<String, dynamic>;
          final uid = data['userId'] as String?;
          if (uid != null) attMap[uid] = data;
          insideMinutes += (data['insideTime'] as num?)?.toInt() ?? 0;
          outsideMinutes += (data['outsideTime'] as num?)?.toInt() ?? 0;
          offlineMinutes += (data['offlineTime'] as num?)?.toInt() ?? 0;
          extraMinutes += (data['extraHours'] as num?)?.toInt() ?? 0;
        }

        final filtered = _filtered;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
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
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Text('Team Directory', style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    )),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${filtered.length} shown',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6366F1), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),

              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search employees...',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                    prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey.shade400),
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
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF6366F1)),
                    ),
                  ),
                ),
              ),

              // Filter chips
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _filters.map((f) => _buildFilterChip(f)).toList(),
                ),
              ),
              const SizedBox(height: 14),

              // Time allocation (live from attendance collection)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TIME ALLOCATION TODAY', style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade400,
                      letterSpacing: 1,
                    )),
                    const SizedBox(height: 10),
                    _timeRow('Inside Office', _formatMins(insideMinutes), const Color(0xFF22C55E)),
                    _timeRow('Outside', _formatMins(outsideMinutes), const Color(0xFFF97316)),
                    _timeRow('Offline/Idle', _formatMins(offlineMinutes), const Color(0xFF94A3B8)),
                    _timeRow('Extra Hours', _formatMins(extraMinutes), const Color(0xFF6366F1)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),

              // Employee list
              ...filtered.map((emp) => _buildEmployeeRow(emp, attMap[emp.userId])),

              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text('No employees match the filter',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label) {
    final isActive = _activeFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF6366F1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: isActive ? null : Border.all(color: Colors.grey.shade200),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isActive ? Colors.white : Colors.grey.shade600,
        )),
      ),
    );
  }

  Widget _timeRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 9, height: 9,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500))),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildEmployeeRow(EmployeeMapData emp, Map<String, dynamic>? att) {
    final isExpanded = _expandedUserId == emp.userId;
    final status = att?['status'] as String? ??
        (emp.status == EmployeeStatus.present
            ? 'present'
            : emp.status == EmployeeStatus.late_
                ? 'late'
                : emp.status == EmployeeStatus.outside
                    ? 'outside'
                    : emp.status == EmployeeStatus.offline
                        ? 'offline'
                        : 'pending');

    final checkInRaw = att?['checkInTime'] as String?;
    final checkOutRaw = att?['checkOutTime'] as String?;
    final checkIn = checkInRaw != null
        ? DateFormat('hh:mm a').format(DateTime.parse(checkInRaw).toLocal())
        : '--:--';
    final checkOut = checkOutRaw != null
        ? DateFormat('hh:mm a').format(DateTime.parse(checkOutRaw).toLocal())
        : '--:--';

    final insideTime = (att?['insideTime'] as num?)?.toInt() ?? 0;
    final outsideTime = (att?['outsideTime'] as num?)?.toInt() ?? 0;
    final offlineTime = (att?['offlineTime'] as num?)?.toInt() ?? 0;
    final extraHours = (att?['extraHours'] as num?)?.toInt() ?? 0;

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expandedUserId = isExpanded ? null : emp.userId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: isExpanded ? const Color(0xFFF8F9FF) : Colors.white,
              border: Border(
                left: BorderSide(
                  color: emp.isOnline ? const Color(0xFF22C55E) : Colors.transparent,
                  width: 3,
                ),
                bottom: BorderSide(color: Colors.grey.shade100),
              ),
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: emp.avatarColor,
                      child: Text(emp.initials, style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold,
                      )),
                    ),
                    Positioned(
                      right: 0, bottom: 0,
                      child: Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                          color: emp.isOnline ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(emp.name, style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade800,
                      )),
                      Text(emp.email, style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                    ],
                  ),
                ),
                _statusBadge(status),
                const SizedBox(width: 6),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 18, color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),

        // Expanded detail panel
        if (isExpanded)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E7FF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Today's Summary", style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade800,
                )),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _detailBox('Check In', checkIn, const Color(0xFF22C55E))),
                    const SizedBox(width: 8),
                    Expanded(child: _detailBox('Check Out', checkOut, const Color(0xFFF97316))),
                  ],
                ),
                const SizedBox(height: 10),
                _detailRow('Inside Office', _formatMins(insideTime), const Color(0xFF22C55E)),
                _detailRow('Outside', _formatMins(outsideTime), const Color(0xFFF97316)),
                _detailRow('Offline/Idle', _formatMins(offlineTime), const Color(0xFF94A3B8)),
                _detailRow('Extra Hours', _formatMins(extraHours), const Color(0xFF6366F1)),
                if (emp.distance != null) ...[
                  const Divider(height: 16),
                  _detailRow('Distance from Office', '${emp.distance}m', Colors.grey.shade600),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _detailBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500))),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case 'present':
        bg = const Color(0xFFDCFCE7); fg = const Color(0xFF16A34A); label = 'Present';
        break;
      case 'late':
        bg = const Color(0xFFFEF9C3); fg = const Color(0xFFCA8A04); label = 'Late';
        break;
      case 'outside':
        bg = const Color(0xFFFFEDD5); fg = const Color(0xFFEA580C); label = 'Out of System';
        break;
      case 'offline':
        bg = const Color(0xFFF1F5F9); fg = const Color(0xFF64748B); label = 'Offline';
        break;
      default:
        bg = const Color(0xFFFEF9C3); fg = const Color(0xFFCA8A04); label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  String _formatMins(int minutes) {
    final m = minutes.abs();
    return '${m ~/ 60}h ${m % 60}m';
  }
}
