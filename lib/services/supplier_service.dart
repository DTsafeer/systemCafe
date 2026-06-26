import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/user_model.dart';
import '../pages/activity_logger.dart';
import 'account_service.dart';

class SupplierService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<List<Map<String, dynamic>>> streamSuppliers(String cafeId, String managerId) {
    return _db.collection('suppliers')
        .where('cafeId', isEqualTo: cafeId)
        .where('parentId', isEqualTo: managerId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => {
              'id': doc.id,
              ...doc.data(),
            }).toList());
  }

  static Future<void> addSupplier({
    required String name,
    required String phone,
    required String company,
    required String cafeId,
    required String managerId,
    double openingBalance = 0.0,
  }) {
    return _db.collection('suppliers').add({
      'name': name,
      'phone': phone,
      'company': company,
      'cafeId': cafeId,
      'parentId': managerId,
      'openingBalance': openingBalance,
      'totalBalance': openingBalance, 
      'totalPaid': 0.0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> savePurchaseBill({
    required String supplierId,
    required String supplierName,
    required String invoiceNo,
    required double totalAmount,
    required double paidAmount,
    required String method,
    required User currentUser,
    required String cafeId,
    required String managerId,
  }) async {
    // 1. التحقق من الرصيد قبل البدء
    bool isDebtMethod = method.contains("دين") || method.contains("ديون");
    if (paidAmount > 0 && !isDebtMethod) {
      bool hasBalance = await AccountService.hasEnoughBalance(cafeId, method, paidAmount);
      if (!hasBalance) {
        throw Exception("عذراً، الرصيد المتوفر في ($method) غير كافٍ لإتمام السداد.");
      }
    }

    final batch = _db.batch();
    double remaining = totalAmount - paidAmount;

    final purchaseRef = _db.collection('purchases').doc();
    batch.set(purchaseRef, {
      'supplierId': supplierId,
      'supplierName': supplierName,
      'invoiceNo': invoiceNo,
      'productName': "فاتورة مشتريات #$invoiceNo",
      'amount': totalAmount,
      'totalAmount': totalAmount,
      'paidAmount': paidAmount,
      'remaining': remaining,
      'date': FieldValue.serverTimestamp(),
      'cafeId': cafeId,
      'parentId': managerId,
      'processedBy': currentUser.name,
      'added_by': currentUser.name,
      'method': remaining > 0 ? (paidAmount > 0 ? "مزيج" : "دين مورد") : (remaining < 0 ? "دفعة زائدة" : method),
    });

    // تحديث أرصدة المورد
    batch.update(_db.collection('suppliers').doc(supplierId), {
      'totalBalance': FieldValue.increment(remaining),
      if (paidAmount > 0 && !isDebtMethod) 'totalPaid': FieldValue.increment(paidAmount),
    });

    // خصم المبلغ من الخزينة المالية
    if (paidAmount > 0 && !isDebtMethod) {
      await AccountService.updateBalance(
        cafeId: cafeId, 
        method: method, 
        amount: -paidAmount, 
        batch: batch
      );
    }

    batch.set(_db.collection('supplier_transactions').doc(), {
      'supplierId': supplierId,
      'type': 'فاتورة #$invoiceNo | سداد ($method)',
      'amount': totalAmount,
      'paid': paidAmount,
      'method': method,
      'date': FieldValue.serverTimestamp(),
      'cafeId': cafeId,
      'parentId': managerId,
      'processedBy': currentUser.name
    });

    await batch.commit();
  }

  static Future<void> processSupplierPayment({
    required String supplierId,
    required String supplierName,
    required double amount,
    required String method,
    required User currentUser,
    required String cafeId,
    required String managerId,
  }) async {
    bool isDebtMethod = method.contains("دين") || method.contains("ديون");
    
    // فحص الرصيد للسداد المباشر
    if (!isDebtMethod) {
      bool hasBalance = await AccountService.hasEnoughBalance(cafeId, method, amount);
      if (!hasBalance) {
        throw Exception("عذراً، الرصيد المتوفر في ($method) غير كافٍ لإتمام الدفع.");
      }
    }

    final batch = _db.batch();
    
    batch.update(_db.collection('suppliers').doc(supplierId), {
      'totalBalance': FieldValue.increment(-amount),
      if (!isDebtMethod) 'totalPaid': FieldValue.increment(amount),
    });

    if (!isDebtMethod) {
      await AccountService.updateBalance(
        cafeId: cafeId, 
        method: method, 
        amount: -amount, 
        batch: batch
      );
    }

    batch.set(_db.collection('supplier_transactions').doc(), {
      'supplierId': supplierId,
      'type': 'سداد ($method)',
      'amount': amount,
      'isPayment': true,
      'method': method,
      'date': FieldValue.serverTimestamp(),
      'cafeId': cafeId,
      'parentId': managerId,
      'processedBy': currentUser.name
    });

    await batch.commit();
  }

  static Future<void> deleteSupplier(String id) => _db.collection('suppliers').doc(id).delete();
}
