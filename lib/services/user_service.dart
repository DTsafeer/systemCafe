import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/user_model.dart';

class UserService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<List<User>> streamUsers(String cafeId, String managerId) {
    return _db.collection('users')
        .where('cafeId', isEqualTo: cafeId)
        .where('parentId', isEqualTo: managerId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => User.fromMap(doc.data(), doc.id)).toList());
  }

  static Future<void> addUser(Map<String, dynamic> userData) {
    return _db.collection('users').doc(userData['username']).set(userData);
  }

  static Future<void> updateUserPermissions(String userId, String permKey, bool value) {
    return _db.collection('users').doc(userId).update({'permissions.$permKey': value});
  }

  static Future<void> toggleUserStatus(String userId, bool isActive) {
    return _db.collection('users').doc(userId).update({'isActive': isActive});
  }

  static Future<void> deleteUser(String userId) {
    return _db.collection('users').doc(userId).delete();
  }

  static Future<bool> usernameExists(String username) async {
    final doc = await _db.collection('users').doc(username).get();
    return doc.exists;
  }
}
