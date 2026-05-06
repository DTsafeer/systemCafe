import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_model.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
class UserDatabase {
  static final CollectionReference _userCollection = FirebaseFirestore.instance.collection('users');

  // التحقق من تسجيل الدخول
  static Future<User?> authenticate(String email, String password) async {
    final query = await _userCollection
        .where('email', isEqualTo: email.trim())
        .where('password', isEqualTo: password.trim())
        .get();

    if (query.docs.isNotEmpty) {
      return User.fromMap(query.docs.first.data() as Map<String, dynamic>, query.docs.first.id);
    }
    return null;
  }

  // حفظ الجلسة
  static Future<void> saveSession(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('email', email);
    await prefs.setString('password', password);
  }

  static Future<Map<String, String?>?> getSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('email')) {
      return {'email': prefs.getString('email'), 'password': prefs.getString('password')};
    }
    return null;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
  static Future<void> updateOnlineStatus(String userId, bool status) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .update({'isOnline': status});
  }

  // استيراد مكتبة الفايربيز ماسيجينج في الأعلى
// import 'package:firebase_messaging/firebase_messaging.dart';

  static Future<void> updateFcmToken(String userId) async {
    try {
      // 1. طلب التوكن الفريد لهذا الجهاز
      String? token = await FirebaseMessaging.instance.getToken();

      if (token != null) {
        // 2. حفظه في مستند المستخدم لكي نتمكن من مراسلته لاحقاً
        await _userCollection.doc(userId).update({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        });
        print("✅ تم تحديث رمز الإشعارات بنجاح");
      }
    } catch (e) {
      print("❌ خطأ في تحديث رمز الإشعارات: $e");
    }
  }
}