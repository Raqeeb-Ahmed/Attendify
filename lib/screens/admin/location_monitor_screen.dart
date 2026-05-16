import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class LocationMonitorScreen extends StatefulWidget {
  final bool isMobile;
  final VoidCallback? onMenuPressed;
  const LocationMonitorScreen({super.key, this.isMobile = false, this.onMenuPressed});

  @override
  State<LocationMonitorScreen> createState() => _LocationMonitorScreenState();
}

class _LocationMonitorScreenState extends State<LocationMonitorScreen> {
  String? _expandedUid;
  final _db = FirebaseFirestore.instance;
  final String _today = DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Column(
      children: [
        _buildHeader(widget.isMobile, widget.onMenuPressed),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db.collection('users').where('role', isEqualTo: 'employee').snapshots(),
            builder: (context, usersSnap) {
              if (!usersSnap.hasData) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));
              }
              final users = usersSnap.data!.docs;
              if (users.isEmpty) {
                return const Center(child: Text('No employees found'));
              }
              return ListView.builder(
                padding: EdgeInsets.all(isMobile ? 12 : 20),
                itemCount: users.length,
                itemBuilder: (context, i) {
                  final user = users[i].data() as Map<String, dynamic>;
                  final uid = users[i].id;
                  return _EmployeeLocationCard(
                    uid: uid,
                    user: user,
                    today: _today,
                    isExpanded: _expandedUid == uid,
                    onTap: () => setState(() => _expandedUid = _expandedUid == uid ? null : uid),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(bool isMobile, VoidCallback? onMenuPressed) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 16),
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
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Location Monitor',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 2),
              Text('Live employee geofence status · ${DateFormat('EEEE, d MMM').format(DateTime.now())}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF86EFAC)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: Color(0xFF22C55E)),
                SizedBox(width: 6),
                Text('LIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Per-employee card with live status + expandable timeline ─────────────────

class _EmployeeLocationCard extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> user;
  final String today;
  final bool isExpanded;
  final VoidCallback onTap;

  const _EmployeeLocationCard({
    required this.uid,
    required this.user,
    required this.today,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnap) {
        final liveUser = userSnap.data?.data() as Map<String, dynamic>? ?? user;
        final perms = liveUser['devicePermissions'] as Map<String, dynamic>?;

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('locations').doc('${uid}_latest').snapshots(),
          builder: (context, locSnap) {
            final loc = locSnap.data?.data() as Map<String, dynamic>?;
            final isOnline = _isOnline(loc?['timestamp'] as String?);
            final isAtOffice = loc?['insideRadius'] as bool? ?? false;
            final dist = loc?['distanceFromOffice'] as int?;
            final lastSeen = _formatTime(loc?['timestamp'] as String?);
            final status = loc?['status'] as String? ?? 'unknown';

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('heartbeats').doc(uid).snapshots(),
              builder: (context, hbSnap) {
                final hb = hbSnap.data?.data() as Map<String, dynamic>?;
                final heartOnline = hb?['online'] as bool? ?? false;
                final effectiveOnline = isOnline && heartOnline;

                // ── Permission health ──
                final locPerm = perms?['location'] as String? ?? 'unknown';
                final notifOk = perms?['notification'] as bool? ?? false;
                final batteryOk = perms?['battery'] as bool? ?? false;
                final permLastUpdated = perms?['lastUpdated'] as String?;
                final allPermsOk = (locPerm == 'always' || locPerm == 'whileInUse') && notifOk && batteryOk;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isExpanded ? const Color(0xFF6366F1).withValues(alpha: 0.3) : Colors.grey.shade200,
                      width: isExpanded ? 1.5 : 1,
                    ),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Column(
                    children: [
                      // ── Main row ──
                      InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              // Avatar with online dot
                              Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                    child: Text(
                                      _initials(liveUser['name'] as String? ?? '?'),
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF6366F1)),
                                    ),
                                  ),
                                  Positioned(
                                    right: 1, bottom: 1,
                                    child: Container(
                                      width: 11, height: 11,
                                      decoration: BoxDecoration(
                                        color: effectiveOnline ? const Color(0xFF22C55E) : Colors.grey.shade400,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 14),
                              // Name + dept + permission pills
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(liveUser['name'] as String? ?? 'Unknown',
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                                    const SizedBox(height: 2),
                                    Text(liveUser['department'] as String? ?? liveUser['designation'] as String? ?? '—',
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                                    const SizedBox(height: 6),
                                    // Permission mini-pills row
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: [
                                        _permPill(_locPermIcon(locPerm), _locPermLabel(locPerm), _locPermOk(locPerm)),
                                        _permPill(Icons.notifications_rounded, 'Notif', notifOk),
                                        _permPill(Icons.battery_charging_full_rounded, 'Battery', batteryOk),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Right column: status + overall health dot + last seen
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _statusBadge(status, isAtOffice, dist),
                                  const SizedBox(height: 6),
                                  // Overall permission health indicator
                                  if (perms != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: allPermsOk ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7ED),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            allPermsOk ? Icons.shield_rounded : Icons.warning_amber_rounded,
                                            size: 11,
                                            color: allPermsOk ? const Color(0xFF16A34A) : const Color(0xFFEA580C),
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            allPermsOk ? 'Full access' : 'Restricted',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: allPermsOk ? const Color(0xFF16A34A) : const Color(0xFFEA580C),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(lastSeen, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                  const SizedBox(height: 2),
                                  Icon(
                                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                    size: 18, color: Colors.grey.shade400,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      // ── Expanded panel ──
                      if (isExpanded)
                        _ExpandedPanel(uid: uid, today: today, perms: perms, permLastUpdated: permLastUpdated),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _permPill(IconData icon, String label, bool ok) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
        ],
      ),
    );
  }

  IconData _locPermIcon(String perm) {
    switch (perm) {
      case 'always': return Icons.location_on_rounded;
      case 'whileInUse': return Icons.location_searching_rounded;
      default: return Icons.location_off_rounded;
    }
  }

  String _locPermLabel(String perm) {
    switch (perm) {
      case 'always': return 'Always';
      case 'whileInUse': return 'In use';
      default: return 'Off';
    }
  }

  bool _locPermOk(String perm) => perm == 'always' || perm == 'whileInUse';

  Widget _statusBadge(String status, bool isAtOffice, int? dist) {
    Color bg, fg;
    String label;
    IconData icon;

    if (status == 'present' || isAtOffice) {
      bg = const Color(0xFFF0FDF4); fg = const Color(0xFF16A34A);
      label = dist != null ? '${dist}m' : 'At office';
      icon = Icons.domain_verification_rounded;
    } else if (status == 'outside') {
      bg = const Color(0xFFFFF7ED); fg = const Color(0xFFEA580C);
      label = dist != null ? '${dist}m away' : 'Outside';
      icon = Icons.directions_walk_rounded;
    } else {
      bg = const Color(0xFFF1F5F9); fg = const Color(0xFF64748B);
      label = 'No data';
      icon = Icons.location_off_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) { return '${parts[0][0]}${parts[1][0]}'.toUpperCase(); }
    if (parts[0].isNotEmpty) { return parts[0][0].toUpperCase(); }
    return '?';
  }

  bool _isOnline(String? timestamp) {
    if (timestamp == null) { return false; }
    try {
      final t = DateTime.parse(timestamp);
      return DateTime.now().difference(t).inMinutes < 5;
    } catch (_) { return false; }
  }

  String _formatTime(String? iso) {
    if (iso == null) { return 'Never'; }
    try {
      final t = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(t);
      if (diff.inSeconds < 60) { return 'Just now'; }
      if (diff.inMinutes < 60) { return '${diff.inMinutes}m ago'; }
      if (diff.inHours < 24) { return DateFormat('hh:mm a').format(t); }
      return DateFormat('d MMM').format(t);
    } catch (_) { return '—'; }
  }
}

// ─── Expanded panel: permission health + movement timeline ───────────────────

class _ExpandedPanel extends StatelessWidget {
  final String uid;
  final String today;
  final Map<String, dynamic>? perms;
  final String? permLastUpdated;

  const _ExpandedPanel({
    required this.uid,
    required this.today,
    required this.perms,
    required this.permLastUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('locations')
          .where('userId', isEqualTo: uid)
          .orderBy('timestamp', descending: false)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1))),
          );
        }

        final allDocs = snap.data?.docs ?? [];
        final todayDocs = allDocs.where((doc) {
          final ts = (doc.data() as Map<String, dynamic>)['timestamp'] as String?;
          if (ts == null) return false;
          try { return DateTime.parse(ts).toLocal().toString().startsWith(today); }
          catch (_) { return false; }
        }).toList();

        final segments = _buildSegments(todayDocs);

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('attendance').doc('${uid}_$today').get(),
          builder: (context, attSnap) {
            final att = attSnap.data?.data() as Map<String, dynamic>?;
            final checkIn = att?['checkInTime'] as String?;
            final checkOut = att?['checkOutTime'] as String?;

            // ── Permission detail values ──
            final locPerm = perms?['location'] as String? ?? 'unknown';
            final notifOk = perms?['notification'] as bool? ?? false;
            final batteryOk = perms?['battery'] as bool? ?? false;
            final syncedAt = _fmtSynced(permLastUpdated);

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 12),

                  // ── Device permission health card ──
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.phone_android_rounded, size: 13, color: Color(0xFF6366F1)),
                            const SizedBox(width: 6),
                            const Text('DEVICE PERMISSIONS',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF6366F1), letterSpacing: 0.8)),
                            const Spacer(),
                            Text('synced $syncedAt',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _permRow(
                              Icons.location_on_rounded,
                              'Location',
                              _locPermLabel(locPerm),
                              _locPermOk(locPerm),
                            ),
                            const SizedBox(width: 12),
                            _permRow(
                              Icons.notifications_rounded,
                              'Notifications',
                              notifOk ? 'Granted' : 'Denied',
                              notifOk,
                            ),
                            const SizedBox(width: 12),
                            _permRow(
                              Icons.battery_charging_full_rounded,
                              'Battery',
                              batteryOk ? 'Unrestricted' : 'Restricted',
                              batteryOk,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Check-in/out summary ──
                  if (checkIn != null) ...[
                    _summaryRow(Icons.login_rounded, 'Checked in', _fmt(checkIn), const Color(0xFF22C55E)),
                    const SizedBox(height: 4),
                  ],
                  if (checkOut != null) ...[
                    _summaryRow(Icons.logout_rounded, 'Checked out', _fmt(checkOut), const Color(0xFF6366F1)),
                    const SizedBox(height: 4),
                  ],

                  const SizedBox(height: 8),
                  const Text('MOVEMENT TIMELINE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 1)),
                  const SizedBox(height: 10),

                  if (segments.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.history_rounded, size: 18, color: Color(0xFF94A3B8)),
                          SizedBox(width: 8),
                          Text('No location data for today',
                              style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                        ],
                      ),
                    )
                  else
                    ...segments.asMap().entries.map((e) {
                      final seg = e.value;
                      final isLast = e.key == segments.length - 1;
                      return _TimelineRow(segment: seg, isLast: isLast);
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _permRow(IconData icon, String label, String value, bool ok) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12,
                  color: ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
            ],
          ),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String time, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Text(time, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      ],
    );
  }

  List<_Segment> _buildSegments(List<QueryDocumentSnapshot> docs) {
    final segments = <_Segment>[];
    if (docs.isEmpty) return segments;

    String? currentStatus;
    DateTime? segStart;
    int? lastDist;

    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      final ts = d['timestamp'] as String?;
      final status = d['status'] as String? ?? 'unknown';
      final dist = d['distanceFromOffice'] as int?;
      if (ts == null) continue;

      DateTime time;
      try { time = DateTime.parse(ts).toLocal(); } catch (_) { continue; }

      if (currentStatus == null) {
        currentStatus = status; segStart = time; lastDist = dist;
      } else if (status != currentStatus) {
        segments.add(_Segment(status: currentStatus, from: segStart!, to: time, dist: lastDist));
        currentStatus = status; segStart = time; lastDist = dist;
      } else {
        lastDist = dist;
      }
    }

    if (currentStatus != null && segStart != null) {
      segments.add(_Segment(status: currentStatus, from: segStart, to: DateTime.now(), dist: lastDist, isOngoing: true));
    }
    return segments;
  }

  String _locPermLabel(String perm) {
    switch (perm) {
      case 'always': return 'Always on';
      case 'whileInUse': return 'While in use';
      case 'denied': return 'Denied';
      case 'deniedForever': return 'Permanently denied';
      default: return 'Not checked';
    }
  }

  bool _locPermOk(String perm) => perm == 'always' || perm == 'whileInUse';

  String _fmt(String iso) {
    try { return DateFormat('hh:mm a').format(DateTime.parse(iso).toLocal()); } catch (_) { return '—'; }
  }

  String _fmtSynced(String? iso) {
    if (iso == null) return 'never';
    try {
      final t = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(t);
      if (diff.inSeconds < 60) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return DateFormat('hh:mm a').format(t);
      return DateFormat('d MMM').format(t);
    } catch (_) { return '—'; }
  }
}

class _Segment {
  final String status;
  final DateTime from;
  final DateTime to;
  final int? dist;
  final bool isOngoing;

  _Segment({required this.status, required this.from, required this.to, this.dist, this.isOngoing = false});

  Duration get duration => to.difference(from);
}

class _TimelineRow extends StatelessWidget {
  final _Segment segment;
  final bool isLast;

  const _TimelineRow({required this.segment, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final isAtOffice = segment.status == 'present';
    final color = isAtOffice ? const Color(0xFF22C55E) : const Color(0xFFF97316);
    final bg = isAtOffice ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7ED);
    final label = isAtOffice ? 'At office' : 'Outside office';
    final icon = isAtOffice ? Icons.domain_verification_rounded : Icons.directions_walk_rounded;
    final durationStr = _fmtDur(segment.duration);
    final fromStr = DateFormat('hh:mm a').format(segment.from);
    final toStr = segment.isOngoing ? 'now' : DateFormat('hh:mm a').format(segment.to);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline line + dot
        Column(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, size: 14, color: color),
            ),
            if (!isLast)
              Container(width: 2, height: 32, color: Colors.grey.shade200),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                          if (segment.isOngoing) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                              child: Text('ongoing', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('$fromStr → $toStr', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                Text(durationStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) { return '${h}h ${m}m'; }
    if (m > 0) { return '${m}m'; }
    return '<1m';
  }
}
