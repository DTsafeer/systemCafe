import 'package:flutter/material.dart';
import 'app_components.dart';

class SettingsDialogs {
  static void showEditSettingDialog({
    required BuildContext context,
    required String title,
    required String initialValue,
    required String hint,
    required IconData icon,
    bool isNumeric = false,
    required Function(String) onSave,
  }) {
    final ctrl = TextEditingController(text: initialValue);
    AppComponents.showAppDialog(
      context: context,
      title: title,
      content: TextField(
        controller: ctrl,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        decoration: AppComponents.fieldInput(hint, icon),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () {
            onSave(ctrl.text.trim());
            Navigator.pop(context);
          },
          child: const Text('حفظ'),
        )
      ],
    );
  }

  static void showPaymentMethodsDialog({
    required BuildContext context,
    required List<String> currentMethods,
    required Function(List<String>) onSave,
  }) {
    List<String> methods = List.from(currentMethods);
    final ctrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text("إدارة طرق الدفع"),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: TextField(controller: ctrl, decoration: const InputDecoration(hintText: "مثلاً: تحويل بنكي"))),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.green),
                        onPressed: () {
                          if (ctrl.text.isNotEmpty) {
                            setS(() => methods.add(ctrl.text.trim()));
                            ctrl.clear();
                          }
                        },
                      )
                    ],
                  ),
                  const Divider(),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: methods.length,
                      itemBuilder: (context, i) => ListTile(
                        title: Text(methods[i]),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => setS(() => methods.removeAt(i)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
              ElevatedButton(
                onPressed: () {
                  onSave(methods);
                  Navigator.pop(context);
                },
                child: const Text("حفظ التغييرات"),
              )
            ],
          ),
        ),
      ),
    );
  }

  static void showClearDataDialog({
    required BuildContext context,
    required Function(Map<String, bool>) onConfirm,
  }) {
    final Map<String, String> collections = {
      'orders': 'طلبات المطبخ',
      'logs': 'سجل النشاطات والحوالات',
      'payments': 'المبيعات والتقارير المالية',
      'expenses': 'المصاريف',
      'inventory': 'المخزون',
      'debts': 'الديون والعملاء',
    };
    Map<String, bool> selection = {for (var key in collections.keys) key: false};

    AppComponents.showAppDialog(
      context: context,
      title: 'تنظيف بيانات الكافيه',
      content: StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: collections.entries.map((e) => CheckboxListTile(
            title: Text(e.value),
            value: selection[e.key],
            activeColor: Colors.red,
            onChanged: (val) => setDialogState(() => selection[e.key] = val ?? false),
          )).toList(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () {
            if (selection.values.contains(true)) {
              Navigator.pop(context);
              onConfirm(selection);
            }
          },
          child: const Text('مسح البيانات المحددة'),
        ),
      ],
    );
  }

  static void showConfirmFinalDelete({
    required BuildContext context,
    required VoidCallback onConfirmed,
  }) {
    AppComponents.showAppDialog(
      context: context,
      title: 'تأكيد الحذف النهائي',
      content: const Text('هل أنت متأكد؟ لا يمكن التراجع عن هذه العملية وسيتم حذف السجلات للأبد.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('تراجع')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () {
            Navigator.pop(context);
            onConfirmed();
          },
          child: const Text('تأكيد الحذف'),
        )
      ],
    );
  }
}
