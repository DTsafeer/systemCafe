import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../pages/user_model.dart';

class SetupService {
  static Future<void> completeSetup({
    required String cafeName,
    required String selectedPackage,
    required int maxEmployees,
    required String currencySymbol,
    required String promoCode,
    required String email,
    required String name,
    required String password,
    required Map<String, dynamic> packagePerms,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    String? cafeId = prefs.getString('cafe_id');

    if (cafeId == null || cafeId.isEmpty) {
      cafeId = "cafe_${DateTime.now().millisecondsSinceEpoch}";
      await prefs.setString('cafe_id', cafeId);
    }

    // 1. إعداد المنشأة
    await FirebaseFirestore.instance.collection('cafes').doc(cafeId).set({
      'cafe_name': cafeName,
      'package': selectedPackage,
      'maxEmployees': maxEmployees,
      'currency_symbol': currencySymbol,
      'promo_code': promoCode,
      'isSetupComplete': true,
      'owner_email': email,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 2. إنشاء حساب المدير
    final userPermissions = { ...packagePerms, 'canManageUsers': true };
    await FirebaseFirestore.instance.collection('users').doc(email).set({
      'cafeId': cafeId,
      'name': name,
      'email': email,
      'username': email,
      'password': password,
      'role': 'admin',
      'isOwner': true,
      'isActive': true,
      'permissions': userPermissions,
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 3. حفظ بيانات الجلسة محلياً
    await prefs.setBool('isSetupComplete', true);
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('user_id', email); // توحيد المفتاح مع AuthService
    await prefs.setString('session_email', email);
    await prefs.setString('cafe_id', cafeId);
    await prefs.setString('cafeName', cafeName);
  }
}
