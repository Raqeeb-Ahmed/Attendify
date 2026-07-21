import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PerformanceManagementScreen extends StatefulWidget {
  final bool isMobile;
  final VoidCallback? onMenuPressed;
  const PerformanceManagementScreen({
    super.key,
    this.isMobile = false,
    this.onMenuPressed,
  });

  @override
  State<PerformanceManagementScreen> createState() =>
      _PerformanceManagementScreenState();
}

class _PerformanceManagementScreenState
    extends State<PerformanceManagementScreen> {
  String _searchQuery = '';
  late Stream<QuerySnapshot> _usersStream;
  late Stream<QuerySnapshot> _attendanceStream;
  late Stream<QuerySnapshot> _warningStream;

  @override
  void initState() {
    super.initState();
    _usersStream = FirebaseFirestore.instance
        .collection('users')
        .where('role', whereIn: const ['employee', 'manager'])
        .snapshots();
    _attendanceStream = FirebaseFirestore.instance
        .collection('attendance')
        .limit(200)
        .snapshots();
    _warningStream = FirebaseFirestore.instance
        .collection('documents')
        .where('type', isEqualTo: 'warning')
        .limit(50)
        .snapshots();
  }

  int _calcScore(List<Map<String, dynamic>> attRecords, int warnings) {
    final present = attRecords.length;
    final late = attRecords.where((a) => a['status'] == 'late').length;
    final onTime = present - late;
    final totalHours = attRecords.fold<double>(
      0,
      (acc, a) => acc + ((a['totalHours'] as num?)?.toDouble() ?? 0),
    );
    double score =
        50 + (onTime * 1.5) - (late * 5) - (warnings * 20) + (totalHours * 0.1);
    return score.clamp(0, 100).round();
  }

  Color _scoreColor(int score) {
    if (score >= 80) return const Color(0xFF16A34A);
    if (score >= 60) return const Color(0xFF2563EB);
    if (score >= 40) return const Color(0xFFCA8A04);
    return const Color(0xFFDC2626);
  }

  String _scoreLabel(int score) {
    if (score >= 80) return 'Outstanding';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Needs Improvement';
    return 'Unsatisfactory';
  }

  Future<void> _showAppraisalDialog(
    BuildContext context,
    Map<String, dynamic> emp,
  ) async {
    int rating = 3;
    final feedbackCtrl = TextEditingController();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            'Appraisal – ${emp['name']}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rating',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(
                  5,
                  (i) => IconButton(
                    onPressed: isSaving ? null : () => setS(() => rating = i + 1),
                    icon: Icon(
                      i < rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: const Color(0xFFF59E0B),
                      size: 28,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Feedback',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: feedbackCtrl,
                maxLines: 3,
                enabled: !isSaving,
                decoration: InputDecoration(
                  hintText: 'Enter feedback...',
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide(color: Color(0xFF6366F1)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      setS(() => isSaving = true);
                      try {
                        final messenger = ScaffoldMessenger.of(context);
                        await FirebaseFirestore.instance.collection('appraisals').add({
                          'userId': emp['id'],
                          'userName': emp['name'],
                          'rating': rating,
                          'feedback': feedbackCtrl.text.trim(),
                          'createdAt': DateTime.now().toIso8601String(),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Appraisal saved'),
                            backgroundColor: Color(0xFF22C55E),
                          ),
                        );
                      } catch (e) {
                        setS(() => isSaving = false);
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save Appraisal',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
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
            _buildSearch(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _usersStream,
                builder: (ctx, usersSnap) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: _attendanceStream,
                    builder: (ctx, attSnap) {
                      return StreamBuilder<QuerySnapshot>(
                        stream: _warningStream,
                        builder: (ctx, warnSnap) {
                          if (usersSnap.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF6366F1),
                              ),
                            );
                          }

                          final attDocs = attSnap.data?.docs ?? [];
                          final warnDocs = warnSnap.data?.docs ?? [];

                          final attMap = <String, List<Map<String, dynamic>>>{};
                          for (var doc in attDocs) {
                            final d = doc.data() as Map<String, dynamic>;
                            final uid = d['userId'] as String? ?? '';
                            attMap.putIfAbsent(uid, () => []).add(d);
                          }

                          final warnMap = <String, int>{};
                          for (var doc in warnDocs) {
                            final uid =
                                (doc.data() as Map<String, dynamic>)['userId']
                                    as String? ??
                                '';
                            warnMap[uid] = (warnMap[uid] ?? 0) + 1;
                          }

                          final employees = (usersSnap.data?.docs ?? [])
                              .map(
                                (d) => {
                                  'id': d.id,
                                  ...d.data() as Map<String, dynamic>,
                                },
                              )
                              .where(
                                (e) => (e['name'] as String? ?? '')
                                    .toLowerCase()
                                    .contains(_searchQuery.toLowerCase()),
                              )
                              .toList();

                          return ListView.builder(
                            padding: EdgeInsets.all(isMobile ? 16 : 24),
                            itemCount: employees.length,
                            itemBuilder: (ctx, i) {
                              final emp = employees[i];
                              final uid = emp['id'] as String;
                              final records = attMap[uid] ?? [];
                              final warnings = warnMap[uid] ?? 0;
                              final score = _calcScore(records, warnings);
                              return _buildPerformanceCard(
                                ctx,
                                emp,
                                records,
                                warnings,
                                score,
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
            Icons.trending_up_rounded,
            color: Color(0xFF6366F1),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Performance Management',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                Text(
                  'Track KPIs, ratings, and appraisals',
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

  Widget _buildSearch() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      color: Colors.white,
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Search employees...',
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
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
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: Color(0xFF6366F1)),
          ),
        ),
      ),
    );
  }

  Widget _buildPerformanceCard(
    BuildContext ctx,
    Map<String, dynamic> emp,
    List<Map<String, dynamic>> records,
    int warnings,
    int score,
  ) {
    final name = emp['name'] as String? ?? 'Unknown';
    final email = emp['email'] as String? ?? '';
    final dept = emp['department'] as String? ?? 'N/A';
    final initials = name
        .split(' ')
        .take(2)
        .map((p) => p.isNotEmpty ? p[0] : '')
        .join()
        .toUpperCase();
    final late = records.where((r) => r['status'] == 'late').length;
    final scoreColor = _scoreColor(score);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: scoreColor.withValues(alpha: 0.12),
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: scoreColor,
                      fontSize: 13,
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
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        '$email · $dept',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$score',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: scoreColor,
                      ),
                    ),
                    Text(
                      _scoreLabel(score),
                      style: TextStyle(
                        fontSize: 10,
                        color: scoreColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: score / 100,
                minHeight: 6,
                backgroundColor: scoreColor.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _kpiChip(
                  Icons.calendar_today_rounded,
                  '${records.length} Days',
                  const Color(0xFF6366F1),
                ),
                _kpiChip(
                  Icons.warning_amber_rounded,
                  '$late Late',
                  const Color(0xFFF59E0B),
                ),
                _kpiChip(
                  Icons.error_outline_rounded,
                  '$warnings Warnings',
                  const Color(0xFFDC2626),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => _showAppraisalDialog(ctx, emp),
                  icon: const Icon(Icons.rate_review_outlined, size: 12),
                  label: const Text(
                    'Appraise',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 8),

          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
