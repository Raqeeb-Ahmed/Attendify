import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  final _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot> getNotifications(String userId) {
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  Future<int> getUnreadCount(String userId) async {
    final snap = await _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();
    return snap.docs.length;
  }

  Stream<int> streamUnreadCount(String userId) {
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length);
  }

  Future<void> markAsRead(String notificationId) async {
    await _db.collection('notifications').doc(notificationId).update({'read': true});
  }

  Future<void> markAllRead(String userId) async {
    final batch = _db.batch();
    final snap = await _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();
    for (var doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> deleteNotification(String notificationId) async {
    await _db.collection('notifications').doc(notificationId).delete();
  }

  Future<void> sendToUser({
    required String userId,
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? data,
  }) async {
    await _db.collection('notifications').add({
      'userId': userId,
      'title': title,
      'body': body,
      'type': type,
      'data': data ?? {},
      'read': false,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> broadcastToAll({
    required String title,
    required String body,
    String type = 'announcement',
  }) async {
    final usersSnap = await _db.collection('users').get();
    final batch = _db.batch();
    for (var userDoc in usersSnap.docs) {
      final ref = _db.collection('notifications').doc();
      batch.set(ref, {
        'userId': userDoc.id,
        'title': title,
        'body': body,
        'type': type,
        'data': {},
        'read': false,
        'createdAt': DateTime.now().toIso8601String(),
      });
    }
    await batch.commit();
  }
}
