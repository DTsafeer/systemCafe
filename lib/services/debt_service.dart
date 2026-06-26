import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/user_model.dart';
import '../pages/activity_logger.dart';

class DebtService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<List<Map<String, dynamic>>> streamDebts(String cafeId, String managerId) {
    return _db.collection('debts')
        .where('cafeId', isEqualTo: cafeId)
        .where('parentId', isEqualTo: managerId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final d = doc.data();
              
              double totalDebt = (d['totalDebt'] as num? ?? 0.0).toDouble();
              double initialBalance = (d['initialBalance'] as num? ?? 0.0).toDouble();
              double totalPaid = (d['totalPaid'] as num? ?? 0.0).toDouble();
              
              double netBalance = (totalDebt - totalPaid) - initialBalance;
              
              return {
                ...d,
                'id': doc.id,
                'customer': d['customer']?.toString() ?? "بدون اسم",
                'phone': d['phone']?.toString() ?? "",
                'netBalance': netBalance,
                'debtLimit': (d['debtLimit'] as num? ?? 0.0).toDouble(),
              };
            }).toList());
  }

  // الدالة المطلوبة من صفحة الديون
  static Future<void> addDebtCustomer({
    required String cafeId,
    required String managerId,
    required String name,
    required String phone,
    required double initialDebt,
    required User currentUser,
    double initialCredit = 0.0,
    double debtLimit = 0.0,
  }) async {
    final batch = _db.batch();
    final docRef = _db.collection('debts').doc();
    
    // تحديد الرصيد الافتتاحي (دائن أو مدين)
    double finalInitialCredit = 0.0;
    double finalInitialDebt = 0.0;

    if (initialCredit >= initialDebt) {
      finalInitialCredit = initialCredit - initialDebt;
      finalInitialDebt = 0.0;
    } else {
      finalInitialCredit = 0.0;
      finalInitialDebt = initialDebt - initialCredit;
    }

    batch.set(docRef, {
      'customer': name,
      'phone': phone,
      'initialBalance': finalInitialCredit,
      'totalDebt': finalInitialDebt, // نسجل الدين الابتدائي مباشرة هنا
      'totalPaid': 0.0,
      'remainingAmount': finalInitialDebt - finalInitialCredit,
      'debtLimit': debtLimit,
      'cafeId': cafeId,
      'parentId': managerId,
      'createdAt': FieldValue.serverTimestamp(),
      'lastUpdate': FieldValue.serverTimestamp(),
      // توليد رقم حساب تلقائي بسيط
      'debtNo': DateTime.now().millisecondsSinceEpoch.toString().substring(7),
    });

    if (finalInitialDebt > 0) {
      final transRef = _db.collection('debt_transactions').doc();
      batch.set(transRef, {
        'debtId': docRef.id,
        'customerName': name,
        'type': "دين ابتدائي",
        'amount': finalInitialDebt,
        'date': FieldValue.serverTimestamp(),
        'cafeId': cafeId,
        'parentId': managerId,
        'processedBy': currentUser.name,
        'userId': currentUser.id,
        'note': "رصيد افتتاحي (دين سابق)",
      });
    }

    await batch.commit();

    await ActivityLogger.log(
      cafeId: cafeId,
      parentId: managerId,
      userId: currentUser.id,
      userName: currentUser.name,
      action: "ديون - إضافة زبون",
      details: "إضافة زبون: $name برصيد ابتدائي: $finalInitialDebt ₪",
    );
  }

  static Future<void> addDebtTransaction({
    required String debtId,
    required String customerName,
    required String type,
    required double amount,
    required User currentUser,
    String? note,
  }) async {
    final String managerId = currentUser.parentId ?? currentUser.id;
    final batch = _db.batch();

    final transRef = _db.collection('debt_transactions').doc();
    batch.set(transRef, {
      'debtId': debtId,
      'customerName': customerName,
      'type': type,
      'amount': amount,
      'date': FieldValue.serverTimestamp(),
      'cafeId': currentUser.cafeId,
      'parentId': managerId,
      'processedBy': currentUser.name,
      'note': note ?? (type == "دين" ? "دين جديد (عليه)" : "سداد / رصيد (له)"),
    });

    final customerRef = _db.collection('debts').doc(debtId);
    if (type == "دين") {
      batch.update(customerRef, {
        'totalDebt': FieldValue.increment(amount),
        'remainingAmount': FieldValue.increment(amount),
        'lastUpdate': FieldValue.serverTimestamp(),
      });
    } else {
      batch.update(customerRef, {
        'totalPaid': FieldValue.increment(amount),
        'remainingAmount': FieldValue.increment(-amount),
        'lastUpdate': FieldValue.serverTimestamp(),
      });
      
      // سداد الدين يسجل كعملية دفع (Payment) ليدخل في الحسابات اليومية
      final paymentRef = _db.collection('payments').doc();
      batch.set(paymentRef, {
        'total_amount': amount,
        'payment_method': 'كاش',
        'is_debt_payment': true,
        'customer_name': customerName,
        'payer_name': customerName,
        'paid_at': FieldValue.serverTimestamp(),
        'day': DateTime.now().day,
        'month': DateTime.now().month,
        'year': DateTime.now().year,
        'cafeId': currentUser.cafeId,
        'parentId': managerId,
        'processed_by': currentUser.name,
        'userId': currentUser.id,
        'is_received': true,
      });
    }

    await batch.commit();

    await ActivityLogger.log(
      cafeId: currentUser.cafeId,
      parentId: managerId,
      userId: currentUser.id,
      userName: currentUser.name,
      action: "ديون - حركة",
      details: "تسجيل $type للزبون $customerName بمبلغ $amount ₪",
    );
  }

  static Future<void> deleteTransaction(String transId, String debtId, String type, double amount, User currentUser) async {
    final batch = _db.batch();
    batch.delete(_db.collection('debt_transactions').doc(transId));
    
    final docRef = _db.collection('debts').doc(debtId);
    if (type == "دين" || type == "دين ابتدائي") {
      batch.update(docRef, {
        'totalDebt': FieldValue.increment(-amount),
        'remainingAmount': FieldValue.increment(-amount)
      });
    } else {
      batch.update(docRef, {
        'totalPaid': FieldValue.increment(-amount),
        'remainingAmount': FieldValue.increment(amount)
      });
    }
    await batch.commit();

    await ActivityLogger.log(
      cafeId: currentUser.cafeId,
      parentId: currentUser.parentId ?? currentUser.id,
      userId: currentUser.id,
      userName: currentUser.name,
      action: "ديون - حذف حركة",
      details: "حذف $type بمبلغ $amount ₪ للزبون (id: $debtId)",
    );
  }

  static Future<void> deleteDebtCustomer(String debtId, User currentUser) async {
    final customerDoc = await _db.collection('debts').doc(debtId).get();
    final customerName = customerDoc.data()?['customer'] ?? "غير معروف";

    var transactions = await _db.collection('debt_transactions').where('debtId', isEqualTo: debtId).get();
    final batch = _db.batch();
    for (var doc in transactions.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_db.collection('debts').doc(debtId));
    await batch.commit();

    await ActivityLogger.log(
      cafeId: currentUser.cafeId,
      parentId: currentUser.parentId ?? currentUser.id,
      userId: currentUser.id,
      userName: currentUser.name,
      action: "ديون - حذف زبون",
      details: "حذف الزبون $customerName مع كافة سجلاته",
    );
  }

  static Future<void> updateDebtCustomer(String debtId, Map<String, dynamic> data, User currentUser) async {
    await _db.collection('debts').doc(debtId).update({
      ...data,
      'lastUpdate': FieldValue.serverTimestamp(),
    });
    
    await ActivityLogger.log(
      cafeId: currentUser.cafeId,
      parentId: currentUser.parentId ?? currentUser.id,
      userId: currentUser.id,
      userName: currentUser.name,
      action: "ديون - تعديل زبون",
      details: "تعديل بيانات الزبون: ${data['customer']}",
    );
  }
}
