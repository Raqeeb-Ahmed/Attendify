import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_service.dart';

class AnnouncementsScreen extends StatefulWidget {
  final bool isMobile;
  final VoidCallback? onMenuPressed;

  const AnnouncementsScreen({
    super.key,
    this.isMobile = false,
    this.onMenuPressed,
  });

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  String _userRole = 'employee';
  String _userName = 'Employee';
  bool _isLoadingRole = true;
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists && mounted) {
          final data = doc.data();
          setState(() {
            _userRole = data?['role'] ?? 'employee';
            _userName = data?['name'] ?? data?['email'] ?? 'User';
            _isLoadingRole = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint("Error fetching user role: $e");
    }
    if (mounted) {
      setState(() {
        _isLoadingRole = false;
      });
    }
  }

  Future<void> _showCreateAnnouncementDialog() async {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isPublishing = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  const Icon(Icons.campaign_rounded, color: Color(0xFF6366F1)),
                  const SizedBox(width: 10),
                  const Text(
                    'New Announcement',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: titleCtrl,
                        decoration: InputDecoration(
                          labelText: 'Title',
                          labelStyle: const TextStyle(fontSize: 13),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFF6366F1),
                              width: 1.5,
                            ),
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Please enter a title'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: contentCtrl,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText: 'Announcement Content',
                          alignLabelWithHint: true,
                          labelStyle: const TextStyle(fontSize: 13),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFF6366F1),
                              width: 1.5,
                            ),
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Please enter content'
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              actions: [
                TextButton(
                  onPressed: isPublishing
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: isPublishing
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() {
                              isPublishing = true;
                            });
                            final navigator = Navigator.of(dialogContext);
                            final scaffoldMessenger = ScaffoldMessenger.of(
                              context,
                            );
                            await _publishAnnouncement(
                              titleCtrl.text.trim(),
                              contentCtrl.text.trim(),
                            );
                            navigator.pop();
                            scaffoldMessenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Announcement published successfully!',
                                ),
                                backgroundColor: Color(0xFF22C55E),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  icon: isPublishing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                  label: Text(
                    isPublishing ? 'Publishing...' : 'Publish',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _publishAnnouncement(String title, String content) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final nowFormatted = DateFormat(
        'dd MMM yyyy, hh:mm a',
      ).format(DateTime.now());

      // 1. Create Firestore Document
      final docRef = _firestore.collection('announcements').doc();
      await docRef.set({
        'id': docRef.id,
        'title': title,
        'content': content,
        'authorId': user.uid,
        'authorName': _userName,
        'createdAt': FieldValue.serverTimestamp(),
        'seenBy': <String>[],
      });

      // 2. Broadcast in-app notification to all users
      await _notificationService.broadcastToAll(
        title: 'New Announcement: $title',
        body: '$content\n\nDate & Time: $nowFormatted',
        type: 'announcement',
      );

      // 3. Send Push Notifications to all users
      final usersSnap = await _firestore.collection('users').get();
      List<String> allTokens = [];
      for (var doc in usersSnap.docs) {
        if (doc.id == user.uid) continue; // Skip sender
        final data = doc.data();
        final tokens = List<String>.from(data['fcmTokens'] ?? []);
        allTokens.addAll(tokens);
      }

      if (allTokens.isNotEmpty) {
        await PushNotificationService.instance.sendPushNotification(
          recipientTokens: allTokens,
          title: 'New Announcement: $title',
          body: '$content\n\nDate & Time: $nowFormatted',
        );
      }
    } catch (e) {
      debugPrint("Error publishing announcement: $e");
    }
  }

  Future<void> _confirmDeleteAnnouncement(String docId) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Announcement'),
        content: const Text(
          'Are you sure you want to delete this announcement? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _firestore.collection('announcements').doc(docId).delete();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Announcement deleted'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _showSeenByBottomSheet(
    String announcementId,
    List<String> seenByList,
  ) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return _SeenByBottomSheet(
              seenByList: seenByList,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final localIsMobile = screenWidth < 768;
    final isMobile = widget.isMobile || localIsMobile;

    final isManager = _userRole == 'admin' || _userRole == 'manager';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: (!_isLoadingRole && isManager)
          ? FloatingActionButton.extended(
              onPressed: _showCreateAnnouncementDialog,
              backgroundColor: const Color(0xFF6366F1),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Post Announcement',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(isMobile, widget.onMenuPressed),
            Expanded(
              child: _isLoadingRole
                  ? const Center(child: CircularProgressIndicator())
                  : StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection('announcements')
                          .orderBy('createdAt', descending: true)
                          .limit(30)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text('Error: ${snapshot.error}'),
                          );
                        }
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return _buildEmptyState(isManager);
                        }

                        return ListView.builder(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 12 : 24,
                            vertical: 16,
                          ),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data() as Map<String, dynamic>;
                            return _buildAnnouncementCard(
                              doc.id,
                              data,
                              isManager,
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

  Widget _buildTopBar(bool isMobile, VoidCallback? onMenuPressed) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 32,
        vertical: isMobile ? 16 : 20,
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
          // if (isMobile && onMenuPressed != null)
          if (isMobile && onMenuPressed == null)
            const SizedBox(width: 40, height: 30),
          const Icon(
            Icons.campaign_rounded,
            color: Color(0xFF6366F1),
            size: 24,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Announcements',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementCard(
    String docId,
    Map<String, dynamic> data,
    bool isManager,
  ) {
    final title = data['title'] ?? 'No Title';
    final content = data['content'] ?? 'No Content';
    final authorName = data['authorName'] ?? 'Manager';
    final seenByList = List<String>.from(data['seenBy'] ?? []);
    final currentUserId = _auth.currentUser?.uid;
    final isNew =
        _userRole == 'employee' &&
        currentUserId != null &&
        !seenByList.contains(currentUserId);

    final bool isExpanded = _expandedIds.contains(docId);

    // Format Timestamp
    String dateStr = 'Just now';
    if (data['createdAt'] != null) {
      if (data['createdAt'] is Timestamp) {
        final dt = (data['createdAt'] as Timestamp).toDate();
        dateStr = DateFormat('MMM dd, yyyy - hh:mm a').format(dt);
      } else if (data['createdAt'] is String) {
        final dt = DateTime.tryParse(data['createdAt']) ?? DateTime.now();
        dateStr = DateFormat('MMM dd, yyyy - hh:mm a').format(dt);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedIds.remove(docId);
              } else {
                _expandedIds.add(docId);
                // Mark as seen for employee
                if (isNew) {
                  _firestore.collection('announcements').doc(docId).update({
                    'seenBy': FieldValue.arrayUnion([currentUserId]),
                  });
                }
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(
                        0xFF6366F1,
                      ).withValues(alpha: 0.1),
                      child: const Icon(
                        Icons.campaign_rounded,
                        color: Color(0xFF6366F1),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              if (isNew)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF22C55E),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'NEW',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'By $authorName • $dateStr',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isManager)
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: Colors.grey.shade500,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onSelected: (value) {
                          if (value == 'delete') {
                            _confirmDeleteAnnouncement(docId);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem<String>(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.red,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Delete',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  content,
                  maxLines: isExpanded ? null : 2,
                  overflow: isExpanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isExpanded ? 'Show less' : 'Read more',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                    if (isManager)
                      InkWell(
                        onTap: () => _showSeenByBottomSheet(docId, seenByList),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.visibility_outlined,
                                size: 13,
                                color: Color(0xFF475569),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Seen by: ${seenByList.length}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isManager) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.campaign_outlined,
              size: 72,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No Announcements',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isManager
                  ? 'Create a new announcement to notify everyone in the team.'
                  : 'You are all caught up! No recent announcements.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeenByBottomSheet extends StatefulWidget {
  final List<String> seenByList;
  final ScrollController scrollController;

  const _SeenByBottomSheet({
    required this.seenByList,
    required this.scrollController,
  });

  @override
  State<_SeenByBottomSheet> createState() => _SeenByBottomSheetState();
}

class _SeenByBottomSheetState extends State<_SeenByBottomSheet> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _searchQuery = '';
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    try {
      final snap = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'employee')
          .get();

      final employees = snap.docs.map((doc) {
        final data = doc.data();
        return {
          'uid': doc.id,
          'name': data['name'] ?? data['email'] ?? 'Unnamed Employee',
          'email': data['email'] ?? '',
        };
      }).toList();

      setState(() {
        _employees = employees;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading employees: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredEmployees = _employees.where((e) {
      final name = e['name'].toString().toLowerCase();
      final email = e['email'].toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase()) ||
          email.contains(_searchQuery.toLowerCase());
    }).toList();

    // Sort: seen ones first
    filteredEmployees.sort((a, b) {
      final aSeen = widget.seenByList.contains(a['uid']);
      final bSeen = widget.seenByList.contains(b['uid']);
      if (aSeen && !bSeen) return -1;
      if (!aSeen && bSeen) return 1;
      return a['name'].toString().compareTo(b['name'].toString());
    });

    final seenCount = _employees
        .where((e) => widget.seenByList.contains(e['uid']))
        .length;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Seen Status',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                if (!_isLoading)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$seenCount / ${_employees.length} Seen',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search employees...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6366F1)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredEmployees.isEmpty
                ? Center(
                    child: Text(
                      'No employees found',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.builder(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: filteredEmployees.length,
                    itemBuilder: (context, idx) {
                      final emp = filteredEmployees[idx];
                      final bool isSeen = widget.seenByList.contains(
                        emp['uid'],
                      );

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: isSeen
                              ? const Color(0xFF22C55E).withValues(alpha: 0.1)
                              : Colors.grey.shade100,
                          child: Text(
                            emp['name'].toString().isNotEmpty
                                ? emp['name'].toString()[0].toUpperCase()
                                : 'E',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isSeen
                                  ? const Color(0xFF22C55E)
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                        title: Text(
                          emp['name'],
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          emp['email'],
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        trailing: isSeen
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF22C55E,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle_rounded,
                                      size: 12,
                                      color: Color(0xFF22C55E),
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Seen',
                                      style: TextStyle(
                                        color: Color(0xFF22C55E),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.watch_later_rounded,
                                      size: 12,
                                      color: Colors.orange,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Unseen',
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
