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
  // الكنترولرز الأساسية
  final _amountController = TextEditingController(); 
  final _qtyController = TextEditingController(); 
  final _noteController = TextEditingController();
  final _productNameController = TextEditingController();
  final _searchController = TextEditingController();

  // كنترولرز نظام العبوات
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
  
  // متغيرات الدفع المتعدد
  bool _isMixed = false;
  final Map<String, TextEditingController> _paymentControllers = {};
  
  final ValueNotifier<String> _methodFilterNotifier = ValueNotifier<String>("الكل");
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>("");
  
  final ScrollController _scrollController = ScrollController();
  List<DocumentSnapshot> _purchasesDocs = [];
  bool _isLoadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final int _pageSize = 15;

  StreamSubscription? _settingsSub;
  Timer? _debounce;

  String get _managerId => widget.currentUser.parentId ?? widget.currentUser.id;

  @override
  void initState() {
    super.initState();
    _initCafeData();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
        _loadPurchases(isLoadMore: true);
      }
    });
    _methodFilterNotifier.addListener(() => _loadPurchases());
    _searchQueryNotifier.addListener(() => _loadPurchases());
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
            FirebaseFirestore.instance.collection('inventory').doc(id).get().then((doc) {
              if (doc.exists && doc.data() != null) {
                setState(() {
                  _itemsPerBoxCtrl.text = (doc.data()!['boxQty'] ?? 1).toString();
                  _boxesPerPalletCtrl.text = (doc.data()!['boxesPerPallet'] ?? 1).toString();
                });
              }
            });
          }); 
        }
      )
    );
  }

  void _updateCalculations({String from = 'piece'}) {
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
      
      if (!_isMixed) {
        _paymentControllers.forEach((_, c) => c.text = "0");
        if (_paymentControllers.containsKey(_selectedMethod)) {
          _paymentControllers[_selectedMethod]!.text = _amountController.text;
        }
      }
    });
  }

  Future<void> _loadPurchases({bool isLoadMore = false}) async {
    if (_activeCafeId == null || _activeCafeId!.isEmpty) return;
    if (isLoadMore && (!_hasMore || _isLoadingMore)) return;
    if (!isLoadMore) {
      setState(() { _purchasesDocs = []; _lastDocument = null; _hasMore = true; });
    }
    setState(() => _isLoadingMore = true);
    try {
      Query query = FirebaseFirestore.instance.collection('purchases')
          .where('cafeId', isEqualTo: _activeCafeId)
          .where('parentId', isEqualTo: _managerId)
          .orderBy('date', descending: true);
      if (_lastDocument != null && isLoadMore) query = query.startAfterDocument(_lastDocument!);
      final snapshot = await query.limit(_pageSize).get();
      if (snapshot.docs.length < _pageSize) _hasMore = false;
      if (mounted) {
        setState(() {
          if (isLoadMore) _purchasesDocs.addAll(snapshot.docs);
          else _purchasesDocs = snapshot.docs;
          if (snapshot.docs.isNotEmpty) _lastDocument = snapshot.docs.last;
          _isLoadingMore = false;
        });
      }
    } catch (e) { if (mounted) setState(() => _isLoadingMore = false); }
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
        _loadPurchases();
        _settingsSub = CafeService.streamCafeSettings(cid).listen((settings) {
          if (mounted) {
            setState(() {
              List<String> methods = ["كاش"];
              for (var m in settings.paymentMethods) {
                if (!m.contains("دين") && !m.contains("ديون") && m != "كاش") {
                  methods.add(m);
                }
              }
              if (!methods.contains("دين للمورد")) {
                methods.add("دين للمورد");
              }
              _paymentMethods = methods;
              
              for (var method in _paymentMethods) {
                if (!_paymentControllers.containsKey(method)) {
                  _paymentControllers[method] = TextEditingController(text: "0");
                }
              }
              if (!_paymentMethods.contains(_selectedMethod) && _paymentMethods.isNotEmpty) {
                _selectedMethod = _paymentMethods.first;
              }
            });
          }
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _searchQueryNotifier.value = query.trim().toLowerCase());
  }

  Future<void> _handleSavePurchase() async {
    if (!widget.currentUser.canCreate('purchases')) return;
    
    double totalAmount = double.tryParse(_amountController.text) ?? 0;
    if (totalAmount <= 0 || _qtyController.text == "0.0") {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إكمال بيانات الكمية والمبلغ")));
      return;
    }

    Map<String, double> payments = {};
    double paidSum = 0;
    
    if (_isMixed) {
      _paymentControllers.forEach((method, ctrl) {
        double val = double.tryParse(ctrl.text) ?? 0;
        if (val > 0) {
          payments[method] = val;
          paidSum += val;
        }
      });
      if ((paidSum - totalAmount).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("مجموع مبالغ الدفع ($paidSum) لا يساوي المبلغ الإجمالي ($totalAmount)")));
        return;
      }
    } else {
      payments[_selectedMethod] = totalAmount;
    }

    if (payments.containsKey("دين للمورد") && _selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يجب اختيار اسم المورد عند الدفع بـ 'دين للمورد'")));
      return;
    }

    setState(() => _isLoading = true);
    try {
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
      );

      _amountController.clear(); _qtyController.clear(); _noteController.clear(); 
      _productNameController.clear(); _piecePriceCtrl.clear(); _pieceCountCtrl.clear();
      _boxPriceCtrl.clear(); _boxCountCtrl.clear(); _palletPriceCtrl.clear(); _palletCountCtrl.clear();
      _selectedProductId = null;
      _paymentControllers.forEach((_, c) => c.text = "0");
      _loadPurchases(); 
      if (mounted) setState(() => _isLoading = false);
    } catch (e) { if (mounted) setState(() => _isLoading = false); }
  }

  @override
  void dispose() {
    _scrollController.dispose(); _amountController.dispose(); _noteController.dispose();
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
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 50),
                children: [
                  const SizedBox(height: 15),
                  if (widget.currentUser.canCreate('purchases')) _buildResponsiveForm(primaryColor),
                  _buildFilters(primaryColor),
                  _buildPurchasesList(),
                  const SizedBox(height: 20),
                  if (_isLoadingMore) 
                    const Center(child: CircularProgressIndicator())
                  else if (_hasMore)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: TextButton.icon(
                        onPressed: () => _loadPurchases(isLoadMore: true),
                        icon: const Icon(Icons.history),
                        label: const Text("تحميل سجلات أقدم"),
                        style: TextButton.styleFrom(foregroundColor: Colors.grey),
                      ),
                    ),
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
      decoration: BoxDecoration(
        color: primary,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(35), bottomRight: Radius.circular(35)),
        boxShadow: [BoxShadow(color: primary.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))]
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("سجل المشتريات", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          Text("إدارة المشتريات وتحديث المخزون", style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildResponsiveForm(Color primary) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15)]),
      child: Column(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('suppliers').where('cafeId', isEqualTo: _activeCafeId).snapshots(),
            builder: (context, snap) {
              final docs = snap.hasData ? snap.data!.docs.where((d) => d['parentId'] == _managerId).toList() : [];
              return DropdownButtonFormField<String>(
                value: _selectedSupplierId,
                decoration: InputDecoration(labelText: "المورد", prefixIcon: const Icon(Icons.business), filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
                items: [const DropdownMenuItem(value: null, child: Text("مورد عام")), ...docs.map((d) => DropdownMenuItem(value: d.id, child: Text(d['name'])))],
                onChanged: (v) => setState(() { _selectedSupplierId = v; _selectedSupplierName = v == null ? null : docs.firstWhere((d) => d.id == v)['name']; }),
              );
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _productNameController,
            onChanged: (v) { if (_selectedProductId != null) setState(() => _selectedProductId = null); },
            decoration: InputDecoration(
              labelText: "اسم الصنف (مخزني أو خارجي)",
              hintText: "اكتب الاسم أو ابحث في المخزن...",
              prefixIcon: const Icon(Icons.shopping_basket_outlined),
              suffixIcon: IconButton(icon: const Icon(Icons.search, color: Colors.blue), onPressed: _showProductSearch),
              filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)
            ),
          ),
          const SizedBox(height: 15),
          const Align(alignment: Alignment.centerRight, child: Text("طريقة الشراء:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
            children: _modes.map((mode) => ChoiceChip(
              label: Text(mode, style: TextStyle(fontSize: 12, color: _purchaseMode == mode ? Colors.white : Colors.black87)),
              selected: _purchaseMode == mode,
              selectedColor: primary,
              onSelected: (selected) { if (selected) { setState(() { _purchaseMode = mode; _updateCalculations(); }); } },
            )).toList(),
          ),
          const SizedBox(height: 15),
          if (["حبة", "لتر", "كيلو", "جرام"].contains(_purchaseMode)) ...[
            Row(
              children: [
                Expanded(child: _modernInput(_piecePriceCtrl, "سعر ال$_purchaseMode", Icons.money, isNum: true, onChanged: (_) => _updateCalculations())),
                const SizedBox(width: 10),
                Expanded(child: _modernInput(_pieceCountCtrl, "الكمية ($_purchaseMode)", Icons.numbers, isNum: true, onChanged: (_) => _updateCalculations())),
              ],
            ),
          ] else if (_purchaseMode == "كرتونة") ...[
            Row(
              children: [
                Expanded(child: _modernInput(_boxPriceCtrl, "سعر الكرتونة", Icons.price_check, isNum: true, onChanged: (_) => _updateCalculations())),
                const SizedBox(width: 10),
                Expanded(child: _modernInput(_boxCountCtrl, "كم كرتونة؟", Icons.inventory, isNum: true, onChanged: (_) => _updateCalculations())),
              ],
            ),
            const SizedBox(height: 10),
            _modernInput(_itemsPerBoxCtrl, "حبة في الكرتونة", Icons.grid_view, isNum: true, onChanged: (_) => _updateCalculations()),
          ] else ...[
            Row(
              children: [
                Expanded(child: _modernInput(_palletPriceCtrl, "سعر المشطاح", Icons.payments, isNum: true, onChanged: (_) => _updateCalculations())),
                const SizedBox(width: 10),
                Expanded(child: _modernInput(_palletCountCtrl, "كم مشطاح؟", Icons.layers, isNum: true, onChanged: (_) => _updateCalculations())),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _modernInput(_boxesPerPalletCtrl, "كرتونة/مشطاح", Icons.view_quilt, isNum: true, onChanged: (_) => _updateCalculations())),
                const SizedBox(width: 10),
                Expanded(child: _modernInput(_itemsPerBoxCtrl, "حبة/كرتونة", Icons.grid_view, isNum: true, onChanged: (_) => _updateCalculations())),
              ],
            ),
          ],
          const Divider(height: 30),
          Row(
            children: [
              Expanded(child: _modernInput(_qtyController, "إجمالي الكمية", Icons.analytics, isReadOnly: false, isNum: true)),
              const SizedBox(width: 10),
              Expanded(child: _modernInput(_amountController, "المبلغ الكلي", Icons.receipt, isReadOnly: false, isNum: true)),
            ],
          ),
          const SizedBox(height: 15),
          _buildPaymentSelection(),
          const SizedBox(height: 10),
          _modernInput(_noteController, "ملاحظات إضافية", Icons.note_add),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isLoading ? null : _handleSavePurchase,
            style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
            child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("تسجيل المشتريات وتحديث المخزون", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _buildPaymentSelection() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("تفاصيل الدفع:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              Row(
                children: [
                  const Text("دفع متعدد", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Switch(
                    value: _isMixed,
                    onChanged: (v) => setState(() {
                      _isMixed = v;
                      if (!v) {
                        _paymentControllers.forEach((_, c) => c.text = "0");
                        if (_paymentControllers.containsKey(_selectedMethod)) {
                          _paymentControllers[_selectedMethod]!.text = _amountController.text;
                        }
                      }
                    }),
                  ),
                ],
              ),
            ],
          ),
          if (!_isMixed) 
            Wrap(
              spacing: 8,
              children: _paymentMethods.map((m) => ChoiceChip(
                label: Text(m),
                selected: _selectedMethod == m,
                onSelected: (v) => setState(() { _selectedMethod = m; _updateCalculations(); }),
              )).toList(),
            )
          else 
            Column(
              children: _paymentMethods.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text(m, style: const TextStyle(fontSize: 13))),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: 40,
                        child: TextField(
                          controller: _paymentControllers[m],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                            filled: true, fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey[300]!)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _modernInput(TextEditingController ctrl, String label, IconData icon, {bool isNum = false, bool isReadOnly = false, Function(String)? onChanged}) => TextField(
    controller: ctrl, readOnly: isReadOnly, onChanged: onChanged,
    keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    decoration: InputDecoration(
      labelText: label, prefixIcon: Icon(icon, size: 20), filled: true, 
      fillColor: isReadOnly ? Colors.grey[100] : Colors.grey[50], 
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)
    ),
  );

  Widget _buildFilters(Color primary) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(hintText: "بحث في المشتريات والملاحظات...", prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<String>(
            valueListenable: _methodFilterNotifier,
            builder: (context, method, _) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ["الكل", ..._paymentMethods].map((m) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(label: Text(m), selected: method == m, onSelected: (v) { if(v) _methodFilterNotifier.value = m; }),
                )).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchasesList() {
    return ValueListenableBuilder2<String, String>(
      first: _searchQueryNotifier,
      second: _methodFilterNotifier,
      builder: (context, query, method, _) {
        final filteredList = _purchasesDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (method != "الكل" && data['method'] != method) return false;
          if (query.isNotEmpty) {
            final name = (data['productName'] ?? "").toString().toLowerCase();
            final supplier = (data['supplierName'] ?? "").toString().toLowerCase();
            final note = (data['note'] ?? "").toString().toLowerCase();
            if (!name.contains(query) && !supplier.contains(query) && !note.contains(query)) return false;
          }
          return true;
        }).toList();

        if (filteredList.isEmpty && !_isLoadingMore) {
          return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("لا توجد نتائج تطابق بحثك حالياً", style: TextStyle(color: Colors.grey))));
        }

        return Column(
          children: filteredList.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
            final String payMethod = data['method'] ?? "كاش";
            final Map<String, dynamic>? breakdown = data['paymentBreakdown'];
            
            return Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]),
              child: ExpansionTile(
                maintainState: true,
                onExpansionChanged: (isExpanded) {
                  if (isExpanded) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      _scrollController.animateTo(
                        _scrollController.offset + 150, 
                        duration: const Duration(milliseconds: 300), 
                        curve: Curves.easeOut
                      );
                    });
                  }
                },
                tilePadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                leading: CircleAvatar(backgroundColor: Colors.blue.withOpacity(0.1), child: const Icon(Icons.shopping_bag_outlined, color: Colors.blue, size: 20)),
                title: Text("${data['productName'] ?? 'مشتريات'} (${data['supplierName'] ?? 'مورد عام'})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text("${intl.DateFormat('yyyy/MM/dd').format(date)} | $payMethod", style: const TextStyle(fontSize: 11)),
                trailing: Text("${data['amount']} ₪", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _detailRow("الكمية المضافة", "${data['quantity'] ?? 0} ${data['unit'] ?? 'حبة/وحدة'}"),
                        _detailRow("الموظف المسجل", data['processedBy'] ?? data['added_by'] ?? "-"),
                        if (breakdown != null && breakdown.length > 1) ...[
                          const Divider(),
                          const Align(alignment: Alignment.centerRight, child: Text("تفصيل الدفع المتعدد:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
                          ...breakdown.entries.map((e) => _detailRow(e.key, "${e.value} ₪")),
                        ],
                        if (data['note'] != null && data['note'].toString().isNotEmpty) ...[
                          const Divider(),
                          const Align(alignment: Alignment.centerRight, child: Text("الملاحظات:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey))),
                          Align(alignment: Alignment.centerRight, child: Text(data['note'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                        ],
                        const SizedBox(height: 10),
                        if (widget.currentUser.canDelete('purchases'))
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text("تأكيد الحذف"),
                                    content: const Text("هل تريد حذف هذه العملية من السجل؟"),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
                                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("حذف", style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await doc.reference.delete();
                                  _loadPurchases();
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                  )
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _detailRow(String l, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l, style: const TextStyle(color: Colors.grey, fontSize: 12)), Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))]));
}

class ValueListenableBuilder2<A, B> extends StatelessWidget {
  final ValueNotifier<A> first;
  final ValueNotifier<B> second;
  final Widget Function(BuildContext, A, B, Widget?) builder;
  const ValueListenableBuilder2({super.key, required this.first, required this.second, required this.builder});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<A>(valueListenable: first, builder: (_, a, __) => ValueListenableBuilder<B>(valueListenable: second, builder: (ctx, b, child) => builder(ctx, a, b, child)));
}
