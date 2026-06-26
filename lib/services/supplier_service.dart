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
  }) {
    return _db.collection('suppliers').add({
      'name': name,
      'phone': phone,
      'company': company,
      'cafeId': cafeId,
      'parentId': managerId,
      'totalBalance': 0.0,
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

    // تحديد ما إذا كانت طريقة الدفع هي "دين"
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
      'method': remaining > 0 ? (paidAmount > 0 ? "مزيج" : "دين مورد") : method,
    });

    // تحديث أرصدة المورد بناءً على نوع الدفع
    Map<String, dynamic> supplierUpdates = {};
    
    // 1. المتبقي (remaining) هو دائماً دين
    if (remaining > 0) {
      supplierUpdates['totalBalance'] = FieldValue.increment(remaining);
    }
    
    // 2. المبلغ المسدد الآن (paidAmount)
    if (paidAmount > 0) {
      if (isDebtMethod) {
        // إذا اختار طريقة دفع هي "دين" للمبلغ المسدد (حالة نادرة لكن نعالجها)
        supplierUpdates['totalBalance'] = FieldValue.increment(paidAmount);
      } else {
        // الدفع الطبيعي (كاش، شبكة، إلخ) يذهب للرصيد المدفوع
        supplierUpdates['totalPaid'] = FieldValue.increment(paidAmount);
      }
    }
    
    if (supplierUpdates.isNotEmpty) {
      batch.update(_db.collection('suppliers').doc(supplierId), supplierUpdates);
    }

    batch.set(_db.collection('supplier_transactions').doc(), {
      'supplierId': supplierId,
      'type': 'شراء فاتورة #$invoiceNo',
      'amount': totalAmount,
      'paid': paidAmount,
      'method': method,
      'date': FieldValue.serverTimestamp(),
      'cafeId': cafeId,
      'parentId': managerId,
      'processedBy': currentUser.name
    });

    // تسجيل مصاريف فقط إذا كان الدفع غير آجل
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
    
    // عند تسديد دفعة: ينقص الدين ويزداد إجمالي المدفوع (بشرط ألا تكون طريقة التسديد هي دين آخر)
    batch.update(_db.collection('suppliers').doc(supplierId), {
      'totalBalance': FieldValue.increment(-amount),
      if (!isDebtMethod) 'totalPaid': FieldValue.increment(amount),
    });

    batch.set(_db.collection('supplier_transactions').doc(), {
      'supplierId': supplierId,
      'type': 'سداد نقدي (دفعة)',
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
