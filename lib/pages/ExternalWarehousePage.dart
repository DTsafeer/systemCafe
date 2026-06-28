import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_barcode_scanner/ai_barcode_scanner.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import 'activity_logger.dart';
import 'addproduct.dart';
import '../widgets/menu_dialogs.dart';

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
  final String currencySymbol = "₪";

  DateTimeRange? _selectedDateRange;

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

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _selectedDateRange,
    );
    if (picked != null && picked != _selectedDateRange) {
      setState(() => _selectedDateRange = picked);
    }
  }

  Future<void> _scanSearchBarcode() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AiBarcodeScanner(
          onDispose: () => Navigator.of(context).pop(),
          onDetect: (BarcodeCapture capture) {
            final String? value = capture.barcodes.first.rawValue;
            if (value != null) {
              setState(() {
                _searchController.text = value;
                _searchQuery = value.toLowerCase();
              });
              Navigator.of(context).pop();
            }
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Colors.orange[900]!;

    if (!widget.currentUser.canRead('external_warehouse')) {
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'external_warehouse',
        child: const Scaffold(body: Center(child: Text("لا تملك صلاحية"))),
      );
    }

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'external_warehouse',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _buildLuxuryHeader(primaryColor),
            Expanded(
              child: _activeCafeId == null 
                ? const Center(child: CircularProgressIndicator()) 
                : _buildWarehouseContent(primaryColor),
            ),
          ],
        ),
        floatingActionButton: widget.currentUser.canCreate('external_warehouse') 
          ? FloatingActionButton.extended(
              onPressed: _addNewItem,
              backgroundColor: primaryColor,
              icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
              label: const Text("إدخال بضاعة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ) 
          : null,
      ),
    );
  }

  Widget _buildLuxuryHeader(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primaryColor, primaryColor.withOpacity(0.8)]),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(35), bottomRight: Radius.circular(35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("المخزن الرئيسي", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                  Text("إدارة التوريدات والباركود", style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.event, color: Colors.white), onPressed: _selectDateRange),
                  GestureDetector(
                    onTap: _scanSearchBarcode,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 15),
          _buildSearchField(),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: "بحث بالاسم أو الباركود...",
          hintStyle: const TextStyle(color: Colors.white60),
          prefixIcon: const Icon(Icons.search, color: Colors.white70),
          filled: true,
          fillColor: Colors.white.withOpacity(0.12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildWarehouseContent(Color primaryColor) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('external_warehouse').where('cafeId', isEqualTo: _activeCafeId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final docs = snapshot.data!.docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          if (data['parentId'] != _managerId) return false;
          if (_searchQuery.isEmpty) return true;
          final name = data['name']?.toString().toLowerCase() ?? "";
          final barcode = data['barcode']?.toString().toLowerCase() ?? "";
          return name.contains(_searchQuery) || barcode.contains(_searchQuery);
        }).toList();

        if (docs.isEmpty) return const Center(child: Text("المخزن فارغ"));
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _buildWarehouseCard(docs[index].id, docs[index].reference, data, primaryColor);
          },
        );
      },
    );
  }

  Widget _buildWarehouseCard(String docId, DocumentReference ref, Map<String, dynamic> data, Color primaryColor) {
    final double qty = (data['quantity'] ?? 0.0).toDouble();
    final double unitCost = (data['unitCost'] ?? 0.0).toDouble();
    final String? barcode = data['barcode'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: ExpansionTile(
        leading: Icon(Icons.inventory_2, color: primaryColor),
        title: Text(data['name'] ?? "بدون اسم", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("$qty | التكلفة: ${unitCost.toStringAsFixed(1)} $currencySymbol", style: const TextStyle(fontSize: 11)),
        children: [
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("باركود: ${barcode ?? 'غير مسجل'}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    if (widget.currentUser.canUpdate('external_warehouse'))
                      TextButton.icon(
                        onPressed: () => _showTransferDialog(ref, data),
                        icon: const Icon(Icons.move_to_inbox, size: 16),
                        label: const Text("تحويل للمحل"),
                      ),
                  ],
                ),
                if (widget.currentUser.canDelete('external_warehouse'))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _confirmDelete(ref, data['name'])),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addNewItem() {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final barcodeCtrl = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text("إدخال بضاعة للمخزن"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "اسم الصنف")),
                  const SizedBox(height: 10),
                  TextField(
                    controller: barcodeCtrl,
                    readOnly: true, // توحيد: الباركود للقراءة فقط هنا
                    decoration: InputDecoration(
                      labelText: "الباركود (يعدل من صفحة المنتج)",
                      prefixIcon: const Icon(Icons.qr_code_2),
                      helperText: "استخدم صفحة 'المنيو' لتعديل الباركود",
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.open_in_new, size: 16),
                        onPressed: () {
                          // توجيه لصفحة البحث/الإضافة لتعريف الباركود
                          Navigator.push(context, MaterialPageRoute(builder: (_) => AddProduct(currentUser: widget.currentUser)));
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "الكمية"))),
                      const SizedBox(width: 10),
                      Expanded(child: TextField(controller: costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "التكلفة الإجمالية"))),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
                ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    if (nameCtrl.text.isEmpty) return;
                    setDialogState(() => isLoading = true);
                    try {
                      final qty = double.tryParse(qtyCtrl.text) ?? 0.0;
                      final cost = double.tryParse(costCtrl.text) ?? 0.0;
                      
                      // عملية الحفظ في Firebase
                      await FirebaseFirestore.instance.collection('external_warehouse').add({
                        'name': nameCtrl.text.trim(),
                        'quantity': qty,
                        'unitCost': qty > 0 ? (cost / qty) : 0.0,
                        'barcode': barcodeCtrl.text.trim(),
                        'cafeId': _activeCafeId,
                        'parentId': _managerId,
                        'dateAdded': FieldValue.serverTimestamp(),
                      });
                      
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setDialogState(() => isLoading = false);
                    }
                  },
                  child: const Text("حفظ"),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showTransferDialog(DocumentReference ref, Map<String, dynamic> data) {
    final qtyCtrl = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text("تحويل ${data['name']} للمحل"),
            content: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "الكمية المحولة")),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ElevatedButton(
                onPressed: isLoading ? null : () async {
                  final double transferQty = double.tryParse(qtyCtrl.text) ?? 0.0;
                  if (transferQty <= 0) return;
                  setDialogState(() => isLoading = true);
                  // تنفيذ عملية التحويل
                  await ref.update({'quantity': FieldValue.increment(-transferQty)});
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text("تحويل"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(DocumentReference ref, String? name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("تأكيد الحذف"),
        content: Text("حذف ($name)؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("حذف")),
        ],
      ),
    );
    if (confirm == true) await ref.delete();
  }
}
