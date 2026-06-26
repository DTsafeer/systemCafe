import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../pages/user_model.dart';
import '../pages/activity_logger.dart';
import 'account_service.dart';

class TransferService {
  static Future<void> syncWithDebts({
    required User currentUser,
    required String customerInput,
    required String phone,
    required double amount,
    required String cafeId,
    String? selectedId,
    bool isAddingDebt = false,
    String type = "سداد دين",
    String? note,
    DateTime? customDate,
    double? oldAmount,
  }) async {
    final String managerId = currentUser.parentId ?? currentUser.id;
    if (cafeId.isEmpty || customerInput == "زبون عام" || customerInput.isEmpty) return;

    try {
      DocumentReference debtRef;
      String debtId;

      if (selectedId != null && selectedId.isNotEmpty) {
        debtId = selectedId;
        debtRef = FirebaseFirestore.instance.collection('debts').doc(debtId);
      } else {
        final snap = await FirebaseFirestore.instance
            .collection('debts')
            .where('parentId', isEqualTo: managerId)
            .where('cafeId', isEqualTo: cafeId)
            .get();

        QueryDocumentSnapshot? existingDoc;
        for (var doc in snap.docs) {
          if ((doc.data() as Map)['customer'].toString().trim().toLowerCase() ==
              customerInput.trim().toLowerCase()) {
            existingDoc = doc;
            break;
          }
        }

        if (existingDoc != null) {
          debtId = existingDoc.id;
          debtRef = existingDoc.reference;
        } else {
          final countSnap = await FirebaseFirestore.instance
              .collection('debts')
              .where('parentId', isEqualTo: managerId)
              .count()
              .get();

          debtRef = FirebaseFirestore.instance.collection('debts').doc();
          debtId = debtRef.id;
          await debtRef.set({
            'cafeId': cafeId,
            'parentId': managerId,
            'customer': customerInput,
            'totalDebt': 0.0,
            'totalPaid': 0.0,
            'initialBalance': 0.0,
            'remainingAmount': 0.0,
            'date': customDate ?? FieldValue.serverTimestamp(),
            'lastUpdate': FieldValue.serverTimestamp(),
            'debtNo': (countSnap.count ?? 0) + 1001,
            'phone': phone,
          });
        }
      }

      double diff = amount - (oldAmount ?? 0.0);

      await debtRef.update({
        isAddingDebt ? 'totalDebt' : 'totalPaid': FieldValue.increment(diff),
        'remainingAmount': FieldValue.increment(isAddingDebt ? diff : -diff),
        'lastUpdate': FieldValue.serverTimestamp(),
        if (phone.isNotEmpty) 'phone': phone,
      });

      await FirebaseFirestore.instance.collection('debt_transactions').add({
        'debtId': debtId,
        'customerName': customerInput,
        'type': oldAmount != null ? "تعديل $type" : type,
        'amount': diff,
        'date': customDate ?? FieldValue.serverTimestamp(),
        'cafeId': cafeId,
        'parentId': managerId,
        'processedBy': currentUser.name ?? "غير معروف",
        'userId': currentUser.id,
        'note': note
      });
    } catch (e) {
      debugPrint("Sync Error: $e");
    }
  }

