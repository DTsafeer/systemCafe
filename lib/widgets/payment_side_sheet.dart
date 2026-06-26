import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/user_model.dart';
import '../services/transfer_service.dart';

class PaymentSideSheet extends StatefulWidget {
  final Map<String, dynamic> tableData;
  final User currentUser;
  final String currencySymbol;
  final double hourlyRate;
  final bool showTimeCounter;
  final List<Map<String, String>> existingCustomers;

  const PaymentSideSheet({
    super.key,
    required this.tableData,
    required this.currentUser,
    required this.currencySymbol,
    required this.hourlyRate,
    required this.showTimeCounter,
    required this.existingCustomers,
  });

  @override
  State<PaymentSideSheet> createState() => _PaymentSideSheetState();
}

class _PaymentSideSheetState extends State<PaymentSideSheet> {
  final TextEditingController _nameController = TextEditingController(),
      _phoneController = TextEditingController(),
      _extraAmountController = TextEditingController(),
      _discountController = TextEditingController();
  double _timePrice = 0.0;
  List<String> _paymentMethods = ["كاش", "شبكة", "دين"];
  String? _selectedDebtId;

  @override
  void initState() {
    super.initState();
    _loadMethods();
    _calculateTimePrice();
  }

  void _loadMethods() {
    FirebaseFirestore.instance
        .collection('cafes')
        .doc(widget.currentUser.cafeId)
        .get()
        .then((doc) {
      if (doc.exists && mounted) {
        setState(() => _paymentMethods = List<String>.from(
            doc.data()?['payment_methods'] ?? ["كاش", "شبكة", "دين"]));
      }
    });
  }

  void _calculateTimePrice() {
    if (!widget.showTimeCounter || widget.tableData['is_open'] != true) return;
    final ts = widget.tableData['start_time'] as Timestamp?;
    final acc = widget.tableData['accumulated_seconds'] ?? 0;
    Duration dur = (ts == null)
        ? Duration(seconds: acc)
        : (DateTime.now().difference(ts.toDate()) + Duration(seconds: acc));
    setState(() => _timePrice = (dur.inSeconds / 3600) * widget.hourlyRate);
  }

