import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/database_helper.dart';
import '../pages/user_model.dart';
import '../pages/activity_logger.dart';

class PurchaseService {
  static final DatabaseHelper _dbHelper = DatabaseHelper();

  static Future<void> savePurchase({
    required User currentUser,
    required String cafeId,
    required String managerId,
    required double amount, 
    required String productName,
    required double qty, 
    required String note,
    String? prodId,
    String? supplierId,
    String? supplierName,
    Map<String, double>? payments,
    String? method,
    double? boxPrice,
    double? itemsPerBox,
    String? unit,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();

    Map<String, double> effectivePayments = payments ?? {};
    if (effectivePayments.isEmpty && amount > 0) {
      effectivePayments[method ?? "كاش"] = amount;
    }

    // حساب المبالغ بدقة بناءً على مسميات طرق الدفع
    double debtPart = 0;
    double paidPart = 0;

    effectivePayments.forEach((m, val) {
      if (m.contains("دين") || m.contains("ديون")) {
        debtPart += val;
      } else {
        paidPart += val;
      }
    });

    String mainMethod = effectivePayments.length == 1 
        ? effectivePayments.keys.first 
        : (effectivePayments.length > 1 ? "مزيج" : (method ?? "كاش"));

    // 1. سجل المشتريات
    final purchaseRef = firestore.collection('purchases').doc();
    batch.set(purchaseRef, {
      'cafeId': cafeId,
      'parentId': managerId,
      'productId': prodId ?? "other",
      'productName': productName,
      'supplierId': supplierId,
      'supplierName': supplierName ?? "مورد عام",
      'amount': amount,
      'quantity': qty,
      'unit': unit ?? "وحدة",
      'note': note, 
      'date': FieldValue.serverTimestamp(),
      'added_by': currentUser.name,
      'processedBy': currentUser.name,
      'method': mainMethod,
      'paymentBreakdown': effectivePayments,
      'paidAmount': paidPart,
      'remaining': debtPart,
      'type': 'direct',
    });

    // 2. تحديث أرصدة المورد (الدين والمدفوع)
    if (supplierId != null) {
      final supplierRef = firestore.collection('suppliers').doc(supplierId);
      
      Map<String, dynamic> supplierUpdates = {};
      if (debtPart > 0) {
        supplierUpdates['totalBalance'] = FieldValue.increment(debtPart);
      }
      if (paidPart > 0) {
        supplierUpdates['totalPaid'] = FieldValue.increment(paidPart);
      }
      
      if (supplierUpdates.isNotEmpty) {
        batch.update(supplierRef, supplierUpdates);
      }
      
      final transRef = firestore.collection('supplier_transactions').doc();
      batch.set(transRef, {
        'supplierId': supplierId,
        'type': debtPart > 0 ? 'شراء آجل: $productName' : 'شراء نقدي: $productName',
        'amount': amount,
        'paid': paidPart,
        'method': mainMethod,
        'date': FieldValue.serverTimestamp(),
        'cafeId': cafeId,
        'parentId': managerId,
        'processedBy': currentUser.name
      });
    }

    // 3. تحديث المخزن الرئيسي
    if (prodId != null && prodId != "other") {
      final invRef = firestore.collection('inventory').doc(prodId);
      Map<String, dynamic> invUpdate = {
        'last_purchase_date': FieldValue.serverTimestamp(),
        'quantity': FieldValue.increment(qty),
      };
      if (qty > 0 && amount > 0) {
        invUpdate['costPrice'] = amount / qty;
      }
      batch.update(invRef, invUpdate);
      _dbHelper.updateInventoryQtyLocal(productName, qty, cafeId); 
    }

    // 4. سجل المصاريف (للمبالغ المدفوعة فقط)
    effectivePayments.forEach((m, amt) {
      if (amt > 0 && !m.contains("دين") && !m.contains("ديون")) {
        final expRef = firestore.collection('expenses').doc();
        batch.set(expRef, {
          'cafeId': cafeId,
          'parentId': managerId,
          'title': "شراء: $productName",
          'amount': amt,
          'category': "مشتريات",
          'method': m,
          'note': note, 
          'date': FieldValue.serverTimestamp(),
          'processedBy': currentUser.name,
        });
      }
    });

    await batch.commit();

    ActivityLogger.log(
      cafeId: cafeId,
      parentId: managerId,
      userId: currentUser.id,
      userName: currentUser.name,
      action: "مشتريات - إضافة",
      details: "شراء $productName بقيمة $amount ₪ ($qty $unit) من $supplierName ($mainMethod)",
    );
  }
}
