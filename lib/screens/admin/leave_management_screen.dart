import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../utils/firebase_exception_handler.dart';
import '../../services/push_notification_service.dart';
import '../../services/cache_service.dart';

class LeaveManagementScreen extends StatefulWidget {
  final bool isMobile;
  final VoidCallback? onMenuPressed;
  const LeaveManagementScreen({
    super.key,
    this.isMobile = false,
    this.onMenuPressed,
  });

  @override
  State<LeaveManagementScreen> createState() => _LeaveManagementScreenState();
}

class _LeaveManagementScreenState extends State<LeaveManagementScreen> {
  String _selectedFilter = 'all';
  final Map<String, bool> _updatingDocs = {};

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final localIsMobile = screenWidth < 768;
    final isMobile = widget.isMobile || localIsMobile;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(isMobile, widget.onMenuPressed),
            _buildFilterTabs(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _getLeavesStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(getFirebaseErrorMessage(snapshot.error)),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text(
                        'No leave requests found',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 16,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: EdgeInsets.all(isMobile ? 16 : 24),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      return _buildLeaveCard(data, docs[index].id, isMobile);
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
            Icons.beach_access_rounded,
            color: Color(0xFF6366F1),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Leave Management',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isMobile ? 16 : 20,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    final filters = [
      {'key': 'all', 'label': 'All'},
      {'key': 'pending', 'label': 'Pending'},
      {'key': 'approved', 'label': 'Approved'},
      {'key': 'rejected', 'label': 'Rejected'},
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((filter) {
            final isSelected = _selectedFilter == filter['key'];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(filter['label']!),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected)
                    setState(() => _selectedFilter = filter['key']!);
                },
                selectedColor: const Color(0xFF6366F1),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Stream<QuerySnapshot> _getLeavesStream() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      'leaves',
    );
    if (_selectedFilter != 'all')
      query = query.where('status', isEqualTo: _selectedFilter);
    return query.limit(30).snapshots();
  }

  Widget _buildLeaveCard(
    Map<String, dynamic> data,
    String docId,
    bool isMobile,
  ) {
    final employeeName = data['employeeName'] ?? 'Unknown';
    final leaveType = data['leaveType'] ?? 'Leave';
    final startDate = _formatDate(data['startDate']);
    final endDate = _formatDate(data['endDate']);
    final status = data['status'] ?? 'pending';
    final reason = data['reason'] ?? 'No reason';
    final days = data['days'] ?? 1;

    Color statusColor;
    Color statusBgColor;
    switch (status) {
      case 'approved':
        statusColor = const Color(0xFF22C55E);
        statusBgColor = const Color(0xFFF0FDF4);
        break;
      case 'rejected':
        statusColor = const Color(0xFFEF4444);
        statusBgColor = const Color(0xFFFEF2F2);
        break;
      default:
        statusColor = const Color(0xFFF59E0B);
        statusBgColor = const Color(0xFFFEF3C7);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
                child: Text(
                  _getInitials(employeeName),
                  style: const TextStyle(
                    color: Color(0xFF6366F1),
                    fontWeight: FontWeight.bold,
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
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      '$leaveType • $days ${days == 1 ? 'day' : 'days'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusBgColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _buildInfoItem(Icons.calendar_today, 'From', startDate),
              _buildInfoItem(Icons.calendar_today, 'To', endDate),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Reason: $reason',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
          if (status == 'pending') ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _updatingDocs[docId] == true
                        ? null
                        : () => _updateStatus(docId, 'approved'),
                    icon:
                        _updatingDocs[docId] == true &&
                            _updatingDocs[docId + '_approved'] == true
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _updatingDocs[docId] == true
                        ? null
                        : () => _updateStatus(docId, 'rejected'),
                    icon:
                        _updatingDocs[docId] == true &&
                            _updatingDocs[docId + '_rejected'] == true
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.close, size: 18),
                    label: const Text('Reject'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
  }

  String _formatDate(dynamic date) {
    if (date == null) return '--';
    if (date is Timestamp)
      return DateFormat('MMM dd, yyyy').format(date.toDate());
    if (date is String) {
      try {
        return DateFormat('MMM dd, yyyy').format(DateTime.parse(date));
      } catch (_) {
        return date;
      }
    }
    return '--';
  }

  Future<void> _updateStatus(String docId, String status) async {
    if (_updatingDocs[docId] == true) return;
    setState(() {
      _updatingDocs[docId] = true;
      _updatingDocs[docId + '_' + status] = true;
    });
    try {
      await FirebaseFirestore.instance.collection('leaves').doc(docId).update({
        'status': status,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      CacheService.instance.invalidate('leaves');

      // Send push notification and save notification in database
      final leaveSnap = await FirebaseFirestore.instance
          .collection('leaves')
          .doc(docId)
          .get();
      if (leaveSnap.exists) {
        final leaveData = leaveSnap.data();
        final userId = leaveData?['userId'] as String?;
        final leaveType = leaveData?['type'] as String?;
        final days = (leaveData?['days'] as num?)?.toInt() ?? 1;

        if (userId != null) {
          // If approved, deduct from user's leave balance in a transaction
          if (status == 'approved' && leaveType != null) {
            final userRef = FirebaseFirestore.instance
                .collection('users')
                .doc(userId);
            String fieldName;
            switch (leaveType) {
              case 'annual':
                fieldName = 'leaveBalanceAnnual';
                break;
              case 'sick':
                fieldName = 'leaveBalanceSick';
                break;
              case 'casual':
                fieldName = 'leaveBalanceCasual';
                break;
              case 'emergency':
                fieldName = 'leaveBalanceEmergency';
                break;
              default:
                fieldName = '';
            }

            if (fieldName.isNotEmpty) {
              await FirebaseFirestore.instance.runTransaction((
                transaction,
              ) async {
                final userSnap = await transaction.get(userRef);
                if (userSnap.exists) {
                  final userData = userSnap.data();
                  int currentBalance = 0;
                  if (userData != null && userData.containsKey(fieldName)) {
                    currentBalance = (userData[fieldName] as num).toInt();
                  } else {
                    if (leaveType == 'annual')
                      currentBalance = 15;
                    else if (leaveType == 'sick')
                      currentBalance = 10;
                    else if (leaveType == 'casual')
                      currentBalance = 7;
                    else if (leaveType == 'emergency')
                      currentBalance = 5;
                  }
                  final newBalance = (currentBalance - days).clamp(0, 999);
                  transaction.update(userRef, {fieldName: newBalance});
                }
              });
            }
          }

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
            content: Text(getFirebaseErrorMessage(e)),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _updatingDocs[docId] = false;
          _updatingDocs[docId + '_' + status] = false;
        });
      }
    }
  }
}
