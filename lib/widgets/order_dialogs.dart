import 'package:flutter/material.dart';
import 'app_components.dart';

class OrderDialogs {
  static double _parseAmount(String input) {
    String western = input.trim()
        .replaceAll('٠', '0').replaceAll('١', '1').replaceAll('٢', '2')
        .replaceAll('٣', '3').replaceAll('٤', '4').replaceAll('٥', '5')
        .replaceAll('٦', '6').replaceAll('٧', '7').replaceAll('٨', '8')
        .replaceAll('٩', '9');
    return double.tryParse(western) ?? 0.0;
  }

  static void showWeightInputDialog({
    required BuildContext context,
    required String id,
    required Map<String, dynamic> data,
    required Function(String, Map<String, dynamic>, double) onConfirm,
  }) {
    final ctrl = TextEditingController();
    AppComponents.showAppDialog(
      context: context,
      title: "إدخل وزن: ${data['name']}",
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        decoration: const InputDecoration(hintText: "0.0", suffixText: "كجم"),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
        ElevatedButton(
          onPressed: () {
            double weight = _parseAmount(ctrl.text);
            if (weight > 0) {
              Navigator.pop(context);
              onConfirm(id, data, weight);
            }
          },
          child: const Text("إضافة"),
        ),
      ],
    );
  }

  static void showEntryDialog({
    required BuildContext context,
    required String id,
    required Map<String, dynamic> data,
    bool isEdit = false,
    required Function(String, Map<String, dynamic>, double, double) onConfirm,
  }) {
    final pController = TextEditingController(
      text: isEdit ? data['price'].toString() : (data['price'] == 0 ? "" : data['price'].toString()),
    );
    double tempQty = isEdit ? (double.tryParse(data['quantity'].toString()) ?? 1.0) : 1.0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.blue[900]!, Colors.blue[700]!]),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.calculate_rounded, color: Colors.white, size: 30),
                      const SizedBox(height: 5),
                      Text(
                        isEdit ? "تعديل الصنف" : "إضافة صنف يدوي",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        data['name'],
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      TextField(
                        controller: pController,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.green),
                        decoration: const InputDecoration(suffixText: "₪", border: InputBorder.none),
                      ),
                      const Divider(),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton.filled(
                            onPressed: () => setDialogState(() {
                              if (tempQty > 0.1) tempQty -= (tempQty > 1 ? 1 : 0.1);
                            }),
                            icon: const Icon(Icons.remove),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 15),
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15)),
                            child: Text(
                              tempQty.toStringAsFixed(tempQty == tempQty.toInt() ? 0 : 2),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton.filled(
                            onPressed: () => setDialogState(() => tempQty += (tempQty >= 1 ? 1 : 0.1)),
                            icon: const Icon(Icons.add),
                          )
                        ],
                      ),
                      const SizedBox(height: 25),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text("إلغاء", style: TextStyle(color: Colors.red)),
                            ),
                          ),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[900],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () {
                                double p = _parseAmount(pController.text);
                                if (p >= 0) {
                                  onConfirm(id, data, tempQty, p);
                                  Navigator.pop(ctx);
                                }
                              },
                              child: const Text("تأكيد"),
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void showCustomItemDialog({
    required BuildContext context,
    required Function(String, double) onConfirm,
  }) {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.orange[800]!, Colors.orange[600]!]),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.edit_note_rounded, color: Colors.white, size: 35),
                    SizedBox(height: 10),
                    Text("طلب خارج المنيو", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    TextField(
                      controller: nameCtrl,
                      textAlign: TextAlign.right,
                      decoration: AppComponents.fieldInput("تفاصيل الطلب", Icons.description_outlined),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: priceCtrl,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green),
                      decoration: AppComponents.fieldInput("السعر", Icons.attach_money).copyWith(prefixText: "₪ "),
                    ),
                    const SizedBox(height: 25),
                    Row(
                      children: [
                        Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء", style: TextStyle(color: Colors.red)))),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange[800],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              double price = _parseAmount(priceCtrl.text);
                              String name = nameCtrl.text.trim();
                              if (name.isNotEmpty && price > 0) {
                                onConfirm(name, price);
                                Navigator.pop(ctx);
                              }
                            },
                            child: const Text("إضافة"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
