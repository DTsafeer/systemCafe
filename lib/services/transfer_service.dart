import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../pages/user_model.dart';
import '../pages/activity_logger.dart';

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

  static Future<void> togglePendingStatus({
    required DocumentSnapshot doc,
    required User currentUser,
  }) async {
    final data = doc.data() as Map;
    final bool currentPending = data['is_pending'] ?? false;
    final bool isDebtRef = data['payment_method'].toString().contains("دين") || (data['is_debt_payment'] ?? false);
    final String customerName = data['customer_name'] ?? "";
    final double amount = (data['total_amount'] ?? 0.0).toDouble();
    final String cafeId = data['cafeId'] ?? "";

    // 1. تحديث حالة التعليق
    await doc.reference.update({'is_pending': !currentPending});

    // 2. إذا كانت مرتبطة بالديون، نقوم بتعديل الرصيد تلقائياً
    if (isDebtRef && customerName != "زبون عام") {
      // إذا كانت العملية ستصبح "معلقة" (كانت نشطة): نسحب المبلغ من رصيد المدفوعات (نزيد الدين)
      // إذا كانت العملية ستصبح "نشطة" (كانت معلقة): نعيد تسجيل الدفعة (نقلل الدين)
      await syncWithDebts(
        currentUser: currentUser,
        customerInput: customerName,
        phone: data['customer_phone'] ?? "",
        amount: currentPending ? amount : 0, // إذا كانت معلقة والآن نفعلها، نرسل المبلغ. إذا كانت نشطة ونعلقها، نرسل 0 مع oldAmount
        oldAmount: currentPending ? 0 : amount,
        cafeId: cafeId,
        isAddingDebt: false, // دائماً تعامل كدفعة (سداد) يتم عكسها أو تفعيلها
        type: currentPending ? "تفعيل حوالة معلقة" : "تعليق حوالة (مراجعة)",
        note: "تعديل تلقائي بسبب تغيير حالة الحوالة إلى ${currentPending ? 'نشطة' : 'معلقة'}",
      );
    }

    await ActivityLogger.log(
      cafeId: cafeId,
      parentId: currentUser.parentId ?? currentUser.id,
      userId: currentUser.id,
      userName: currentUser.name,
      action: "حوالات - تغيير حالة",
      details: "تحويل حالة حوالة الزبون $customerName بقيمة $amount إلى ${currentPending ? 'نشطة' : 'معلقة'}",
    );
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

    if (!isUpdate && !skipPaymentRecord && shouldSaveToPayments) {
      await FirebaseFirestore.instance.collection('payments').add(data);
    } else if (isUpdate) {
      await editDoc.reference.update(data);
    }

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

    if ((data['is_received'] == true || data['is_debt_payment'] == true || data['payment_method'].toString().contains("دين")) &&
        data['customer_name'] != "زبون عام" && (data['is_pending'] != true)) {
      await syncWithDebts(
        currentUser: currentUser,
        customerInput: data['customer_name'] ?? "",
        phone: data['customer_phone'] ?? "",
        amount: 0,
        oldAmount: (data['total_amount'] ?? 0).toDouble(),
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
      details: "حذف عملية بقيمة ${data['total_amount']} ₪ للزبون ${data['customer_name']}",
    );

    await doc.reference.delete();
  }
}
