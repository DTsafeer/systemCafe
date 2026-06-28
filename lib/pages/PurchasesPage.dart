import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/purchase_service.dart';
import '../services/cafe_service.dart';
import '../widgets/product_search_sheet.dart';
import 'user_model.dart';
import 'MainLayout.dart';

class PurchasesPage extends StatefulWidget {
  final User currentUser;
  const PurchasesPage({super.key, required this.currentUser});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _amountController = TextEditingController(); 
  final _qtyController = TextEditingController(); 
  final _noteController = TextEditingController();
  final _productNameController = TextEditingController();
  final _searchController = TextEditingController();

  final _piecePriceCtrl = TextEditingController();
  final _pieceCountCtrl = TextEditingController();
  final _boxPriceCtrl = TextEditingController();
  final _boxCountCtrl = TextEditingController();
  final _itemsPerBoxCtrl = TextEditingController(text: "1");
  final _palletPriceCtrl = TextEditingController();
  final _palletCountCtrl = TextEditingController();
  final _boxesPerPalletCtrl = TextEditingController(text: "1");

  String _purchaseMode = "حبة"; 
  final List<String> _modes = ["حبة", "لتر", "كيلو", "جرام", "كرتونة", "مشطاح"];
  
  String? _selectedProductId;
  String? _selectedSupplierId;
  String? _selectedSupplierName;
  String? _activeCafeId;
  bool _isLoading = false;
  
  List<String> _paymentMethods = ["كاش", "شبكة", "دين للمورد"];
  String _selectedMethod = "كاش";
  bool _isMixed = false;
  final Map<String, TextEditingController> _paymentControllers = {};
  
  final ValueNotifier<String> _methodFilterNotifier = ValueNotifier<String>("الكل");
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>("");
  
  StreamSubscription? _settingsSub;
  Timer? _debounce;

  // الإضافة الجديدة: وجهة الشراء
  bool _toShopInventory = false;

  String get _managerId => widget.currentUser.parentId ?? widget.currentUser.id;

  @override
  void initState() {
    super.initState();
    _initCafeData();
    _methodFilterNotifier.addListener(() => setState(() {}));
    _searchQueryNotifier.addListener(() => setState(() {}));
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
        _settingsSub = CafeService.streamCafeSettings(cid).listen((settings) {
          if (mounted) {
            setState(() {
              List<String> methods = ["كاش"];
              for (var m in settings.paymentMethods) {
                if (!m.contains("دين") && !m.contains("ديون") && m != "كاش") {
                  methods.add(m);
                }
              }
              if (!methods.contains("دين للمورد")) methods.add("دين للمورد");
              _paymentMethods = methods;
              for (var method in _paymentMethods) {
                if (!_paymentControllers.containsKey(method)) {
                  _paymentControllers[method] = TextEditingController(text: "0");
                }
              }
            });
          }
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _searchQueryNotifier.value = query.trim().toLowerCase();
    });
  }

