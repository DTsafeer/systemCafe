import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui' as ui;

class ExpenseDialogs {
  static void showAddExpenseDialog({
    required BuildContext context,
    required String cafeId,
    required String managerId,
    required String userName,
  }) {
    final titleCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    String category = "أخرى";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            title: const Text("مصروف جديد"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "البيان")),
                TextField(controller: amtCtrl, decoration: const InputDecoration(labelText: "المبلغ"), keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                DropdownButton<String>(
                  value: category,
                  isExpanded: true,
                  items: ["رواتب", "إيجار", "كهرباء", "مياه", "إنترنت", "صيانة", "مواد تنظيف", "أخرى"]
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => category = v!),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ElevatedButton(
                onPressed: () {
                  final amt = double.tryParse(amtCtrl.text) ?? 0.0;
                  if (titleCtrl.text.isNotEmpty && amt > 0) {
                    FirebaseFirestore.instance.collection('expenses').add({
                      'cafeId': cafeId,
                      'parentId': managerId,
                      'title': titleCtrl.text.trim(),
                      'amount': amt,
                      'category': category,
                      'date': FieldValue.serverTimestamp(),
                      'processedBy': userName,
                    });
                    Navigator.pop(ctx);
                  }
                },
                child: const Text("حفظ"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void showDeleteExpenseDialog({
    required BuildContext context,
    required String id,
    required String title,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text("حذف"),
          content: Text("حذف $title؟"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
            TextButton(
              onPressed: () {
                FirebaseFirestore.instance.collection('expenses').doc(id).delete();
                Navigator.pop(ctx);
              },
              child: const Text("حذف", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}
