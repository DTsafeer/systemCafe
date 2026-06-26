import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_components.dart';
import '../pages/user_model.dart';
import '../pages/activity_logger.dart';
import '../services/purchase_service.dart'; // استيراد خدمة المشتريات

class InventoryDialogs {
  static void showAddInventoryItem({
    required BuildContext context,
    required User currentUser,
  }) {
    _showInventoryDialog(context: context, currentUser: currentUser);
  }

  static void showEditInventoryItem({
    required BuildContext context,
    required DocumentReference ref,
    required Map data,
    required User currentUser,
  }) {
    _showInventoryDialog(context: context, currentUser: currentUser, ref: ref, data: data);
  }

  static void _showInventoryDialog({
    required BuildContext context,
    required User currentUser,
    DocumentReference? ref,
    Map? data,
  }) {
    final isEdit = ref != null;
    final nameCtrl = TextEditingController(text: data?['name'] ?? "");
    final qtyCtrl = TextEditingController(text: (data?['quantity'] ?? 0.0).toString());
    final unitCtrl = TextEditingController(text: data?['unit'] ?? "حبة");
    final barcodeCtrl = TextEditingController(text: data?['barcode'] ?? "");
    final costPriceCtrl = TextEditingController(text: (data?['costPrice'] ?? 0.0).toString());
    final boxPriceCtrl = TextEditingController(text: (data?['boxPrice'] ?? 0.0).toString());
    final boxQtyCtrl = TextEditingController(text: (data?['boxQty'] ?? 1.0).toString());
    final minStockCtrl = TextEditingController(text: (data?['low_stock_threshold'] ?? 5.0).toString());
    
    final totalAmountCtrl = TextEditingController(text: "0");
    final boxCountCtrl = TextEditingController(text: "0");
    final sellingPriceCtrl = TextEditingController(text: (data?['sellingPrice'] ?? 0.0).toString());
    final boxSellingPriceCtrl = TextEditingController(text: (data?['boxSellingPrice'] ?? 0.0).toString());

    final palletPriceCtrl = TextEditingController(text: (data?['palletPrice'] ?? 0.0).toString());
    final palletCountCtrl = TextEditingController(text: "0");
    final boxesPerPalletCtrl = TextEditingController(text: (data?['boxesPerPallet'] ?? 1.0).toString());
    final pieceInputCountCtrl = TextEditingController(text: "0");
    final pieceInputPriceCtrl = TextEditingController(text: "0");

    String purchaseMode = "كرتونة"; 
    final currentInventoryQty = data?['quantity'] ?? 0.0;

    final managerId = currentUser.parentId ?? currentUser.id;
    bool isLoading = false;

    void updateCalculations({String from = 'box'}) {
      double pPrice = double.tryParse(palletPriceCtrl.text) ?? 0;
      double pCount = double.tryParse(palletCountCtrl.text) ?? 0;
      double boxesPerPallet = double.tryParse(boxesPerPalletCtrl.text) ?? 1;

      double bPrice = double.tryParse(boxPriceCtrl.text) ?? 0;
      double boxes = double.tryParse(boxCountCtrl.text) ?? 0;
      double piecesPerBox = double.tryParse(boxQtyCtrl.text) ?? 1;
      
      double pieceInPrice = double.tryParse(pieceInputPriceCtrl.text) ?? 0;
      double pieceInCount = double.tryParse(pieceInputCountCtrl.text) ?? 0;

      double total = 0;
      double qtyToAdd = 0;

      if (purchaseMode == "مشطاح") {
        total = pPrice * pCount;
        qtyToAdd = pCount * boxesPerPallet * piecesPerBox;
      } else if (purchaseMode == "كرتونة") {
        total = bPrice * boxes;
        qtyToAdd = boxes * piecesPerBox;
      } else if (purchaseMode == "حبة") {
        total = pieceInPrice * pieceInCount;
        qtyToAdd = pieceInCount;
      }

      totalAmountCtrl.text = total.toStringAsFixed(2);
      
      // في حالة الإضافة، الكمية المعروضة هي الكمية الحالية + المضافة
      qtyCtrl.text = (currentInventoryQty + qtyToAdd).toStringAsFixed(1);
    }

    Widget _buildSectionTitle(String title, IconData icon, Color color) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(width: 10),
          const Expanded(child: Divider()),
        ],
      ),
    );

    Widget _buildFieldLabel(String label, IconData icon) => Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 15),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blueGrey[700]),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
        ],
      ),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          double costPerPiece = double.tryParse(costPriceCtrl.text) ?? 0;
          double sellPerPiece = double.tryParse(sellingPriceCtrl.text) ?? 0;
          double costPerBox = double.tryParse(boxPriceCtrl.text) ?? 0;
          double sellPerBox = double.tryParse(boxSellingPriceCtrl.text) ?? 0;

          double profitPerPiece = sellPerPiece > 0 ? sellPerPiece - costPerPiece : 0;
          double profitPerBox = sellPerBox > 0 ? sellPerBox - costPerBox : 0;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
              title: Container(
                padding: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.blue.shade100, width: 2))),
                child: Row(
                  children: [
                    CircleAvatar(backgroundColor: Colors.blue.shade50, child: Icon(isEdit ? Icons.edit : Icons.add_box, color: Colors.blue)),
                    const SizedBox(width: 15),
                    Text(isEdit ? "بيانات الصنف: ${data?['name']}" : "إضافة صنف جديد", 
                         style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                  ],
                ),
              ),
              content: SizedBox(
                width: 750,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSectionTitle("البيانات الأساسية", Icons.info_outline, Colors.blueGrey),
                      Row(
                        children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldLabel("اسم الصنف", Icons.label_important),
                              TextField(controller: nameCtrl, style: const TextStyle(fontSize: 18), decoration: AppComponents.fieldInput("اسم الصنف", Icons.inventory_2)),
                            ],
                          )),
                          const SizedBox(width: 15),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldLabel("باركود", Icons.qr_code),
                              TextField(controller: barcodeCtrl, style: const TextStyle(fontSize: 18), decoration: AppComponents.fieldInput("الباركود", Icons.qr_code_scanner)),
                            ],
                          )),
                        ],
                      ),

                      _buildSectionTitle("إعدادات العبوات والوحدات", Icons.settings_suggest, Colors.indigo),
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
                        child: Row(
                          children: [
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildFieldLabel("وحدة القياس", Icons.straighten),
                                TextField(controller: unitCtrl, decoration: AppComponents.fieldInput("حبة/كيلو/لتر", Icons.unfold_more)),
                              ],
                            )),
                            const SizedBox(width: 15),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildFieldLabel("حبة/وحدة في الكرتونة", Icons.grid_view),
                                TextField(controller: boxQtyCtrl, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("24 مثلاً", Icons.add_box), onChanged: (_) => setDialogState(() => updateCalculations())),
                              ],
                            )),
                            const SizedBox(width: 15),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildFieldLabel("كرتونة في المشطاح", Icons.layers),
                                TextField(controller: boxesPerPalletCtrl, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("50 مثلاً", Icons.view_quilt), onChanged: (_) => setDialogState(() => updateCalculations())),
                              ],
                            )),
                          ],
                        ),
                      ),

                      _buildSectionTitle("إضافة مخزون جديد (عبر المشتريات)", Icons.add_shopping_cart, Colors.blue),
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blue.shade100)),
                        child: Column(
                          children: [
                            ToggleButtons(
                              isSelected: [purchaseMode == "حبة", purchaseMode == "كرتونة", purchaseMode == "مشطاح"],
                              onPressed: (index) => setDialogState(() {
                                purchaseMode = ["حبة", "كرتونة", "مشطاح"][index];
                                updateCalculations();
                              }),
                              borderRadius: BorderRadius.circular(15),
                              selectedColor: Colors.white,
                              fillColor: Colors.blue,
                              constraints: BoxConstraints(minWidth: (700 / 3) - 20, minHeight: 45),
                              children: const [Text("بالحبة/كغم/لتر"), Text("بالكرتونة"), Text("بالمشطاح")],
                            ),
                            const SizedBox(height: 20),
                            if (purchaseMode == "مشطاح") ...[
                              Row(
                                children: [
                                  Expanded(child: _modernInput(palletPriceCtrl, "سعر المشطاح", Icons.money, isNum: true, onChanged: (_) => updateCalculations())),
                                  const SizedBox(width: 15),
                                  Expanded(child: _modernInput(palletCountCtrl, "عدد المشاطيح المضافة", Icons.numbers, isNum: true, onChanged: (_) => updateCalculations())),
                                ],
                              ),
                            ] else if (purchaseMode == "كرتونة") ...[
                              Row(
                                children: [
                                  Expanded(child: _modernInput(boxPriceCtrl, "سعر الكرتونة", Icons.grid_view, isNum: true, onChanged: (_) => updateCalculations())),
                                  const SizedBox(width: 15),
                                  Expanded(child: _modernInput(boxCountCtrl, "عدد الكراتين المضافة", Icons.numbers, isNum: true, onChanged: (_) => updateCalculations())),
                                ],
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(child: _modernInput(pieceInputPriceCtrl, "سعر الحبة/الوحدة", Icons.money, isNum: true, onChanged: (_) => updateCalculations())),
                                  const SizedBox(width: 15),
                                  Expanded(child: _modernInput(pieceInputCountCtrl, "عدد الحبات المضافة", Icons.numbers, isNum: true, onChanged: (_) => updateCalculations())),
                                ],
                              ),
                            ],
                            const SizedBox(height: 10),
                            _modernInput(totalAmountCtrl, "إجمالي تكلفة الإضافة (المشتريات)", Icons.payments, isReadOnly: true),
                          ],
                        ),
                      ),

                      _buildSectionTitle("التسعير والمربح", Icons.monetization_on, Colors.green),
                      Row(
                        children: [
                          Expanded(child: _modernInput(boxSellingPriceCtrl, "سعر بيع الكرتونة", Icons.shopping_basket, isNum: true, color: Colors.green)),
                          const SizedBox(width: 15),
                          Expanded(child: _modernInput(sellingPriceCtrl, "سعر بيع الحبة/الوحدة", Icons.sell, isNum: true, color: Colors.green)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          _profitBox("مربح الكرتونة", profitPerBox, sellPerBox > 0),
                          const SizedBox(width: 15),
                          _profitBox("مربح الحبة", profitPerPiece, sellPerPiece > 0),
                        ],
                      ),

                      _buildSectionTitle("حالة المخزون (تحديث تلقائي)", Icons.analytics, Colors.orange),
                      Row(
                        children: [
                          Expanded(child: _modernInput(qtyCtrl, "الكمية الكلية المتوفرة", Icons.format_list_numbered, isReadOnly: true)),
                          const SizedBox(width: 15),
                          Expanded(child: _modernInput(minStockCtrl, "تنبيه النقص عند", Icons.warning_amber_rounded, isNum: true)),
                        ],
                      ),
                      const SizedBox(height: 30),
                      if (isLoading) const Center(child: CircularProgressIndicator()),
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
              actions: [
                TextButton(onPressed: isLoading ? null : () => Navigator.pop(ctx), child: const Text("إلغاء", style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), elevation: 5),
                  onPressed: isLoading ? null : () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    setDialogState(() => isLoading = true);
                    try {
                      final mapData = {
                        'name': nameCtrl.text.trim(),
                        'unit': unitCtrl.text.trim(),
                        'barcode': barcodeCtrl.text.trim(),
                        'boxQty': double.tryParse(boxQtyCtrl.text) ?? 1.0,
                        'sellingPrice': double.tryParse(sellingPriceCtrl.text) ?? 0.0,
                        'boxSellingPrice': double.tryParse(boxSellingPriceCtrl.text) ?? 0.0,
                        'low_stock_threshold': double.tryParse(minStockCtrl.text) ?? 5.0,
                        'boxesPerPallet': double.tryParse(boxesPerPalletCtrl.text) ?? 1.0,
                        'cafeId': currentUser.cafeId,
                        'parentId': managerId,
                      };

                      DocumentReference itemRef;
                      if (isEdit) {
                        itemRef = ref;
                        await itemRef.update(mapData);
                      } else {
                        mapData['quantity'] = 0.0;
                        mapData['costPrice'] = 0.0;
                        final newDoc = await FirebaseFirestore.instance.collection('inventory').add(mapData);
                        itemRef = newDoc;
                      }

                      // تسجيل المشتريات إذا تم إدخال كمية
                      double amount = double.tryParse(totalAmountCtrl.text) ?? 0;
                      double qtyToAdd = (double.tryParse(qtyCtrl.text) ?? 0) - currentInventoryQty;

                      if (qtyToAdd > 0) {
                        await PurchaseService.savePurchase(
                          currentUser: currentUser,
                          cafeId: currentUser.cafeId,
                          managerId: managerId,
                          amount: amount,
                          productName: nameCtrl.text.trim(),
                          qty: qtyToAdd,
                          note: "إضافة مخزون عبر شاشة إدارة الأصناف",
                          prodId: itemRef.id,
                          method: "كاش",
                        );
                      }

                      ActivityLogger.log(cafeId: currentUser.cafeId, parentId: managerId, userId: currentUser.id, userName: currentUser.name, action: isEdit ? "مخزن - تعديل" : "مخزن - إضافة", details: "${isEdit ? 'تعديل' : 'إضافة'} صنف: ${nameCtrl.text}");

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? "✅ تم التحديث بنجاح" : "✅ تم الحفظ والإضافة للمخزن")));
                      }
                    } catch (e) {
                      setDialogState(() => isLoading = false);
                      if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
                    }
                  }, 
                  child: Text(isEdit ? "حفظ التغييرات" : "تأكيد الإضافة", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static Widget _modernInput(TextEditingController ctrl, String label, IconData icon, {bool isNum = false, bool isReadOnly = false, Color? color, Function(String)? onChanged}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 5, right: 5),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ),
      TextField(
        controller: ctrl,
        readOnly: isReadOnly,
        onChanged: onChanged,
        keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        decoration: AppComponents.fieldInput("", icon, iconColor: color),
      ),
    ],
  );

  static Widget _profitBox(String label, double profit, bool hasSellingPrice) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: hasSellingPrice ? (profit >= 0 ? Colors.green.shade50 : Colors.red.shade50) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: hasSellingPrice ? (profit >= 0 ? Colors.green.shade200 : Colors.red.shade200) : Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(hasSellingPrice ? "${profit.toStringAsFixed(2)} ₪" : "---", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: hasSellingPrice ? (profit >= 0 ? Colors.green.shade900 : Colors.red.shade900) : Colors.grey)),
          ],
        ),
      ),
    );
  }

  static void showConfirmDelete({
    required BuildContext context,
    required DocumentReference ref,
    required String name,
    required User currentUser,
  }) {
    final managerId = currentUser.parentId ?? currentUser.id;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text("حذف صنف"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("هل أنت متأكد من حذف ($name) نهائياً؟"),
                if (isLoading) const Padding(padding: EdgeInsets.only(top: 15), child: CircularProgressIndicator()),
              ],
            ),
            actions: [
              TextButton(onPressed: isLoading ? null : () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red), 
                onPressed: isLoading ? null : () async { 
                  setDialogState(() => isLoading = true);
                  try {
                    await ref.delete(); 
                    ActivityLogger.log(cafeId: currentUser.cafeId, parentId: managerId, userId: currentUser.id, userName: currentUser.name, action: "مخزن - حذف", details: "حذف الصنف: $name نهائياً");
                    if (ctx.mounted) {
                      Navigator.pop(ctx); 
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم الحذف بنجاح")));
                    }
                  } catch (e) {
                    setDialogState(() => isLoading = false);
                    if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
                  }
                }, 
                child: const Text("حذف الآن", style: TextStyle(color: Colors.white))
              ),
            ],
          ),
        ),
      ),
    );
  }
}
