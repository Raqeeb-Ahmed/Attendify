import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/notification_service.dart';

class NotificationsScreen extends StatelessWidget {
  final VoidCallback? onBack;
  const NotificationsScreen({super.key, this.onBack});

  static const Map<String, Map<String, dynamic>> _typeConfig = {
    'leave': {'icon': Icons.beach_access_rounded, 'color': Color(0xFF06B6D4), 'bg': Color(0xFFECFEFF)},
    'payroll': {'icon': Icons.account_balance_wallet_rounded, 'color': Color(0xFF8B5CF6), 'bg': Color(0xFFF5F3FF)},
    'attendance': {'icon': Icons.calendar_month_rounded, 'color': Color(0xFF22C55E), 'bg': Color(0xFFF0FDF4)},
    'warning': {'icon': Icons.warning_amber_rounded, 'color': Color(0xFFDC2626), 'bg': Color(0xFFFEE2E2)},
    'announcement': {'icon': Icons.campaign_rounded, 'color': Color(0xFF6366F1), 'bg': Color(0xFFEEF2FF)},
    'expense': {'icon': Icons.receipt_long_rounded, 'color': Color(0xFFF97316), 'bg': Color(0xFFFFF7ED)},
    'document': {'icon': Icons.folder_rounded, 'color': Color(0xFFCA8A04), 'bg': Color(0xFFFEF9C3)},
    'general': {'icon': Icons.notifications_rounded, 'color': Color(0xFF6366F1), 'bg': Color(0xFFEEF2FF)},
  };

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Not logged in')),
      );
    }
    final notifService = NotificationService();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, user.uid, notifService),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: notifService.getNotifications(user.uid),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return _buildSkeleton();
                  }
                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return _buildEmpty();
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final d = docs[i].data() as Map<String, dynamic>;
                      return _buildNotifCard(ctx, docs[i].id, d, notifService);
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

  Widget _buildTopBar(BuildContext context, String userId, NotificationService service) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1E293B)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            )
          else if (Navigator.of(context).canPop())
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1E293B)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          if (onBack != null || Navigator.of(context).canPop()) const SizedBox(width: 12),
          const Icon(Icons.notifications_rounded, color: Color(0xFF6366F1), size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notifications', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                Text('Stay up to date with your activity', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => service.markAllRead(userId),
            icon: const Icon(Icons.done_all_rounded, size: 16),
            label: const Text('Mark all read', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF6366F1)),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifCard(BuildContext ctx, String docId, Map<String, dynamic> d, NotificationService service) {
    final type = d['type'] as String? ?? 'general';
    final config = _typeConfig[type] ?? _typeConfig['general']!;
    final title = d['title'] as String? ?? '';
    final body = d['body'] as String? ?? '';
    final read = d['read'] as bool? ?? false;
    final createdAt = d['createdAt'] as String?;
    final timeStr = createdAt != null ? _formatTime(createdAt) : '';

    return Dismissible(
      key: Key(docId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 22),
      ),
      onDismissed: (_) => service.deleteNotification(docId),
      child: GestureDetector(
        onTap: () {
          if (!read) service.markAsRead(docId);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: read ? Colors.white : const Color(0xFFF8F5FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: read ? const Color(0xFFF1F5F9) : const Color(0xFF6366F1).withValues(alpha: 0.25),
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: config['bg'] as Color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(config['icon'] as IconData, color: config['color'] as Color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(title,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: read ? FontWeight.w500 : FontWeight.w700,
                                    color: const Color(0xFF1E293B))),
                          ),
                          if (!read)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF6366F1),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(body,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Text(timeStr, style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 6,
      itemBuilder: (context, i) => _SkeletonCard(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.notifications_off_rounded, size: 40, color: Color(0xFF6366F1)),
          ),
          const SizedBox(height: 16),
          const Text('No notifications yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
          const SizedBox(height: 6),
          Text('You\'re all caught up!', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return '';
    }
  }
}

class _SkeletonCard extends StatefulWidget {
  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 0.9).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _box(40, 40, radius: 10, opacity: _anim.value),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _box(16, double.infinity, opacity: _anim.value),
                  const SizedBox(height: 8),
                  _box(12, 200, opacity: _anim.value * 0.7),
                  const SizedBox(height: 6),
                  _box(10, 80, opacity: _anim.value * 0.5),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _box(double height, double width, {double radius = 6, required double opacity}) {
    return Container(
      height: height,
      width: width == double.infinity ? null : width,
      decoration: BoxDecoration(
        color: Color.fromRGBO(203, 213, 225, opacity),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
