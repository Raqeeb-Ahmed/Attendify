import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../utils/firebase_exception_handler.dart';
import '../../services/cache_service.dart';
import '../../services/push_notification_service.dart';

class EmployeeManagementScreen extends StatefulWidget {
  final bool isMobile;
  final VoidCallback? onMenuPressed;
  const EmployeeManagementScreen({
    super.key,
    this.isMobile = false,
    this.onMenuPressed,
  });

  @override
  State<EmployeeManagementScreen> createState() =>
      _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  String email = 'raqeebdeveloper@gmail.com';
  String _searchQuery = '';
  String _filterDept = 'All';
  bool _isSaving = false;
  final Map<String, bool> _processingDocs = {};

  final List<String> _departments = [
    'All',
    'Human Resources',
    'Engineering',
    'Design',
    'Marketing',
    'Sales',
    'Finance',
    'Operations',
    'Management',
  ];

  final List<String> _designations = [
    'Intern',
    'Software Developer',
    'Manager',
    'HR Manager',
    'Accountant',
    'Sales Executive',
    'Visa Officer',
    'E-Visa Officer',
    'Ticketing Officer',
    'Visa Consultant',
    'Director',
    'CEO',
  ];

  Future<void> _showEditDialog(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) async {
    final nameCtrl = TextEditingController(text: data['name'] ?? '');
    final deptNotifier = ValueNotifier<String>(
      data['department'] ?? _departments[1],
    );
    final desgNotifier = ValueNotifier<String>(
      data['designation'] ?? _designations[0],
    );
    final salaryCtrl = TextEditingController(
      text: (data['baseSalary'] ?? 0).toString(),
    );
    final allowanceCtrl = TextEditingController(
      text: (data['allowances'] ?? 0).toString(),
    );
    final roleNotifier = ValueNotifier<String>(data['role'] ?? 'employee');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Edit Employee',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogField('Full Name', nameCtrl),
                const SizedBox(height: 14),
                _dialogLabel('Department'),
                ValueListenableBuilder<String>(
                  valueListenable: deptNotifier,
                  builder: (context, val, child) => _dialogDropdown(
                    val,
                    _departments.skip(1).toList(),
                    (v) => deptNotifier.value = v!,
                  ),
                ),
                const SizedBox(height: 14),
                _dialogLabel('Designation'),
                ValueListenableBuilder<String>(
                  valueListenable: desgNotifier,
                  builder: (context, val, child) => _dialogDropdown(
                    val,
                    _designations,
                    (v) => desgNotifier.value = v!,
                  ),
                ),
                const SizedBox(height: 14),
                _dialogLabel('Role'),
                ValueListenableBuilder<String>(
                  valueListenable: roleNotifier,
                  builder: (context, val, child) => _dialogDropdown(val, const [
                    'employee',
                    'admin',
                  ], (v) => roleNotifier.value = v!),
                ),
                const SizedBox(height: 14),
                _dialogField('Base Salary (PKR)', salaryCtrl, isNumber: true),
                const SizedBox(height: 14),
                _dialogField('Allowances (PKR)', allowanceCtrl, isNumber: true),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          StatefulBuilder(
            builder: (ctx2, setS) => ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
              ),
              onPressed: _isSaving
                  ? null
                  : () async {
                      setS(() => _isSaving = true);

                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(docId)
                          .update({
                            'name': nameCtrl.text.trim(),
                            'department': deptNotifier.value,
                            'designation': desgNotifier.value,
                            'role': roleNotifier.value,
                            'baseSalary': double.tryParse(salaryCtrl.text) ?? 0,
                            'allowances':
                                double.tryParse(allowanceCtrl.text) ?? 0,
                          });
                      CacheService.instance.invalidate('users');

                      setS(() => _isSaving = false);

                      if (ctx2.mounted) {
                        Navigator.pop(ctx2);
                      }

                      if (!context.mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Employee updated"),
                          backgroundColor: Color(0xFF22C55E),
                        ),
                      );
                    },
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
    setState(() => _isSaving = false);
  }

  late Stream<QuerySnapshot> _usersStream;

  @override
  void initState() {
    super.initState();
    _usersStream = FirebaseFirestore.instance
        .collection('users')
        .orderBy('name')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final localIsMobile = MediaQuery.of(context).size.width < 768;
    final isMobile = widget.isMobile || localIsMobile;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(isMobile, widget.onMenuPressed),
            _buildFilters(isMobile),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _usersStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF6366F1),
                      ),
                    );
                  }
                  final docs = snapshot.data?.docs ?? [];
                  final filtered = docs.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final name = (d['name'] as String? ?? '').toLowerCase();
                    final email = (d['email'] as String? ?? '').toLowerCase();
                    final dept = d['department'] as String? ?? '';
                    return (name.contains(_searchQuery.toLowerCase()) ||
                            email.contains(_searchQuery.toLowerCase())) &&
                        (_filterDept == 'All' || dept == _filterDept);
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        'No employees found',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: EdgeInsets.all(isMobile ? 16 : 24),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final doc = filtered[i];
                      final d = doc.data() as Map<String, dynamic>;
                      return _buildEmployeeCard(ctx, doc.id, d);
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
        horizontal: isMobile ? 16 : 32,
        vertical: 16,
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
            ),
          const Icon(Icons.people_rounded, color: Color(0xFF6366F1), size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Employee Management',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  'Manage staff records, roles, and profiles',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(bool isMobile) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      color: Colors.white,
      child: isMobile
          ? Column(
              children: [
                _searchField(),
                const SizedBox(height: 10),
                _deptDropdownRow(),
              ],
            )
          : Row(
              children: [
                Expanded(child: _searchField()),
                const SizedBox(width: 16),
                _deptDropdownRow(),
              ],
            ),
    );
  }

  Widget _searchField() {
    return TextField(
      onChanged: (v) => setState(() => _searchQuery = v),
      decoration: InputDecoration(
        hintText: 'Search by name or email...',
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
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF6366F1)),
        ),
      ),
    );
  }

  Widget _deptDropdownRow() {
    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xFFF8FAFC),
        ),
        child: DropdownButton<String>(
          value: _filterDept,
          items: _departments
              .map(
                (d) => DropdownMenuItem(
                  value: d,
                  child: Text(d, style: const TextStyle(fontSize: 13)),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _filterDept = v!),
        ),
      ),
    );
  }

  Widget _buildEmployeeCard(
    BuildContext ctx,
    String docId,
    Map<String, dynamic> d,
  ) {
    final name = d['name'] as String? ?? 'Unknown';
    final email = d['email'] as String? ?? '';
    final dept = d['department'] as String? ?? 'N/A';
    final designation = d['designation'] as String? ?? 'N/A';
    final role = d['role'] as String? ?? 'employee';
    final salary = d['baseSalary'] ?? 0;
    final initials = name
        .split(' ')
        .take(2)
        .map((p) => p.isNotEmpty ? p[0] : '')
        .join()
        .toUpperCase();
    final perms = d['devicePermissions'] as Map<String, dynamic>?;
    final approved = d['approved'] ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
              child: Text(
                initials,
                style: const TextStyle(
                  color: Color(0xFF6366F1),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      _roleBadge(role),
                      if (!approved)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFCD34D)),
                          ),
                          child: const Text(
                            'PENDING APPROVAL',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _infoChip(Icons.business_center_rounded, dept),
                      _infoChip(Icons.work_outline_rounded, designation),
                      _infoChip(
                        Icons.attach_money_rounded,
                        'PKR ${salary.toString()}',
                      ),
                    ],
                  ),
                  if (perms != null) ..._permChips(perms),
                ],
              ),
            ),
            if (!approved) ...[
              _processingDocs[docId] == true && _processingDocs[docId + '_rejected'] == true
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFEF4444),
                      ),
                    )
                  : IconButton(
                      onPressed: _processingDocs[docId] == true
                          ? null
                          : () async {
                              setState(() {
                                _processingDocs[docId] = true;
                                _processingDocs[docId + '_rejected'] = true;
                              });
                              try {
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(docId)
                                    .delete();
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text('$name registration rejected & deleted!'),
                                      backgroundColor: const Color(0xFFEF4444),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } catch (e) {
                                debugPrint('Error rejecting employee: $e');
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _processingDocs[docId] = false;
                                    _processingDocs[docId + '_rejected'] = false;
                                  });
                                }
                              }
                            },
                      icon: const Icon(
                        Icons.cancel_rounded,
                        color: Color(0xFFEF4444),
                        size: 24,
                      ),
                    ),
              const SizedBox(width: 6),
              _processingDocs[docId] == true && _processingDocs[docId + '_approved'] == true
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF22C55E),
                      ),
                    )
                  : IconButton(
                      onPressed: _processingDocs[docId] == true
                          ? null
                          : () async {
                              setState(() {
                                _processingDocs[docId] = true;
                                _processingDocs[docId + '_approved'] = true;
                              });
                              try {
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(docId)
                                    .update({'approved': true});

                                // Send approval notification
                                final userSnap = await FirebaseFirestore.instance.collection('users').doc(docId).get();
                                if (userSnap.exists) {
                                  final userData = userSnap.data();
                                  final tokens = List<String>.from(userData?['fcmTokens'] ?? []);
                                  if (tokens.isNotEmpty) {
                                    await PushNotificationService.instance.sendPushNotification(
                                      recipientTokens: tokens,
                                      title: 'Account Approved',
                                      body: 'Congratulations! Your account has been approved by the Admin.',
                                    );
                                  }
                                }

                                await FirebaseFirestore.instance.collection('notifications').add({
                                  'userId': docId,
                                  'title': 'Account Approved',
                                  'body': 'Congratulations! Your account has been approved by the Admin.',
                                  'type': 'approval',
                                  'data': {},
                                  'read': false,
                                  'createdAt': DateTime.now().toIso8601String(),
                                });

                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text('$name approved successfully!'),
                                      backgroundColor: const Color(0xFF22C55E),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } catch (e) {
                                debugPrint('Error approving employee: $e');
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _processingDocs[docId] = false;
                                    _processingDocs[docId + '_approved'] = false;
                                  });
                                }
                              }
                            },
                      icon: const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF22C55E),
                        size: 24,
                      ),
                    ),
              const SizedBox(width: 8),
            ],
            IconButton(
              onPressed: () => _showEditDialog(ctx, docId, d),
              icon: const Icon(
                Icons.edit_outlined,
                color: Color(0xFF6366F1),
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _permChips(Map<String, dynamic> perms) {
    final locPerm = perms['location'] as String? ?? 'unknown';
    final notifOk = perms['notification'] as bool? ?? false;
    final batteryOk = perms['battery'] as bool? ?? false;
    final locOk = locPerm == 'always' || locPerm == 'whileInUse';
    final allOk = locOk && notifOk && batteryOk;

    String locLabel;
    switch (locPerm) {
      case 'always':
        locLabel = 'Location: Always';
        break;
      case 'whileInUse':
        locLabel = 'Location: In use';
        break;
      case 'denied':
        locLabel = 'Location: Denied';
        break;
      case 'deniedForever':
        locLabel = 'Location: Blocked';
        break;
      default:
        locLabel = 'Location: Unknown';
    }

    return [
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          _devicePermChip(
            icon: Icons.location_on_rounded,
            label: locLabel,
            ok: locOk,
          ),
          _devicePermChip(
            icon: Icons.notifications_rounded,
            label: notifOk ? 'Notif: On' : 'Notif: Off',
            ok: notifOk,
          ),
          _devicePermChip(
            icon: Icons.battery_charging_full_rounded,
            label: batteryOk ? 'Battery: Free' : 'Battery: Limited',
            ok: batteryOk,
          ),
          if (!allOk)
            _devicePermChip(
              icon: Icons.warning_amber_rounded,
              label: 'Tracking limited',
              ok: false,
              isWarning: true,
            ),
        ],
      ),
    ];
  }

  Widget _devicePermChip({
    required IconData icon,
    required String label,
    required bool ok,
    bool isWarning = false,
  }) {
    final Color bg = isWarning
        ? const Color(0xFFFFF7ED)
        : ok
        ? const Color(0xFFF0FDF4)
        : const Color(0xFFFEF2F2);
    final Color fg = isWarning
        ? const Color(0xFFEA580C)
        : ok
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: fg),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleBadge(String role) {
    final isAdmin = role == 'admin' || email == 'raqeebdeveloper@gmail.com';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isAdmin ? const Color(0xFFEEF2FF) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        role,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isAdmin ? const Color(0xFF6366F1) : const Color(0xFF16A34A),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey.shade400),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _dialogField(
    String label,
    TextEditingController ctrl, {
    bool isNumber = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dialogLabel(label),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF6366F1)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dialogLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade600,
      ),
    );
  }

  Widget _dialogDropdown(
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: items.contains(value) ? value : items.first,
      items: items
          .map(
            (i) => DropdownMenuItem(
              value: i,
              child: Text(i, style: const TextStyle(fontSize: 13)),
            ),
          )
          .toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF6366F1)),
        ),
      ),
    );
  }
}
