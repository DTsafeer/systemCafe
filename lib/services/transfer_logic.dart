import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../pages/user_model.dart';
import 'account_service.dart';

class TransferLogic {
  final User currentUser;
  final String cafeId;

  TransferLogic({required this.currentUser, required this.cafeId});

  /// الحصول على تيار الحوالات
  Stream<QuerySnapshot> getPaymentsStream() {
    return FirebaseFirestore.instance
        .collection('payments')
        .where('cafeId', isEqualTo: cafeId)
        .snapshots();
  }

  /// الحصول على إعدادات المقهى
  Stream<DocumentSnapshot> getCafeSettingsStream() {
    return FirebaseFirestore.instance
        .collection('cafes')
        .doc(cafeId)
        .snapshots();
  }

  /// مزامنة الديون
  Future<void> syncWithDebts({
    required String customerInput,
    required String phone,
    required double amount,
    String type = "إضافة دين (حوالة)",
  }) async {
    final String managerId = currentUser.parentId ?? currentUser.id;
    if (cafeId.isEmpty || customerInput == "زبون عام") return;

    try {
      final allDebts = await FirebaseFirestore.instance
          .collection('debts')
          .where('cafeId', isEqualTo: cafeId)
          .where('parentId', isEqualTo: managerId)
          .get();

      DocumentReference? existingRef;
      for (var doc in allDebts.docs) {
        if (doc.data()['customer']?.toString().toLowerCase() == customerInput.toLowerCase()) {
          existingRef = doc.reference;
          break;
        }
      }

      if (existingRef != null) {
        await existingRef.update({
          'totalDebt': FieldValue.increment(amount),
          'remainingAmount': FieldValue.increment(amount),
          'lastUpdate': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseFirestore.instance.collection('debts').add({
          'cafeId': cafeId,
          'parentId': managerId,
          'customer': customerInput,
          'totalDebt': amount,
          'totalPaid': 0.0,
          'remainingAmount': amount,
          'date': FieldValue.serverTimestamp(),
          'debtNo': allDebts.size + 1001,
          'phone': phone,
        });
      }
    } catch (e) {
      debugPrint("Debt Sync Error: $e");
    }
  }

  /// إضافة حوالة جديدة مع تحديث الخزينة المالية
  Future<void> addManualTransfer({
    required String name,
    required String phone,
    required double amount,
    required String method,
  }) async {
    final batch = FirebaseFirestore.instance.batch();
    final managerId = currentUser.parentId ?? currentUser.id;

    // 1. إذا كانت دين، نحدث سجل الديون
    if (method.contains("دين")) {
      await syncWithDebts(customerInput: name, phone: phone, amount: amount);
    }
    
    // 2. تحديث الخزينة المالية (زيادة الرصيد) إذا لم تكن ديناً
    if (amount > 0 && !method.contains("دين")) {
      await AccountService.updateBalance(
        cafeId: cafeId, 
        method: method, 
        amount: amount, 
        batch: batch
      );
    }

    // 3. إضافة سجل الحوالة
    final paymentRef = FirebaseFirestore.instance.collection('payments').doc();
    batch.set(paymentRef, {
      'customer_name': name,
      'customer_phone': phone,
      'total_amount': amount,
      'payment_method': method,
      'paid_at': FieldValue.serverTimestamp(),
      'processed_by': currentUser.name,
      'cafeId': cafeId,
      'parentId': managerId,
      'is_received': method.contains("كاش") || method.contains("نقدي"),
      'items': [],
      'table': 'حوالة يدوية'
    });

    await batch.commit();
  }

  /// حذف حوالة مع عكس رصيد الخزينة
  Future<void> deleteTransfer(String docId, Map data) async {
    final batch = FirebaseFirestore.instance.batch();
    final double amount = (data['total_amount'] ?? 0.0).toDouble();
    final String method = data['payment_method'] ?? "كاش";

    if (amount > 0 && !method.contains("دين")) {
      await AccountService.updateBalance(
        cafeId: cafeId, 
        method: method, 
        amount: -amount, 
        batch: batch
      );
    }

    batch.delete(FirebaseFirestore.instance.collection('payments').doc(docId));
    await batch.commit();
  }
}
