import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/user_model.dart';
import '../pages/activity_logger.dart';

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
    double remaining = totalAmount - paidAmount;
    final batch = _db.batch();

    bool isDebtMethod = method.contains("دين") || method.contains("ديون");

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

    Map<String, dynamic> supplierUpdates = {};
    supplierUpdates['totalBalance'] = FieldValue.increment(remaining);
    
    if (paidAmount > 0) {
      if (isDebtMethod) {
        supplierUpdates['totalBalance'] = FieldValue.increment(paidAmount);
      } else {
        supplierUpdates['totalPaid'] = FieldValue.increment(paidAmount);
      }
    }
    
    batch.update(_db.collection('suppliers').doc(supplierId), supplierUpdates);

    // تفاصيل الحركة للفاتورة: سداد (طريقة الدفع)
    String purchaseType = 'فاتورة #$invoiceNo | سداد ($method)';

    batch.set(_db.collection('supplier_transactions').doc(), {
      'supplierId': supplierId,
      'type': purchaseType,
      'amount': totalAmount,
      'paid': paidAmount,
      'method': method,
      'date': FieldValue.serverTimestamp(),
      'cafeId': cafeId,
      'parentId': managerId,
      'processedBy': currentUser.name
    });

    if (paidAmount > 0 && !isDebtMethod) {
      batch.set(_db.collection('expenses').doc(), {
        'title': "سداد للمورد: $supplierName (فاتورة $invoiceNo)",
        'amount': paidAmount,
        'category': "مشتريات",
        'method': method,
        'date': FieldValue.serverTimestamp(),
        'cafeId': cafeId,
        'parentId': managerId,
        'processedBy': currentUser.name
      });
    }

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
    final batch = _db.batch();
    bool isDebtMethod = method.contains("دين") || method.contains("ديون");
    
    batch.update(_db.collection('suppliers').doc(supplierId), {
      'totalBalance': FieldValue.increment(-amount),
      if (!isDebtMethod) 'totalPaid': FieldValue.increment(amount),
    });

    // تفاصيل الحركة للسداد المباشر: سداد (طريقة الدفع)
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

    if (!isDebtMethod) {
      batch.set(_db.collection('expenses').doc(), {
        'title': "سداد دفعة للمورد: $supplierName",
        'amount': amount,
        'category': "مشتريات",
        'method': method,
        'date': FieldValue.serverTimestamp(),
        'cafeId': cafeId,
        'parentId': managerId,
        'processedBy': currentUser.name
      });
    }

    await batch.commit();
  }

  static Future<void> deleteSupplier(String id) => _db.collection('suppliers').doc(id).delete();
}
