import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ActivityLogger {
  static Future<void> log(String cafeId, String action, String details) async {
    final prefs = await SharedPreferences.getInstance();
    // تأكد أنك تخزن اسم المستخدم عند تسجيل الدخول بهذا المفتاح
    String? userName = prefs.getString('user_full_name') ?? "موظف";

    await FirebaseFirestore.instance.collection('activity_logs').add({
      'cafeId': cafeId,
      'userName': userName,
      'action': action,
      'details': details,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}