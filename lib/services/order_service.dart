import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../pages/user_model.dart';
import '../pages/activity_logger.dart';
import 'transfer_service.dart';
import 'cafe_service.dart';

class OrderService {
  static Future<Map<String, dynamic>> submitOrder({
    required BuildContext context,
    required User currentUser,
    required String tableId,
    required String tableName,
    required String method,
    required List<Map<String, dynamic>> itemsList,
    required double finalTotal,
    required String customerName,
    required String customerPhone,
    String? selectedCustomerId,
    required bool autoStartTimer,
    bool skipSync = false,
    bool skipPaymentRecord = false,
    double timerPrice = 0.0,
  }) async {
    final String managerId = currentUser.parentId ?? currentUser.id;
    final String cafeId = currentUser.cafeId;
    final String waiterName = currentUser.name;
    final String currentTime = intl.DateFormat('yyyy/MM/dd hh:mm a').format(DateTime.now());

    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      
      final settings = await CafeService.getCafeSettings(cafeId);
      final bool isTrackingEnabled = settings.isInventoryTrackingEnabled;

      List<Map<String, dynamic>> processedItems = [];

      for (var item in itemsList) {
        final newItem = Map<String, dynamic>.from(item);
        if (newItem['added_at'] == null) newItem['added_at'] = currentTime;

        double qty = (newItem['quantity'] ?? 1.0).toDouble();
        double unitCost = (double.tryParse(newItem['costPriceAtSale']?.toString() ?? "") ?? 
                          double.tryParse(newItem['costPrice']?.toString() ?? "0") ?? 0.0);
        
        newItem['costPriceAtSale'] = unitCost;
        processedItems.add(newItem);

        if (isTrackingEnabled && newItem['id'] != null && !newItem['id'].toString().startsWith('custom_')) {
          final String itemId = newItem['id'];

          // 1. تحديث الكمية في مجموعة المنتجات (للعرض في المنيو)
          batch.update(firestore.collection('products').doc(itemId), {
            'stockQuantity': FieldValue.increment(-qty)
          });

          // 2. الخصم من المخزن العادي (Inventory)
          final ingredients = newItem['ingredients'];
          if (ingredients != null && ingredients is List && ingredients.isNotEmpty) {
            // الخصم من المكونات إذا وجدت
            for (var ing in ingredients) {
              if (ing == null || ing['id'] == null) continue;
              double usage = (double.tryParse(ing['amount']?.toString() ?? "0") ?? 0.0) * qty;
              if (usage > 0) {
                batch.update(firestore.collection('inventory').doc(ing['id']), {
                  'quantity': FieldValue.increment(-usage)
                });
              }
            }
          } else {
            // خصم الصنف نفسه من المخزن العادي إذا لم يكن له مكونات (صنف جاهز)
            // نستخدم set مع merge: true بدلاً من update لتفادي فشل العملية إذا لم يكن الصنف موجوداً في المخزن
            batch.set(firestore.collection('inventory').doc(itemId), {
              'quantity': FieldValue.increment(-qty),
              'last_sale_at': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        }
      }

      String? orderId;
      if (itemsList.isNotEmpty) {
        final orderDoc = firestore.collection('orders').doc();
        orderId = orderDoc.id;
        batch.set(orderDoc, {
          'items': processedItems,
          'cafeId': cafeId,
          'parentId': managerId,
          'table': tableName,
          'ordered_at': FieldValue.serverTimestamp(),
          'waiter_name': waiterName,
          'paid': method != "pending",
          'customer_name': customerName,
          'total': finalTotal,
        });
      }

      double totalToPay = finalTotal;
      List<Map<String, dynamic>> allItemsForPayment = List.from(processedItems);

      if (method != "pending") {
        final pendingQuery = await firestore.collection('orders')
            .where('table', isEqualTo: tableName)
            .where('cafeId', isEqualTo: cafeId)
            .where('paid', isEqualTo: false)
            .get();

        for (var doc in pendingQuery.docs) {
          if (doc.id == orderId) continue;
          final List items = doc.data()['items'] as List? ?? [];
          for (var it in items) {
            final Map<String, dynamic> itemMap = Map<String, dynamic>.from(it);
            if (itemMap['costPriceAtSale'] == null) {
              itemMap['costPriceAtSale'] = (double.tryParse(itemMap['costPrice']?.toString() ?? "0") ?? 0.0);
            }
            allItemsForPayment.add(itemMap);
          }
          totalToPay += (doc.data()['total'] as num? ?? 0.0).toDouble();
          batch.update(doc.reference, {'paid': true});
        }

        if (timerPrice > 0.01) {
          allItemsForPayment.add({
            'name': 'رسوم وقت / شحن',
            'price': timerPrice,
            'quantity': 1,
            'total': timerPrice,
            'category': 'رسوم',
            'costPriceAtSale': 0.0,
            'added_at': currentTime,
          });
        }

        if (!skipPaymentRecord) {
          await TransferService.performSave(
            context: context, currentUser: currentUser, customerName: customerName,
            phone: customerPhone, amt: totalToPay, method: method, cafeId: cafeId,
            isDebtPayment: false, selectedDebtId: selectedCustomerId, items: allItemsForPayment,
            table: tableName, note: "دفع فاتورة $tableName", skipSync: skipSync,
          );
        }
      }

      if (tableId != "takeaway") {
        Map<String, dynamic> tableUpdate = {
          'is_open': method == "pending" || allItemsForPayment.isNotEmpty,
          'last_order_at': FieldValue.serverTimestamp(),
        };
        
        if (method != "pending") {
          tableUpdate['is_open'] = false;
          tableUpdate['start_time'] = null;
          tableUpdate['accumulated_seconds'] = 0;
        } else if (autoStartTimer) {
          tableUpdate['start_time'] = FieldValue.serverTimestamp();
        }
        
        batch.update(firestore.collection('tables').doc(tableId), tableUpdate);
      }

      await batch.commit();
      return {'total': totalToPay, 'items': allItemsForPayment};
    } catch (e) {
      debugPrint("Error in OrderService: $e");
      rethrow;
    }
  }

  static Future<void> deleteSingleOrder({
    required String orderId,
    required String tableName,
    required double amount,
    required String itemsSummary,
    required User currentUser,
  }) async {
    final String managerId = currentUser.parentId ?? currentUser.id;
    final firestore = FirebaseFirestore.instance;
    try {
      final orderDoc = await firestore.collection('orders').doc(orderId).get();
      if (!orderDoc.exists) return;

      final data = orderDoc.data()!;
      final List items = data['items'] as List? ?? [];
      final batch = firestore.batch();

      final settings = await CafeService.getCafeSettings(currentUser.cafeId);
      if (settings.isInventoryTrackingEnabled) {
        for (var item in items) {
          if (item['id'] != null && !item['id'].toString().startsWith('custom_')) {
            final String itemId = item['id'];
            
            batch.update(firestore.collection('products').doc(itemId), {
              'stockQuantity': FieldValue.increment((item['quantity'] ?? 1).toDouble())
            });
            
            final ingredients = item['ingredients'];
            if (ingredients != null && ingredients is List && ingredients.isNotEmpty) {
              for (var ing in ingredients) {
                if (ing == null || ing['id'] == null) continue;
                double usage = (double.tryParse(ing['amount']?.toString() ?? "0") ?? 0.0) * (item['quantity'] ?? 1).toDouble();
                if (usage > 0) {
                  batch.update(firestore.collection('inventory').doc(ing['id']), {
                    'quantity': FieldValue.increment(usage)
                  });
                }
              }
            } else {
              batch.update(firestore.collection('inventory').doc(itemId), {
                'quantity': FieldValue.increment((item['quantity'] ?? 1).toDouble())
              });
            }
          }
        }
      }
      batch.delete(orderDoc.reference);
      await batch.commit();

      await ActivityLogger.log(
        cafeId: currentUser.cafeId, parentId: managerId, userId: currentUser.id, userName: currentUser.name,
        action: "حذف طلب", details: "حذف طلب من $tableName بقيمة $amount ₪",
      );
    } catch (e) { rethrow; }
  }

  static Future<void> clearTable({
    required String tableId,
    required String tableName,
    required String cafeId,
    required String managerId,
    required User currentUser,
  }) async {
    final ordersQuery = await FirebaseFirestore.instance.collection('orders')
        .where('cafeId', isEqualTo: cafeId)
        .where('table', isEqualTo: tableName)
        .where('paid', isEqualTo: false)
        .get();

    for (var doc in ordersQuery.docs) {
      await deleteSingleOrder(orderId: doc.id, tableName: tableName, amount: (doc.data()['total'] ?? 0).toDouble(), itemsSummary: "تصفير", currentUser: currentUser);
    }

    if (tableId != "takeaway") {
      await FirebaseFirestore.instance.collection('tables').doc(tableId).update({
        'is_open': false,
        'start_time': null,
        'accumulated_seconds': 0,
      });
    }
  }

  static Future<void> mergeTables({
    required String sourceTableId,
    required String sourceTableName,
    required String targetTableId,
    required String targetTableName,
    required String cafeId,
    required User currentUser,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    final sourceOrders = await firestore.collection('orders')
        .where('cafeId', isEqualTo: cafeId)
        .where('table', isEqualTo: sourceTableName)
        .where('paid', isEqualTo: false)
        .get();

    for (var doc in sourceOrders.docs) {
      batch.update(doc.reference, {'table': targetTableName});
    }

    batch.update(firestore.collection('tables').doc(targetTableId), {'is_open': true});
    batch.update(firestore.collection('tables').doc(sourceTableId), {'is_open': false, 'start_time': null, 'accumulated_seconds': 0});
    await batch.commit();
  }

  static Future<void> transferItems({
    required String sourceOrderId,
    required String targetTableName,
    required List<Map<String, dynamic>> itemsToTransfer,
    required User currentUser,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    final sourceDoc = await firestore.collection('orders').doc(sourceOrderId).get();
    if (!sourceDoc.exists) return;

    final newOrderDoc = firestore.collection('orders').doc();
    batch.set(newOrderDoc, {
      'items': itemsToTransfer,
      'cafeId': currentUser.cafeId,
      'parentId': currentUser.parentId ?? currentUser.id,
      'table': targetTableName,
      'ordered_at': FieldValue.serverTimestamp(),
      'paid': false,
      'total': itemsToTransfer.fold(0.0, (sum, it) => sum + (it['total'] as num).toDouble()),
    });
    await batch.commit();
  }
}
