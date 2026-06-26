import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'app_components.dart';
import '../pages/user_model.dart';

class DebtDialogs {
  static void showAddDebtDialog({
    required BuildContext context,
    required User currentUser,
    required String managerId,
  }) {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final balanceCtrl = TextEditingController();
    final limitCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    AppComponents.showAppDialog(
      context: context,
      title: "إضافة حساب جديد",
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: AppComponents.fieldInput("اسم الزبون", Icons.person)),
            const SizedBox(height: 10),
            TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: AppComponents.fieldInput("رقم الهاتف", Icons.phone)),
            const SizedBox(height: 10),
            TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("مبلغ الدين الحالي", Icons.money_off)),
            const SizedBox(height: 10),
            TextField(controller: balanceCtrl, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("رصيد سابق له", Icons.wallet)),
            const SizedBox(height: 10),
            TextField(controller: limitCtrl, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("سقف الدين (الحد)", Icons.warning_amber_rounded)),
            const SizedBox(height: 10),
            TextField(controller: noteCtrl, decoration: AppComponents.fieldInput("ملاحظات", Icons.note_add_outlined)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
        ElevatedButton(
          onPressed: () async {
            final name = nameCtrl.text.trim();
            if (name.isNotEmpty) {
              final double amt = double.tryParse(amountCtrl.text) ?? 0.0;
              final double bal = double.tryParse(balanceCtrl.text) ?? 0.0;
              final double lim = double.tryParse(limitCtrl.text) ?? 0.0;
              final note = noteCtrl.text.trim();
              final docRef = FirebaseFirestore.instance.collection('debts').doc();
              await docRef.set({
                'cafeId': currentUser.cafeId,
                'parentId': managerId,
                'customer': name,
                'totalDebt': amt,
                'totalPaid': 0.0,
                'initialBalance': bal,
                'debtLimit': lim,
                'date': Timestamp.now(),
                'lastUpdate': Timestamp.now(),
                'phone': phoneCtrl.text.trim()
              });
              if (amt > 0) _logTx(currentUser, managerId, docRef.id, name, "دين ابتدائي", amt, note);
              if (bal > 0) _logTx(currentUser, managerId, docRef.id, name, "رصيد سابق", bal, "إيداع رصيد ابتدائي");
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: const Text("حفظ"),
        )
      ],
    );
  }

  static Future<void> _logTx(User user, String managerId, String docId, String name, String type, double amt, [String? note]) async {
    await FirebaseFirestore.instance.collection('debt_transactions').add({
      'debtId': docId,
      'customerName': name,
      'type': type,
      'amount': amt,
      'date': Timestamp.now(),
      'cafeId': user.cafeId,
      'parentId': managerId,
      'processedBy': user.name,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }

  static void showReportPopup(BuildContext context, String id, Map<String, dynamic> customerData) {
    AppComponents.showAppDialog(
      context: context,
      title: "كشف حساب: ${customerData['customer']}",
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('debt_transactions').where('debtId', isEqualTo: id).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data!.docs.toList()..sort((a, b) => (b['date'] as Timestamp).compareTo(a['date'] as Timestamp));
            return ListView.builder(
              shrinkWrap: true,
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final d = docs[i].data() as Map<String, dynamic>;
                bool isPay = d['type'].toString().contains("تسديد") || d['type'].toString().contains("سداد");
                final String? note = d['note'];
                return ListTile(
                  title: Text(d['type'] ?? ""),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(intl.DateFormat('yyyy/MM/dd hh:mm a').format((d['date'] as Timestamp).toDate())),
                      if (note != null && note.isNotEmpty)
                        Text(note, style: const TextStyle(color: Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  trailing: Text("${d['amount']} ₪", style: TextStyle(fontWeight: FontWeight.bold, color: isPay ? Colors.green : Colors.red)),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("إغلاق")),
      ],
    );
  }

  static void showManageOptions({
    required BuildContext context,
    required String id,
    required String name,
    required bool isPayment,
    required User currentUser,
    required String managerId,
  }) {
    final amtCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    AppComponents.showAppDialog(
      context: context,
      title: isPayment ? "تسديد لـ $name" : "إضافة دين لـ $name",
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("المبلغ", Icons.attach_money)),
          const SizedBox(height: 10),
          TextField(controller: noteCtrl, decoration: AppComponents.fieldInput("ملاحظات (اختياري)", Icons.note_add_outlined)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
        ElevatedButton(
          onPressed: () async {
            double amt = double.tryParse(amtCtrl.text) ?? 0.0;
            String note = noteCtrl.text.trim();
            if (amt > 0) {
              if (!isPayment) {
                // فحص سقف الدين
                final doc = await FirebaseFirestore.instance.collection('debts').doc(id).get();
                final data = doc.data();
                if (data != null) {
                  double currentDebt = (data['totalDebt'] ?? 0.0) - (data['totalPaid'] ?? 0.0) - (data['initialBalance'] ?? 0.0);
                  double limit = (data['debtLimit'] ?? 0.0).toDouble();
                  if (limit > 0 && (currentDebt + amt) > limit) {
                    bool? proceed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => Directionality(
                        textDirection: TextDirection.rtl,
                        child: AlertDialog(
                          title: const Text("تجاوز سقف الدين"),
                          content: Text("هذا الزبون سيتجاوز الحد المسموح به ($limit ₪). هل تريد الاستمرار؟"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("تراجع")),
                            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("نعم، استمر")),
                          ],
                        ),
                      ),
                    );
                    if (proceed != true) return;
                  }
                }
              }

              await FirebaseFirestore.instance.collection('debts').doc(id).update({
                isPayment ? 'totalPaid' : 'totalDebt': FieldValue.increment(amt),
                'lastUpdate': Timestamp.now()
              });
              await FirebaseFirestore.instance.collection('debt_transactions').add({
                'debtId': id,
                'customerName': name,
                'type': isPayment ? "تسديد" : "زيادة دين",
                'amount': amt,
                'date': Timestamp.now(),
                'cafeId': currentUser.cafeId,
                'parentId': managerId,
                'processedBy': currentUser.name,
                'note': note.isNotEmpty ? note : null
              });
            }
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text("تأكيد"),
        )
      ],
    );
  }

  static void showEditDialog(BuildContext context, String id, Map<String, dynamic> data) {
    final nC = TextEditingController(text: data['customer'] ?? '');
    final pC = TextEditingController(text: data['phone'] ?? '');
    final lC = TextEditingController(text: (data['debtLimit'] ?? 0).toString());
    AppComponents.showAppDialog(
      context: context,
      title: "تعديل البيانات",
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nC, decoration: AppComponents.fieldInput("الاسم", Icons.person)),
        const SizedBox(height: 10),
        TextField(controller: pC, decoration: AppComponents.fieldInput("الهاتف", Icons.phone)),
        const SizedBox(height: 10),
        TextField(controller: lC, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("سقف الدين", Icons.warning_amber_rounded)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
        ElevatedButton(
          onPressed: () async {
            final double lim = double.tryParse(lC.text) ?? 0.0;
            await FirebaseFirestore.instance.collection('debts').doc(id).update({
              'customer': nC.text.trim(), 
              'phone': pC.text.trim(),
              'debtLimit': lim,
            });
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text("تحديث"),
        )
      ],
    );
  }

  static void showDeleteDialog(BuildContext context, String id, String name) {
    AppComponents.showAppDialog(
      context: context,
      title: "تأكيد الحذف",
      content: Text("حذف حساب $name نهائياً؟"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
        ElevatedButton(
          onPressed: () async {
            await FirebaseFirestore.instance.collection('debts').doc(id).delete();
            if (context.mounted) Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text("حذف", style: TextStyle(color: Colors.white)),
        )
      ],
    );
  }
}
