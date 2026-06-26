import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_model.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class UserDatabase {
  static final CollectionReference _userCollection = FirebaseFirestore.instance.collection('users');

  /// جلب الموظفين التابعين لكافيه معين فقط
  /// تم إزالة الفلترة بـ parentId هنا للسماح للمديرين برؤية زملائهم الموظفين في نفس الكافيه
  static Stream<List<User>> getCafeEmployees(String cafeId) {
    return _userCollection
        .where('cafeId', isEqualTo: cafeId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => User.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  /// التحقق من تسجيل الدخول عبر البحث في القاعدة وليس عبر الـ ID مباشرة
  /// هذا يحل مشكلة التداخل إذا وُجد نفس اسم المستخدم في كافيهات مختلفة
  static Future<User?> authenticate(String username, String password) async {
    try {
      final query = await _userCollection
          .where('username', isEqualTo: username.trim().toLowerCase())
          .where('password', isEqualTo: password.trim())
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        return User.fromMap(query.docs.first.data() as Map<String, dynamic>, query.docs.first.id);
      }
    } catch (e) {
      print("Auth error: $e");
    }
    return null;
  }

  static Future<void> updateOnlineStatus(String userId, bool status) async {
    try {
      await _userCollection.doc(userId).update({'isOnline': status});
    } catch (e) {
      print("Status update error: $e");
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  static Future<void> updateFcmToken(String userId) async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _userCollection.doc(userId).update({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print("FCM Token error: $e");
    }
  }
}
