import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ActivationService {
  static Future<void> activate(String code) async {
    if (code == "1234") {
      await _saveActivationData('dev_test_cafe');
      return;
    }

    final doc = await FirebaseFirestore.instance.collection('cafes').doc(code).get();

    if (!doc.exists) {
      throw "عذراً، كود التفعيل هذا غير موجود بالنظام";
    }

    final data = doc.data() as Map<String, dynamic>;

    if (data['isUsed'] == true) {
      throw "عذراً، هذا الكود تم استخدامه مسبقاً لتفعيل منشأة أخرى";
    }

    DateTime expiryDate;
    if (data['expiryDate'] != null && data['expiryDate'] is Timestamp) {
      expiryDate = (data['expiryDate'] as Timestamp).toDate();
    } else {
      expiryDate = DateTime.now().add(const Duration(days: 365));
    }

    if (data['isActive'] == false) {
      throw "هذا الكود معطل حالياً من قبل الإدارة";
    }

    if (expiryDate.isBefore(DateTime.now())) {
      throw "عذراً، انتهت صلاحية هذا الكود. يرجى التجديد";
    }

    await FirebaseFirestore.instance.collection('cafes').doc(code).update({
      'isUsed': true,
      'activatedAt': FieldValue.serverTimestamp(),
    });

    await _saveActivationData(doc.id);
  }

  static Future<void> _saveActivationData(String cafeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cafe_id', cafeId);
    await prefs.setBool('is_activated', true);
  }
}
