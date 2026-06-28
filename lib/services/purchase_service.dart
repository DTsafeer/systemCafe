import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/user_model.dart';
import '../pages/activity_logger.dart';

class PurchaseService {
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
    String? method,
    String? unit,
    Map<String, double>? payments,
    bool toShopInventory = false,
    double sellingPrice = 0.0, // إضافة سعر البيع
  }) async {
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    
    final String collectionName = toShopInventory ? 'inventory' : 'external_warehouse';
    
    final query = await firestore.collection(collectionName)
        .where('cafeId', isEqualTo: cafeId)
        .where('name', isEqualTo: productName)
        .limit(1).get();
        
    DocumentReference itemRef;
    double newAvgCost = 0.0;

    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      final data = doc.data();
      itemRef = doc.reference;
      
      double currentQty = (data['quantity'] ?? 0.0).toDouble();
      double currentAvgCost = (data[toShopInventory ? 'costPrice' : 'unitCost'] ?? 0.0).toDouble();
      
      double totalNewQty = currentQty + qty;
      if (totalNewQty > 0) {
        newAvgCost = ((currentQty * currentAvgCost) + amount) / totalNewQty;
      }

      Map<String, dynamic> updateData = {
        'quantity': FieldValue.increment(qty),
        'dateAdded': FieldValue.serverTimestamp(),
      };
      
      if (toShopInventory) {
        updateData['costPrice'] = newAvgCost;
        updateData['lastCostPrice'] = newAvgCost;
        // تحديث سعر البيع فقط إذا كان أكبر من صفر، للحفاظ على السعر القديم إذا لم يُدخل سعر جديد
        if (sellingPrice > 0) updateData['sellingPrice'] = sellingPrice;
      } else {
        updateData['unitCost'] = newAvgCost;
      }

      batch.update(itemRef, updateData);
    } else {
      itemRef = firestore.collection(collectionName).doc();
      newAvgCost = qty > 0 ? (amount / qty) : 0.0;
      
      Map<String, dynamic> setData = {
        'name': productName,
        'quantity': qty,
        'unit': unit ?? "وحدة",
        'cafeId': cafeId,
        'parentId': managerId,
        'dateAdded': FieldValue.serverTimestamp(),
      };

      if (toShopInventory) {
        setData['costPrice'] = newAvgCost;
        setData['lastCostPrice'] = newAvgCost;
        setData['sellingPrice'] = sellingPrice;
      } else {
        setData['unitCost'] = newAvgCost;
        setData['supplier'] = supplierName ?? "مورد عام";
        setData['note'] = note;
      }
      
      batch.set(itemRef, setData);
    }

    final purchaseRef = firestore.collection('purchases').doc();
    batch.set(purchaseRef, {
      'cafeId': cafeId,
      'parentId': managerId,
      'productName': productName,
      'amount': amount,
      'quantity': qty,
      'unit': unit ?? "وحدة",
      'unitCost': qty > 0 ? (amount / qty) : 0.0,
      'movingAvgCost': newAvgCost,
      'date': FieldValue.serverTimestamp(),
      'added_by': currentUser.name,
      'method': method ?? "كاش",
      'target': toShopInventory ? "مخزن المحل" : "المخزن الرئيسي",
    });

    await batch.commit();

    ActivityLogger.log(
      cafeId: cafeId,
      parentId: managerId,
      userId: currentUser.id,
      userName: currentUser.name,
      action: "مشتريات",
      details: "إضافة $qty $productName إلى ${toShopInventory ? 'مخزن المحل' : 'المخزن الرئيسي'} (WAC: ${newAvgCost.toStringAsFixed(2)})",
    );
  }
}
