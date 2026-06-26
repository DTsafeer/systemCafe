import 'package:cloud_firestore/cloud_firestore.dart';

class InventoryService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<List<Map<String, dynamic>>> streamInventory(String cafeId, String managerId) {
    return _db.collection('inventory')
        .where('cafeId', isEqualTo: cafeId)
        .snapshots()
        .map((snapshot) => snapshot.docs.where((doc) {
              final data = doc.data();
              return data['parentId'] == managerId;
            }).map((doc) => {
              'id': doc.id,
              ...doc.data(),
            }).toList());
  }

  static Future<void> addInventoryItem({
    required String name,
    required double quantity,
    required String unit,
    required String cafeId,
    required String managerId,
    double lowStockThreshold = 5.0,
  }) {
    return _db.collection('inventory').add({
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'cafeId': cafeId,
      'parentId': managerId,
      'low_stock_threshold': lowStockThreshold,
    });
  }

  static Future<void> updateQuantity(String itemId, double newQuantity) {
    return _db.collection('inventory').doc(itemId).update({'quantity': newQuantity});
  }

  static Future<void> deleteItem(String itemId) {
    return _db.collection('inventory').doc(itemId).delete();
  }
}
