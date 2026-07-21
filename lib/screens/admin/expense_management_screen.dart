import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/cache_service.dart';

class ExpenseManagementScreen extends StatefulWidget {
  final bool isMobile;
  final VoidCallback? onMenuPressed;
  const ExpenseManagementScreen({super.key, this.isMobile = false, this.onMenuPressed});

  @override
  State<ExpenseManagementScreen> createState() => _ExpenseManagementScreenState();
}

class _ExpenseManagementScreenState extends State<ExpenseManagementScreen> {
  String _filterStatus = 'all';
  final Map<String, bool> _updatingDocs = {};

  final List<Map<String, String>> _statusTabs = [
    {'id': 'all', 'label': 'All'},
    {'id': 'pending', 'label': 'Pending'},
    {'id': 'approved', 'label': 'Approved'},
    {'id': 'rejected', 'label': 'Rejected'},
  ];

  Future<void> _updateStatus(String docId, String status) async {
    if (_updatingDocs[docId] == true) return;
    setState(() => _updatingDocs[docId] = true);
    try {
      await FirebaseFirestore.instance.collection('expenses').doc(docId).update({
        'status': status,
        'reviewedAt': DateTime.now().toIso8601String(),
      });
      CacheService.instance.invalidate('expenses');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Expense ${status == 'approved' ? 'approved' : 'rejected'}'),
            backgroundColor: status == 'approved' ? const Color(0xFF22C55E) : Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updatingDocs[docId] = false);
      }
    }
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
            _buildStatusTabs(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _filterStatus == 'all'
                    ? FirebaseFirestore.instance
                        .collection('expenses')
                        .orderBy('createdAt', descending: true)
                        .limit(30)
                        .snapshots()
                    : FirebaseFirestore.instance
                        .collection('expenses')
                        .where('status', isEqualTo: _filterStatus)
                        .limit(30)
                        .snapshots(),
                builder: (ctx, snap) {
                  print("Filter: $_filterStatus");
                  print("Docs: ${snap.data?.docs.length}");

                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        snap.error.toString(),
                        style: const TextStyle(color: Colors.red),
                      ),
                    );
                  }


                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));
                  }
                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Center(child: Text('No expense claims found', style: TextStyle(color: Colors.grey.shade400)));
                  }
                  return ListView.builder(
                    padding: EdgeInsets.all(isMobile ? 16 : 24),
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final d = docs[i].data() as Map<String, dynamic>;
                      return _buildExpenseCard(docs[i].id, d);
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
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 32, vertical: isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
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
          const Icon(Icons.receipt_long_rounded, color: Color(0xFF6366F1), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Expense Management',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                Text(
                  'Review and approve employee claims',
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

  Widget _buildStatusTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _statusTabs.map((tab) {
            final isActive = _filterStatus == tab['id'];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _filterStatus = tab['id']!),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFF6366F1) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(tab['label']!,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isActive ? Colors.white : Colors.grey.shade600)),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildExpenseCard(String docId, Map<String, dynamic> d) {
    final userName = d['userName'] as String? ?? 'Unknown';
    final category = d['category'] as String? ?? 'Other';
    final amount = (d['amount'] as num?)?.toDouble() ?? 0;
    final description = d['description'] as String? ?? '';
    final status = d['status'] as String? ?? 'pending';
    final createdAt = d['createdAt'];

    String dateStr = '';

    if (createdAt is Timestamp) {
      dateStr = DateFormat('dd MMM yyyy').format(createdAt.toDate());
    } else if (createdAt is String && createdAt.isNotEmpty) {
      dateStr = DateFormat('dd MMM yyyy')
          .format(DateTime.parse(createdAt).toLocal());
    }

    final fmt = NumberFormat('#,##0.00', 'en_US');

    Color statusColor;
    Color statusBg;
    String statusLabel;
    switch (status) {
      case 'approved':
        statusColor = const Color(0xFF16A34A); statusBg = const Color(0xFFDCFCE7); statusLabel = 'Approved';
        break;
      case 'rejected':
        statusColor = const Color(0xFFDC2626); statusBg = const Color(0xFFFEE2E2); statusLabel = 'Rejected';
        break;
      default:
        statusColor = const Color(0xFFCA8A04); statusBg = const Color(0xFFFEF9C3); statusLabel = 'Pending';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.receipt_rounded, color: Color(0xFF6366F1), size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                      Text('$category · $dateStr', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('PKR ${fmt.format(amount)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(8)),
                      child: Text(statusLabel,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
                    ),
                  ],
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
            if (status == 'pending') ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _updatingDocs[docId] == true
                        ? null
                        : () => _updateStatus(docId, 'rejected'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: _updatingDocs[docId] == true && status == 'rejected'
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFFDC2626),
                            ),
                          )
                        : const Text('Reject', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _updatingDocs[docId] == true
                        ? null
                        : () => _updateStatus(docId, 'approved'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: _updatingDocs[docId] == true && status == 'approved'
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Approve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
