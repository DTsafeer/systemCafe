import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class AccountService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // الحصول على رصيد طريقة دفع معينة
  static Future<double> getMethodBalance(String cafeId, String method) async {
    final doc = await _db.collection('cafes').doc(cafeId).collection('accounts').doc(method).get();
    if (doc.exists) {
      return max(0.0, (doc.data()?['balance'] ?? 0.0).toDouble());
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
    // نستخدم increment ولكن عند العرض والمزامنة نضمن عدم النزول عن 0
    batch.set(ref, {
      'balance': FieldValue.increment(amount),
      'lastUpdate': FieldValue.serverTimestamp(),
      'methodName': method,
    }, SetOptions(merge: true));
  }

  // التحقق من كفاية الرصيد (منع النزول عن 0)
  static Future<bool> hasEnoughBalance(String cafeId, String method, double requiredAmount) async {
    if (method.contains("دين") || method.contains("ديون")) return true;
    double currentBalance = await getMethodBalance(cafeId, method);
    return currentBalance >= requiredAmount;
  }

  // إعادة احتساب الأرصدة (مقبوضات - مدفوعات) مع ضمان الحد الأدنى 0
  static Future<void> syncAllAccountBalances(String cafeId, String managerId) async {
    final paymentsSnap = await _db.collection('payments')
        .where('cafeId', isEqualTo: cafeId)
        .where('parentId', isEqualTo: managerId)
        .get();

    final expensesSnap = await _db.collection('expenses')
        .where('cafeId', isEqualTo: cafeId)
        .where('parentId', isEqualTo: managerId)
        .get();

    Map<String, double> newBalances = {};

    // إضافة كل ما دخل (مقبوضات مبيعات وسداد ديون)
    for (var doc in paymentsSnap.docs) {
      String method = doc.data()['payment_method'] ?? "كاش";
      double amt = (doc.data()['total_amount'] ?? 0.0).toDouble();
      if (!method.contains("دين")) {
        newBalances[method] = (newBalances[method] ?? 0.0) + amt;
      }
    }

    // طرح كل ما خرج (مصاريف ومشتريات)
    for (var doc in expensesSnap.docs) {
      String method = doc.data()['method'] ?? "كاش";
      double amt = (doc.data()['amount'] ?? 0.0).toDouble();
      if (!method.contains("دين")) {
        newBalances[method] = (newBalances[method] ?? 0.0) - amt;
      }
    }

    final batch = _db.batch();
    for (var entry in newBalances.entries) {
      final ref = _db.collection('cafes').doc(cafeId).collection('accounts').doc(entry.key);
      // قاعدة الصرامة: الرصيد لا يقل عن صفر أبداً
      double finalBal = max(0.0, entry.value);
      
      batch.set(ref, {
        'balance': finalBal,
        'methodName': entry.key,
        'lastSync': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }
}