  Future<void> _handleSavePurchase() async {
    if (!widget.currentUser.canCreate('purchases')) return;
    
    double totalAmount = double.tryParse(_amountController.text) ?? 0;
    if (totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال المبلغ")));
      return;
    }

    setState(() => _isLoading = true);
    try {
      Map<String, double> payments = {};
      if (_isMixed) {
        _paymentControllers.forEach((method, ctrl) {
          double val = double.tryParse(ctrl.text) ?? 0;
          if (val > 0) payments[method] = val;
        });
      } else {
        payments[_selectedMethod] = totalAmount;
      }

      await PurchaseService.savePurchase(
        currentUser: widget.currentUser,
        cafeId: _activeCafeId!,
        managerId: _managerId,
        amount: totalAmount,
        productName: _productNameController.text.isEmpty ? "مشتريات عامة" : _productNameController.text,
        qty: double.tryParse(_qtyController.text) ?? 0,
        note: _noteController.text,
        prodId: _selectedProductId,
        supplierId: _selectedSupplierId,
        supplierName: _selectedSupplierName,
        payments: payments, 
        unit: _purchaseMode,
        toShopInventory: _toShopInventory, // تمرير الوجهة
      );

      _amountController.clear(); _qtyController.clear(); _noteController.clear(); 
      _productNameController.clear(); _piecePriceCtrl.clear(); _pieceCountCtrl.clear();
      _boxPriceCtrl.clear(); _boxCountCtrl.clear(); _palletPriceCtrl.clear(); _palletCountCtrl.clear();
      _selectedProductId = null;
      _paymentControllers.forEach((_, c) => c.text = "0");
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم الحفظ وتحديث المخزن والسجل"), backgroundColor: Colors.green));
      
      if (mounted) setState(() => _isLoading = false);
    } catch (e) { 
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
      }
    }
  }

  void _showProductSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) => ProductSearchSheet(
        activeCafeId: _activeCafeId!,
        managerId: _managerId,
        onItemSelected: (id, name, qty, unit) { 
          setState(() { 
            _selectedProductId = id; 
            _productNameController.text = name;
          }); 
        }
      )
    );
  }

  void _updateCalculations() {
    double pPrice = double.tryParse(_piecePriceCtrl.text) ?? 0;
    double pCount = double.tryParse(_pieceCountCtrl.text) ?? 0;
    double bPrice = double.tryParse(_boxPriceCtrl.text) ?? 0;
    double bCount = double.tryParse(_boxCountCtrl.text) ?? 0;
    double itemsPerBox = double.tryParse(_itemsPerBoxCtrl.text) ?? 1;
    double palPrice = double.tryParse(_palletPriceCtrl.text) ?? 0;
    double palCount = double.tryParse(_palletCountCtrl.text) ?? 0;
    double boxesPerPallet = double.tryParse(_boxesPerPalletCtrl.text) ?? 1;

    double totalAmount = 0;
    double totalQty = 0;

    if (["حبة", "لتر", "كيلو", "جرام"].contains(_purchaseMode)) {
      totalAmount = pPrice * pCount;
      totalQty = pCount;
    } else if (_purchaseMode == "كرتونة") {
      totalAmount = bPrice * bCount;
      totalQty = bCount * itemsPerBox;
    } else if (_purchaseMode == "مشطاح") {
      totalAmount = palPrice * palCount;
      totalQty = palCount * boxesPerPallet * itemsPerBox;
    }

    setState(() {
      _amountController.text = totalAmount.toStringAsFixed(2);
      _qtyController.text = totalQty.toStringAsFixed(1);
      if (!_isMixed && _paymentControllers.containsKey(_selectedMethod)) {
        _paymentControllers[_selectedMethod]!.text = _amountController.text;
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose(); _noteController.dispose();
    _productNameController.dispose(); _qtyController.dispose(); _searchController.dispose();
    _piecePriceCtrl.dispose(); _pieceCountCtrl.dispose(); _boxPriceCtrl.dispose();
    _boxCountCtrl.dispose(); _itemsPerBoxCtrl.dispose(); _palletPriceCtrl.dispose();
    _palletCountCtrl.dispose(); _boxesPerPalletCtrl.dispose();
    _paymentControllers.forEach((_, c) => c.dispose());
    _methodFilterNotifier.dispose(); _searchQueryNotifier.dispose();
    _settingsSub?.cancel(); _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'purchases',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _buildHeaderDashboard(primaryColor),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 50),
                children: [
                  const SizedBox(height: 15),
                  if (widget.currentUser.canCreate('purchases')) _buildResponsiveForm(primaryColor),
                  _buildFilters(primaryColor),
                  _buildPurchasesList(),
                  const SizedBox(height: 100), 
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderDashboard(Color primary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(25, 40, 25, 25),
      decoration: BoxDecoration(color: primary, borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(35), bottomRight: Radius.circular(35))),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("سجل المشتريات والمخزن الرئيسي", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          Text("كل شروة تُحفظ في السجل وتحدث المخزن فوراً", style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildResponsiveForm(Color primary) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: Column(
        children: [
          // إضافة خيار وجهة الشراء
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.blue.withOpacity(0.1))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(children: [Icon(Icons.location_on_outlined, size: 18, color: Colors.blue), SizedBox(width: 8), Text("وجهة التخزين:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))]),
                Row(children: [
                   Text(_toShopInventory ? "مخزن المحل" : "المخزن الرئيسي", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                   Switch(value: _toShopInventory, activeColor: Colors.blue, onChanged: (v) => setState(() => _toShopInventory = v)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 15),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('suppliers').where('cafeId', isEqualTo: _activeCafeId).snapshots(),
            builder: (context, snap) {
              final docs = snap.hasData ? snap.data!.docs : [];
              String? safeValue = _selectedSupplierId;
              if (safeValue != null && !docs.any((d) => d.id == safeValue)) {
                safeValue = null;
              }

              return DropdownButtonFormField<String>(
                value: safeValue,
                decoration: InputDecoration(labelText: "المورد", prefixIcon: const Icon(Icons.business), filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text("مورد عام")),
                  ...docs.map((d) => DropdownMenuItem<String>(value: d.id, child: Text(d['name'] ?? "بدون اسم"))).toList(),
                ],
                onChanged: (v) => setState(() { 
                  _selectedSupplierId = v; 
                  _selectedSupplierName = v == null ? null : docs.firstWhere((d) => d.id == v)['name']; 
                }),
              );
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _productNameController,
            decoration: InputDecoration(
              labelText: "اسم الصنف",
              prefixIcon: const Icon(Icons.shopping_basket_outlined),
              suffixIcon: IconButton(icon: const Icon(Icons.search, color: Colors.blue), onPressed: _showProductSearch),
              filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, alignment: WrapAlignment.center,
            children: _modes.map((mode) => ChoiceChip(
              label: Text(mode, style: TextStyle(fontSize: 12, color: _purchaseMode == mode ? Colors.white : Colors.black87)),
              selected: _purchaseMode == mode,
              selectedColor: primary,
              onSelected: (selected) { if (selected) { setState(() { _purchaseMode = mode; _updateCalculations(); }); } },
            )).toList(),
          ),
          const SizedBox(height: 10),
          if (["حبة", "لتر", "كيلو", "جرام"].contains(_purchaseMode)) ...[
            Row(children: [
              Expanded(child: _modernInput(_piecePriceCtrl, "سعر ال$_purchaseMode", Icons.money, isNum: true, onChanged: (_) => _updateCalculations())),
              const SizedBox(width: 10),
              Expanded(child: _modernInput(_pieceCountCtrl, "الكمية", Icons.numbers, isNum: true, onChanged: (_) => _updateCalculations())),
            ]),
          ] else if (_purchaseMode == "كرتونة") ...[
            Row(children: [
              Expanded(child: _modernInput(_boxPriceCtrl, "سعر الكرتونة", Icons.price_check, isNum: true, onChanged: (_) => _updateCalculations())),
              const SizedBox(width: 10),
              Expanded(child: _modernInput(_boxCountCtrl, "الكمية", Icons.inventory, isNum: true, onChanged: (_) => _updateCalculations())),
            ]),
            const SizedBox(height: 10),
            _modernInput(_itemsPerBoxCtrl, "حبة في الكرتونة", Icons.grid_view, isNum: true, onChanged: (_) => _updateCalculations()),
          ] else ...[
            Row(children: [
              Expanded(child: _modernInput(_palletPriceCtrl, "سعر المشطاح", Icons.payments, isNum: true, onChanged: (_) => _updateCalculations())),
              const SizedBox(width: 10),
              Expanded(child: _modernInput(_palletCountCtrl, "الكمية", Icons.layers, isNum: true, onChanged: (_) => _updateCalculations())),
            ]),
          ],
          const Divider(height: 30),
          Row(children: [
            Expanded(child: _modernInput(_qtyController, "إجمالي الكمية", Icons.analytics, isReadOnly: true)),
            const SizedBox(width: 10),
            Expanded(child: _modernInput(_amountController, "المبلغ الكلي", Icons.receipt, isReadOnly: false, isNum: true, onChanged: (v) {
              setState(() { if (!_isMixed && _paymentControllers.containsKey(_selectedMethod)) _paymentControllers[_selectedMethod]!.text = v; });
            })),
          ]),
          const SizedBox(height: 15),
          _buildPaymentSelection(),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isLoading ? null : _handleSavePurchase,
            style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
            child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("حفظ المشتريات"),
          )
        ],
      ),
    );
  }

  Widget _buildPaymentSelection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("طريقة الدفع:", style: TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                const Text("دفع متعدد", style: TextStyle(fontSize: 10)),
                Switch(value: _isMixed, onChanged: (v) => setState(() {
                  _isMixed = v;
                  _paymentControllers.forEach((_, c) => c.text = "0");
                  if (!v && _paymentControllers.containsKey(_selectedMethod)) _paymentControllers[_selectedMethod]!.text = _amountController.text;
                })),
              ]),
            ],
          ),
          if (!_isMixed) 
            Wrap(spacing: 8, children: _paymentMethods.map((m) => ChoiceChip(label: Text(m), selected: _selectedMethod == m, onSelected: (v) => setState(() { _selectedMethod = m; _updateCalculations(); }))).toList())
          else 
            ..._paymentMethods.map((m) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(child: Text(m, style: const TextStyle(fontSize: 12))),
                Expanded(child: SizedBox(height: 35, child: TextField(controller: _paymentControllers[m], keyboardType: TextInputType.number, decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))))),
              ]),
            )),
        ],
      ),
    );
  }

  Widget _modernInput(TextEditingController ctrl, String label, IconData icon, {bool isNum = false, bool isReadOnly = false, Function(String)? onChanged}) => TextField(
    controller: ctrl, readOnly: isReadOnly, onChanged: onChanged,
    keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20), filled: true, fillColor: isReadOnly ? Colors.grey[100] : Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
  );

  Widget _buildFilters(Color primary) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(hintText: "بحث...", prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ["الكل", "مزيج", ..._paymentMethods].map((m) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(label: Text(m), selected: _methodFilterNotifier.value == m, onSelected: (v) { if(v) { setState(() { _methodFilterNotifier.value = m; }); } }),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchasesList() {
    if (_activeCafeId == null || _activeCafeId!.isEmpty) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('purchases')
          .where('cafeId', isEqualTo: _activeCafeId)
          .where('parentId', isEqualTo: _managerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("خطأ في تحميل السجلات: ${snapshot.error}"));
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final allDocs = snapshot.data?.docs ?? [];
        
        final sortedDocs = List<DocumentSnapshot>.from(allDocs);
        sortedDocs.sort((a, b) {
          final da = (a.data() as Map)['date'] as Timestamp?;
          final db = (b.data() as Map)['date'] as Timestamp?;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });

        final query = _searchQueryNotifier.value;
        final method = _methodFilterNotifier.value;

        final filteredList = sortedDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (method != "الكل" && data['method'] != method) return false;
          if (query.isNotEmpty) {
            final name = (data['productName'] ?? "").toString().toLowerCase();
            final supplier = (data['supplierName'] ?? "").toString().toLowerCase();
            if (!name.contains(query) && !supplier.contains(query)) return false;
          }
          return true;
        }).take(50).toList(); 

        if (filteredList.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("لا توجد سجلات مشتريات حالياً", style: TextStyle(color: Colors.grey))));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredList.length,
          itemBuilder: (context, index) {
            final doc = filteredList[index];
            final data = doc.data() as Map<String, dynamic>;
            final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
            final double unitCost = (data['unitCost'] ?? 0.0).toDouble();

            return Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.withOpacity(0.1),
                  child: const Icon(Icons.inventory_2, color: Colors.blue, size: 20)
                ),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(data['productName'] ?? 'مشتريات', style: const TextStyle(fontWeight: FontWeight.bold))),
                    Text("${data['amount']} ₪", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green)),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text("${intl.DateFormat('yyyy/MM/dd | HH:mm').format(date)} | ${data['supplierName'] ?? 'مورد عام'} | الدفع: ${data['method'] ?? 'كاش'}", style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            "التكلفة للوحدة: ${unitCost.toStringAsFixed(2)} ₪ (${data['quantity']} ${data['unit'] ?? ''})",
                            style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (data['target'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(
                              data['target'],
                              style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
