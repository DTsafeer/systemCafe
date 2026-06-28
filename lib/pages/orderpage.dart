import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:ai_barcode_scanner/ai_barcode_scanner.dart';
import '../services/order_service.dart';
import '../services/inventory_service.dart';
import '../services/debt_service.dart';
import '../services/cafe_service.dart';
import '../services/table_service.dart';
import '../services/transfer_service.dart';
import '../widgets/app_components.dart';
import '../widgets/category_grid_view.dart';
import 'user_model.dart';
import 'addproduct.dart';
import 'homepage.dart';

class OrderPage extends StatefulWidget {
  final User currentUser;
  final String tableId;
  final String tableName;
  final Map<String, dynamic>? restoreData;

  const OrderPage({
    super.key,
    required this.currentUser,
    required this.tableId,
    required this.tableName,
    this.restoreData,
  });

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> with TickerProviderStateMixin {
  final ValueNotifier<Map<String, Map<String, dynamic>>> cartNotifier = ValueNotifier({});
  final ValueNotifier<String> searchNotifier = ValueNotifier("");
  final ValueNotifier<Map<String, double>> inventoryNotifier = ValueNotifier({});

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _receivedAmountController = TextEditingController();

  final FocusNode _barcodeFieldFocusNode = FocusNode();
  final TextEditingController _barcodeInputController = TextEditingController();

  List<String> _paymentMethods = ["كاش", "شبكة", "دين"];
  String? _activeCafeId;
  CafeSettings? _settings;
  StreamSubscription? _settingsSub;
  StreamSubscription? _inventorySub;
  StreamSubscription? _debtSub;
  StreamSubscription? _tablesSub;
  StreamSubscription? _productsSub;
  StreamSubscription? _tableSub;
  Timer? _debounce;
  Timer? _timerTick;

  TabController? _tabController;
  List<Map<String, String>> _customerSuggestions = [];
  List<Map<String, dynamic>> _allTables = [];
  String? _selectedCustomerId;
  String? _selectedCustomerBalance;
  double? _selectedCustomerLimit;

  List<QueryDocumentSnapshot> _allProducts = [];
  Map<String, dynamic>? _tableData;
  double _currentTimerPrice = 0.0;

  Stream<QuerySnapshot>? _pendingOrdersStream;

  // Scanner status logic
  bool _isScannerConnected = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _initCafeData();
    _searchController.addListener(_onSearchChanged);
    if (widget.restoreData != null) _restoreOrder(widget.restoreData!);

    _timerTick = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) _calculateTimerPrice();
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // تحديث الحالة بناءً على التركيز في خانة الباركود بدلاً من استشعار الجهاز
    _barcodeFieldFocusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isScannerConnected = _barcodeFieldFocusNode.hasFocus;
        });
      }
    });
  }

  void _restoreOrder(Map<String, dynamic> data) {
    Map<String, Map<String, dynamic>> restoredCart = {};
    final items = data['items'];
    if (items != null && items is List) {
      for (var item in items) {
        if (item is Map && item['id'] != null) {
          restoredCart[item['id'].toString()] = Map<String, dynamic>.from(item);
        }
      }
    }
    cartNotifier.value = restoredCart;
    _nameController.text = data['customer_name']?.toString() ?? "";
    _phoneController.text = data['customer_phone']?.toString() ?? "";
    _selectedCustomerId = data['selectedCustomerId']?.toString();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        searchNotifier.value = _searchController.text.trim().toLowerCase();
      }
    });
  }

  Future<void> _initCafeData() async {
    String cid = widget.currentUser.cafeId;
    if (cid.isEmpty) cid = await CafeService.getActiveCafeId();
    final String managerId = widget.currentUser.parentId ?? widget.currentUser.id;

    if (mounted) {
      setState(() {
        _activeCafeId = cid;
        if (cid.isNotEmpty && widget.tableId != "takeaway") {
          _pendingOrdersStream = FirebaseFirestore.instance
              .collection('orders')
              .where('cafeId', isEqualTo: cid)
              .where('table', isEqualTo: widget.tableName)
              .where('paid', isEqualTo: false)
              .snapshots();

          _tableSub = FirebaseFirestore.instance.collection('tables').doc(widget.tableId).snapshots().listen((snap) {
            if (mounted && snap.exists) {
              setState(() {
                _tableData = snap.data();
                _calculateTimerPrice();
              });
            }
          });
        }
      });
      if (cid.isNotEmpty) {
        _listenToCafeSettings(cid);
        _listenToCustomers(cid);
        _listenToInventory(cid);
        _listenToAllTables(cid, managerId);
        _loadAllProducts(cid, managerId);
      }
    }
  }

  void _calculateTimerPrice() {
    if (_tableData == null || _settings == null) return;

    final Timestamp? startTime = _tableData!['start_time'];
    final int accumulatedSeconds = _tableData!['accumulated_seconds'] ?? 0;
    final double hourlyRate = _settings!.hourlyRate;

    int totalSeconds = accumulatedSeconds;
    if (startTime != null) {
      totalSeconds += DateTime.now().difference(startTime.toDate()).inSeconds;
    }

    setState(() {
      _currentTimerPrice = ((totalSeconds / 3600) * hourlyRate).roundToDouble();
    });
  }

  void _loadAllProducts(String cid, String managerId) {
    _productsSub = FirebaseFirestore.instance
        .collection('products')
        .where('cafeId', isEqualTo: cid)
        .where('parentId', isEqualTo: managerId)
        .snapshots()
        .listen((snap) {
          if (mounted) setState(() => _allProducts = snap.docs);
        }, onError: (e) => debugPrint("Products Stream Error: $e"));
  }

  Future<void> _openCameraScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AiBarcodeScanner(
          onDetect: (BarcodeCapture capture) {
            final String? value = capture.barcodes.first.rawValue;
            if (value != null) {
              _onBarcodeScanned(value);
              Navigator.of(context).pop();
            }
          },
        ),
      ),
    );
  }

  void _onBarcodeScanned(String code) {
    if (!mounted) return;
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) return;

    debugPrint("🔍 جاري البحث عن الباركود: $cleanCode");

    try {
      final doc = _allProducts.firstWhere(
        (p) {
          final data = p.data() as Map;
          return data['barcode']?.toString() == cleanCode;
        },
      );

      final data = doc.data() as Map<String, dynamic>;
      final String id = doc.id;

      double availableStock = inventoryNotifier.value[id] ?? (data['stockQuantity'] as num? ?? 0.0).toDouble();
      double currentInCart = cartNotifier.value[id]?['quantity'] ?? 0.0;

      if (currentInCart + 1 > availableStock && (_settings?.isInventoryTrackingEnabled ?? true)) {
         HapticFeedback.vibrate();
         debugPrint("⚠️ تنبيه: المخزن غير كافٍ لمنتج ${data['name']}");

         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text("⚠️ مخزن غير كافٍ لـ: ${data['name']}"),
             backgroundColor: Colors.red[800],
             behavior: SnackBarBehavior.floating,
           )
         );
      } else {
         _updateCart(id, data, currentInCart + 1);

         HapticFeedback.mediumImpact();
         debugPrint("✅ نجاح: تم العثور على ${data['name']} وإضافته للسلة.");

         ScaffoldMessenger.of(context).clearSnackBars();
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Row(
               children: [
                 const Icon(Icons.check_circle, color: Colors.white, size: 20),
                 const SizedBox(width: 10),
                 Expanded(child: Text("تمت إضافة ${data['name']} (الكمية: ${(currentInCart + 1).toInt()})")),
               ],
             ),
             duration: const Duration(milliseconds: 1200),
             backgroundColor: Colors.green[800],
             behavior: SnackBarBehavior.floating,
             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
             margin: const EdgeInsets.all(10),
           )
         );
      }

      _barcodeInputController.clear();
    } catch (e) {
      debugPrint("❌ خطأ: الباركود ($cleanCode) غير مسجل في النظام.");

      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ الصنف ($cleanCode) غير موجود"),
          backgroundColor: Colors.orange[800],
          behavior: SnackBarBehavior.floating,
        )
      );
      _barcodeInputController.clear();
    }

    Future.microtask(() {
      if (mounted) _barcodeFieldFocusNode.requestFocus();
    });
  }

  void _listenToAllTables(String cid, String managerId) {
    _tablesSub = TableService.streamTables(cid, managerId).listen((data) {
      if (mounted) setState(() => _allTables = data);
    });
  }

  void _listenToInventory(String cid) {
    final String managerId = widget.currentUser.parentId ?? widget.currentUser.id;
    _inventorySub = InventoryService.streamInventory(cid, managerId).listen((items) {
      if (mounted) {
        Map<String, double> stocks = {};
        for (var item in items) {
          stocks[item['id']] = (item['quantity'] ?? 0.0).toDouble();
        }
        inventoryNotifier.value = stocks;
      }
    });
  }

  void _listenToCustomers(String cid) {
    final String managerId = widget.currentUser.parentId ?? widget.currentUser.id;
    _debtSub = DebtService.streamDebts(cid, managerId).listen((data) {
      if (mounted) {
        setState(() {
          _customerSuggestions = data.map((d) => {
            'name': d['customer']?.toString() ?? "",
            'phone': d['phone']?.toString() ?? "",
            'debt': (d['netBalance'] as num).toDouble().toStringAsFixed(1),
            'id': d['id'].toString(),
            'limit': (d['debtLimit'] as num? ?? 0.0).toDouble().toString()
          }).toList();
        });
      }
    });
  }

  void _listenToCafeSettings(String cid) {
    _settingsSub = CafeService.streamCafeSettings(cid).listen((settings) {
      if (mounted) {
        setState(() {
          _settings = settings;
          _paymentMethods = settings.paymentMethods;
          _calculateTimerPrice();
        });
      }
    });
  }

  void _updateCart(String id, Map<String, dynamic> data, double qty) {
    if (!mounted) return;

    final currentQtyInCart = cartNotifier.value[id]?['quantity'] ?? 0.0;
    bool isTrackingEnabled = _settings?.isInventoryTrackingEnabled ?? true;

    if (isTrackingEnabled && qty > currentQtyInCart && !id.startsWith('custom_')) {
      double stock = inventoryNotifier.value[id] ?? (data['stockQuantity'] as num? ?? 0.0).toDouble();

      if (qty > stock) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("⚠️ الصنف (${data['name']}) مخلص أو الكمية غير كافية في المخزن (المتوفر: $stock)"), backgroundColor: Colors.red, duration: const Duration(seconds: 2))
        );
        return;
      }

      if (data['ingredients'] != null && data['ingredients'] is List) {
        for (var ing in (data['ingredients'] as List)) {
          String ingId = ing['id'];
          double needed = (ing['amount'] as num? ?? 0.0).toDouble() * qty;
          double available = inventoryNotifier.value[ingId] ?? 0.0;
          if (needed > available) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("⚠️ المكونات غير كافية لتحضير الطلب: ${ing['name']}"), backgroundColor: Colors.orange)
            );
            return;
          }
        }
      }
    }

    final currentCart = Map<String, Map<String, dynamic>>.from(cartNotifier.value);
    if (qty <= 0) {
      currentCart.remove(id);
    } else {
      double price = (double.tryParse(data['price'].toString()) ?? 0.0);
      double taxPercent = (double.tryParse(data['tax']?.toString() ?? "0") ?? 0.0);
      double extraCosts = (double.tryParse(data['extraCosts']?.toString() ?? "0") ?? 0.0);

      double costAtSale = (double.tryParse(data['lastCostPrice']?.toString() ?? "") ??
                           double.tryParse(data['costPrice']?.toString() ?? "0") ?? 0.0);

      double baseWithExtra = price + extraCosts;
      double totalWithTax = baseWithExtra * (1 + (taxPercent / 100));

      String time = intl.DateFormat('yyyy/MM/dd hh:mm a').format(DateTime.now());

      currentCart[id] = {
        ...data,
        'quantity': qty,
        'price': price,
        'costPrice': costAtSale,
        'costPriceAtSale': costAtSale,
        'tax': taxPercent,
        'extraCosts': extraCosts,
        'extraDetails': data['extraDetails'] ?? "",
        'id': id,
        'total': totalWithTax * qty,
        'added_at': currentCart[id]?['added_at'] ?? time,
      };
    }
    cartNotifier.value = currentCart;
  }

  void _clearAndCloseTable() async {
    final bool isTakeaway = widget.tableId == "takeaway";

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(isTakeaway ? "تفريغ السلة" : "تصفير الطاولة"),
          content: Text(isTakeaway
              ? "هل أنت متأكد من مسح جميع الأصناف وبيانات الزبون الحالية؟"
              : "سيتم حذف جميع الطلبات غير المدفوعة وتصفير العداد وإغلاق الطاولة نهائياً. هل أنت متأكد؟"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: Text(isTakeaway ? "تفريغ" : "تأكيد التصفير", style: const TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      if (isTakeaway) {
        cartNotifier.value = {};
        _nameController.clear();
        _phoneController.clear();
        _barcodeInputController.clear();
        _receivedAmountController.clear();
        _selectedCustomerId = null;
        _selectedCustomerBalance = null;
        _selectedCustomerLimit = null;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم تفريغ السلة والبيانات"), backgroundColor: Colors.blue));
      } else {
        final String cafeId = _activeCafeId ?? widget.currentUser.cafeId;
        final String managerId = widget.currentUser.parentId ?? widget.currentUser.id;
        try {
          await OrderService.clearTable(
            tableId: widget.tableId,
            tableName: widget.tableName,
            cafeId: cafeId,
            managerId: managerId, currentUser: widget.currentUser,
          );
          if (!mounted) return;
          cartNotifier.value = {};
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم تصفير الطاولة وإغلاقها"), backgroundColor: Colors.green));
          _onBackTap();
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ خطأ في النظام: $e"), backgroundColor: Colors.red));
        }
      }
    }
  }

  void _showCustomOrderDialog() {
    final nameC = TextEditingController();
    final priceC = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [Icon(Icons.add_shopping_cart, color: Colors.blue), SizedBox(width: 10), Text("طلب يدوي")]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: "التفاصيل (اسم الطلب)",
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.edit_note),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: priceC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: "السعر",
                  suffixText: "₪",
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.monetization_on_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[900],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                final name = nameC.text.trim();
                final price = double.tryParse(priceC.text.trim()) ?? 0.0;
                if (name.isNotEmpty && price > 0) {
                  final String customId = "custom_${DateTime.now().millisecondsSinceEpoch}";
                  _updateCart(customId, {
                    'name': name,
                    'price': price,
                    'costPrice': 0.0,
                    'category': 'يدوي',
                    'image': '',
                  }, 1);
                  Navigator.pop(ctx);
                }
              },
              child: const Text("إضافة للسلة", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showMergeDialog() {
    final busyTables = _allTables.where((t) => t['is_open'] == true && t['id'] != widget.tableId).toList();

    if (busyTables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("لا توجد طاولات أخرى مشغولة لدمجها")));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [Icon(Icons.merge_type, color: Colors.blueGrey), SizedBox(width: 8), Text("دمج حساب طاولة أخرى")]),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: busyTables.length,
              itemBuilder: (context, index) {
                final table = busyTables[index];
                return ListTile(
                  leading: const Icon(Icons.table_bar, color: Colors.orange),
                  title: Text(table['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text("سحب جميع الطلبات إلى هذه الفاتورة", style: TextStyle(fontSize: 11)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    _confirmMerge(table['id'], table['name']);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _confirmMerge(String sourceId, String sourceName) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text("تأكيد الدمج"),
          content: Text("هل أنت متأكد من نقل حساب ($sourceName) إلى (${widget.tableName})؟ سيتم إغلاق طاولة $sourceName."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("تأكيد النقل", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );

    if (confirm == true) {
      try {
        await OrderService.mergeTables(
          sourceTableId: sourceId,
          sourceTableName: sourceName,
          targetTableId: widget.tableId,
          targetTableName: widget.tableName,
          cafeId: _activeCafeId ?? widget.currentUser.cafeId,
          currentUser: widget.currentUser,
        );
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم دمج الطاولات بنجاح"), backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ خطأ: $e")));
      }
    }
  }

  void _showTransferSingleItemDialog(Map<String, dynamic> item) {
    String? selectedTargetTable;
    double qtyToMove = (item['quantity'] as num).toDouble();
    double maxQty = qtyToMove;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (contextDialog, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text("نقل الصنف لطاولة أخرى"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("الصنف: ${item['name']}"),
                const SizedBox(height: 15),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('tables')
                      .where('cafe_id', isEqualTo: _activeCafeId)
                      .snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const CircularProgressIndicator();
                    final tables = snap.data!.docs.where((d) {
                       final data = d.data() as Map;
                       return data['name'] != widget.tableName;
                    }).toList();

                    if (tables.isEmpty) return const Text("لا توجد طاولات أخرى متاحة");

                    return DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: AppComponents.fieldInput("اختر الطاولة الهدف", Icons.table_restaurant),
                      items: tables.map((t) {
                        final name = (t.data() as Map)['name'].toString();
                        return DropdownMenuItem(value: name, child: Text(name));
                      }).toList(),
                      onChanged: (v) => setDialogState(() => selectedTargetTable = v),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: qtyToMove > 1 ? () => setDialogState(() => qtyToMove -= 1) : null),
                    Text(qtyToMove.toStringAsFixed(0), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: qtyToMove < maxQty ? () => setDialogState(() => qtyToMove += 1) : null),
                  ],
                ),
                Text("من أصل $maxQty", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ElevatedButton(
                onPressed: (selectedTargetTable != null) ? () async {
                  try {
                    Navigator.pop(ctx);
                    final List<Map<String, dynamic>> itemsToTransfer = [
                      {
                        ...item,
                        'quantity': qtyToMove,
                        'total': qtyToMove * (item['price'] as num).toDouble(),
                      }
                    ];
                    await OrderService.transferItems(
                      sourceOrderId: item['orderId'],
                      targetTableName: selectedTargetTable!,
                      itemsToTransfer: itemsToTransfer,
                      currentUser: widget.currentUser,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم نقل الصنف بنجاح"), backgroundColor: Colors.green));
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ خطأ: $e"), backgroundColor: Colors.red));
                    }
                  }
                } : null,
                child: const Text("تأكيد النقل"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onBackTap() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomePage(currentUser: widget.currentUser)));
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _debounce?.cancel();
    _timerTick?.cancel();
    _searchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _receivedAmountController.dispose();
    _barcodeInputController.dispose();
    _barcodeFieldFocusNode.dispose();
    _tabController?.dispose();
    _settingsSub?.cancel();
    _inventorySub?.cancel();
    _debtSub?.cancel();
    _tablesSub?.cancel();
    _productsSub?.cancel();
    _tableSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.currentUser.canRead('orders')) {
      return const Scaffold(body: Center(child: Text("عذراً، لا تملك صلاحية الوصول لصفحة الطلبات", style: TextStyle(fontWeight: FontWeight.bold))));
    }
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth > 800;

        return Scaffold(
          backgroundColor: const Color(0xFFF0F2F5),
          body: Row(children: [
            Expanded(
              flex: 3,
              child: Column(children: [
                _buildDashboardHeader(theme),
                _buildSearchBox_withBarcode(),
                Expanded(child: _buildProductSection()),
              ]),
            ),
            if (isWide)
              Container(
                width: 360,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(right: BorderSide(color: Colors.black12)),
                ),
                child: _buildInvoiceSide(),
              ),
          ]),
          floatingActionButton: (!isWide && (widget.currentUser.canPayOrders || widget.currentUser.canMakeOrders)) ? ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
            valueListenable: cartNotifier,
            builder: (context, cart, _) {
              if (cart.isEmpty && widget.tableId == "takeaway") return const SizedBox.shrink();
              return FloatingActionButton.extended(
                onPressed: () => _showMobileInvoice(),
                label: Text("الفاتورة (${cart.length})"),
                icon: const Icon(Icons.shopping_basket),
                backgroundColor: Colors.blue[900],
              );
            },
          ) : null,
        );
      }
    );
  }

  Widget _buildDashboardHeader(ThemeData theme) {
    final double topPad = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad > 10 ? topPad + 5 : 25, 16, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [theme.primaryColor, theme.primaryColor.withBlue(200)]),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
        boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))]
      ),
      child: Column(
        children: [
          Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20), onPressed: _onBackTap),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.tableName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                _buildScannerStatus(),
              ],
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 28),
              onPressed: _openCameraScanner,
              tooltip: "فتح الكاميرا للمسح"
            ),
            if (widget.currentUser.canDeleteOrders)
              IconButton(
                icon: const Icon(Icons.delete_sweep, color: Colors.white),
                onPressed: _clearAndCloseTable,
                tooltip: "تفريغ الفاتورة"
              ),
          ]),
          const SizedBox(height: 15),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
              valueListenable: cartNotifier,
              builder: (context, cart, _) => _dashboardStat("الأصناف", "${cart.length}", Icons.shopping_cart, Colors.greenAccent),
            ),
            ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
              valueListenable: cartNotifier,
              builder: (context, cart, _) {
                double total = cart.values.fold(0.0, (acc, item) => acc + (item['total'] ?? 0));
                if (widget.tableId != "takeaway") {
                  total += _currentTimerPrice;
                }
                return _dashboardStat("إجمالي الحساب", "${total.round()}", Icons.payments, Colors.orangeAccent);
              }
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildScannerStatus() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Container(
              width: 7, height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isScannerConnected ? Colors.greenAccent : Colors.white24,
                boxShadow: _isScannerConnected ? [
                  BoxShadow(
                    color: Colors.greenAccent.withOpacity(0.4 * _pulseController.value),
                    blurRadius: 10, spreadRadius: 3,
                  )
                ] : null,
              ),
            );
          },
        ),
        const SizedBox(width: 5),
        Text(
          _isScannerConnected ? "جاهز للمسح" : "بانتظار تفعيل البحث",
          style: TextStyle(
            color: _isScannerConnected ? Colors.greenAccent : Colors.white60,
            fontSize: 9, fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _dashboardStat(String label, String value, IconData icon, Color col) {
    return Column(children: [
      Row(children: [Icon(icon, color: col, size: 14), const SizedBox(width: 4), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11))]),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildSearchBox_withBarcode() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "بحث بالاسم...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: TextField(
              controller: _barcodeInputController,
              focusNode: _barcodeFieldFocusNode,
              onSubmitted: _onBarcodeScanned,
              decoration: InputDecoration(
                hintText: "الباركود...",
                prefixIcon: Icon(
                  Icons.barcode_reader,
                  color: _isScannerConnected ? Colors.green : Colors.blueGrey[300],
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.camera_alt, color: Colors.blue, size: 18),
                  onPressed: _openCameraScanner,
                ),
                filled: true,
                fillColor: _isScannerConnected ? Colors.green[50] : Colors.blue[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _isScannerConnected ? Colors.green.withOpacity(0.2) : Colors.blue.withOpacity(0.1))
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductSection() {
    final allDocs = _allProducts;
    final categories = [
      "الكل",
      ...allDocs
          .map((d) => (d.data() as Map)['category']?.toString() ?? "عام")
          .toSet()
          .toList()
        ..sort()
    ];

    if (_tabController == null || _tabController!.length != categories.length) {
      _tabController?.dispose();
      _tabController = TabController(length: categories.length, vsync: this);
    }

    return Column(children: [
      TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: Colors.blue[900],
        unselectedLabelColor: Colors.grey,
        indicatorColor: Colors.blue[900],
        tabs: categories.map((cat) => Tab(text: cat)).toList(),
      ),
      Expanded(
        child: TabBarView(
          controller: _tabController,
          children: categories.map<Widget>((cat) => CategoryGridView(
            category: cat,
            allDocs: allDocs,
            searchNotifier: searchNotifier,
            cartNotifier: cartNotifier,
            inventoryNotifier: inventoryNotifier,
            onProductTap: (id, data, q) => _updateCart(id, data, q),
            onProductLongPress: (id, data) {
              if (widget.currentUser.canEditMenu) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddProduct(
                      currentUser: widget.currentUser,
                      productToEdit: {'id': id, ...data},
                    ),
                  ),
                );
              }
            },
          )).toList(),
        ),
      ),
    ]);
  }

  Widget _buildInvoiceSide() {
    return StreamBuilder<QuerySnapshot>(
      stream: _pendingOrdersStream,
      builder: (context, snapshot) {
        List<Map<String, dynamic>> previousItems = [];
        double previousTotal = 0;

        if (snapshot.hasData) {
          final docs = snapshot.data!.docs.toList();
          docs.sort((a, b) {
            final t1 = (a.data() as Map<String, dynamic>)['ordered_at'] as Timestamp?;
            final t2 = (b.data() as Map<String, dynamic>)['ordered_at'] as Timestamp?;
            if (t1 == null) return 1;
            if (t2 == null) return -1;
            return t1.compareTo(t2);
          });

          for (var doc in docs) {
            var data = doc.data() as Map<String, dynamic>;
            var items = data['items'] as List? ?? [];
            for (var it in items) {
              final itemMap = Map<String, dynamic>.from(it);
              itemMap['orderId'] = doc.id;
              previousItems.add(itemMap);
            }
            previousTotal += (data['total'] as num? ?? 0).toDouble();
          }
        }

        return Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.blue),
                const SizedBox(width: 8),
                const Text("تفاصيل الفاتورة", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (widget.currentUser.canMakeOrders && widget.tableId != "takeaway")
                   IconButton(
                    icon: const Icon(Icons.merge_type, color: Colors.blueGrey),
                    onPressed: _showMergeDialog,
                    tooltip: "دمج حساب طاولة أخرى",
                  ),
                if (widget.currentUser.canMakeOrders)
                  TextButton.icon(
                    onPressed: _showCustomOrderDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text("يدوي", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(foregroundColor: Colors.blue[900]),
                  )
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: ListView(
            children: [
              if (_currentTimerPrice > 0.01) ...[
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.timer_outlined, color: Colors.orange, size: 20),
                  title: const Text("رسوم الوقت / الشحن", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  trailing: Text("${_currentTimerPrice.round()} ₪", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                ),
                const Divider(),
              ],

              if (previousItems.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.history, size: 16, color: Colors.grey),
                      SizedBox(width: 5),
                      Text("طلبات سابقة (موجودة)", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ),
                ...previousItems.map((item) => ListTile(
                  dense: true,
                  title: Text(item['name'], style: const TextStyle(color: Colors.black54)),
                  subtitle: Text("${item['price']} ₪ x ${item['quantity']} | ${item['added_at'] ?? ''}", style: const TextStyle(fontSize: 11)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("${(item['total'] ?? 0).round()} ₪", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      if (item['orderId'] != null)
                        IconButton(
                          icon: const Icon(Icons.move_up_rounded, color: Colors.blue, size: 18),
                          onPressed: () => _showTransferSingleItemDialog(item),
                          tooltip: "نقل هذا صنف",
                        ),
                    ],
                  ),
                )),
                const Divider(),
              ],

              ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
                valueListenable: cartNotifier,
                builder: (context, cart, _) {
                  if (cart.isEmpty && previousItems.isEmpty && _currentTimerPrice < 0.01) return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("السلة فارغة", style: TextStyle(color: Colors.grey))));

                  return Column(
                    children: cart.entries.map((entry) {
                      final item = entry.value;
                      final id = entry.key;
                      return ListTile(
                        dense: true,
                        title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text("${item['price']} ₪ x ${item['quantity']}"),
                                if ((item['tax'] ?? 0) > 0 || (item['extraCosts'] ?? 0) > 0) ...[
                                  const SizedBox(width: 5),
                                  GestureDetector(
                                    onTap: () {
                                      AppComponents.showAppDialog(
                                        context: context,
                                        title: "تفاصيل التكاليف لـ ${item['name']}",
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text("السعر الأساسي: ${item['price']} ₪"),
                                            if ((item['tax'] ?? 0) > 0) Text("الضريبة: ${item['tax']}%"),
                                            if ((item['extraCosts'] ?? 0) > 0) Text("تكاليف إضافية: ${item['extraCosts']} ₪"),
                                            if (item['extraDetails'] != null && item['extraDetails'].toString().isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 8.0),
                                                child: Text("ملاحظات: ${item['extraDetails']}", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                              ),
                                          ],
                                        ),
                                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء"))]
                                      );
                                    },
                                    child: const Icon(Icons.info_outline, size: 14, color: Colors.orange),
                                  ),
                                ]
                              ],
                            ),
                            if (item['added_at'] != null)
                              Text(item['added_at'], style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text("${item['total'].round()} ₪", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 4),
                          IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 20), onPressed: () => _updateCart(id, item, item['quantity'] + 1)),
                          IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20), onPressed: () => _updateCart(id, item, item['quantity'] - 1)),
                        ]),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          )),
          _buildCheckoutSection(previousTotal),
        ]);
      }
    );
  }

  Widget _buildCheckoutSection(double previousTotal) {
    return ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
        valueListenable: cartNotifier,
        builder: (context, cart, _) {
          double subTotal = cart.values.fold(0.0, (acc, item) => acc + (item['total'] ?? 0));
          double grandTotal = subTotal + previousTotal + _currentTimerPrice;
          final bool isTakeaway = widget.tableId == "takeaway";

          final bool canShowPayment = widget.currentUser.canPayOrders && (
            widget.currentUser.role == UserRole.super_admin ||
            widget.currentUser.role == UserRole.admin ||
            widget.currentUser.role == UserRole.manager ||
            widget.currentUser.role == UserRole.cashier ||
            widget.currentUser.role == UserRole.custom
          );

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("إجمالي الحساب:", style: TextStyle(fontSize: 16)), Text("${grandTotal.round()} ₪", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue[900]))]),
              const SizedBox(height: 16),
              if (!isTakeaway && widget.currentUser.canMakeOrders) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  onPressed: cart.isEmpty ? null : () => _submitOrder("pending", subTotal),
                  icon: const Icon(Icons.table_bar),
                  label: const Text("إضافة للطاولة / إرسال", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 10),
              ],
              if (canShowPayment)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  onPressed: (cart.isEmpty && previousTotal == 0 && _currentTimerPrice == 0) ? null : () => _showPaymentDialog(grandTotal),
                  icon: const Icon(Icons.check_circle),
                  label: Text(isTakeaway ? "إتمام ودفع" : "دفع وإغلاق الطاولة", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                )
            ]),
          );
        }
    );
  }

  void _showMobileInvoice() {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (_) => Container(height: MediaQuery.of(context).size.height * 0.8, child: _buildInvoiceSide()));
  }

  void _showPaymentDialog(double total) {
    List<Map<String, dynamic>> payers = [
      {
        'nameController': TextEditingController(text: _nameController.text),
        'phoneController': TextEditingController(text: _phoneController.text),
        'amountController': TextEditingController(text: total.round().toString()),
        'method': "كاش",
        'id': _selectedCustomerId,
        'balance': _selectedCustomerBalance,
        'limit': _selectedCustomerLimit,
      }
    ];

    String? surplusRecipientId;
    String? surplusRecipientName;
    String? surplusRecipientPhone;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (contextDialog, setDialogState) {
          double totalReceived = 0;
          for (var p in payers) {
            totalReceived += double.tryParse(p['amountController'].text.trim()) ?? 0.0;
          }

          double balance = totalReceived - total;
          double remaining = total - totalReceived;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text("إتمام الدفع (تقسيم على أشخاص)", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),

                  ...payers.asMap().entries.map((entry) {
                    int idx = entry.key;
                    var p = entry.value;
                    return _buildPayerInputBlock(idx, p, remaining, setDialogState, contextDialog);
                  }),

                  const SizedBox(height: 10),

                  ElevatedButton.icon(
                    onPressed: () {
                      setDialogState(() {
                        payers.add({
                          'nameController': TextEditingController(),
                          'phoneController': TextEditingController(),
                          'amountController': TextEditingController(text: remaining > 0 ? remaining.round().toString() : "0"),
                          'method': "كاش",
                          'id': null,
                          'balance': null,
                          'limit': null,
                        });
                      });
                    },
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text("إضافة شخص آخر للدفع"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[50],
                      foregroundColor: Colors.blue[900],
                      elevation: 0,
                      minimumSize: const Size(double.infinity, 45),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                  ),

                  const Divider(height: 20),
                  const Row(
                    children: [
                      Icon(Icons.person_add_alt, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Text("إضافة الرصيد المتبقي في رصيد الصديق (اختياري)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Autocomplete<Map<String, String>>(
                    displayStringForOption: (option) => option['name']!,
                    optionsBuilder: (textEditingValue) {
                      if (textEditingValue.text.isEmpty) return const Iterable.empty();
                      final q = textEditingValue.text.toLowerCase();
                      return _customerSuggestions.where((c) => c['name']!.toLowerCase().contains(q));
                    },
                    onSelected: (selection) {
                      setDialogState(() {
                        surplusRecipientId = selection['id'];
                        surplusRecipientName = selection['name'];
                        surplusRecipientPhone = selection['phone'];
                      });
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: AppComponents.fieldInput("ابحث عن صديق لتحويل الفائض له...", Icons.person_search),
                      );
                    },
                  ),
                  if (surplusRecipientName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Chip(
                        label: Text("الفائض سيذهب لـ: $surplusRecipientName", style: const TextStyle(fontSize: 11)),
                        onDeleted: () => setDialogState(() {
                          surplusRecipientId = null;
                          surplusRecipientName = null;
                        }),
                        backgroundColor: Colors.orange[50],
                      ),
                    ),

                  const Divider(height: 30),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: balance >= 0 ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: balance >= 0 ? Colors.green[100]! : Colors.red[100]!)
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(balance >= 0 ? "يتبقى له (رصيد):" : "يتبقى عليه (دين):", style: TextStyle(fontWeight: FontWeight.bold, color: balance >= 0 ? Colors.green[800] : Colors.red[800])),
                        Text("${balance.abs().round()} ₪", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: balance >= 0 ? Colors.green[800] : Colors.red[800])),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                    ),
                    onPressed: () => _handleMultiPayerSubmission(
                      context, total, totalReceived, payers, ctx,
                      friendId: surplusRecipientId,
                      friendName: surplusRecipientName,
                      friendPhone: surplusRecipientPhone
                    ),
                    icon: const Icon(Icons.check_circle),
                    label: const Text("تأكيد العملية وتسجيل الحوالات", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),

                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("إلغاء", style: TextStyle(color: Colors.grey)),
                  ),
                ]),
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildPayerInputBlock(int index, Map<String, dynamic> p, double remaining, StateSetter setDialogState, BuildContext ctx) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: index == 0 ? Colors.blue.withOpacity(0.03) : Colors.grey[50],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: index == 0 ? Colors.blue[100]! : Colors.grey[200]!)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Border_Wrapper(index),
          const SizedBox(height: 8),
          Autocomplete<Map<String, String>>(
            displayStringForOption: (option) => option['name']!,
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) return const Iterable.empty();
              final q = textEditingValue.text.toLowerCase();
              return _customerSuggestions.where((c) => c['name']!.toLowerCase().contains(q) || c['phone']!.contains(q));
            },
            onSelected: (selection) {
              setDialogState(() {
                p['nameController'].text = selection['name']!;
                p['phoneController'].text = selection['phone'] ?? "";
                p['id'] = selection['id'];
                p['balance'] = selection['debt'];
                p['limit'] = double.tryParse(selection['limit'] ?? "0") ?? 0;
              });
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              if (controller.text.isEmpty && p['nameController'].text.isNotEmpty) {
                controller.text = p['nameController'].text;
              }
              return TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: (v) => setDialogState(() {
                  p['nameController'].text = v;
                  p['id'] = null;
                }),
                decoration: AppComponents.fieldInput("اسم الزبون...", Icons.person_outline),
              );
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: p['phoneController'],
            keyboardType: TextInputType.phone,
            decoration: AppComponents.fieldInput("رقم الهاتف", Icons.phone_android_outlined),
          ),
          if (p['balance'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text("الرصيد الحالي: ${p['balance']} ₪ ${p['limit'] != null && p['limit'] > 0 ? '(الحد: ${p['limit']})' : ''}",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: (double.tryParse(p['balance']?.toString() ?? "0") ?? 0) > 0 ? Colors.red[800] : Colors.blueGrey
                        )),
                      const SizedBox(width: 8),
                      if ((double.tryParse(p['balance']?.toString() ?? "0") ?? 0) > 0)
                        TextButton.icon(
                          onPressed: () {
                            setDialogState(() {
                              double currentDebt = double.tryParse(p['balance'].toString()) ?? 0.0;
                              double currentAmt = double.tryParse(p['amountController'].text.trim()) ?? 0.0;
                              p['amountController'].text = (currentAmt + currentDebt).round().toString();
                            });
                          },
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          icon: const Icon(Icons.add_circle_outline, size: 14),
                          label: const Text("دفع مع الدين السابق", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: p['amountController'],
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setDialogState(() {}),
                  decoration: AppComponents.fieldInput("المبلغ", Icons.payments_outlined),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[900], foregroundColor: Colors.white),
                onPressed: () {
                  double currentVal = double.tryParse(p['amountController'].text.trim()) ?? 0.0;
                  double needed = remaining + currentVal;
                  p['amountController'].text = needed > 0 ? needed.round().toString() : "0";
                  setDialogState(() {});
                },
                child: const Text("باقي"),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _paymentMethods.where((m) => m != "دين" || widget.currentUser.canManageDebts).map((m) {
                bool isSelected = p['method'] == m;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text(m, style: TextStyle(color: isSelected ? Colors.white : Colors.black, fontSize: 12)),
                    selected: isSelected,
                    selectedColor: m == "دين" ? Colors.orange[900] : Colors.blue[900],
                    onSelected: (v) => setDialogState(() => p['method'] = m),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget Border_Wrapper(int index) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(index == 0 ? "المسدد الأساسي" : "مشارك دفع #${index + 1}",
          style: TextStyle(fontWeight: FontWeight.bold, color: index == 0 ? Colors.blue[900] : Colors.black87)),
      ],
    );
  }

  Future<void> _handleMultiPayerSubmission(
    BuildContext context, double total, double totalReceived, List<Map<String, dynamic>> payers, BuildContext ctx,
    {String? friendId, String? friendName, String? friendPhone}
  ) async {
    for (var p in payers) {
      if (p['method'] == "دين" && p['limit'] != null && p['limit'] > 0) {
        double amt = double.tryParse(p['amountController'].text.trim()) ?? 0;
        double cur = double.tryParse(p['balance']?.toString() ?? "0") ?? 0;
        if ((cur + amt) > p['limit']) {
          bool? allow = await showDialog<bool>(
            context: context,
            builder: (c) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text("⚠️ تجاوز الحد الائتماني"),
                content: Text("الحساب (${p['nameController'].text}) سيتجاوز الحد المسموح به (${p['limit']} ₪).\nالمديونية الإجمالية ستصبح: ${(cur + amt).round()} ₪.\nهل تريد المتابعة؟"),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("إلغاء")),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("نعم، متابعة")),
                ],
              ),
            ),
          );
          if (allow != true) return;
        }
      }
    }

    double diff = total - totalReceived;
    String mainCustomer = payers[0]['nameController'].text.trim();
    if (diff != 0 && mainCustomer.isNotEmpty && mainCustomer != "زبون عام") {
       String title = diff > 0 ? "تأكيد تسجيل متبقي (دين)" : "تأكيد تسجيل فائض (رصيد)";
       String content = diff > 0
          ? "يوجد مبلغ متبقي ${diff.round()} ₪ لم يغطى. هل تريد تسجيله كدين إضافي على $mainCustomer؟"
          : "يوجد مبلغ زائد ${diff.abs().round()} ₪. هل تريد تسجيله كرصيد؟";

       bool? confirm = await showDialog<bool>(
         context: context,
         builder: (c) => Directionality(
           textDirection: TextDirection.rtl,
           child: AlertDialog(
             title: Text(title),
             content: Text(content),
             actions: [
               TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("تجاهل الفرق")),
               TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("تأكيد التسجيل في الديون")),
             ],
           ),
         ),
       );
       if (confirm == null) return;
       if (ctx.mounted) Navigator.pop(ctx);
       _submitOrderMultiPayer(total, totalReceived, payers, confirm, friendId: friendId, friendName: friendName, friendPhone: friendPhone);
       return;
    }

    if (ctx.mounted) Navigator.pop(ctx);
    _submitOrderMultiPayer(total, totalReceived, payers, true, friendId: friendId, friendName: friendName, friendPhone: friendPhone);
  }

  void _submitOrderMultiPayer(
    double total, double totalReceived, List<Map<String, dynamic>> payers, bool recordBalanceChange,
    {String? friendId, String? friendName, String? friendPhone}
  ) async {
    final String cafeId = _activeCafeId ?? widget.currentUser.cafeId;

    try {
      final result = await OrderService.submitOrder(
        context: context, currentUser: widget.currentUser, tableId: widget.tableId, tableName: widget.tableName,
        method: "دين", itemsList: cartNotifier.value.values.toList(), finalTotal: total.roundToDouble(),
        customerName: payers[0]['nameController'].text.trim().isEmpty ? "زبون عام" : payers[0]['nameController'].text.trim(),
        customerPhone: payers[0]['phoneController'].text.trim(),
        selectedCustomerId: payers[0]['id'], autoStartTimer: false,
        skipSync: true, skipPaymentRecord: true,
        timerPrice: _currentTimerPrice,
      );

      final List allItems = result['items'] ?? [];
      String itemsSummary = allItems.map((it) => "${it['quantity'] ?? 1}x ${it['name'] ?? 'صنف'}").join("، ");
      double remainingInvoice = total;

      for (int i = 0; i < payers.length; i++) {
        var p = payers[i];
        double totalAmt = (double.tryParse(p['amountController'].text.trim()) ?? 0).roundToDouble();
        if (totalAmt <= 0 && p['method'] != "دين") continue;

        String pName = p['nameController'].text.trim().isEmpty ? "زبون عام" : p['nameController'].text.trim();
        String pPhone = p['phoneController'].text.trim();
        String? pId = p['id'];
        String pMethod = p['method'];

        if (pMethod.contains( "دين")||pMethod.contains('ديون')) {
          remainingInvoice -= totalAmt;
          await TransferService.performSave(
            context: context,
            currentUser: widget.currentUser,
            customerName: pName,
            phone: pPhone,
            amt: totalAmt,
            method: pMethod,
            items: allItems,
            selectedDebtId: pId,
            cafeId: cafeId,
            table: widget.tableName,
            note: "فاتورة ${widget.tableName}: $itemsSummary",
            skipSync: false,
          );
        } else {
          double contribution = 0;
          double surplus = 0;

          if (remainingInvoice > 0) {
            contribution = totalAmt > remainingInvoice ? remainingInvoice : totalAmt;
            surplus = totalAmt - contribution;
            remainingInvoice -= contribution;
          } else {
            surplus = totalAmt;
          }

          if (contribution > 0) {
            await TransferService.performSave(
              context: context, currentUser: widget.currentUser, customerName: pName,
              phone: pPhone, amt: contribution, method: pMethod,
              cafeId: cafeId, isDebtPayment: false, selectedDebtId: pId,
              table: widget.tableName, note: "مشاركة دفع (${widget.tableName}): $itemsSummary",
              skipSync: true,
              items: i == 0 ? allItems : [],
            );
          }

          if (surplus > 0) {
            String recipientName = (friendName != null && friendName.isNotEmpty) ? friendName : pName;
            String? recipientId = (friendName != null && friendName.isNotEmpty) ? friendId : pId;
            String recipientPhone = (friendName != null && friendName.isNotEmpty) ? (friendPhone ?? "") : pPhone;

            await TransferService.performSave(
              context: context, currentUser: widget.currentUser, customerName: recipientName,
              phone: recipientPhone, amt: surplus, method: pMethod,
              cafeId: cafeId, isDebtPayment: recordBalanceChange, selectedDebtId: recipientId,
              table: widget.tableName, note: "سداد رصيد زائد من فاتورة ${widget.tableName}${friendName != null ? ' (دفع بواسطة $pName)' : ''}",
              skipSync: !recordBalanceChange,
              items: [],
            );
          }
        }
      }

      if (remainingInvoice > 0.01 && recordBalanceChange) {
        String mainCustomer = payers[0]['nameController'].text.trim();
        String mainPhone = payers[0]['phoneController'].text.trim();
        if (mainCustomer != "زبون عام") {
          await TransferService.syncWithDebts(
            currentUser: widget.currentUser, customerInput: mainCustomer, phone: mainPhone,
            amount: remainingInvoice, cafeId: cafeId, selectedId: payers[0]['id'],
            isAddingDebt: true,
            type: "باقي فاتورة",
            note: "باقي فاتورة ${widget.tableName}: $itemsSummary",
            items: allItems,
          );
        }
      }

      _clearUIAndPop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تمت العملية بنجاح وترحيل الأصناف لسجل الديون"), backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint("Error in multi-payer submission: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ خطأ: $e"), backgroundColor: Colors.red));
    }
  }

  void _submitOrder(String method, double total) async {
    final cart = cartNotifier.value;
    try {
      await OrderService.submitOrder(
        context: context,
        currentUser: widget.currentUser,
        tableId: widget.tableId,
        tableName: widget.tableName,
        method: method,
        itemsList: cart.values.toList(),
        finalTotal: total.roundToDouble(),
        customerName: _nameController.text.isEmpty ? "زبون عام" : _nameController.text,
        customerPhone: _phoneController.text.trim(),
        selectedCustomerId: _selectedCustomerId,
        autoStartTimer: false,
        timerPrice: _currentTimerPrice,
      );
      _clearUIAndPop();
    } catch (e) {
      debugPrint("Order Submission Error: $e");
    }
  }

  void _clearUIAndPop() {
    if (!mounted) return;
    cartNotifier.value = {};
    _nameController.clear();
    _phoneController.clear();
    _receivedAmountController.clear();
    _barcodeInputController.clear();
    _selectedCustomerId = null;
    _selectedCustomerBalance = null;
    _selectedCustomerLimit = null;
    _onBackTap();
  }
}
