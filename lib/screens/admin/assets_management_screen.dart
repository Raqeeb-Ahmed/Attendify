import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AssetsManagementScreen extends StatefulWidget {
  final bool isMobile;
  final VoidCallback? onMenuPressed;

  const AssetsManagementScreen({
    super.key,
    this.isMobile = false,
    this.onMenuPressed,
  });

  @override
  State<AssetsManagementScreen> createState() => _AssetsManagementScreenState();
}

class _AssetsManagementScreenState extends State<AssetsManagementScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late TabController _tabController;

  String _searchQuery = '';
  String _selectedTypeFilter = 'all';
  bool isSelected = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  IconData _getAssetIcon(String type) {
    switch (type.toLowerCase()) {
      case 'laptop':
        return Icons.laptop_mac_rounded;
      case 'vehicle':
      case 'bike':
        return Icons.directions_bike_rounded;
      case 'mobile':
      case 'phone':
        return Icons.phone_android_rounded;
      case 'keys':
      case 'key':
        return Icons.vpn_key_rounded;
      case 'access card':
      case 'card':
        return Icons.badge_rounded;
      case 'furniture':
        return Icons.chair_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return const Color(0xFF10B981); // Emerald Green
      case 'returned':
        return const Color(0xFF64748B); // Slate Grey
      case 'damaged':
        return const Color(0xFFF59E0B); // Amber
      case 'lost':
        return const Color(0xFFEF4444); // Red
      default:
        return const Color(0xFF6366F1); // Indigo
    }
  }

  Future<void> _showAssignAssetDialog({
    String? assetId,
    String? employeeId,
    String? employeeName,
    String? name,
    String? type,
    String? assignedDate,
    String? notes,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: name);
    final notesCtrl = TextEditingController(text: notes);

    String? selectedEmpId = employeeId;
    String selectedEmpName = employeeName ?? '';
    String selectedType = type ?? 'Laptop';
    DateTime selectedDate = assignedDate != null
        ? (DateTime.tryParse(assignedDate) ?? DateTime.now())
        : DateTime.now();

    final isEdit = assetId != null;
    bool isSaving = false;

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
                  Icon(
                    isEdit
                        ? Icons.edit_note_rounded
                        : Icons.add_moderator_rounded,
                    color: const Color(0xFF6366F1),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isEdit ? 'Edit Allocation' : 'Assign Asset',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: 400,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Employee Selector
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Assign to Employee',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          subtitle: Text(
                            selectedEmpName.isEmpty
                                ? 'Select Employee'
                                : selectedEmpName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: selectedEmpName.isEmpty
                                  ? Colors.grey.shade400
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                          ),
                          onTap: isEdit
                              ? null
                              : () async {
                                  final result =
                                      await _showEmployeeSelectionDialog(
                                        dialogContext,
                                      );
                                  if (result != null) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (context.mounted) {
                                        setDialogState(() {
                                          selectedEmpId = result['uid'];
                                          selectedEmpName = result['name'] ?? '';
                                        });
                                      }
                                    });
                                  }
                                },
                        ),
                        const Divider(),
                        const SizedBox(height: 12),

                        // Asset Type
                        const Text(
                          'Asset Category',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: selectedType,
                          items:
                              [
                                    'Laptop',
                                    'Vehicle',
                                    'Mobile',
                                    'Keys',
                                    'Access Card',
                                    'Furniture',
                                    'Other',
                                  ]
                                  .map(
                                    (t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(
                                        t,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) =>
                              setDialogState(() => selectedType = v!),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Asset Name
                        TextFormField(
                          controller: nameCtrl,
                          decoration: InputDecoration(
                            labelText: 'Asset Name (e.g., MacBook Air M2)',
                            labelStyle: const TextStyle(fontSize: 13),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFF6366F1),
                              ),
                            ),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Please enter asset name'
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // Assignment Date
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Assigned Date: ${DateFormat('yyyy-MM-dd').format(selectedDate)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setDialogState(() => selectedDate = picked);
                                }
                              },
                              icon: const Icon(
                                Icons.date_range_rounded,
                                size: 16,
                              ),
                              label: const Text('Change'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Notes
                        TextFormField(
                          controller: notesCtrl,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Additional Notes / Accessories Details',
                            labelStyle: const TextStyle(fontSize: 13),
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFF6366F1),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (selectedEmpId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please select an employee'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          if (formKey.currentState!.validate()) {
                            setDialogState(() => isSaving = true);
                            try {
                              final docRef = isEdit
                                  ? _firestore.collection('assets').doc(assetId)
                                  : _firestore.collection('assets').doc();

                              final Map<String, dynamic> dataMap = {
                                'employeeId': selectedEmpId,
                                'employeeName': selectedEmpName,
                                'name': nameCtrl.text.trim(),
                                'type': selectedType,
                                'assignedDate': selectedDate
                                    .toIso8601String()
                                    .split('T')[0],
                                'notes': notesCtrl.text.trim(),
                              };

                              if (!isEdit) {
                                dataMap['id'] = docRef.id;
                                dataMap['status'] = 'Assigned';
                                dataMap['createdAt'] =
                                    FieldValue.serverTimestamp();
                              }

                              final navigator = Navigator.of(dialogContext);
                              final scaffoldMessenger = ScaffoldMessenger.of(
                                context,
                              );
                              await docRef.set(
                                dataMap,
                                SetOptions(merge: true),
                              );

                              navigator.pop();
                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    isEdit
                                        ? 'Asset updated successfully'
                                        : 'Asset assigned successfully',
                                  ),
                                  backgroundColor: const Color(0xFF22C55E),
                                ),
                              );
                            } catch (e) {
                              debugPrint("Error saving asset: $e");
                            }
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
                  icon: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                  label: Text(
                    isSaving ? 'Saving...' : 'Save',
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

  Future<Map<String, String>?> _showEmployeeSelectionDialog(
    BuildContext parentContext,
  ) async {
    String searchEmp = '';
    bool isSelected = false;
    return showDialog<Map<String, String>>(
      context: parentContext,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setS) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Select Employee',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 320,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      onChanged: (v) => setS(() => searchEmp = v),
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: FutureBuilder<QuerySnapshot>(
                        future: _firestore
                            .collection('users')
                            .where(
                              'role',
                              whereIn: const ['employee', 'manager'],
                            )
                            .get(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final docs = snapshot.data?.docs ?? [];
                          final filtered = docs.where((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final name = (data['name'] ?? '')
                                .toString()
                                .toLowerCase();
                            final email = (data['email'] ?? '')
                                .toString()
                                .toLowerCase();
                            return name.contains(searchEmp.toLowerCase()) ||
                                email.contains(searchEmp.toLowerCase());
                          }).toList();

                          if (filtered.isEmpty) {
                            return const Center(
                              child: Text('No employees found'),
                            );
                          }

                          return ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, idx) {
                              final doc = filtered[idx];
                              final data = doc.data() as Map<String, dynamic>;
                              final name =
                                  data['name'] ?? data['email'] ?? 'Unnamed';
                              final email = data['email'] ?? '';

                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: const Color(
                                    0xFF6366F1,
                                  ).withValues(alpha: 0.1),
                                  child: Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : 'E',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF6366F1),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  email,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onTap: () {
                                  if (!isSelected) {
                                    isSelected = true;
                                    Future.delayed(Duration.zero, () {
                                      if (ctx.mounted) {
                                        Navigator.pop(ctx, <String, String>{
                                          'uid': doc.id,
                                          'name': name,
                                        });
                                      }
                                    });
                                  }
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
          },
        );
      },
    );
  }

  Future<void> _updateAssetStatus(String assetId, String status) async {
    try {
      final updateData = {'status': status};
      if (status == 'Returned') {
        updateData['returnedDate'] = DateTime.now().toIso8601String().split(
          'T',
        )[0];
      }
      await _firestore.collection('assets').doc(assetId).update(updateData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Asset status updated to $status'),
            backgroundColor: _getStatusColor(status),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error updating asset status: $e");
    }
  }

  Future<void> _deleteAsset(String assetId) async {
    bool isDeleting = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Delete Log'),
          content: const Text(
            'Are you sure you want to delete this allocation history? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isDeleting
                  ? null
                  : () async {
                      setS(() => isDeleting = true);
                      try {
                        await _firestore.collection('assets').doc(assetId).delete();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Log deleted'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } catch (e) {
                        setS(() => isDeleting = false);
                      }
                    },
              child: isDeleting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.red,
                      ),
                    )
                  : const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final localIsMobile = screenWidth < 768;
    final isMobile = widget.isMobile || localIsMobile;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAssignAssetDialog,
        backgroundColor: const Color(0xFF6366F1),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Assign Asset',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(isMobile, widget.onMenuPressed),
            _buildSearchAndFilters(isMobile),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAssetsStream(onlyActive: true, isMobile: isMobile),
                  _buildAssetsStream(onlyActive: false, isMobile: isMobile),
                ],
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
            Icons.devices_other_rounded,
            color: Color(0xFF6366F1),
            size: 24,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Assets Management',
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

  Widget _buildSearchAndFilters(bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: 12,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search asset or employee...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                fillColor: Colors.white,
                filled: true,
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
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: _selectedTypeFilter,
            items:
                [
                      'all',
                      'Laptop',
                      'Vehicle',
                      'Mobile',
                      'Keys',
                      'Access Card',
                      'Furniture',
                      'Other',
                    ]
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(
                          type == 'all' ? 'All Categories' : type,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    )
                    .toList(),
            onChanged: (v) => setState(() => _selectedTypeFilter = v!),
            underline: const SizedBox(),
            icon: const Icon(Icons.filter_list_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFF6366F1),
        unselectedLabelColor: Colors.grey.shade500,
        indicatorColor: const Color(0xFF6366F1),
        indicatorWeight: 3,
        tabs: const [
          Tab(text: 'Active Allocations'),
          Tab(text: 'History Archive'),
        ],
      ),
    );
  }

  Widget _buildAssetsStream({
    required bool onlyActive,
    required bool isMobile,
  }) {
    Query query = _firestore.collection('assets');

    if (onlyActive) {
      query = query.where('status', isEqualTo: 'Assigned');
    } else {
      query = query.where('status', whereIn: ['Returned', 'Damaged', 'Lost']);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        final filtered = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final name = (data['name'] ?? '').toString().toLowerCase();
          final employee = (data['employeeName'] ?? '')
              .toString()
              .toLowerCase();
          final type = (data['type'] ?? '').toString();

          final matchesSearch =
              name.contains(_searchQuery.toLowerCase()) ||
              employee.contains(_searchQuery.toLowerCase());

          final matchesCategory =
              _selectedTypeFilter == 'all' || type == _selectedTypeFilter;

          return matchesSearch && matchesCategory;
        }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Text(
              onlyActive
                  ? 'No active assets assigned.'
                  : 'No allocation history.',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 24,
            vertical: 12,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, idx) {
            final doc = filtered[idx];
            final data = doc.data() as Map<String, dynamic>;
            return _buildAssetCard(doc.id, data, isMobile);
          },
        );
      },
    );
  }

  Widget _buildAssetCard(String id, Map<String, dynamic> data, bool isMobile) {
    final name = data['name'] ?? 'Asset Name';
    final type = data['type'] ?? 'Other';
    final employee = data['employeeName'] ?? 'Employee';
    final status = data['status'] ?? 'Assigned';
    final date = data['assignedDate'] ?? 'Date N/A';
    final notes = data['notes'] ?? '';
    final returnedDate = data['returnedDate'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 6,
            offset: const Offset(0, 1),
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
                  radius: 18,
                  backgroundColor: const Color(
                    0xFF6366F1,
                  ).withValues(alpha: 0.1),
                  child: Icon(
                    _getAssetIcon(type),
                    color: const Color(0xFF6366F1),
                    size: 18,
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
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        'Category: $type',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: Colors.grey.shade500,
                    size: 20,
                  ),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showAssignAssetDialog(
                        assetId: id,
                        employeeId: data['employeeId'],
                        employeeName: employee,
                        name: name,
                        type: type,
                        assignedDate: date,
                        notes: notes,
                      );
                    } else if (value == 'delete') {
                      _deleteAsset(id);
                    } else {
                      _updateAssetStatus(id, value);
                    }
                  },
                  itemBuilder: (context) => [
                    if (status == 'Assigned') ...[
                      const PopupMenuItem(
                        value: 'Returned',
                        child: Text(
                          'Mark as Returned',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'Damaged',
                        child: Text(
                          'Mark as Damaged',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'Lost',
                        child: Text(
                          'Mark as Lost',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      const PopupMenuDivider(),
                    ],
                    if (status != 'Assigned') ...[
                      const PopupMenuItem(
                        value: 'Assigned',
                        child: Text(
                          'Re-assign / Re-active',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      const PopupMenuDivider(),
                    ],
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text(
                        'Edit details',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete log',
                        style: TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assigned to',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      employee,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      status == 'Returned' ? 'Returned On' : 'Assigned On',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status == 'Returned' ? returnedDate : date,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  notes,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(status),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
