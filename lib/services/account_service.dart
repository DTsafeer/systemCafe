import 'package:cloud_firestore/cloud_firestore.dart';

class AccountService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // الحصول على رصيد طريقة دفع معينة
  static Future<double> getMethodBalance(String cafeId, String method) async {
    final doc = await _db.collection('cafes').doc(cafeId).collection('accounts').doc(method).get();
    if (doc.exists) {
      return (doc.data()?['balance'] ?? 0.0).toDouble();
    }
    return 0.0;
  }

  // تحديث الرصيد (موجب للإيداع/المبيعات، سالب للصرف/المشتريات)
  static Future<void> updateBalance({
    required String cafeId,
    required String method,
    required double amount,
    required WriteBatch batch,
  }) async {
    final ref = _db.collection('cafes').doc(cafeId).collection('accounts').doc(method);
    batch.set(ref, {
      'balance': FieldValue.increment(amount),
      'lastUpdate': FieldValue.serverTimestamp(),
      'methodName': method,
    }, SetOptions(merge: true));
  }

  // التحقق من كفاية الرصيد
  static Future<bool> hasEnoughBalance(String cafeId, String method, double requiredAmount) async {
    // طرق الدفع الآجلة (الديون) لا تحتاج لفحص رصيد
    if (method.contains("دين") || method.contains("ديون")) return true;
    
    double currentBalance = await getMethodBalance(cafeId, method);
    return currentBalance >= requiredAmount;
  }
}
