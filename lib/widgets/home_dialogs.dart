import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/user_model.dart';
import '../services/transfer_service.dart';
import 'app_components.dart';

class HomeDialogs {
  static void showAddTableDialog({
    required BuildContext context,
    required User currentUser,
  }) {
    final nameController = TextEditingController();
    AppComponents.showAppDialog(
      context: context,
      title: "طاولة جديدة",
      content: TextField(
        controller: nameController,
        autofocus: true,
        textAlign: TextAlign.center,
        decoration: AppComponents.fieldInput("اسم الطاولة", Icons.edit_note),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("تراجع")),
        ElevatedButton(
          onPressed: () {
            if (nameController.text.trim().isEmpty) return;
            FirebaseFirestore.instance.collection('tables').add({
              'name': nameController.text.trim(),
              'cafe_id': currentUser.cafeId,
              'parentId': currentUser.parentId ?? currentUser.id,
              'is_open': false,
              'start_time': null,
              'accumulated_seconds': 0
            });
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          child: const Text("حفظ"),
        )
      ],
    );
  }

  static void showAddDebtDialog({
    required BuildContext context,
    required User currentUser,
    required List<Map<String, String>> existingCustomers,
  }) {
    final customerController = TextEditingController();
    final amountController = TextEditingController();
    final prevBalanceController = TextEditingController();
    final detailsController = TextEditingController();

    AppComponents.showAppDialog(
      context: context,
      title: "إضافة حساب / دين جديد",
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Autocomplete<String>(
              optionsBuilder: (v) => existingCustomers
                  .map((e) => e['name']!)
                  .where((s) => s.toLowerCase().contains(v.text.toLowerCase())),
              onSelected: (s) => customerController.text = s,
              fieldViewBuilder: (c, ctrl, node, submit) {
                ctrl.addListener(() => customerController.text = ctrl.text);
                return TextField(
                  controller: ctrl,
                  focusNode: node,
                  decoration: AppComponents.fieldInput("اسم الزبون", Icons.person_add_alt),
                );
              },
            ),
            const SizedBox(height: 15),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: AppComponents.fieldInput("مبلغ الدين الآن", Icons.money_off),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: detailsController,
              decoration: AppComponents.fieldInput("تفاصيل الدين", Icons.description_outlined),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: prevBalanceController,
              keyboardType: TextInputType.number,
              decoration: AppComponents.fieldInput("رصيد سابق (له)", Icons.wallet_outlined),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          onPressed: () {
            final String name = customerController.text.trim();
            if (name.isEmpty) return;

            final double amount = double.tryParse(amountController.text) ?? 0.0;
            final double credit = double.tryParse(prevBalanceController.text) ?? 0.0;
            String? existingId = existingCustomers
                .where((c) => c['name']!.toLowerCase() == name.toLowerCase())
                .firstOrNull?['id'];

            TransferService.syncWithDebts(
              currentUser: currentUser,
              customerInput: name,
              phone: '',
              amount: amount - credit,
              cafeId: currentUser.cafeId,
              selectedId: existingId,
              isAddingDebt: true,
              type: amount > credit ? "زيادة دين" : "رصيد سابق",
              note: detailsController.text.trim(),
            );
            Navigator.pop(context);
          },
          child: const Text("حفظ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  static void confirmDeleteTable({
    required BuildContext context,
    required Map<String, dynamic> table,
  }) {
    AppComponents.showAppDialog(
      context: context,
      title: "حذف طاولة",
      content: Text("هل أنت متأكد من حذف (${table['name']})؟"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () {
            FirebaseFirestore.instance.collection('tables').doc(table['id']).delete();
            Navigator.pop(context);
          },
          child: const Text("حذف الآن", style: TextStyle(color: Colors.white)),
        )
      ],
    );
  }
}
