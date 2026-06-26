import 'package:cloud_firestore/cloud_firestore.dart';

class KitchenService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<List<Map<String, dynamic>>> streamActiveOrders(String cafeId, String managerId) {
    return _db.collection('orders')
        .where('cafeId', isEqualTo: cafeId)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          final orders = snapshot.docs.where((doc) {
            final data = doc.data();
            final status = data['kitchen_status'] ?? 'pending';
            final paid = data['paid'] ?? false;
            return data['parentId'] == managerId && status != 'completed' && paid == false;
          }).map((doc) => {
            'id': doc.id,
            ...doc.data(),
          }).toList();

          orders.sort((a, b) {
            Timestamp t1 = a['ordered_at'] ?? Timestamp.now();
            Timestamp t2 = b['ordered_at'] ?? Timestamp.now();
            return t1.compareTo(t2);
          });
          
          return orders;
        });
  }

  static Future<void> updateOrderStatus(String orderId, String status) {
    String nextStatus = status == 'pending' ? 'preparing' : 'completed';
    return _db.collection('orders').doc(orderId).update({
      'kitchen_status': nextStatus
    });
  }

  static Future<void> deleteOrder(String orderId) {
    return _db.collection('orders').doc(orderId).delete();
  }
}
