import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../pages/user_model.dart';
import '../utils/database_helper.dart';
import '../pages/activity_logger.dart';
import 'transfer_service.dart';
import 'cafe_service.dart';

class OrderService {
  static final DatabaseHelper _dbHelper = DatabaseHelper();

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

        double currentCost = 0.0;
        if (newItem['id'] != null && !newItem['id'].toString().startsWith('custom_')) {
          final prodDoc = await firestore.collection('products').doc(newItem['id']).get();
          if (prodDoc.exists) {
            currentCost = (prodDoc.data()?['costPrice'] ?? 0.0).toDouble();
            
            if (isTrackingEnabled) {
              batch.update(prodDoc.reference, {'stockQuantity': FieldValue.increment(-(newItem['quantity'] ?? 1))});
            }
          }
        }
        newItem['costPriceAtSale'] = currentCost;
        processedItems.add(newItem);

        if (isTrackingEnabled && newItem.containsKey('ingredients') && newItem['ingredients'] is List) {
          for (var ing in (newItem['ingredients'] as List)) {
            if (ing == null || ing['id'] == null) continue;
            double usage = (ing['amount'] as num? ?? 0.0).toDouble() * (newItem['quantity'] as num? ?? 1.0).toDouble();
            if (usage > 0) {
              batch.update(firestore.collection('inventory').doc(ing['id']), {'quantity': FieldValue.increment(-usage)});
            }
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
          'kitchen_status': 'pending',
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
          final data = doc.data();
          final List items = data['items'] as List? ?? [];
          allItemsForPayment.addAll(List<Map<String, dynamic>>.from(items));
          totalToPay += (data['total'] as num? ?? 0.0).toDouble();
          batch.update(doc.reference, {'paid': true});
        }

        if (timerPrice > 0.01) {
          final timerItem = {
            'name': 'رسوم وقت / شحن',
            'price': timerPrice,
            'quantity': 1,
            'total': timerPrice,
            'category': 'رسوم',
            'costPriceAtSale': 0.0,
            'added_at': currentTime,
          };
          allItemsForPayment.add(timerItem);
        }

        if (!skipPaymentRecord) {
          String note = allItemsForPayment.map((it) => "${it['quantity'] ?? 1}x ${it['name'] ?? 'صنف'}").join("، ");
          TransferService.performSave(
            context: context, currentUser: currentUser, customerName: customerName,
            phone: customerPhone, amt: totalToPay, method: method, cafeId: cafeId,
            isDebtPayment: false, selectedDebtId: selectedCustomerId, items: allItemsForPayment,
            table: tableName, note: note, skipSync: skipSync,
            skipPaymentRecord: false,
          );
        }

        ActivityLogger.log(
          cafeId: cafeId, parentId: managerId, userId: currentUser.id, userName: currentUser.name,
          action: "مبيعات - دفع", details: "إتمام دفع $tableName بقيمة $totalToPay ₪ ($method)",
        );
      }

