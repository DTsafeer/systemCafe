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
  }) {
    final invCtrl = TextEditingController(), amtCtrl = TextEditingController(), paidCtrl = TextEditingController();
    String? selectedSupplierId, selectedSupplierName;
    String selectedMethod = "كاش"; // الطريقة الافتراضية
    
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
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: SupplierService.streamSuppliers(cafeId, managerId),
                    builder: (context, snap) {
                      if (!snap.hasData) return const CircularProgressIndicator();
                      final suppliers = snap.data!;
                      return DropdownButtonFormField<String>(
                        decoration: InputDecoration(filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
                        hint: const Text("اختر المورد"),
                        items: suppliers.map((s) => DropdownMenuItem(value: s['id'].toString(), child: Text(s['name']))).toList(),
                        onChanged: (v) { 
                          final s = suppliers.firstWhere((s) => s['id'] == v); 
                          selectedSupplierId = v; 
                          selectedSupplierName = s['name']; 
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _popInput(invCtrl, "رقم الفاتورة الورقية", Icons.numbers),
                  const SizedBox(height: 12),
                  _popInput(amtCtrl, "إجمالي مبلغ الفاتورة", Icons.monetization_on_outlined, isNum: true),
                  const SizedBox(height: 12),
                  _popInput(paidCtrl, "المبلغ المسدد الآن", Icons.payments_outlined, isNum: true),
                  const SizedBox(height: 12),
                  // إضافة اختيار طريقة الدفع
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('settings').doc(cafeId).snapshots(),
                    builder: (context, snap) {
                      List<String> methods = ["كاش", "شبكة"];
                      if (snap.hasData && snap.data!.exists) {
                        methods = List<String>.from(snap.data!['paymentMethods'] ?? ["كاش", "شبكة"]);
                        methods.removeWhere((m) => m == "دين");
                      }
                      return DropdownButtonFormField<String>(
                        value: selectedMethod,
                        decoration: InputDecoration(labelText: "طريقة الدفع", filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
                        items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                        onChanged: (v) => setDialogState(() => selectedMethod = v!),
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
                            invoiceNo: invCtrl.text,
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
                  Text("${(data['totalBalance'] ?? 0.0).toStringAsFixed(1)} ₪", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 20)),
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
                showSupplierHistory(context: context, sId: id, sName: data['name']); 
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
                  keyboardType: const TextInputType.numberWithOptions(decimal: true), 
                  decoration: InputDecoration(labelText: "المبلغ المدفوع", prefixIcon: const Icon(Icons.money), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)))
                ),
                const SizedBox(height: 15),
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('settings').doc(cafeId).snapshots(),
                  builder: (context, snap) {
                    List<String> methods = ["كاش", "شبكة"];
                    if (snap.hasData && snap.data!.exists) {
                      methods = List<String>.from(snap.data!['paymentMethods'] ?? ["كاش", "شبكة"]);
                      methods.removeWhere((m) => m == "دين");
                    }
                    return DropdownButtonFormField<String>(
                      value: selectedMethod,
                      decoration: InputDecoration(labelText: "طريقة الدفع", border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))),
                      items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                      onChanged: (v) => setDialogState(() => selectedMethod = v!),
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
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
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
                    Text("كشف حساب: $sName", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('supplier_transactions').where('supplierId', isEqualTo: sId).snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (!snap.hasData || snap.data!.docs.isEmpty) return const Center(child: Text("لا توجد عمليات مسجلة"));
                    final docs = snap.data!.docs;
                    docs.sort((a, b) => (b['date'] as Timestamp).compareTo(a['date'] as Timestamp));

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                      itemCount: docs.length,
                      separatorBuilder: (context, i) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final d = docs[i].data() as Map<String, dynamic>;
                        final DateTime date = (d['date'] as Timestamp?)?.toDate() ?? DateTime.now();
                        final String type = d['type'] ?? "";
                        final bool isPayment = type.contains("سداد") || type.contains("دفعة") || (d['isPayment'] == true);
                        
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                          leading: CircleAvatar(
                            backgroundColor: isPayment ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                            child: Icon(isPayment ? Icons.arrow_downward : Icons.arrow_upward, color: isPayment ? Colors.green : Colors.orange),
                          ),
                          title: Text(type, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text("${intl.DateFormat('yyyy/MM/dd | hh:mm a').format(date)} | ${d['method'] ?? 'كاش'}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          trailing: Text("${d['amount']} ₪", style: TextStyle(fontWeight: FontWeight.w900, color: isPayment ? Colors.green : Colors.black, fontSize: 16)),
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

  static Widget _popInput(TextEditingController ctrl, String label, IconData icon, {bool isNum = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20), filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
    );
  }
}
