import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class EmployeeSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final String userName;

  const EmployeeSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Row(
              children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Core Flow HCM',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
              ],
            ),
          ),
          const SizedBox(height: 4),

          _buildNavItem(context, 0, Icons.dashboard_rounded, 'Dashboard'),
          _buildNavItem(context, 1, Icons.event_note_rounded, 'Attendance'),
          _buildNavItem(context, 2, Icons.beach_access_rounded, 'Leaves'),
          _buildNavItem(context, 3, Icons.receipt_long_rounded, 'Payslips'),
          _buildNavItem(context, 4, Icons.trending_up_rounded, 'Performance'),
          _buildNavItem(context, 5, Icons.account_balance_wallet_rounded, 'Expenses'),
          _buildNavItem(context, 6, Icons.school_rounded, 'My Learning'),
          _buildNavItem(context, 7, Icons.description_rounded, 'My Documents'),
          _buildNavItem(context, 8, Icons.person_rounded, 'My Profile'),

          const Spacer(),

          // Bottom user info
          Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF22C55E),
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'E',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName.length > 12 ? '${userName.substring(0, 12)}...' : userName,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                      ),
                      Text('Employee', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () async {
                    await AuthService().signOut();
                    // AuthWrapper auto-redirects to login when auth state changes
                  },
                  child: Icon(Icons.logout_outlined, size: 22, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int index, IconData icon, String label) {
    final bool isSelected = selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            onItemSelected(index);
            _handleNavigation(context, index, label);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF6366F1).withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isSelected ? Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)) : null,
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: isSelected ? const Color(0xFF6366F1) : Colors.grey.shade500),
                const SizedBox(width: 10),
                Text(label, style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? const Color(0xFF6366F1) : Colors.grey.shade600,
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleNavigation(BuildContext context, int index, String label) {
    // Navigation is handled by the parent dashboard via onItemSelected callback.
    // Close the drawer if this sidebar is rendered inside a Drawer widget (mobile).
    final scaffoldState = Scaffold.maybeOf(context);
    if (scaffoldState != null && scaffoldState.isDrawerOpen) {
      scaffoldState.closeDrawer();
    }
  }
}
