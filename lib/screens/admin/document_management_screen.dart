import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class DocumentManagementScreen extends StatefulWidget {
  final bool isMobile;
  final VoidCallback? onMenuPressed;
  const DocumentManagementScreen({super.key, this.isMobile = false, this.onMenuPressed});

  @override
  State<DocumentManagementScreen> createState() => _DocumentManagementScreenState();
}

class _DocumentManagementScreenState extends State<DocumentManagementScreen> {
  String _searchQuery = '';
  String _filterType = 'All';

  final List<String> _docTypes = [
    'All', 'offer_letter', 'contract', 'warning', 'experience', 'payslip'
  ];

  final Map<String, String> _typeLabels = {
    'offer_letter': 'Offer Letter',
    'contract': 'Employment Contract',
    'warning': 'Warning Letter',
    'experience': 'Experience Certificate',
    'payslip': 'Payslip',
  };

  Future<void> _showCreateDialog(BuildContext context) async {
    String? selectedUserId;
    String selectedType = 'offer_letter';
    final titleCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final usersSnap =
        await FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'employee').get();
    final users = usersSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();

    if (!mounted) return;
    await showDialog(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Create Document',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Employee'),
                DropdownButtonFormField<String>(
                  initialValue: selectedUserId,
                  hint: const Text('Select employee', style: TextStyle(fontSize: 13)),
                  items: users
                      .map((u) => DropdownMenuItem(
                          value: u['id'] as String,
                          child: Text(u['name'] as String? ?? '', style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (v) => setS(() => selectedUserId = v),
                  decoration: _inputDec(),
                ),
                const SizedBox(height: 12),
                _label('Document Type'),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  items: _docTypes
                      .skip(1)
                      .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(_typeLabels[t] ?? t, style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (v) => setS(() => selectedType = v!),
                  decoration: _inputDec(),
                ),
                const SizedBox(height: 12),
                _label('Title'),
                TextField(
                  controller: titleCtrl,
                  decoration: _inputDec(hint: 'Document title'),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                _label('Notes'),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: _inputDec(hint: 'Additional notes...'),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
              onPressed: () async {
                if (selectedUserId == null) return;
                final messenger = ScaffoldMessenger.of(context);
                final user = users.firstWhere((u) => u['id'] == selectedUserId);
                await FirebaseFirestore.instance.collection('documents').add({
                  'userId': selectedUserId,
                  'userName': user['name'] ?? '',
                  'type': selectedType,
                  'title': titleCtrl.text.trim().isEmpty ? (_typeLabels[selectedType] ?? selectedType) : titleCtrl.text.trim(),
                  'notes': notesCtrl.text.trim(),
                  'createdAt': DateTime.now().toIso8601String(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Document created'), backgroundColor: Color(0xFF22C55E)),
                );
              },
              child: const Text('Create', style: TextStyle(color: Colors.white)),
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
            _buildFilters(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('documents')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));
                  }
                  final docs = (snap.data?.docs ?? []).where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final name = (d['userName'] as String? ?? '').toLowerCase();
                    final type = d['type'] as String? ?? '';
                    return name.contains(_searchQuery.toLowerCase()) &&
                        (_filterType == 'All' || type == _filterType);
                  }).toList();

                  if (docs.isEmpty) {
                    return Center(child: Text('No documents found', style: TextStyle(color: Colors.grey.shade400)));
                  }
                  return ListView.builder(
                    padding: EdgeInsets.all(isMobile ? 16 : 24),
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final d = docs[i].data() as Map<String, dynamic>;
                      return _buildDocCard(docs[i].id, d);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context),
        backgroundColor: const Color(0xFF6366F1),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Document', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildTopBar(bool isMobile, VoidCallback? onMenuPressed) {
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
          const Icon(Icons.folder_open_rounded, color: Color(0xFF6366F1), size: 22),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Document Management',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              Text('HR documents, contracts, and letters',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      color: Colors.white,
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search by employee name...',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: Color(0xFF6366F1))),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _docTypes.map((t) {
                final isActive = _filterType == t;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filterType = t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFF6366F1) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(t == 'All' ? 'All' : (_typeLabels[t] ?? t),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isActive ? Colors.white : Colors.grey.shade600)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocCard(String docId, Map<String, dynamic> d) {
    final type = d['type'] as String? ?? '';
    final title = d['title'] as String? ?? _typeLabels[type] ?? type;
    final userName = d['userName'] as String? ?? '';
    final notes = d['notes'] as String? ?? '';
    final createdAt = d['createdAt'] as String?;
    final dateStr = createdAt != null
        ? DateFormat('dd MMM yyyy').format(DateTime.parse(createdAt).toLocal())
        : '';

    final isWarning = type == 'warning';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isWarning ? Border.all(color: const Color(0xFFFCA5A5), width: 1) : null,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isWarning ? const Color(0xFFFEE2E2) : const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isWarning ? Icons.warning_amber_rounded : Icons.description_rounded,
                color: isWarning ? const Color(0xFFDC2626) : const Color(0xFF6366F1),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                  const SizedBox(height: 2),
                  Text(userName, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(notes, style: TextStyle(fontSize: 11, color: Colors.grey.shade400), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isWarning ? const Color(0xFFFEE2E2) : const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_typeLabels[type] ?? type,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isWarning ? const Color(0xFFDC2626) : const Color(0xFF6366F1))),
                ),
                const SizedBox(height: 4),
                Text(dateStr, style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Document'),
                        content: const Text('Are you sure you want to delete this document?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await FirebaseFirestore.instance.collection('documents').doc(docId).delete();
                    }
                  },
                  child: Icon(Icons.delete_outline_rounded, size: 16, color: Colors.grey.shade400),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDec({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Color(0xFF6366F1))),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
    );
  }
}
