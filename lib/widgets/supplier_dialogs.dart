import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import '../services/supplier_service.dart';
import '../services/cafe_service.dart';
import '../pages/user_model.dart';

class SupplierDialogs {
  static void showAddSupplierDialog({
    required BuildContext context,
    required String cafeId,
    required String managerId,
  }) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final companyCtrl = TextEditingController();
    final openBalCtrl = TextEditingController(text: "0");
    
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("إضافة مورد جديد", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 25),
                _popInput(nameCtrl, "اسم المورد المسؤول", Icons.person_outline),
                const SizedBox(height: 12),
                _popInput(phoneCtrl, "رقم الهاتف", Icons.phone_android, isNum: true),
                const SizedBox(height: 12),
                _popInput(companyCtrl, "اسم الشركة / النشاط", Icons.business_outlined),
                const SizedBox(height: 12),
                _popInput(openBalCtrl, "رصيد افتتاحي (دين سابق)", Icons.account_balance_wallet_outlined, isNum: true),
                const SizedBox(height: 30),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor, 
                    minimumSize: const Size(double.infinity, 55), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  onPressed: () {
                    if (nameCtrl.text.isNotEmpty) {
                      SupplierService.addSupplier(
                        name: nameCtrl.text.trim(),
                        phone: phoneCtrl.text.trim(),
                        company: companyCtrl.text.trim(),
                        cafeId: cafeId,
                        managerId: managerId,
                        openingBalance: double.tryParse(openBalCtrl.text) ?? 0.0,
                      );
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text("حفظ المورد", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void showAddPurchaseDialog({
    required BuildContext context,
    required User currentUser,
    required String cafeId,
    required String managerId,
    String? initialSupplierId,
  }) {
    // توليد رقم فاتورة من 6 خانات (5 أرقام وحرف واحد)
    final random = Random();
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const digits = '0123456789';
    List<String> chars = List.generate(5, (i) => digits[random.nextInt(digits.length)]);
    chars.add(letters[random.nextInt(letters.length)]);
    chars.shuffle();
    final String autoInvoiceNo = chars.join();
    
    final amtCtrl = TextEditingController(), paidCtrl = TextEditingController();
          
    String? selectedSupplierId = initialSupplierId;
    String? selectedSupplierName;
    String selectedMethod = "كاش";
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("تسجيل فاتورة مشتريات", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 25),
                  
                  // صندوق عرض رقم الفاتورة (للمشاهدة فقط)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey[50],
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.blueGrey[100]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.tag, color: Colors.blueGrey, size: 18),
                            SizedBox(width: 8),
                            Text("رقم الفاتورة الآلي:", style: TextStyle(color: Colors.blueGrey, fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Text(autoInvoiceNo, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black, fontSize: 16, letterSpacing: 1.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),

                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: SupplierService.streamSuppliers(cafeId, managerId),
                    builder: (context, snap) {
                      if (!snap.hasData) return const CircularProgressIndicator();
                      final suppliers = snap.data!;
                      if (selectedSupplierId != null && selectedSupplierName == null) {
                        try {
                          selectedSupplierName = suppliers.firstWhere((s) => s['id'] == selectedSupplierId)['name'];
                        } catch(_) {}
                      }

                      return DropdownButtonFormField<String>(
                        value: selectedSupplierId,
                        decoration: InputDecoration(filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
                        hint: const Text("اختر المورد"),
                        items: suppliers.map((s) => DropdownMenuItem(value: s['id'].toString(), child: Text(s['name']))).toList(),
                        onChanged: (v) { 
                          final s = suppliers.firstWhere((s) => s['id'] == v); 
                          setDialogState(() {
                            selectedSupplierId = v; 
                            selectedSupplierName = s['name']; 
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _popInput(amtCtrl, "إجمالي مبلغ الفاتورة", Icons.monetization_on_outlined, isNum: true),
                  const SizedBox(height: 12),
                  _popInput(paidCtrl, "المبلغ المسدد الآن", Icons.payments_outlined, isNum: true, onChanged: (_) => setDialogState(() {})),
                  const SizedBox(height: 12),
                  StreamBuilder<CafeSettings>(
                    stream: CafeService.streamCafeSettings(cafeId),
                    builder: (context, snap) {
                      List<String> methods = ["كاش"];
                      if (snap.hasData) {
                        for (var m in snap.data!.paymentMethods) {
                          if (!m.contains("دين") && !m.contains("ديون") && m != "كاش") {
                            methods.add(m);
                          }
                        }
                      }
                      double paidVal = double.tryParse(paidCtrl.text) ?? 0;
                      bool isEnabled = paidVal > 0;

                      return DropdownButtonFormField<String>(
                        value: methods.contains(selectedMethod) ? selectedMethod : methods.first,
                        onChanged: isEnabled ? (v) => setDialogState(() => selectedMethod = v!) : null,
                        decoration: InputDecoration(
                          labelText: "طريقة الدفع", 
                          filled: true, 
                          fillColor: isEnabled ? Colors.grey[50] : Colors.grey[200],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)
                        ),
                        items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m, style: TextStyle(color: isEnabled ? Colors.black : Colors.grey)))).toList(),
                      );
                    }
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                    onPressed: () { 
                       if (selectedSupplierId != null && amtCtrl.text.isNotEmpty) {
                          SupplierService.savePurchaseBill(
                            supplierId: selectedSupplierId!,
                            supplierName: selectedSupplierName!,
                            invoiceNo: autoInvoiceNo,
                            totalAmount: double.tryParse(amtCtrl.text) ?? 0,
                            paidAmount: double.tryParse(paidCtrl.text) ?? 0,
                            method: selectedMethod,
                            currentUser: currentUser,
                            cafeId: cafeId,
                            managerId: managerId,
                          );
                          Navigator.pop(ctx); 
                       }
                    },
                    child: const Text("تأكيد وحفظ الفاتورة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void showSupplierOptions({
    required BuildContext context,
    required String id,
    required Map data,
    required User currentUser,
    required String cafeId,
    required String managerId,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
              child: Row(
                children: [
                  CircleAvatar(radius: 25, backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1), child: Icon(Icons.person, color: Theme.of(context).primaryColor)),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        Text("${data['company'] ?? 'شركة غير محددة'} | ${data['phone'] ?? 'بدون رقم'}", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ),
                  Text("${(data['totalBalance'] ?? 0.0).abs().toStringAsFixed(1)} ₪", 
                    style: TextStyle(color: (data['totalBalance'] ?? 0.0) >= 0 ? Colors.red : Colors.green, fontWeight: FontWeight.w900, fontSize: 20)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.payment_rounded, color: Colors.green),
              title: const Text("تسديد دفعة للمورد"),
              onTap: () { 
                Navigator.pop(ctx); 
                showPaySupplierDialog(context: context, sId: id, sName: data['name'], currentUser: currentUser, cafeId: cafeId, managerId: managerId); 
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded, color: Colors.blue),
              title: const Text("كشف حساب المورد"),
              onTap: () { 
                Navigator.pop(ctx); 
                showSupplierHistory(context: context, sId: id, sName: data['name'], openingBalance: (data['openingBalance'] ?? 0.0).toDouble()); 
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
              title: const Text("حذف بيانات المورد"),
              onTap: () { 
                Navigator.pop(ctx); 
                SupplierService.deleteSupplier(id); 
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  static void showPaySupplierDialog({
    required BuildContext context,
    required String sId,
    required String sName,
    required User currentUser,
    required String cafeId,
    required String managerId,
  }) {
    final amtCtrl = TextEditingController();
    String selectedMethod = "كاش";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            title: Text("تسديد دفعة لـ $sName"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amtCtrl, 
                  onChanged: (_) => setDialogState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true), 
                  decoration: InputDecoration(labelText: "المبلغ المدفوع", prefixIcon: const Icon(Icons.money), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)))
                ),
                const SizedBox(height: 15),
                StreamBuilder<CafeSettings>(
                  stream: CafeService.streamCafeSettings(cafeId),
                  builder: (context, snap) {
                    List<String> methods = ["كاش"];
                    if (snap.hasData) {
                      for (var m in snap.data!.paymentMethods) {
                        if (!m.contains("دين") && !m.contains("ديون") && m != "كاش") {
                          methods.add(m);
                        }
                      }
                    }
                    double paidAmt = double.tryParse(amtCtrl.text) ?? 0;
                    bool isEnabled = paidAmt > 0;

                    return DropdownButtonFormField<String>(
                      value: methods.contains(selectedMethod) ? selectedMethod : methods.first,
                      onChanged: isEnabled ? (v) => setDialogState(() => selectedMethod = v!) : null,
                      decoration: InputDecoration(
                        labelText: "طريقة الدفع", 
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                        filled: !isEnabled,
                        fillColor: isEnabled ? null : Colors.grey[200],
                      ),
                      items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m, style: TextStyle(color: isEnabled ? Colors.black : Colors.grey)))).toList(),
                    );
                  }
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () {
                  double amt = double.tryParse(amtCtrl.text) ?? 0;
                  if (amt > 0) {
                    SupplierService.processSupplierPayment(
                      supplierId: sId,
                      supplierName: sName,
                      amount: amt,
                      method: selectedMethod,
                      currentUser: currentUser,
                      cafeId: cafeId,
                      managerId: managerId,
                    );
                  }
                  Navigator.pop(ctx);
                }, 
                child: const Text("تأكيد الدفع", style: TextStyle(color: Colors.white))
              )
            ],
          ),
        ),
      ),
    );
  }

  static void showSupplierHistory({
    required BuildContext context,
    required String sId,
    required String sName,
    double openingBalance = 0,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              const SizedBox(height: 15),
              Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("سجل حساب المورد: $sName", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              const Divider(),
              Table(
                border: TableBorder.all(color: Colors.black45, width: 1),
                columnWidths: const {
                  0: FlexColumnWidth(1.2), 
                  1: FlexColumnWidth(1.2), 
                  2: FlexColumnWidth(1.5), 
                  3: FlexColumnWidth(1.2), 
                  4: FlexColumnWidth(1.2), 
                },
                children: [
                  TableRow(
                    children: [
                      _buildHeaderCell("الرصيد المستحق للمورد (له)"),
                      _buildHeaderCell("المبالغ المسددة (عليه)"),
                      _buildHeaderCell("تفاصيل الحركة"),
                      _buildHeaderCell("المبلغ الصافي"),
                      _buildHeaderCell("تاريخ اليوم"),
                    ],
                  ),
                ],
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('supplier_transactions').where('supplierId', isEqualTo: sId).snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    
                    final docs = List.from(snap.data?.docs ?? []);
                    docs.sort((a, b) => (a.data() as Map)['date'].compareTo((b.data() as Map)['date']));

                    double runningBalance = openingBalance;
                    Map<String, List<Map<String, dynamic>>> groupedData = {};
                    List<String> sortedDateKeys = [];

                    if (openingBalance != 0) {
                      String startKey = "رصيد سابق";
                      groupedData[startKey] = [{
                        'isPayment': false,
                        'amount': openingBalance,
                        'netBalance': openingBalance,
                        'data': {'type': 'رصيد افتتاحي'},
                        'time': '--:--',
                      }];
                      sortedDateKeys.add(startKey);
                    }

                    for (var doc in docs) {
                      final d = doc.data() as Map<String, dynamic>;
                      final DateTime date = (d['date'] as Timestamp?)?.toDate() ?? DateTime.now();
                      final String dateKey = intl.DateFormat('yyyy/MM/dd').format(date);
                      
                      final double amt = (d['amount'] as num).toDouble();
                      final String type = d['type'] ?? "";
                      final bool isPayment = type.contains("سداد") || type.contains("دفعة") || (d['isPayment'] == true);

                      if (isPayment) runningBalance -= amt; 
                      else {
                        double debtAdded = amt - (d['paid'] ?? amt).toDouble();
                        runningBalance += debtAdded;
                      }

                      if (!groupedData.containsKey(dateKey)) {
                        groupedData[dateKey] = [];
                        sortedDateKeys.add(dateKey);
                      }

                      groupedData[dateKey]!.add({
                        'data': d,
                        'isPayment': isPayment,
                        'amount': isPayment ? amt : (amt - (d['paid'] ?? amt).toDouble()),
                        'netBalance': runningBalance,
                        'time': intl.DateFormat('hh:mm a').format(date),
                      });
                    }

                    final displayDateKeys = sortedDateKeys.reversed.toList();

                    return ListView.builder(
                      itemCount: displayDateKeys.length,
                      padding: const EdgeInsets.only(bottom: 50),
                      itemBuilder: (context, dateIndex) {
                        String dateKey = displayDateKeys[dateIndex];
                        List<Map<String, dynamic>> dayRows = groupedData[dateKey]!.reversed.toList();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 15),
                          decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 1.5), borderRadius: BorderRadius.circular(4)),
                          child: Table(
                            border: const TableBorder(verticalInside: BorderSide(color: Colors.black, width: 1)),
                            columnWidths: const {
                              0: FlexColumnWidth(1.2),
                              1: FlexColumnWidth(1.2),
                              2: FlexColumnWidth(1.5),
                              3: FlexColumnWidth(1.2),
                              4: FlexColumnWidth(1.2),
                            },
                            children: dayRows.asMap().entries.map((entry) {
                              int i = entry.key;
                              var row = entry.value;
                              final bool isPayment = row['isPayment'];
                              final double net = row['netBalance'];

                              String creditStr = !isPayment ? "${row['time']}\n${row['amount'].toStringAsFixed(1)}" : "0";
                              String debitStr = isPayment ? "${row['time']}\n${row['amount'].toStringAsFixed(1)}" : "0";
                              String netDisplay = net >= 0 ? "له: ${net.abs().toStringAsFixed(1)}" : "مسبق: ${net.abs().toStringAsFixed(1)}";

                              return TableRow(
                                decoration: BoxDecoration(color: i % 2 == 0 ? Colors.white : Colors.grey[50]),
                                children: [
                                  _buildDataCell(creditStr, color: !isPayment ? Colors.orange[800] : Colors.black),
                                  _buildDataCell(debitStr, color: isPayment ? Colors.green[800] : Colors.black),
                                  _buildDataCell(row['data']['type'] ?? "-", isSmall: true),
                                  _buildDataCell(netDisplay, fontWeight: FontWeight.bold, color: net >= 0 ? Colors.red[900] : Colors.green[900]),
                                  _buildDataCell(i == 0 ? dateKey : ""),
                                ],
                              );
                            }).toList(),
                          ),
                        );
                      },
                    );
                  }
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildHeaderCell(String text) => Container(
    height: 50, alignment: Alignment.center, padding: const EdgeInsets.all(4.0),
    child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
  );

  static Widget _buildDataCell(String text, {Color? color, FontWeight? fontWeight, bool isSmall = false}) => Container(
    height: 45, alignment: Alignment.center, padding: const EdgeInsets.all(6.0),
    child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: color, fontWeight: fontWeight, fontSize: isSmall ? 9 : 11)),
  );

  static Widget _popInput(TextEditingController ctrl, String label, IconData icon, {bool isNum = false, bool isReadOnly = false, Function(String)? onChanged}) {
    return TextField(
      controller: ctrl,
      onChanged: onChanged,
      readOnly: isReadOnly,
      keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        labelText: label, 
        prefixIcon: Icon(icon, size: 20), 
        filled: true, 
        fillColor: isReadOnly ? Colors.grey[200] : Colors.grey[50], 
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)
      ),
    );
  }
}
