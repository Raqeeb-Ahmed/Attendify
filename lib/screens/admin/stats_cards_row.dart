import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class StatsCardsRow extends StatelessWidget {
  final bool isMobile;
  final String? selectedDate;
  final String selectedFilter;
  final ValueChanged<String> onFilterChanged;

  const StatsCardsRow({
    super.key,
    this.isMobile = false,
    this.selectedDate,
    required this.selectedFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final today =
        selectedDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Combine multiple streams for accurate stats
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: const ['employee', 'manager'])
          .snapshots(),
      builder: (context, usersSnapshot) {
        return StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance.ref('presence').onValue,
          builder: (context, heartbeatSnapshot) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('attendance')
                  .where('date', isEqualTo: today)
                  .snapshots(),
              builder: (context, attendanceSnapshot) {
                int totalStaff = 0;
                int present = 0;
                int late = 0;
                int outOfSystem = 0;
                int offline = 0;
                int online = 0;
                int inOffice = 0;

                // Count total staff from users collection (employees only)
                final employeeIds = <String>{};
                if (usersSnapshot.hasData) {
                  totalStaff = usersSnapshot.data!.docs.length;
                  for (var doc in usersSnapshot.data!.docs) {
                    employeeIds.add(doc.id);
                  }
                }

                // Map attendance status
                final attMap = <String, String>{};
                if (attendanceSnapshot.hasData) {
                  for (var doc in attendanceSnapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final uid = data['userId'] as String?;
                    final status =
                        (data['status'] as String?)?.toLowerCase() ?? '';
                    final atOffice = data['atOffice'] as bool? ?? false;

                    if (uid != null) {
                      attMap[uid] = status;
                    }

                    if (status == 'present') {
                      present++;
                      if (atOffice) inOffice++;
                    } else if (status == 'late') {
                      late++;
                      if (atOffice) inOffice++;
                    } else if (status == 'outside') {
                      outOfSystem++;
                    }
                  }
                }

                // Count online/offline only for known employees
                if (heartbeatSnapshot.hasData && employeeIds.isNotEmpty) {
                  final dbEvent = heartbeatSnapshot.data!;
                  final hbData =
                      dbEvent.snapshot.value as Map<dynamic, dynamic>? ?? {};

                  hbData.forEach((key, val) {
                    if (val != null) {
                      final data = Map<String, dynamic>.from(val as Map);
                      final uid = data['userId'] as String? ?? key.toString();
                      if (employeeIds.contains(uid)) {
                        final isOnline = data['online'] == true;
                        final status = attMap[uid] ?? 'pending';
                        final isCheckInOk =
                            status == 'present' || status == 'late';

                        if (isOnline && isCheckInOk) {
                          online++;
                        } else {
                          offline++;
                        }
                      }
                    }
                  });
                }

                final cards = [
                  _StatData(
                    Icons.groups_rounded,
                    'TOTAL STAFF',
                    totalStaff.toString(),
                    const Color(0xFF6366F1),
                    const Color(0xFFEEF2FF),
                    'ALL',
                  ),
                  _StatData(
                    Icons.download_rounded,
                    'PRESENT',
                    present.toString(),
                    const Color(0xFF22C55E),
                    const Color(0xFFF0FDF4),
                    'PRESENT',
                  ),
                  _StatData(
                    Icons.warning_amber_rounded,
                    'LATE',
                    late.toString(),
                    const Color(0xFFF59E0B),
                    const Color(0xFFFEF3C7),
                    'LATE',
                  ),
                  _StatData(
                    Icons.logout_rounded,
                    'OUT OF SYSTEM',
                    outOfSystem.toString(),
                    const Color(0xFFF97316),
                    const Color(0xFFFFF7ED),
                    'OUT_OF_SYSTEM',
                  ),
                  _StatData(
                    Icons.wifi_off_rounded,
                    'OFFLINE',
                    offline.toString(),
                    const Color(0xFF64748B),
                    const Color(0xFFF8FAFC),
                    'OFFLINE',
                  ),
                  _StatData(
                    Icons.cell_tower_rounded,
                    'ONLINE',
                    online.toString(),
                    const Color(0xFF06B6D4),
                    const Color(0xFFECFEFF),
                    'ONLINE',
                  ),
                  _StatData(
                    Icons.arrow_upward_rounded,
                    'IN OFFICE',
                    inOffice.toString(),
                    const Color(0xFF8B5CF6),
                    const Color(0xFFF5F3FF),
                    'IN_OFFICE',
                  ),
                ];

                if (isMobile) {
                  return SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: cards.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 12),
                      itemBuilder: (context, index) =>
                          SizedBox(width: 160, child: _buildCard(cards[index])),
                    ),
                  );
                }

                return Row(
                  children: cards.asMap().entries.map((entry) {
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: entry.key < cards.length - 1 ? 14 : 0,
                        ),
                        child: _buildCard(entry.value),
                      ),
                    );
                  }).toList(),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCard(_StatData data) {
    final isSelected = selectedFilter == data.filterKey;
    return GestureDetector(
      onTap: () => onFilterChanged(data.filterKey),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 10 : 18,
          vertical: isMobile ? 10 : 20,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? data.color : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? data.color.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: isSelected ? 12 : 10,
              offset: const Offset(0, 2),
            ),
            if (!isSelected)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 10 : 12),
              decoration: BoxDecoration(
                color: data.bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                data.icon,
                color: data.color,
                size: isMobile ? 20 : 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF94A3B8),
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.value,
                    style: TextStyle(
                      fontSize: isMobile ? 20 : 24,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
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
}

class _StatData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color bgColor;
  final String filterKey;
  const _StatData(
    this.icon,
    this.label,
    this.value,
    this.color,
    this.bgColor,
    this.filterKey,
  );
}
