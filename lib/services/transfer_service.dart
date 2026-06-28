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
    List items = const [],
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
        'note': note,
        'items': items, // حفظ المنتجات في سجل الديون
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
    bool? isPending,
  }) async {
    final String managerId = currentUser.parentId ?? currentUser.id;
    final bool isUpdate = editDoc != null;
    final DateTime now = customDate ?? DateTime.now();

    final Map? oldData = isUpdate ? editDoc.data() as Map : null;
    final bool oldIsPending = oldData?['is_pending'] ?? false;
    final bool newIsPending = isPending ?? oldIsPending;

    bool shouldSaveToPayments = !method.contains("دين") && !method.contains("ديون");
    if (isDebtPayment) shouldSaveToPayments = true; 

    final batch = FirebaseFirestore.instance.batch();

    if (shouldSaveToPayments) {
      if (isUpdate) {
        String oldMethod = oldData?['payment_method'] ?? "كاش";
        double oldAmtValue = (oldData?['total_amount'] ?? 0.0).toDouble();
        
        if (!oldIsPending && !newIsPending) {
          if (oldMethod == method) {
              double netDiff = amt - oldAmtValue;
              if (netDiff < 0) {
                 bool canDeduct = await AccountService.hasEnoughBalance(cafeId, method, netDiff.abs());
                 if (!canDeduct) throw Exception("عذراً، الرصيد في ($method) لا يسمح بتقليل المبلغ لهذه القيمة.");
              }
              await AccountService.updateBalance(cafeId: cafeId, method: method, amount: netDiff, batch: batch);
          } else {
              bool canDeductOld = await AccountService.hasEnoughBalance(cafeId, oldMethod, oldAmtValue);
              if (!canDeductOld) throw Exception("عذراً، لا يمكن تغيير طريقة الدفع لأن الرصيد في ($oldMethod) غير كافٍ لسحب المبلغ القديم.");
              
              await AccountService.updateBalance(cafeId: cafeId, method: oldMethod, amount: -oldAmtValue, batch: batch);
              await AccountService.updateBalance(cafeId: cafeId, method: method, amount: amt, batch: batch);
          }
        } else if (oldIsPending && !newIsPending) {
          // Confirming a pending transfer
          await AccountService.updateBalance(cafeId: cafeId, method: method, amount: amt, batch: batch);
        } else if (!oldIsPending && newIsPending) {
          // Moving a confirmed transfer back to pending
          bool canDeduct = await AccountService.hasEnoughBalance(cafeId, oldMethod, oldAmtValue);
          if (!canDeduct) throw Exception("عذراً، لا يمكن تعليق الحوالة لأن رصيد ($oldMethod) غير كافٍ لسحب المبلغ.");
          await AccountService.updateBalance(cafeId: cafeId, method: oldMethod, amount: -oldAmtValue, batch: batch);
        }
      } else if (amt > 0 && !newIsPending) {
        await AccountService.updateBalance(cafeId: cafeId, method: method, amount: amt, batch: batch);
      }
    }

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
      'is_pending': newIsPending,
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

    if (!isUpdate && !skipPaymentRecord && shouldSaveToPayments) {
      final newDocRef = FirebaseFirestore.instance.collection('payments').doc();
      batch.set(newDocRef, data);
    } else if (isUpdate) {
      batch.update(editDoc.reference, data);
    }

    await batch.commit();

    // Only sync with debts if NOT pending
    if (!newIsPending && !skipSync && (isDebtPayment || method.contains("دين") || method.contains("ديون"))) {
      await syncWithDebts(
        currentUser: currentUser,
        customerInput: customerName,
        phone: phone,
        amount: amt,
        cafeId: cafeId,
        selectedId: selectedDebtId,
        oldAmount: oldIsPending ? 0.0 : oldAmount, // If it was pending, old amount for debt sync is effectively 0
        isAddingDebt: (method.contains("دين") || method.contains("ديون")) && !isDebtPayment,
        type: isDebtPayment ? "سداد دين (حوالة)" : "طلب (دين)",
        customDate: customDate,
        note: note,
        items: items, // تمرير المنتجات لمزامنتها مع سجل الديون
      ).catchError((e) => debugPrint("Background Debt Sync: $e"));
    } else if (oldIsPending == false && newIsPending == true && !skipSync && (isDebtPayment || method.contains("دين"))) {
       // If it was confirmed and moved to pending, we must reverse the debt sync
       await syncWithDebts(
        currentUser: currentUser,
        customerInput: customerName,
        phone: phone,
        amount: 0.0,
        cafeId: cafeId,
        selectedId: selectedDebtId,
        oldAmount: oldAmount,
        isAddingDebt: false,
        type: "تعليق حوالة",
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
      details: "${isUpdate ? 'تعديل' : 'تسجيل'} عملية بقيمة $amt ₪ ($method) للزبون $customerName ${newIsPending ? '(معلقة)' : ''}",
    );
  }

  static Future<void> deleteTransfer({
    required DocumentSnapshot doc,
    required User currentUser,
    String? activeCafeId,
  }) async {
    final data = doc.data() as Map;
    final String cafeId = data['cafeId'] ?? activeCafeId ?? "";
    final String method = data['payment_method'] ?? "كاش";
    final double amount = (data['total_amount'] ?? 0).toDouble();
    final bool isPending = data['is_pending'] ?? false;

    final batch = FirebaseFirestore.instance.batch();

    if (amount > 0 && !method.contains("دين") && !isPending) {
      bool canDeduct = await AccountService.hasEnoughBalance(cafeId, method, amount);
      if (!canDeduct) throw Exception("عذراً، لا يمكن حذف هذه الحوالة لأن رصيد الخزينة ($method) أقل من مبلغها.");

      await AccountService.updateBalance(
        cafeId: cafeId, 
        method: method, 
        amount: -amount, 
        batch: batch
      );
    }

    if (!isPending && (data['is_received'] == true || data['is_debt_payment'] == true || data['payment_method'].toString().contains("دين")) &&
        data['customer_name'] != "زبون عام") {
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
      parentId: currentUser.parentId ?? currentUser.id,
      userId: currentUser.id,
      userName: currentUser.name,
      action: "حوالات - حذف",
      details: "حذف عملية بقيمة $amount ₪ للزبون ${data['customer_name']}",
    );

    batch.delete(doc.reference);
    await batch.commit();
  }
}
