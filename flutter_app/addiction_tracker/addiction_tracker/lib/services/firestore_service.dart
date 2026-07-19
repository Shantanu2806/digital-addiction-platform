import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> saveScreenTime({
    required String userId,
    required int totalMinutes,
    required DateTime date,
  }) async {
    try {
      String dateId = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      await _db
          .collection('users')
          .doc(userId)
          .collection('screen_time')
          .doc(dateId)
          .set({
        'total_minutes': totalMinutes,
        'date': Timestamp.fromDate(date),
        'hours': totalMinutes ~/ 60,
        'minutes': totalMinutes % 60,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving: $e');
    }
  }

  Future<int> getTodayScreenTime(String userId) async {
    try {
      DateTime today = DateTime.now();
      String dateId = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      DocumentSnapshot doc = await _db
          .collection('users')
          .doc(userId)
          .collection('screen_time')
          .doc(dateId)
          .get();
      if (doc.exists) {
        return (doc.data() as Map<String, dynamic>)['total_minutes'] ?? 0;
      }
      return 0;
    } catch (e) {
      print('Error getting today: $e');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getWeeklyData(String userId) async {
    try {
      DateTime now = DateTime.now();
      DateTime weekAgo = now.subtract(const Duration(days: 7));
      QuerySnapshot snapshot = await _db
          .collection('users')
          .doc(userId)
          .collection('screen_time')
          .where('date', isGreaterThan: Timestamp.fromDate(weekAgo))
          .orderBy('date', descending: false)
          .get();
      return snapshot.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      print('Error getting weekly: $e');
      return [];
    }
  }
}