  static Future<void> performSave({
    required BuildContext context,
    DocumentSnapshot? editDoc,
    required User currentUser,
    required String customerName,
    String? payerName,
    required String phone,
    required double amt,
    required String method,
    required String cafeId,
    bool isDebtPayment = false,
    String? selectedDebtId,
    double? oldAmount,
    DateTime? customDate,
    List items = const [],
    String table = 'حوالة يدوية',
    String? note,
    String? proofImageUrl,
    bool skipSync = false,
    bool skipPaymentRecord = false,
  }) async {
    final String managerId = currentUser.parentId ?? currentUser.id;
    final bool isUpdate = editDoc != null;
    final DateTime now = customDate ?? DateTime.now();

    bool shouldSaveToPayments = !method.contains("دين") && !method.contains("ديون");
    if (isDebtPayment) shouldSaveToPayments = true; 

    final batch = FirebaseFirestore.instance.batch();

    final data = {
      'customer_name': customerName,
      'payer_name': payerName,
      'customer_phone': phone,
      'total_amount': amt,
      'payment_method': method,
      'processed_by': currentUser.name ?? "غير معروف",
      'userId': currentUser.id,
      'is_received': isUpdate
          ? (editDoc.data() as Map)['is_received'] ?? false
          : (method.contains("كاش") || method.contains("نقدي")),
      'is_debt_payment': isDebtPayment,
      'is_pending': isUpdate ? ((editDoc.data() as Map)['is_pending'] ?? false) : false,
      'cafeId': cafeId,
      'parentId': managerId,
      'paid_at': customDate ?? FieldValue.serverTimestamp(),
      'day': now.day,
      'month': now.month,
      'year': now.year,
      'items': items,
      'table': table,
      'note': note,
      'proof_url': proofImageUrl,
    };

    // 1. تحديث رصيد الخزينة (زيادة عند البيع أو سداد الديون)
    if (!isUpdate && shouldSaveToPayments && amt > 0) {
      await AccountService.updateBalance(
        cafeId: cafeId, 
        method: method, 
        amount: amt, 
        batch: batch
      );
    }

    if (!isUpdate && !skipPaymentRecord && shouldSaveToPayments) {
      final newDocRef = FirebaseFirestore.instance.collection('payments').doc();
      batch.set(newDocRef, data);
    } else if (isUpdate) {
      batch.update(editDoc.reference, data);
    }

    await batch.commit();

    if (!skipSync && (isDebtPayment || method.contains("دين") || method.contains("ديون"))) {
      await syncWithDebts(
        currentUser: currentUser,
        customerInput: customerName,
        phone: phone,
        amount: amt,
        cafeId: cafeId,
        selectedId: selectedDebtId,
        oldAmount: oldAmount,
        isAddingDebt: (method.contains("دين") || method.contains("ديون")) && !isDebtPayment,
        type: isDebtPayment ? "سداد دين (حوالة)" : "طلب (دين)",
        customDate: customDate,
        note: note
      ).catchError((e) => debugPrint("Background Debt Sync: $e"));
    }

    await ActivityLogger.log(
      cafeId: cafeId,
      parentId: managerId,
      userId: currentUser.id,
      userName: currentUser.name,
      action: isDebtPayment ? "ديون - سداد" : (isUpdate ? "حوالات - تعديل" : "مبيعات - حوالة"),
      details: "${isUpdate ? 'تعديل' : 'تسجيل'} عملية بقيمة $amt ₪ ($method) للزبون $customerName ${payerName != null ? 'بواسطة $payerName' : ''}",
    );
  }

  static Future<void> deleteTransfer({
    required DocumentSnapshot doc,
    required User currentUser,
    String? activeCafeId,
  }) async {
    final data = doc.data() as Map;
    final String cafeId = data['cafeId'] ?? activeCafeId ?? "";
    final String managerId = currentUser.parentId ?? currentUser.id;
    final String method = data['payment_method'] ?? "كاش";
    final double amount = (data['total_amount'] ?? 0).toDouble();

    final batch = FirebaseFirestore.instance.batch();

    // عكس رصيد الخزينة عند الحذف (خصم)
    if (amount > 0 && !method.contains("دين")) {
      await AccountService.updateBalance(
        cafeId: cafeId, 
        method: method, 
        amount: -amount, 
        batch: batch
      );
    }

    if ((data['is_received'] == true || data['is_debt_payment'] == true || data['payment_method'].toString().contains("دين")) &&
        data['customer_name'] != "زبون عام" && (data['is_pending'] != true)) {
      await syncWithDebts(
        currentUser: currentUser,
        customerInput: data['customer_name'] ?? "",
        phone: data['customer_phone'] ?? "",
        amount: 0,
        oldAmount: amount,
        cafeId: cafeId,
        isAddingDebt: data['payment_method'].toString().contains("دين") && data['is_debt_payment'] != true,
        type: "حذف عملية",
      ).catchError((e) => debugPrint("Background Revert Sync: $e"));
    }

    await ActivityLogger.log(
      cafeId: cafeId,
      parentId: managerId,
      userId: currentUser.id,
      userName: currentUser.name,
      action: "حوالات - حذف",
      details: "حذف عملية بقيمة $amount ₪ للزبون ${data['customer_name']}",
    );

    batch.delete(doc.reference);
    await batch.commit();
  }
}
