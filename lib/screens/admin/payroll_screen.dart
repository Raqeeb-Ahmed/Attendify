import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class PayrollScreen extends StatefulWidget {
  final bool isMobile;
  final VoidCallback? onMenuPressed;
  const PayrollScreen({super.key, this.isMobile = false, this.onMenuPressed});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  String _searchQuery = '';
  int _selectedYear = DateTime.now().year;
  static const double _taxRate = 0.10;

  final List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _monthKey(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  Future<void> _markAsPaid(
    Map<String, dynamic> emp,
    String monthKey, {
    double deductions = 0,
    double advance = 0,
  }) async {
    try {
      final base = (emp['baseSalary'] as num?)?.toDouble() ?? 0;
      final allowances = (emp['allowances'] as num?)?.toDouble() ?? 0;
      final tax = (base + allowances) * _taxRate;
      final net = base + allowances - tax - deductions - advance;
      final payrollId = '${emp['id']}_$monthKey';

      await FirebaseFirestore.instance
          .collection('payroll')
          .doc(payrollId)
          .set({
            'userId': emp['id'],
            'userName': emp['name'] ?? '',
            'month': monthKey,
            'baseSalary': base,
            'allowances': allowances,
            'tax': tax,
            'deductions': deductions,
            'advance': advance,
            'netSalary': net,
            'status': 'paid',
            'processedAt': DateTime.now().toIso8601String(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payroll processed for ${emp['name']}'),
            backgroundColor: const Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showPaymentDialog(
    BuildContext context,
    Map<String, dynamic> emp,
    String monthKey,
  ) async {
    final deductCtrl = TextEditingController(text: '0');
    final advCtrl = TextEditingController(text: '0');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Process Payroll – ${emp['name']}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogField('Deductions (PKR)', deductCtrl),
            const SizedBox(height: 14),
            _dialogField('Advance Deduction (PKR)', advCtrl),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _markAsPaid(
                emp,
                monthKey,
                deductions: double.tryParse(deductCtrl.text) ?? 0,
                advance: double.tryParse(advCtrl.text) ?? 0,
              );
            },
            child: const Text(
              'Mark as Paid',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dialogField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
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
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              borderSide: BorderSide(color: Color(0xFF6366F1)),
            ),
          ),
        ),
      ],
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
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where('role', whereIn: const ['employee', 'manager'])
                    .snapshots(),
                builder: (ctx, usersSnap) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('payroll')
                        .limit(50)
                        .snapshots(),
                    builder: (ctx, paySnap) {
                      final users = (usersSnap.data?.docs ?? [])
                          .map(
                            (d) => {
                              'id': d.id,
                              ...d.data() as Map<String, dynamic>,
                            },
                          )
                          .where(
                            (e) =>
                                (e['name'] as String? ?? '')
                                    .toLowerCase()
                                    .contains(_searchQuery.toLowerCase()) ||
                                (e['email'] as String? ?? '')
                                    .toLowerCase()
                                    .contains(_searchQuery.toLowerCase()),
                          )
                          .toList();

                      final payDocs = paySnap.data?.docs ?? [];
                      final paidSet = <String>{};
                      final paidMap = <String, Map<String, dynamic>>{};
                      for (var doc in payDocs) {
                        final d = doc.data() as Map<String, dynamic>;
                        paidSet.add(doc.id);
                        paidMap[doc.id] = d;
                      }

                      if (usersSnap.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF6366F1),
                          ),
                        );
                      }

                      return Column(
                        children: [
                          _buildSearchBar(),
                          Expanded(
                            child: ListView.builder(
                              padding: EdgeInsets.all(isMobile ? 16 : 24),
                              itemCount: users.length,
                              itemBuilder: (ctx, i) =>
                                  _buildEmployeePayrollCard(
                                    ctx,
                                    users[i],
                                    paidSet,
                                    paidMap,
                                  ),
                            ),
                          ),
                        ],
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
            Icons.account_balance_wallet_rounded,
            color: Color(0xFF6366F1),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payroll Management',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isMobile ? 15 : 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                Text(
                  'Year: $_selectedYear',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => setState(() => _selectedYear--),
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: Color(0xFF6366F1),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              Text(
                '$_selectedYear',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _selectedYear < DateTime.now().year
                    ? () => setState(() => _selectedYear++)
                    : null,
                icon: Icon(
                  Icons.chevron_right_rounded,
                  color: _selectedYear < DateTime.now().year
                      ? const Color(0xFF6366F1)
                      : Colors.grey.shade300,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
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

  Widget _buildEmployeePayrollCard(
    BuildContext ctx,
    Map<String, dynamic> emp,
    Set<String> paidSet,
    Map<String, Map<String, dynamic>> paidMap,
  ) {
    final bool isMobile = MediaQuery.of(ctx).size.width < 500;
    final name = emp['name'] as String? ?? 'Unknown';
    final email = emp['email'] as String? ?? '';
    final base = (emp['baseSalary'] as num?)?.toDouble() ?? 0;
    final allowances = (emp['allowances'] as num?)?.toDouble() ?? 0;
    final tax = (base + allowances) * _taxRate;
    final net = base + allowances - tax;
    final initials = name
        .split(' ')
        .take(2)
        .map((p) => p.isNotEmpty ? p[0] : '')
        .join()
        .toUpperCase();
    final fmt = NumberFormat('#,##0', 'en_US');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
                  backgroundColor: const Color(
                    0xFF6366F1,
                  ).withValues(alpha: 0.15),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
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
                        email,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Net: PKR ${fmt.format(net)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (!isMobile)
                      Text(
                        'Base: PKR ${fmt.format(base)} + Allow: PKR ${fmt.format(allowances)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade400,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (isMobile) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Base: PKR ${fmt.format(base)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Allowances: PKR ${fmt.format(allowances)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Text(
              'Monthly Status – $_selectedYear',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade400,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(12, (mi) {
                final monthKey = _monthKey(_selectedYear, mi + 1);
                final payrollId = '${emp['id']}_$monthKey';
                final isPaid = paidSet.contains(payrollId);
                final payData = paidMap[payrollId];
                final isCurrentMonth =
                    DateTime.now().year == _selectedYear &&
                    DateTime.now().month == mi + 1;
                final isFuture = DateTime(
                  _selectedYear,
                  mi + 1,
                ).isAfter(DateTime.now());

                return GestureDetector(
                  onTap: (!isPaid && !isFuture)
                      ? () => _showPaymentDialog(ctx, emp, monthKey)
                      : isPaid
                      ? () => _showPaymentDetails(ctx, payData!, _months[mi])
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isFuture
                          ? Colors.grey.shade100
                          : isPaid
                          ? const Color(0xFFDCFCE7)
                          : isCurrentMonth
                          ? const Color(0xFFFEF9C3)
                          : const Color(0xFFFFEDD5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isFuture
                            ? Colors.grey.shade200
                            : isPaid
                            ? const Color(0xFF86EFAC)
                            : isCurrentMonth
                            ? const Color(0xFFFDE68A)
                            : const Color(0xFFFED7AA),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _months[mi].substring(0, 3),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isFuture
                                ? Colors.grey.shade400
                                : isPaid
                                ? const Color(0xFF16A34A)
                                : isCurrentMonth
                                ? const Color(0xFFCA8A04)
                                : const Color(0xFFEA580C),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Icon(
                          isFuture
                              ? Icons.remove
                              : isPaid
                              ? Icons.check_circle_outline_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 14,
                          color: isFuture
                              ? Colors.grey.shade300
                              : isPaid
                              ? const Color(0xFF16A34A)
                              : isCurrentMonth
                              ? const Color(0xFFCA8A04)
                              : const Color(0xFFEA580C),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentDetails(
    BuildContext ctx,
    Map<String, dynamic> data,
    String month,
  ) {
    final fmt = NumberFormat('#,##0', 'en_US');
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(
          'Payslip – $month',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _payRow(
              'Base Salary',
              'PKR ${fmt.format(data['baseSalary'] ?? 0)}',
            ),
            _payRow('Allowances', 'PKR ${fmt.format(data['allowances'] ?? 0)}'),
            _payRow('Tax (10%)', '– PKR ${fmt.format(data['tax'] ?? 0)}'),
            _payRow(
              'Deductions',
              '– PKR ${fmt.format(data['deductions'] ?? 0)}',
            ),
            _payRow('Advance', '– PKR ${fmt.format(data['advance'] ?? 0)}'),
            const Divider(),
            _payRow(
              'Net Salary',
              'PKR ${fmt.format(data['netSalary'] ?? 0)}',
              bold: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Processed: ${data['processedAt'] ?? ''}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _payRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: bold ? const Color(0xFF1E293B) : Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
