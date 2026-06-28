import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_components.dart';
import '../pages/user_model.dart';
import '../pages/activity_logger.dart';
import '../services/purchase_service.dart';
import '../pages/addproduct.dart';

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
    
    final lastCostPrice = (data?['lastCostPrice'] ?? data?['costPrice'] ?? 0.0).toDouble();
    
    final boxQtyCtrl = TextEditingController(text: (data?['boxQty'] ?? 1.0).toString());
    final minStockCtrl = TextEditingController(text: (data?['low_stock_threshold'] ?? 5.0).toString());
    
    final sellingPriceCtrl = TextEditingController(text: (data?['sellingPrice'] ?? 0.0).toString());
    final boxSellingPriceCtrl = TextEditingController(text: (data?['boxSellingPrice'] ?? 0.0).toString());

    final totalAmountCtrl = TextEditingController(text: "0");
    final boxCountCtrl = TextEditingController(text: "0");
    final boxPriceCtrl = TextEditingController(text: "0");
    final palletPriceCtrl = TextEditingController(text: "0");
    final palletCountCtrl = TextEditingController(text: "0");
    final boxesPerPalletCtrl = TextEditingController(text: (data?['boxesPerPallet'] ?? 1.0).toString());
    final pieceInputCountCtrl = TextEditingController(text: "0");
    final pieceInputPriceCtrl = TextEditingController(text: "0");

    String purchaseMode = "حبة"; 
    final currentInventoryQty = (data?['quantity'] ?? 0.0).toDouble();
    final managerId = currentUser.parentId ?? currentUser.id;
    bool isLoading = false;

    void updateCalculations() {
      double pPrice = double.tryParse(palletPriceCtrl.text) ?? 0;
      double pCount = double.tryParse(palletCountCtrl.text) ?? 0;
      double bpp = double.tryParse(boxesPerPalletCtrl.text) ?? 1;
      double bPrice = double.tryParse(boxPriceCtrl.text) ?? 0;
      double bCount = double.tryParse(boxCountCtrl.text) ?? 0;
      double ppb = double.tryParse(boxQtyCtrl.text) ?? 1;
      double piPrice = double.tryParse(pieceInputPriceCtrl.text) ?? 0;
      double piCount = double.tryParse(pieceInputCountCtrl.text) ?? 0;

      double total = 0;
      double qtyToAdd = 0;

      if (purchaseMode == "مشطاح") {
        total = pPrice * pCount;
        qtyToAdd = pCount * bpp * ppb;
      } else if (purchaseMode == "كرتونة") {
        total = bPrice * bCount;
        qtyToAdd = bCount * ppb;
      } else {
        total = piPrice * piCount;
        qtyToAdd = piCount;
      }

      totalAmountCtrl.text = total.toStringAsFixed(2);
      qtyCtrl.text = (currentInventoryQty + qtyToAdd).toStringAsFixed(1);
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          double currentSellPrice = double.tryParse(sellingPriceCtrl.text) ?? 0;
          double currentProfit = currentSellPrice - lastCostPrice;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              title: Row(
                children: [
                  Icon(isEdit ? Icons.inventory_2 : Icons.add_business, color: isEdit ? Colors.blueGrey : Colors.blue),
                  const SizedBox(width: 10),
                  Text(isEdit ? "تفاصيل الصنف: ${data?['name']}" : "إضافة صنف جديد"),
                ],
              ),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSectionTitle("البيانات الأساسية", Icons.info, Colors.blueGrey),
                      Row(
                        children: [
                          Expanded(child: TextField(
                            controller: nameCtrl, 
                            readOnly: isEdit, 
                            decoration: AppComponents.fieldInput("اسم الصنف", isEdit ? Icons.lock_outline : Icons.label)
                          )),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: barcodeCtrl, 
                              readOnly: true, // الباركود للقراءة فقط هنا
                              decoration: AppComponents.fieldInput("الباركود (للعرض فقط)", Icons.qr_code).copyWith(
                                helperText: "يعدل من صفحة المنتج فقط",
                                suffixIcon: isEdit ? IconButton(
                                  icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => AddProduct(
                                      currentUser: currentUser,
                                      productToEdit: {'id': ref.id, ...data!},
                                    )));
                                  },
                                ) : null,
                              )
                            )
                          ),
                        ],
                      ),

                      if (!isEdit) ...[
                        _buildSectionTitle("إعدادات العبوات والوحدات", Icons.settings, Colors.indigo),
                        Row(
                          children: [
                            Expanded(child: TextField(controller: unitCtrl, decoration: AppComponents.fieldInput("الوحدة (حبة/لتر)", Icons.straighten))),
                            const SizedBox(width: 10),
                            Expanded(child: TextField(controller: boxQtyCtrl, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("حبة في الكرتونة", Icons.grid_view))),
                          ],
                        ),
                        _buildSectionTitle("إضافة بضاعة (مشتريات)", Icons.add_shopping_cart, Colors.orange),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
                          child: Column(
                            children: [
                              SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(value: "حبة", label: Text("حبة")),
                                  ButtonSegment(value: "كرتونة", label: Text("كرتونة")),
                                  ButtonSegment(value: "مشطاح", label: Text("مشطاح")),
                                ],
                                selected: {purchaseMode},
                                onSelectionChanged: (val) => setDialogState(() { purchaseMode = val.first; updateCalculations(); }),
                              ),
                              const SizedBox(height: 15),
                              if (purchaseMode == "حبة")
                                Row(children: [
                                  Expanded(child: TextField(controller: pieceInputPriceCtrl, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("سعر الحبة", Icons.money), onChanged: (_)=>setDialogState(updateCalculations))),
                                  const SizedBox(width: 10),
                                  Expanded(child: TextField(controller: pieceInputCountCtrl, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("الكمية", Icons.numbers), onChanged: (_)=>setDialogState(updateCalculations))),
                                ])
                              else if (purchaseMode == "كرتونة")
                                Row(children: [
                                  Expanded(child: TextField(controller: boxPriceCtrl, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("سعر الكرتونة", Icons.inventory), onChanged: (_)=>setDialogState(updateCalculations))),
                                  const SizedBox(width: 10),
                                  Expanded(child: TextField(controller: boxCountCtrl, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("الكمية", Icons.numbers), onChanged: (_)=>setDialogState(updateCalculations))),
                                ])
                              else
                                Row(children: [
                                  Expanded(child: TextField(controller: palletPriceCtrl, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("سعر المشطاح", Icons.layers), onChanged: (_)=>setDialogState(updateCalculations))),
                                  const SizedBox(width: 10),
                                  Expanded(child: TextField(controller: palletCountCtrl, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("الكمية", Icons.numbers), onChanged: (_)=>setDialogState(updateCalculations))),
                                ]),
                            ],
                          ),
                        ),
                      ],

                      _buildSectionTitle(isEdit ? "بيانات التكلفة الحالية" : "تحديد أسعار البيع والمربح", Icons.monetization_on, isEdit ? Colors.blueGrey : Colors.green),
                      
                      if (isEdit) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey[50], 
                            borderRadius: BorderRadius.circular(15), 
                            border: Border.all(color: Colors.blueGrey.shade200)
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("التكلفة الحالية للحبة:", style: TextStyle(fontSize: 16, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                                  Text("${lastCostPrice.toStringAsFixed(2)} ₪", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.blue)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const Text("(هذه التكلفة ممررة من المخزن الرئيسي بناءً على آخر عمليات شراء)", 
                                style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(child: TextField(
                              controller: sellingPriceCtrl, 
                              keyboardType: TextInputType.number, 
                              decoration: AppComponents.fieldInput("سعر بيع الحبة", Icons.sell),
                              onChanged: (_) => setDialogState(() {}),
                            )),
                            const SizedBox(width: 10),
                            Expanded(child: TextField(
                              controller: boxSellingPriceCtrl, 
                              keyboardType: TextInputType.number, 
                              decoration: AppComponents.fieldInput("سعر بيع الكرتونة", Icons.shopping_cart),
                              onChanged: (_) => setDialogState(() {}),
                            )),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: currentProfit >= 0 ? Colors.green[50] : Colors.red[50], 
                            borderRadius: BorderRadius.circular(15), 
                            border: Border.all(color: currentProfit >= 0 ? Colors.green.shade200 : Colors.red.shade200)
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("صافي الربح المتوقع:", style: TextStyle(fontWeight: FontWeight.bold)),
                              Text("${currentProfit.toStringAsFixed(2)} ₪", 
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: currentProfit >= 0 ? Colors.green[900] : Colors.red[900])),
                            ],
                          ),
                        ),
                      ],

                      _buildSectionTitle("إعدادات المخزون", Icons.analytics, Colors.blueGrey),
                      Row(
                        children: [
                          if (isEdit) Expanded(child: TextField(controller: qtyCtrl, readOnly: true, decoration: AppComponents.fieldInput("الكمية المتوفرة", Icons.storage))),
                          if (isEdit) const SizedBox(width: 10),
                          Expanded(child: TextField(controller: minStockCtrl, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("تنبيه النقص عند", Icons.notifications_active))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: isEdit ? Colors.blueGrey : Colors.blue, foregroundColor: Colors.white),
                  onPressed: isLoading ? null : () async {
                    if (nameCtrl.text.isEmpty) return;
                    setDialogState(() => isLoading = true);
                    try {
                      final mapData = {
                        'name': nameCtrl.text.trim(),
                        'barcode': barcodeCtrl.text.trim(),
                        'sellingPrice': double.tryParse(sellingPriceCtrl.text) ?? 0.0,
                        'boxSellingPrice': double.tryParse(boxSellingPriceCtrl.text) ?? 0.0,
                        'low_stock_threshold': double.tryParse(minStockCtrl.text) ?? 5.0,
                        'updatedAt': FieldValue.serverTimestamp(),
                      };

                      if (!isEdit) {
                        mapData['unit'] = unitCtrl.text.trim();
                        mapData['boxQty'] = double.tryParse(boxQtyCtrl.text) ?? 1.0;
                        mapData['boxesPerPallet'] = double.tryParse(boxesPerPalletCtrl.text) ?? 1.0;
                        mapData['quantity'] = 0.0;
                        mapData['cafeId'] = currentUser.cafeId;
                        mapData['parentId'] = managerId;
                        mapData['createdAt'] = FieldValue.serverTimestamp();
                      }

                      DocumentReference itemRef;
                      if (isEdit) {
                        itemRef = ref;
                        await itemRef.update(mapData);
                      } else {
                        final newDoc = await FirebaseFirestore.instance.collection('inventory').add(mapData);
                        itemRef = newDoc;
                      }

                      if (!isEdit) {
                        double amount = double.tryParse(totalAmountCtrl.text) ?? 0;
                        double qtyToAdd = (double.tryParse(qtyCtrl.text) ?? 0);
                        if (qtyToAdd > 0) {
                          await PurchaseService.savePurchase(
                            currentUser: currentUser,
                            cafeId: currentUser.cafeId,
                            managerId: managerId,
                            amount: amount,
                            productName: nameCtrl.text.trim(),
                            qty: qtyToAdd,
                            note: "إضافة صنف جديد",
                            prodId: itemRef.id,
                            method: "كاش",
                            unit: unitCtrl.text,
                          );
                        }
                      }

                      ActivityLogger.log(cafeId: currentUser.cafeId, parentId: managerId, userId: currentUser.id, userName: currentUser.name, action: isEdit ? "مخزن - تعديل" : "مخزن - إضافة", details: "${isEdit ? 'تعديل بيانات' : 'إضافة'} صنف: ${nameCtrl.text}");

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? "✅ تم تحديث بيانات الصنف" : "✅ تم حفظ الصنف الجديد")));
                      }
                    } catch (e) {
                      setDialogState(() => isLoading = false);
                      if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
                    }
                  }, 
                  child: Text(isEdit ? "حفظ التغييرات" : "تأكيد الإضافة")
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static Widget _buildSectionTitle(String title, IconData icon, Color color) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(width: 10),
        const Expanded(child: Divider()),
      ],
    ),
  );

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
                Text("هل أنت متأكد من حذف ($name) نهائياً من المخزن؟"),
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
