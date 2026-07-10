import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/firebase_exception_handler.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Attendance ──

  /// Get today's attendance record for a user
  Future<Map<String, dynamic>?> getTodayAttendance(String uid) async {
    try {
      final today = _todayKey();
      final snap = await _db
          .collection('attendance')
          .where('userId', isEqualTo: uid)
          .where('date', isEqualTo: today)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty ? snap.docs.first.data() : null;
    } catch (e) {
      throw AppException(getFirebaseErrorMessage(e));
    }
  }

  /// Stream of attendance records for a user (attendance log)
  Stream<QuerySnapshot> getAttendanceRecords(String uid, {int limit = 30}) {
    return _db
        .collection('attendance')
        .where('userId', isEqualTo: uid)
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots();
  }

  // ── Admin ──

  /// Stream all employee live locations for admin map
  Stream<QuerySnapshot> getLiveLocations() {
    return _db.collection('locations').snapshots();
  }

  /// Get all employees
  Stream<QuerySnapshot> getEmployees() {
    return _db
        .collection('users')
        .where('role', whereIn: const ['employee', 'manager'])
        .snapshots();
  }

  /// Get all attendance for a specific date (admin view)
  Stream<QuerySnapshot> getAllAttendanceForDate(String dateKey) {
    return _db
        .collection('attendance')
        .where('date', isEqualTo: dateKey)
        .snapshots();
  }

  // ── Helpers ──
  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
