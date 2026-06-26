import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import 'activity_logger.dart';

class ExternalWarehousePage extends StatefulWidget {
  final User currentUser;
  const ExternalWarehousePage({super.key, required this.currentUser});

  @override
  State<ExternalWarehousePage> createState() => _ExternalWarehousePageState();
}

class _ExternalWarehousePageState extends State<ExternalWarehousePage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  Timer? _debounce;
  List<String> _suppliersList = ["مورد عام"];
  String? _activeCafeId;

  String get _managerId => widget.currentUser.parentId ?? widget.currentUser.id;

  @override
  void initState() {
    super.initState();
    _initCafeData();
  }

  Future<void> _initCafeData() async {
    String cid = widget.currentUser.cafeId;
    if (cid.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      cid = prefs.getString('cafe_id') ?? "";
    }
    if (mounted) {
      setState(() => _activeCafeId = cid);
      if (cid.isNotEmpty) {
        _loadSuppliers(cid);
      }
    }
  }

  void _loadSuppliers(String cid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('suppliers')
          .where('cafeId', isEqualTo: cid)
          .get();
      
      final List<DocumentSnapshot> filteredDocs = snap.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['parentId'] == _managerId;
      }).toList();
      
      if (mounted) {
        setState(() {
          _suppliersList = filteredDocs.map((doc) => (doc.data() as Map<String, dynamic>)['name'].toString()).toList();
          if (!_suppliersList.contains("مورد عام")) _suppliersList.add("مورد عام");
        });
      }
    } catch (e) {
      debugPrint("Error loading suppliers: $e");
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _searchQuery = query.toLowerCase();
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _addNewItem() {
    if (!widget.currentUser.canCreate('external_warehouse')) return;
    
    if (_activeCafeId == null || _activeCafeId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى الانتظار حتى تحميل بيانات المقهى")));
      return;
    }

    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: "قطعة");
    final costCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String selectedSupplier = _suppliersList.isNotEmpty ? _suppliersList.first : "مورد عام";
    bool addToExpenses = true;
    double unitPrice = 0.0;
    DateTime selectedDate = DateTime.now();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          void calculateUnitPrice() {
            double q = double.tryParse(qtyCtrl.text) ?? 0.0;
            double c = double.tryParse(costCtrl.text) ?? 0.0;
            setDialogState(() {
              unitPrice = (q > 0) ? (c / q) : 0.0;
            });
          }

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.add_business_rounded, color: Colors.orange, size: 30),
                          const SizedBox(width: 12),
                          const Text("مشتريات جديدة للمخزن", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        value: selectedSupplier,
                        decoration: const InputDecoration(labelText: "المورد", border: OutlineInputBorder()),
                        items: _suppliersList.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: isLoading ? null : (v) => setDialogState(() => selectedSupplier = v!),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: nameCtrl,
                        enabled: !isLoading,
                        decoration: const InputDecoration(labelText: "اسم الصنف (مثل: قهوة)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.inventory_2_outlined)),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: qtyCtrl, enabled: !isLoading, onChanged: (_) => calculateUnitPrice(), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "الكمية", border: OutlineInputBorder()))),
                          const SizedBox(width: 10),
                          Expanded(child: TextField(controller: unitCtrl, enabled: !isLoading, decoration: const InputDecoration(labelText: "الوحدة", border: OutlineInputBorder()))),
                        ],
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: costCtrl,
                        enabled: !isLoading,
                        onChanged: (_) => calculateUnitPrice(),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: "التكلفة الإجمالية", border: OutlineInputBorder(), suffixText: "₪"),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: noteCtrl,
                        enabled: !isLoading,
                        decoration: const InputDecoration(labelText: "التفاصيل / ملاحظات", border: OutlineInputBorder(), prefixIcon: Icon(Icons.notes_rounded)),
                      ),
                      if (unitPrice > 0)
                        Padding(padding: const EdgeInsets.all(8), child: Text("تكلفة الواحدة: ${unitPrice.toStringAsFixed(2)} ₪", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
                      
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        enabled: !isLoading,
                        leading: const Icon(Icons.calendar_today, color: Colors.blue),
                        title: Text("التاريخ: ${intl.DateFormat('yyyy/MM/dd').format(selectedDate)}"),
                        onTap: () async {
                          final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now());
                          if (picked != null) setDialogState(() => selectedDate = picked);
                        },
                      ),
          
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        enabled: !isLoading,
                        title: const Text("تسجيل كمصروف مالي", style: TextStyle(fontSize: 14)),
                        value: addToExpenses,
                        onChanged: (v) => setDialogState(() => addToExpenses = v!),
                      ),
                      if (isLoading) const Center(child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator())),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(child: TextButton(onPressed: isLoading ? null : () => Navigator.pop(ctx), child: const Text("إلغاء"))),
                          const SizedBox(width: 10),
                          Expanded(child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white),
                            onPressed: isLoading ? null : () async {
                               final name = nameCtrl.text.trim();
                               if (name.isEmpty) return;
                               
                               setDialogState(() => isLoading = true);
                               try {
                                 final qty = double.tryParse(qtyCtrl.text) ?? 0.0;
                                 final cost = double.tryParse(costCtrl.text) ?? 0.0;
                                 final note = noteCtrl.text.trim();
            
                                 final batch = FirebaseFirestore.instance.batch();
                                 
                                 final warehouseRef = FirebaseFirestore.instance.collection('external_warehouse').doc();
                                 batch.set(warehouseRef, {
                                   'name': name,
                                   'quantity': qty,
                                   'unit': unitCtrl.text,
                                   'costPrice': cost,
                                   'supplier': selectedSupplier,
                                   'unitCost': (qty > 0) ? (cost / qty) : 0.0,
                                   'cafeId': _activeCafeId,
                                   'parentId': _managerId,
                                   'note': note,
                                   'dateAdded': Timestamp.fromDate(selectedDate),
                                 });
            
                                 if (addToExpenses && cost > 0) {
                                   final expenseRef = FirebaseFirestore.instance.collection('expenses').doc();
                                   batch.set(expenseRef, {
                                     'cafeId': _activeCafeId,
                                     'parentId': _managerId,
                                     'title': "مشتريات من $selectedSupplier: $name",
                                     'amount': cost,
                                     'category': "مشتريات مخزن",
                                     'note': note,
                                     'date': Timestamp.fromDate(selectedDate),
                                     'processedBy': widget.currentUser.name,
                                   });
                                 }
                                 
                                 await batch.commit();

                                 ActivityLogger.log(
                                   cafeId: _activeCafeId!,
                                   parentId: _managerId,
                                   userId: widget.currentUser.id,
                                   userName: widget.currentUser.name,
                                   action: "مشتريات مخزن - إضافة",
                                   details: "إضافة بضاعة للمخزن: $name بكمية $qty من $selectedSupplier",
                                 );

                                 if (ctx.mounted) {
                                   Navigator.pop(ctx);
                                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم الحفظ (سيتم المزامنة تلقائياً)")));
                                 }
                               } catch (e) {
                                 setDialogState(() => isLoading = false);
                                 if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
                               }
                            },
                            child: const Text("حفظ المشتريات"),
                          )),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showTransferDialog(DocumentReference ref, Map<String, dynamic> data) {
    if (!widget.currentUser.canUpdate('external_warehouse')) return;

    final qtyCtrl = TextEditingController();
    final double currentQty = (data['quantity'] ?? 0.0).toDouble();
    DateTime transferDate = DateTime.now();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text("تحويل ${data['name']} إلى المحل"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("الكمية المتوفرة في المخزن: $currentQty ${data['unit'] ?? ''}", style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: qtyCtrl,
                    enabled: !isLoading,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: "الكمية المراد تحويلها للمحل",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    enabled: !isLoading,
                    leading: const Icon(Icons.calendar_today, color: Colors.blue, size: 20),
                    title: Text("تاريخ التحويل: ${intl.DateFormat('yyyy/MM/dd').format(transferDate)}", style: const TextStyle(fontSize: 13)),
                    onTap: () async {
                      final picked = await showDatePicker(context: context, initialDate: transferDate, firstDate: DateTime(2020), lastDate: DateTime.now());
                      if (picked != null) setDialogState(() => transferDate = picked);
                    },
                  ),
                  if (isLoading) const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator()),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: isLoading ? null : () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: isLoading ? null : () async {
                  final double transferQty = double.tryParse(qtyCtrl.text) ?? 0.0;
                  if (transferQty <= 0 || transferQty > currentQty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال كمية صحيحة"), backgroundColor: Colors.red));
                    return;
                  }
          
                  setDialogState(() => isLoading = true);
                  try {
                    final batch = FirebaseFirestore.instance.batch();
                    
                    batch.update(ref, {'quantity': FieldValue.increment(-transferQty)});
            
                    final invSnap = await FirebaseFirestore.instance.collection('inventory')
                        .where('cafeId', isEqualTo: _activeCafeId)
                        .where('parentId', isEqualTo: _managerId)
                        .where('name', isEqualTo: data['name']).limit(1).get();
            
                    if (invSnap.docs.isNotEmpty) {
                      batch.update(invSnap.docs.first.reference, {'quantity': FieldValue.increment(transferQty)});
                    } else {
                      final newInvRef = FirebaseFirestore.instance.collection('inventory').doc();
                      batch.set(newInvRef, {
                        'name': data['name'],
                        'quantity': transferQty,
                        'unit': data['unit'],
                        'cafeId': _activeCafeId,
                        'parentId': _managerId,
                        'low_stock_threshold': 5.0,
                      });
                    }
            
                    final transferRef = FirebaseFirestore.instance.collection('warehouse_transfers').doc();
                    batch.set(transferRef, {
                      'itemName': data['name'],
                      'quantity': transferQty,
                      'unit': data['unit'],
                      'transferMethod': "تحويل من المخزن الخارجي",
                      'processedBy': widget.currentUser.name,
                      'transferredAt': Timestamp.fromDate(transferDate),
                      'isReceived': true,
                      'cafeId': _activeCafeId,
                      'parentId': _managerId,
                    });
            
                    await batch.commit();

                    ActivityLogger.log(
                      cafeId: _activeCafeId!,
                      parentId: _managerId,
                      userId: widget.currentUser.id,
                      userName: widget.currentUser.name,
                      action: "مخزن - تحويل للمحل",
                      details: "تحويل $transferQty ${data['unit']} من صنف ${data['name']} للمحل",
                    );
            
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم التحويل للمحل بنجاح"), backgroundColor: Colors.green));
                    }
                  } catch (e) {
                    setDialogState(() => isLoading = false);
                    if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ أثناء التحويل: $e")));
                  }
                },
                child: const Text("تأكيد التحويل"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!widget.currentUser.canRead('external_warehouse')) {
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'external_warehouse',
        child: const Scaffold(
          body: Center(
            child: Text("عذراً، لا تملك صلاحية لعرض صفحة المخزن الخارجي", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'external_warehouse',
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Text("المخزن الخارجي", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.orange[900])),
                    const Spacer(),
                    _buildSearchField(),
                  ],
                ),
              ),
              Expanded(
                child: _activeCafeId == null 
                  ? const Center(child: CircularProgressIndicator()) 
                  : StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('external_warehouse')
                      .where('cafeId', isEqualTo: _activeCafeId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return Center(child: Text("خطأ في تحميل البيانات: ${snapshot.error}"));
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    
                    final docs = snapshot.data!.docs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      if (data['parentId'] != _managerId) return false;
                      if (_searchQuery.isEmpty) return true;
                      final name = data['name']?.toString().toLowerCase() ?? "";
                      return name.contains(_searchQuery);
                    }).toList();

                    if (docs.isEmpty) return const Center(child: Text("المخزن فارغ أو لم يتم العثور على نتائج"));
                    
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          child: ListTile(
                            leading: CircleAvatar(backgroundColor: Colors.orange[50], child: const Icon(Icons.inventory, color: Colors.orange)),
                            title: Text(data['name'] ?? "بدون اسم", style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("الكمية: ${data['quantity'] ?? 0} ${data['unit'] ?? ''} | المصدر: ${data['supplier'] ?? 'مورد عام'}"),
                                if (data['note'] != null && data['note'].toString().isNotEmpty)
                                  Text("ملاحظة: ${data['note']}", style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.blueGrey)),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.currentUser.canUpdate('external_warehouse'))
                                  IconButton(
                                    tooltip: "تحويل إلى المحل",
                                    icon: const Icon(Icons.move_to_inbox_rounded, color: Colors.blue), 
                                    onPressed: () => _showTransferDialog(docs[index].reference, data),
                                  ),
                                if (widget.currentUser.canDelete('external_warehouse'))
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red), 
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text("تأكيد الحذف"),
                                          content: const Text("هل تريد حذف هذا الصنف من المخزن؟"),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
                                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("حذف", style: TextStyle(color: Colors.red))),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        try {
                                          docs[index].reference.delete();
                                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم الحذف")));
                                        } catch (e) {
                                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
                                        }
                                      }
                                    },
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          if (widget.currentUser.canCreate('external_warehouse'))
            Positioned(
              bottom: 20,
              left: 20,
              child: FloatingActionButton.extended(
                onPressed: _addNewItem,
                backgroundColor: Colors.orange[800],
                icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
                label: const Text("إدخل بضاعة", style: TextStyle(color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      width: 250, 
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged, 
        decoration: InputDecoration(
          hintText: "بحث عن بضاعة...", 
          prefixIcon: const Icon(Icons.search), 
          filled: true, 
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        )
      )
    );
  }
}
