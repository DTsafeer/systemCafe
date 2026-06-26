import 'package:cloud_firestore/cloud_firestore.dart';

class TableService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<List<Map<String, dynamic>>> streamTables(String cafeId, String managerId) {
    return _db.collection('tables')
        .where('cafe_id', isEqualTo: cafeId)
        .where('parentId', isEqualTo: managerId)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) => snapshot.docs.map((doc) => {
              'id': doc.id,
              'metadata': doc.metadata,
              ...doc.data(),
            }).toList());
  }

  static Future<void> addTable(String name, String cafeId, String managerId) {
    return _db.collection('tables').add({
      'name': name,
      'cafe_id': cafeId,
      'parentId': managerId,
      'is_open': false,
      'start_time': null,
      'accumulated_seconds': 0
    });
  }

  static Future<void> updateTableStatus(String tableId, bool isOpen, {DateTime? startTime, int accumulatedSeconds = 0}) {
    return _db.collection('tables').doc(tableId).update({
      'is_open': isOpen,
      'start_time': startTime != null ? Timestamp.fromDate(startTime) : null,
      'accumulated_seconds': accumulatedSeconds,
    });
  }

  static Future<void> pauseTimer(String tableId, int currentTotalSeconds) {
    return _db.collection('tables').doc(tableId).update({
      'start_time': null,
      'accumulated_seconds': currentTotalSeconds,
    });
  }

  static Future<void> resumeTimer(String tableId) {
    return _db.collection('tables').doc(tableId).update({
      'start_time': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> resetTimer(String tableId, bool keepRunning) {
    return _db.collection('tables').doc(tableId).update({
      'start_time': keepRunning ? FieldValue.serverTimestamp() : null,
      'accumulated_seconds': 0,
    });
  }

  static Future<void> deleteTable(String tableId) {
    return _db.collection('tables').doc(tableId).delete();
  }
}