  void _showDebtSearchDialog({bool isMandatory = false, VoidCallback? onSelected}) {
    final searchC = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: !isMandatory,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setS) {
          final query = searchC.text.trim().toLowerCase();
          final filtered = widget.existingCustomers
              .where((s) =>
                  s['name']!.toLowerCase().contains(query) ||
                  (s['no'] ?? "").contains(query))
              .toList();
          return PopScope(
            canPop: !isMandatory,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                title: Row(children: [
                  const Icon(Icons.person_search, color: Colors.blueGrey),
                  const SizedBox(width: 10),
                  Text(isMandatory ? "يجب اختيار زبون للدين" : "اختر الزبون", style: const TextStyle(fontSize: 20))
                ]),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                          controller: searchC,
                          autofocus: true,
                          onChanged: (v) => setS(() {}),
                          style: const TextStyle(fontSize: 18),
                          decoration: InputDecoration(
                              hintText: "بحث...",
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              fillColor: Colors.grey[100],
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide.none))),
                      const SizedBox(height: 15),
                      if (filtered.isEmpty && query.isNotEmpty)
                        ListTile(
                          title: Text("إضافة زبون جديد: $query", style: const TextStyle(fontSize: 18)),
                          leading: const Icon(Icons.person_add, color: Colors.blue),
                          onTap: () {
                            final String managerId = widget.currentUser.parentId ?? widget.currentUser.id;
                            final newDoc = FirebaseFirestore.instance.collection('debts').doc();
                            newDoc.set({
                              'cafeId': widget.currentUser.cafeId,
                              'parentId': managerId,
                              'customer': query,
                              'totalDebt': 0.0,
                              'totalPaid': 0.0,
                              'initialBalance': 0.0,
                              'remainingAmount': 0.0,
                              'date': FieldValue.serverTimestamp(),
                              'lastUpdate': FieldValue.serverTimestamp(),
                              'debtNo': widget.existingCustomers.length + 1001,
                              'phone': ''
                            });
                            setState(() {
                              _nameController.text = query;
                              _phoneController.text = "";
                              _selectedDebtId = newDoc.id;
                            });
                            Navigator.pop(ctx);
                            if (onSelected != null) onSelected();
                          },
                        ),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxHeight: MediaQuery.of(context).size.height * 0.4),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final s = filtered[i];
                              return ListTile(
                                title: Text(s['name']!,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                trailing: Text("${s['debt']} ₪",
                                    style: const TextStyle(
                                        color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
                                onTap: () {
                                  setState(() {
                                    _nameController.text = s['name']!;
                                    _phoneController.text = s['phone']!;
                                    _selectedDebtId = s['id'];
                                  });
                                  Navigator.pop(ctx);
                                  if (onSelected != null) onSelected();
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: isMandatory
                    ? []
                    : [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء", style: TextStyle(fontSize: 18)))],
              ),
            ),
          );
        },
      ),
    );
  }

  void _processPayment(String method, double total, List<QueryDocumentSnapshot> orders) {
    final cafeId = widget.currentUser.cafeId;
    final name = _nameController.text.trim().isEmpty ? "زبون عام" : _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final tableName = widget.tableData['name'];
    final tableId = widget.tableData['id'];
    final selectedDebtId = _selectedDebtId;
    final timePriceSnap = _timePrice;

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⏳ جاري إغلاق الحساب...", style: TextStyle(fontSize: 16)), duration: Duration(seconds: 1)));

    Future(() async {
      try {
        final batch = FirebaseFirestore.instance.batch();
        List items = [];
        for (var o in orders) {
          items.addAll((o.data() as Map)['items'] ?? []);
        }
        if (timePriceSnap > 0)
          items.add({'name': 'وقت طاولة', 'price': timePriceSnap, 'quantity': 1});
        String details = items.map((it) => "${it['quantity']}x ${it['name']}").join("، ");

        await TransferService.performSave(
          context: context,
          currentUser: widget.currentUser,
          customerName: name,
          phone: phone,
          amt: total,
          method: method,
          cafeId: cafeId,
          isDebtPayment: false,
          selectedDebtId: selectedDebtId,
          items: items,
          table: tableName,
          note: details,
        );

        for (var o in orders) batch.delete(o.reference);
        batch.update(FirebaseFirestore.instance.collection('tables').doc(tableId),
            {'is_open': false, 'start_time': null, 'accumulated_seconds': 0});

        await batch.commit();
      } catch (e) {
        debugPrint("Background Payment Error: $e");
      }
    });
  }

  double _parseAmount(String input) {
    String western = input
        .trim()
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9');
    return double.tryParse(western) ?? 0.0;
  }

  Widget _summaryBox(String label, double amount, Color color, IconData icon) => Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.1))),
      child: Column(children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        Text(amount.toStringAsFixed(1),
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 22))
      ]));

  Widget _field(TextEditingController c, String h, IconData i,
          {bool isNum = false, Color? color, Function(String)? onChanged}) =>
      TextField(
          controller: c,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 18),
          keyboardType: isNum
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(
              hintText: h,
              prefixIcon: Icon(i, size: 24, color: color ?? Colors.blueGrey),
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15)));

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final managerId = widget.currentUser.parentId ?? widget.currentUser.id;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('cafeId', isEqualTo: widget.currentUser.cafeId)
          .where('parentId', isEqualTo: managerId)
          .where('table', isEqualTo: widget.tableData['name'])
          .where('paid', isEqualTo: false)
          .snapshots(includeMetadataChanges: true),
      builder: (context, snap) {
        double itemsTotal = 0;
        final orders = snap.data?.docs ?? [];
        List allItems = [];
        for (var o in orders) {
          final items = (o.data() as Map)['items'] as List? ?? [];
          for (var it in items) {
            itemsTotal += (it['price'] ?? 0) * (it['quantity'] ?? 0);
            allItems.add(it);
          }
        }
        double finalTotal = itemsTotal +
            _timePrice +
            _parseAmount(_extraAmountController.text) -
            _parseAmount(_discountController.text);
        return Column(children: [
          Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30))),
              child: Row(children: [
                const Icon(Icons.payment_rounded, color: Colors.white, size: 32),
                const SizedBox(width: 15),
                Text("دفع حساب ${widget.tableData['name']}",
                    style:
                        const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context))
              ])),
          Expanded(
              child: ListView(padding: const EdgeInsets.all(20), children: [
            Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.withOpacity(0.2))),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("الإجمالي المطلوب:",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text("${finalTotal.toStringAsFixed(1)} ${widget.currencySymbol}",
                      style: const TextStyle(
                          color: Colors.green, fontWeight: FontWeight.w900, fontSize: 36))
                ])),
            const SizedBox(height: 25),
            Row(children: [
              Expanded(child: _summaryBox("الطلبات", itemsTotal, Colors.blue, Icons.shopping_basket_outlined)),
              const SizedBox(width: 15),
              Expanded(child: _summaryBox("الوقت", _timePrice, Colors.orange, Icons.access_time))
            ]),
            const SizedBox(height: 30),
            Row(children: [
              Expanded(
                  child: _field(_extraAmountController, "زيادة (+)", Icons.add_circle_outline,
                      isNum: true, onChanged: (_) => setState(() {}))),
              const SizedBox(width: 10),
              Expanded(
                  child: _field(_discountController, "خصم (-)", Icons.remove_circle_outline,
                      isNum: true, color: Colors.redAccent, onChanged: (_) => setState(() {})))
            ]),
            const SizedBox(height: 25),
            GestureDetector(
                onTap: () => _showDebtSearchDialog(),
                child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration:
                        BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15)),
                    child: Row(children: [
                      const Icon(Icons.person_search, color: Colors.blueGrey, size: 26),
                      const SizedBox(width: 15),
                      Expanded(
                          child: Text(
                              _nameController.text.isEmpty ? "اختر الشخص المعني" : _nameController.text,
                              style: TextStyle(
                                  fontSize: 18,
                                  color: _nameController.text.isEmpty ? Colors.grey : Colors.black,
                                  fontWeight: FontWeight.bold)))
                    ]))),
            const SizedBox(height: 10),
            _field(_phoneController, "رقم الهاتف", Icons.phone_android_outlined),
            const SizedBox(height: 30),
            const Text("تفاصيل الأصناف:",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 16)),
            const Divider(),
            ...allItems.map((it) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 0,
                color: Colors.grey[50],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                    dense: false,
                    title: Text(it['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    subtitle: it['added_at'] != null
                        ? Text("تم الطلب الساعة: ${it['added_at']}",
                            style: const TextStyle(fontSize: 13, color: Colors.grey))
                        : null,
                    trailing: Text("${it['price']} x ${it['quantity']}",
                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 18)))))
          ])),
          Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -5))
                  ]),
              child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _paymentMethods
                      .map((method) => SizedBox(
                          width: (MediaQuery.of(context).size.width > 500
                                  ? 410
                                  : MediaQuery.of(context).size.width * 0.85) /
                              (_paymentMethods.length > 2 ? 2.1 : 1),
                          height: 65,
                          child: ElevatedButton(
                              onPressed: () {
                                if (method.contains("دين")) {
                                  if (_selectedDebtId == null) {
                                    _showDebtSearchDialog(
                                        isMandatory: true,
                                        onSelected: () => _processPayment(method, finalTotal, orders));
                                  } else {
                                    _processPayment(method, finalTotal, orders);
                                  }
                                } else {
                                  _processPayment(method, finalTotal, orders);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: method.contains("كاش")
                                      ? Colors.green[700]!
                                      : method.contains("شبكة")
                                          ? Colors.blue[700]!
                                          : method.contains("دين")
                                              ? Colors.red[700]!
                                              : Colors.brown,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  elevation: 2),
                              child: Text(method,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)))))
                      .toList())),
        ]);
      },
    );
  }
}
