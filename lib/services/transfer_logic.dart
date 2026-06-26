import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../pages/user_model.dart';

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

  /// الحصول على إعدادات المقهى (العملة وطرق الدفع)
  Stream<DocumentSnapshot> getCafeSettingsStream() {
    return FirebaseFirestore.instance
        .collection('cafes')
        .doc(cafeId)
        .snapshots();
  }

  /// الحصول على قائمة الزبائن الحاليين (للإكمال التلقائي)
  Stream<List<Map<String, String>>> getExistingCustomersStream() {
    return FirebaseFirestore.instance
        .collection('debts')
        .where('cafeId', isEqualTo: cafeId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return {
                'name': data['customer']?.toString() ?? "",
                'phone': data['phone']?.toString() ?? "",
              };
            }).toList());
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

    final int? inputNo = int.tryParse(customerInput);
    try {
      final allDebts = await FirebaseFirestore.instance
          .collection('debts')
          .where('cafeId', isEqualTo: cafeId)
          .where('parentId', isEqualTo: managerId)
          .get();

      DocumentReference? existingRef;
      String actualName = customerInput;
      for (var doc in allDebts.docs) {
        final data = doc.data();
        if (inputNo != null && data['debtNo'] == inputNo) {
          existingRef = doc.reference;
          actualName = data['customer'];
          break;
        } else if (data['customer']?.toString().toLowerCase() ==
            customerInput.toLowerCase()) {
          existingRef = doc.reference;
          actualName = data['customer'];
          break;
        }
      }

      String debtDocId;
      if (existingRef != null) {
        debtDocId = existingRef.id;
        await existingRef.update({
          'totalDebt': FieldValue.increment(amount),
          'remainingAmount': FieldValue.increment(amount),
          'lastUpdate': FieldValue.serverTimestamp(),
          if (phone.isNotEmpty) 'phone': phone,
        });
      } else {
        if (inputNo != null || amount < 0) return;
        final newDoc = await FirebaseFirestore.instance.collection('debts').add({
          'cafeId': cafeId,
          'parentId': managerId,
          'customer': customerInput,
          'totalDebt': amount,
          'totalPaid': 0.0,
          'remainingAmount': amount,
          'date': FieldValue.serverTimestamp(),
          'lastUpdate': FieldValue.serverTimestamp(),
          'debtNo': allDebts.size + 1001,
          'phone': phone,
        });
        debtDocId = newDoc.id;
      }
      await FirebaseFirestore.instance.collection('debt_transactions').add({
        'debtId': debtDocId,
        'customerName': actualName,
        'type': type,
        'amount': amount,
        'date': FieldValue.serverTimestamp(),
        'cafeId': cafeId,
        'parentId': managerId,
        'processed_by': currentUser.name
      });
    } catch (e) {
      debugPrint("Debt Sync Error: $e");
    }
  }

  /// حذف حوالة
  Future<void> deleteTransfer(String docId, Map data) async {
    if (data['payment_method'].toString().contains("دين")) {
      await syncWithDebts(
        customerInput: data['customer_name'] ?? "",
        phone: "",
        amount: -(data['total_amount'] ?? 0).toDouble(),
        type: "حذف حوالة",
      );
    }
    await FirebaseFirestore.instance.collection('payments').doc(docId).delete();
  }

  /// إضافة حوالة جديدة
  Future<void> addManualTransfer({
    required String name,
    required String phone,
    required double amount,
    required String method,
  }) async {
    if (method.contains("دين")) {
      await syncWithDebts(
        customerInput: name,
        phone: phone,
        amount: amount,
      );
    }
    
    // الحوالات اليدوية تكون غير مستلمة تلقائياً إلا إذا كانت نقداً
    bool isReceived = method.contains("كاش") || method.contains("نقدي");

    await FirebaseFirestore.instance.collection('payments').add({
      'customer_name': name,
      'customer_phone': phone,
      'total_amount': amount,
      'payment_method': method,
      'paid_at': FieldValue.serverTimestamp(),
      'processed_by': currentUser.name,
      'cafeId': cafeId,
      'parentId': currentUser.parentId ?? currentUser.id,
      'is_received': isReceived,
      'items': [],
      'table': 'حوالة يدوية'
    });
  }

  /// تحديث حالة الوصول
  Future<void> updateReceivedStatus(String docId, bool status) async {
    await FirebaseFirestore.instance
        .collection('payments')
        .doc(docId)
        .update({'is_received': status});
  }

  /// تصدير البيانات إلى Excel (CSV)
  Future<String?> exportToCSV(List<QueryDocumentSnapshot> docs) async {
    if (docs.isEmpty) return null;
    String csv = '\uFEFFالاسم,الهاتف,المبلغ,الطريقة,التاريخ,الوقت,الموظف,الأصناف\n';
    for (var doc in docs) {
      final d = doc.data() as Map;
      final ts = d['paid_at'] as Timestamp?;
      final items = d['items'] as List? ?? [];
      final itemsStr = items.map((i) => "${i['quantity']}x ${i['name']}").join(" | ");
      csv += "${d['customer_name'] ?? "عام"},${d['customer_phone'] ?? ""},${d['total_amount']},${d['payment_method']},${ts != null ? DateFormat('yyyy/MM/dd').format(ts.toDate()) : "--"},${ts != null ? DateFormat('hh:mm a').format(ts.toDate()) : "--"},${d['processed_by'] ?? "--"},\"$itemsStr\"\n";
    }

    if (kIsWeb) {
      await launchUrl(Uri.parse("data:text/csv;charset=utf-8,${Uri.encodeComponent(csv)}"));
      return "web";
    } else {
      final path = "${(await getExternalStorageDirectory())?.path}/Transfers_${DateTime.now().millisecondsSinceEpoch}.csv";
      await File(path).writeAsString(csv);
      return path;
    }
  }
}