      if (tableId != "takeaway") {
        Map<String, dynamic> tableUpdate = {
          'is_open': method == "pending",
          'last_order_at': FieldValue.serverTimestamp(),
        };
        if (method == "pending" && autoStartTimer) {
          tableUpdate['start_time'] = FieldValue.serverTimestamp();
        }
        if (method != "pending") {
          tableUpdate['start_time'] = null;
          tableUpdate['accumulated_seconds'] = 0;
          tableUpdate['is_open'] = false;
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
    final String managerId = currentUser.parentId ?? currentUser.id;

    try {
      final sourceTableDoc = await firestore.collection('tables').doc(sourceTableId).get();
      final sourceTableData = sourceTableDoc.data() ?? {};
      final Timestamp? sourceStartTime = sourceTableData['start_time'];
      final int sourceAccSeconds = sourceTableData['accumulated_seconds'] ?? 0;

      final sourceOrders = await firestore.collection('orders')
          .where('cafeId', isEqualTo: cafeId)
          .where('table', isEqualTo: sourceTableName)
          .where('paid', isEqualTo: false)
          .get();

      if (sourceOrders.docs.isEmpty && sourceStartTime == null) return;

      for (var doc in sourceOrders.docs) {
        batch.update(doc.reference, {
          'table': targetTableName,
          'ordered_at': FieldValue.serverTimestamp(),
        });
      }

      final targetTableDoc = await firestore.collection('tables').doc(targetTableId).get();
      final targetTableData = targetTableDoc.data() ?? {};
      
      Map<String, dynamic> targetUpdate = {'is_open': true};
      if (targetTableData['is_open'] != true && sourceStartTime != null) {
        targetUpdate['start_time'] = sourceStartTime;
        targetUpdate['accumulated_seconds'] = sourceAccSeconds;
      }

      batch.update(firestore.collection('tables').doc(targetTableId), targetUpdate);

      batch.update(firestore.collection('tables').doc(sourceTableId), {
        'is_open': false,
        'start_time': null,
        'accumulated_seconds': 0,
      });

      await batch.commit();

      ActivityLogger.log(
        cafeId: cafeId,
        parentId: managerId,
        userId: currentUser.id,
        userName: currentUser.name,
        action: "طاولات - دمج",
        details: "دمج حساب $sourceTableName مع $targetTableName (تم نقل الطلبات والوقت)",
      );
    } catch (e) {
      debugPrint("Error merging tables: $e");
      rethrow;
    }
  }

  static Future<void> transferItems({
    required String sourceOrderId,
    required String targetTableName,
    required List<Map<String, dynamic>> itemsToTransfer,
    required User currentUser,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    final String managerId = currentUser.parentId ?? currentUser.id;

    try {
      final sourceDoc = await firestore.collection('orders').doc(sourceOrderId).get();
      if (!sourceDoc.exists) return;

      final sourceData = sourceDoc.data()!;
      List<Map<String, dynamic>> sourceItems = List<Map<String, dynamic>>.from(sourceData['items'] ?? []);
      String sourceTableName = sourceData['table'] ?? "؟";

      for (var transferredItem in itemsToTransfer) {
        final String itemId = transferredItem['id'] ?? transferredItem['name'];
        final double qtyToMove = (transferredItem['quantity'] as num).toDouble();

        for (int i = 0; i < sourceItems.length; i++) {
          final sItem = sourceItems[i];
          final String sId = sItem['id'] ?? sItem['name'];
          if (sId == itemId) {
            double currentQty = (sItem['quantity'] as num).toDouble();
            if (currentQty <= qtyToMove) {
              sourceItems.removeAt(i);
            } else {
              sourceItems[i]['quantity'] = currentQty - qtyToMove;
              sourceItems[i]['total'] = (currentQty - qtyToMove) * (sItem['price'] as num).toDouble();
            }
            break;
          }
        }
      }

      bool sourceOrderDeleted = false;
      if (sourceItems.isEmpty) {
        batch.delete(sourceDoc.reference);
        sourceOrderDeleted = true;
      } else {
        double newTotal = sourceItems.fold(0.0, (sum, it) => sum + (it['total'] as num).toDouble());
        batch.update(sourceDoc.reference, {
          'items': sourceItems,
          'total': newTotal,
        });
      }

      double transferredTotal = itemsToTransfer.fold(0.0, (sum, it) => sum + (it['total'] as num).toDouble());
      final newOrderDoc = firestore.collection('orders').doc();
      batch.set(newOrderDoc, {
        'items': itemsToTransfer,
        'cafeId': currentUser.cafeId,
        'parentId': managerId,
        'table': targetTableName,
        'ordered_at': FieldValue.serverTimestamp(),
        'kitchen_status': 'completed',
        'waiter_name': currentUser.name,
        'paid': false,
        'customer_name': '',
        'total': transferredTotal,
      });

      final targetTableQuery = await firestore.collection('tables')
          .where('cafe_id', isEqualTo: currentUser.cafeId)
          .where('name', isEqualTo: targetTableName)
          .limit(1)
          .get();
      
      if (targetTableQuery.docs.isNotEmpty) {
        batch.update(targetTableQuery.docs.first.reference, {'is_open': true});
      }

      if (sourceOrderDeleted) {
        final remainingOrders = await firestore.collection('orders')
            .where('cafeId', isEqualTo: currentUser.cafeId)
            .where('table', isEqualTo: sourceTableName)
            .where('paid', isEqualTo: false)
            .get();
        
        if (remainingOrders.docs.length <= 1) {
           final sourceTableQuery = await firestore.collection('tables')
              .where('cafe_id', isEqualTo: currentUser.cafeId)
              .where('name', isEqualTo: sourceTableName)
              .limit(1)
              .get();
           if (sourceTableQuery.docs.isNotEmpty) {
             batch.update(sourceTableQuery.docs.first.reference, {
               'is_open': false,
               'start_time': null,
               'accumulated_seconds': 0,
             });
           }
        }
      }

      await batch.commit();

      ActivityLogger.log(
        cafeId: currentUser.cafeId,
        parentId: managerId,
        userId: currentUser.id,
        userName: currentUser.name,
        action: "طاولات - نقل أصناف",
        details: "نقل أصناف من $sourceTableName إلى $targetTableName بقيمة $transferredTotal ₪ مع تحديث الوقت",
      );
    } catch (e) {
      debugPrint("Error transferring items: $e");
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
      final bool isTrackingEnabled = settings.isInventoryTrackingEnabled;

      if (isTrackingEnabled) {
        for (var item in items) {
          if (item['id'] != null && !item['id'].toString().startsWith('custom_')) {
            batch.update(firestore.collection('products').doc(item['id']), {
              'stockQuantity': FieldValue.increment((item['quantity'] ?? 1).toDouble())
            });
          }
          
          if (item['ingredients'] != null && item['ingredients'] is List) {
            for (var ing in (item['ingredients'] as List)) {
              double usage = (ing['amount'] as num? ?? 0.0).toDouble() * (item['quantity'] as num? ?? 1.0).toDouble();
              if (usage > 0) {
                batch.update(firestore.collection('inventory').doc(ing['id']), {
                  'quantity': FieldValue.increment(usage)
                });
              }
            }
          }
        }
      }

      batch.delete(orderDoc.reference);
      await batch.commit();

      ActivityLogger.log(
        cafeId: currentUser.cafeId,
        parentId: managerId,
        userId: currentUser.id,
        userName: currentUser.name,
        action: "طاولات - حذف طلب",
        details: "حذف طلب من $tableName بقيمة $amount ₪. (المخزن: ${isTrackingEnabled ? 'تم الاسترجاع' : 'لم يتأثر'})",
      );
    } catch (e) {
      debugPrint("Error deleting and reverting order: $e");
      rethrow;
    }
  }

  static Future<void> clearTable({
    required String tableId,
    required String tableName,
    required String cafeId,
    required String managerId,
    required User currentUser,
  }) async {
    try {
      final ordersQuery = await FirebaseFirestore.instance.collection('orders')
          .where('cafeId', isEqualTo: cafeId)
          .where('table', isEqualTo: tableName)
          .where('paid', isEqualTo: false)
          .get();

      double total = 0;
      for (var doc in ordersQuery.docs) {
        total += (doc.data()['total'] as num? ?? 0.0).toDouble();
        await deleteSingleOrder(
          orderId: doc.id,
          tableName: tableName,
          amount: (doc.data()['total'] ?? 0).toDouble(),
          itemsSummary: "تصفير طاولة",
          currentUser: currentUser
        );
      }

      if (tableId != "takeaway") {
        await FirebaseFirestore.instance.collection('tables').doc(tableId).update({
          'is_open': false,
          'start_time': null,
          'accumulated_seconds': 0,
        });
      }

      ActivityLogger.log(
        cafeId: cafeId, parentId: managerId, userId: currentUser.id, userName: currentUser.name,
        action: "طاولات - تصفير", details: "تصفير كامل لـ $tableName بقيمة $total ₪",
      );
    } catch (e) {
      rethrow;
    }
  }
}
