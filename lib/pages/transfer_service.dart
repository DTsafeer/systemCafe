import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'user_model.dart';

class TransferService {
  /// تحديث حساب الديون عند إضافة أو حذف حوالة
  static Future<void> syncWithDebts({
    required User currentUser,
    required String customerInput,
    required String phone,
    required double amount,
    required String cafeId,
    String type = "إضافة دين (حوالة)",
  }) async {
    final String managerId = currentUser.parentId ?? currentUser.id;
    if (cafeId.isEmpty || customerInput == "زبون عام") return;

    final int? inputNo = int.tryParse(customerInput);
    try {
      DocumentReference? existingRef;
      String actualName = customerInput;

      QuerySnapshot query;
      if (inputNo != null) {
        query = await FirebaseFirestore.instance
            .collection('debts')
            .where('cafeId', isEqualTo: cafeId)
            .where('parentId', isEqualTo: managerId)
            .where('debtNo', isEqualTo: inputNo)
            .limit(1)
            .get();
      } else {
        query = await FirebaseFirestore.instance
            .collection('debts')
            .where('cafeId', isEqualTo: cafeId)
            .where('parentId', isEqualTo: managerId)
            .where('customer', isEqualTo: customerInput)
            .limit(1)
            .get();
      }

      if (query.docs.isNotEmpty) {
        existingRef = query.docs.first.reference;
        actualName = query.docs.first.get('customer');
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
        final countSnap = await FirebaseFirestore.instance
            .collection('debts')
            .where('cafeId', isEqualTo: cafeId)
            .where('parentId', isEqualTo: managerId)
            .count()
            .get();

        final newDoc = await FirebaseFirestore.instance.collection('debts').add({
          'cafeId': cafeId,
          'parentId': managerId,
          'customer': customerInput,
          'totalDebt': amount,
          'totalPaid': 0.0,
          'remainingAmount': amount,
          'date': FieldValue.serverTimestamp(),
          'lastUpdate': FieldValue.serverTimestamp(),
          'debtNo': (countSnap.count ?? 0) + 1001,
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
        'processedBy': currentUser.name
      });
    } catch (e) {
      debugPrint("Error syncing debts: $e");
    }
  }

  static void showAddTransferDialog({
    required BuildContext context,
    required User currentUser,
    required List<String> paymentMethods,
    required String currencySymbol,
    required List<Map<String, String>> existingCustomers,
    required String cafeId,
    DocumentSnapshot? editDoc,
  }) {
    final d = editDoc?.data() as Map?;
    final nC = TextEditingController(text: d?['customer_name'] ?? ""),
        aC = TextEditingController(text: d?['total_amount']?.toString() ?? ""),
        pC = TextEditingController(text: d?['customer_phone'] ?? "");
    String method = d?['payment_method'] ?? (paymentMethods.isNotEmpty ? paymentMethods.first : "كاش");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Theme.of(context).primaryColor,
                        Theme.of(context).primaryColor.withOpacity(0.8)
                      ]),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.add_card_rounded, color: Colors.white, size: 28),
                      const SizedBox(width: 15),
                      Text(editDoc == null ? "إضافة حوالة يدوية" : "تعديل حوالة",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold))
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(25),
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(15)),
                          child: Autocomplete<Map<String, String>>(
                            displayStringForOption: (option) => option['name']!,
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              if (textEditingValue.text == '') {
                                return const Iterable<Map<String, String>>.empty();
                              }
                              return existingCustomers.where((option) => option['name']!
                                  .toLowerCase()
                                  .contains(textEditingValue.text.toLowerCase()));
                            },
                            onSelected: (selection) {
                              nC.text = selection['name']!;
                              pC.text = selection['phone']!;
                            },
                            fieldViewBuilder:
                                (context, controller, focusNode, onFieldSubmitted) {
                              if (nC.text.isNotEmpty && controller.text.isEmpty) {
                                controller.text = nC.text;
                              }
                              controller.addListener(() {
                                if (nC.text != controller.text) nC.text = controller.text;
                              });
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  hintText: "اسم الزبون أو رقم الحساب",
                                  prefixIcon:
                                      Icon(Icons.person_outline, color: Colors.blueGrey),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(15),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        _popupInput(pC, "رقم الهاتف (اختياري)", Icons.phone_android,
                            isPhone: true),
                        const SizedBox(height: 12),
                        _popupInput(
                            aC, "المبلغ ($currencySymbol)", Icons.monetization_on_outlined,
                            isNum: true),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<String>(
                          value: method,
                          items: paymentMethods
                              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                              .toList(),
                          onChanged: (v) => setStateDialog(() => method = v!),
                          decoration: InputDecoration(
                              labelText: "طريقة الدفع",
                              filled: true,
                              fillColor: Colors.blue[50],
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide.none)),
                        ),
                        const SizedBox(height: 30),
                        Row(
                          children: [
                            Expanded(
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(context).primaryColor,
                                        padding:
                                            const EdgeInsets.symmetric(vertical: 15),
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(15))),
                                    onPressed: () {
                                      if (nC.text.isEmpty || aC.text.isEmpty) return;
                                      final amt = double.tryParse(aC.text) ?? 0;
                                      final customerName = nC.text.trim();
                                      final phone = pC.text.trim();
                                      final currentMethod = method;

                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                              content: Text("⏳ جاري المعالجة..."),
                                              duration: Duration(seconds: 1)));

                                      _performBackgroundSave(
                                        editDoc: editDoc,
                                        currentUser: currentUser,
                                        customerName: customerName,
                                        phone: phone,
                                        amt: amt,
                                        method: currentMethod,
                                        cafeId: cafeId,
                                      ).then((_) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                                content: Text("✅ تم الحفظ بنجاح"),
                                                backgroundColor: Colors.green),
                                          );
                                        }
                                      });
                                    },
                                    child: Text(editDoc == null ? "حفظ الحوالة" : "تحديث",
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)))),
                            const SizedBox(width: 15),
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text("إلغاء")),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _performBackgroundSave({
    DocumentSnapshot? editDoc,
    required User currentUser,
    required String customerName,
    required String phone,
    required double amt,
    required String method,
    required String cafeId,
  }) async {
    try {
      if (editDoc != null) {
        final oldData = editDoc.data() as Map;
        if (oldData['payment_method'].toString().contains("دين")) {
          await syncWithDebts(
            currentUser: currentUser,
            customerInput: oldData['customer_name'] ?? "",
            phone: "",
            amount: -(oldData['total_amount'] ?? 0).toDouble(),
            cafeId: cafeId,
            type: "تعديل حوالة (عكس)",
          );
        }
        
        await editDoc.reference.update({
          'customer_name': customerName,
          'customer_phone': phone,
          'total_amount': amt,
          'payment_method': method,
          'last_edit_at': FieldValue.serverTimestamp(),
          'is_received': (editDoc.data() as Map)['is_received'] ?? false,
        });
      } else {
        await FirebaseFirestore.instance.collection('payments').add({
          'customer_name': customerName,
          'customer_phone': phone,
          'total_amount': amt,
          'payment_method': method,
          'paid_at': FieldValue.serverTimestamp(),
          'processed_by': currentUser.name,
          'cafeId': cafeId,
          'parentId': currentUser.parentId ?? currentUser.id,
          'is_received': false, // القيمة الافتراضية "غير واصل" (ساعة رملية)
          'items': [],
          'table': 'حوالة يدوية'
        });
      }

      if (method.contains("دين")) {
        await syncWithDebts(
          currentUser: currentUser,
          customerInput: customerName,
          phone: phone,
          amount: amt,
          cafeId: cafeId,
        );
      }
    } catch (e) {
      debugPrint("Background Save Error: $e");
    }
  }

  static Widget _popupInput(TextEditingController ctrl, String label, IconData icon,
      {bool isNum = false, bool isPhone = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNum
          ? const TextInputType.numberWithOptions(decimal: true)
          : (isPhone ? TextInputType.phone : TextInputType.text),
      decoration: InputDecoration(
          hintText: label,
          prefixIcon: Icon(icon, color: Colors.blueGrey),
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
    );
  }

  static Future<void> deleteTransfer({
    required String docId,
    required Map data,
    required User currentUser,
    required String activeCafeId,
  }) async {
    if (data['payment_method'].toString().contains("دين")) {
      await syncWithDebts(
        currentUser: currentUser,
        customerInput: data['customer_name'] ?? "",
        phone: "",
        amount: -(data['total_amount'] ?? 0).toDouble(),
        cafeId: activeCafeId,
        type: "حذف حوالة",
      );
    }
    await FirebaseFirestore.instance.collection('payments').doc(docId).delete();
  }
}
