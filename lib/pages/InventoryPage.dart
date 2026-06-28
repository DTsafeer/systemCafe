import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/database_helper.dart';
import '../widgets/app_components.dart';
import '../widgets/inventory_dialogs.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import 'addproduct.dart';

class InventoryPage extends StatefulWidget {
  final User currentUser;
  const InventoryPage({super.key, required this.currentUser});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>("");
  Timer? _debounce;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  late String managerId;
  final String currencySymbol = "₪";

  @override
  void initState() {
    super.initState();
    managerId = widget.currentUser.parentId ?? widget.currentUser.id;
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchQueryNotifier.value = query.trim().toLowerCase();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchQueryNotifier.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    
    if (!widget.currentUser.canRead('inventory')) {
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'inventory',
        child: const Scaffold(body: Center(child: Text("عذراً، لا تملك صلاحية لعرض صفحة المخزن"))),
      );
    }

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'inventory',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _buildLuxuryHeader(primaryColor),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: _searchQueryNotifier,
                builder: (context, query, _) {
                  return _InventoryGrid(
                    searchQuery: query, 
                    managerId: managerId, 
                    currentUser: widget.currentUser, 
                    dbHelper: _dbHelper,
                    currencySymbol: currencySymbol,
                  );
                },
              ),
            ),
          ],
        ),
        floatingActionButton: widget.currentUser.canCreate('inventory') ? FloatingActionButton.extended(
          onPressed: () => InventoryDialogs.showAddInventoryItem(context: context, currentUser: widget.currentUser),
          backgroundColor: primaryColor,
          icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
          label: const Text("إضافة صنف", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ) : null,
      ),
    );
  }

  Widget _buildLuxuryHeader(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(25, 45, 25, 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, primaryColor.withOpacity(0.8)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
        boxShadow: [
          BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))
        ],
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
                  Text("مخزن المحل", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  Text("الأصناف المتوفرة للبيع حالياً (Inventory)", style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(15)),
                child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 30),
              ),
            ],
          ),
          const SizedBox(height: 25),
          _buildQuickStats(primaryColor),
          const SizedBox(height: 25),
          _buildSearchField(),
        ],
      ),
    );
  }

  Widget _buildQuickStats(Color primary) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('inventory').where('cafeId', isEqualTo: widget.currentUser.cafeId).snapshots(),
      builder: (context, snapshot) {
        int lowStockCount = 0;
        double totalCostValue = 0;
        double totalExpectedProfit = 0;

        if (snapshot.hasData) {
          final filtered = snapshot.data!.docs.where((doc) => (doc.data() as Map)['parentId'] == managerId);
          for (var doc in filtered) {
            final data = doc.data() as Map<String, dynamic>;
            double qty = (data['quantity'] ?? 0.0).toDouble();
            double cost = (data['lastCostPrice'] ?? data['costPrice'] ?? 0.0).toDouble();
            double sell = (data['sellingPrice'] ?? 0.0).toDouble();
            double threshold = (data['low_stock_threshold'] ?? 5.0).toDouble();
            
            totalCostValue += (qty * cost);
            if (sell > 0) {
              totalExpectedProfit += (qty * (sell - cost));
            }
            if (qty <= threshold) lowStockCount++;
          }
        }
        
        return Row(
          children: [
            _statItem("تكلفة المخزون", "${totalCostValue.toStringAsFixed(0)} $currencySymbol", Icons.account_balance_wallet_outlined),
            const SizedBox(width: 10),
            _statItem("ربح متوقع", "${totalExpectedProfit.toStringAsFixed(0)} $currencySymbol", Icons.trending_up, color: Colors.green[400]),
            const SizedBox(width: 10),
            _statItem("نواقص", lowStockCount.toString(), Icons.warning_amber_rounded, isWarning: lowStockCount > 0),
          ],
        );
      },
    );
  }

  Widget _statItem(String label, String value, IconData icon, {bool isWarning = false, Color? color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isWarning ? Colors.red.withOpacity(0.3) : (color?.withOpacity(0.2) ?? Colors.white.withOpacity(0.15)),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white70, size: 14),
                const SizedBox(width: 5),
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 5),
            FittedBox(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900))),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: _onSearchChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: "بحث عن صنف في المحل...",
        hintStyle: const TextStyle(color: Colors.white60, fontSize: 14),
        prefixIcon: const Icon(Icons.search, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
      ),
    );
  }
}

class _InventoryGrid extends StatefulWidget {
  final String searchQuery;
  final String managerId;
  final User currentUser;
  final DatabaseHelper dbHelper;
  final String currencySymbol;

  const _InventoryGrid({required this.searchQuery, required this.managerId, required this.currentUser, required this.dbHelper, required this.currencySymbol});

  @override
  State<_InventoryGrid> createState() => _InventoryGridState();
}

class _InventoryGridState extends State<_InventoryGrid> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('inventory').where('cafeId', isEqualTo: widget.currentUser.cafeId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['parentId'] != widget.managerId) return false;
          if (widget.searchQuery.isEmpty) return true;
          return data['name'].toString().toLowerCase().contains(widget.searchQuery);
        }).toList();

        if (docs.isEmpty) return _buildEmptyState();

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 280, 
            childAspectRatio: 0.68, // تعديل الارتفاع ليكون أقل
            crossAxisSpacing: 15, 
            mainAxisSpacing: 15
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _buildItemCard(docs[index].id, docs[index].reference, data);
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text("لم يتم العثور على نتائج", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildItemCard(String docId, DocumentReference ref, Map<String, dynamic> data) {
    double qty = (data['quantity'] ?? 0.0).toDouble();
    double cost = (data['lastCostPrice'] ?? data['costPrice'] ?? 0.0).toDouble();
    double sell = (data['sellingPrice'] ?? 0.0).toDouble();
    double profit = sell - cost;
    double threshold = (data['low_stock_threshold'] ?? 5.0).toDouble();
    bool isLow = qty <= threshold;
    double totalCost = qty * cost;
    double totalProfit = qty * profit;
    bool isPriceSet = sell > 0;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: isLow ? Colors.red.withOpacity(0.2) : Colors.transparent, width: 1.5),
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                height: 75, // تصغير ارتفاع الهيدر
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isLow ? Colors.red[50] : Colors.blue[50],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                ),
                child: Icon(Icons.inventory_2_rounded, size: 35, color: isLow ? Colors.red[300] : Colors.blue[300]),
              ),
              if (isLow)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
                    child: const Text("ناقص", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // تقليل الحشو
              child: Column(
                children: [
                  Text(data['name'] ?? "", 
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14), 
                    textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text("$qty ${data['unit'] ?? ''}", 
                    style: TextStyle(color: isLow ? Colors.red : Colors.blue[900], fontWeight: FontWeight.w900, fontSize: 13)),
                  
                  const Spacer(),
                  const Divider(height: 10, thickness: 0.5),
                  
                  _priceRow("تكلفة الوحدة:", "${cost.toStringAsFixed(1)} ${widget.currencySymbol}", Colors.grey[600]!),
                  _priceRow("إجمالي التكلفة:", "${totalCost.toStringAsFixed(1)} ${widget.currencySymbol}", Colors.orange[900]!),
                  _priceRow("سعر البيع:", "${sell.toStringAsFixed(1)} ${widget.currencySymbol}", Colors.blue[800]!),
                  
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: !isPriceSet ? Colors.orange[50] : (profit >= 0 ? Colors.green[50] : Colors.red[50]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: !isPriceSet 
                      ? const Center(child: Text("حدد سعر البيع", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)))
                      : Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("ربح القطعة:", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                              Text("${profit.toStringAsFixed(1)} ${widget.currencySymbol}", 
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: profit >= 0 ? Colors.green[900] : Colors.red[900])),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("إجمالي الربح:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              Text("${totalProfit.toStringAsFixed(1)} ${widget.currencySymbol}", 
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: profit >= 0 ? Colors.green[900] : Colors.red[900])),
                            ],
                          ),
                        ],
                      ),
                  ),
                  
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _actionIcon(Icons.sell_outlined, Colors.orange, () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => AddProduct(
                          currentUser: widget.currentUser,
                          productToEdit: {
                            'id': docId,
                            'name': data['name'],
                            'costPrice': cost,
                            'barcode': data['barcode'] ?? "",
                            'trackInventory': true,
                          },
                        )));
                      }),
                      _actionIcon(Icons.edit_rounded, Colors.blueGrey, () => 
                        InventoryDialogs.showEditInventoryItem(context: context, ref: ref, data: data, currentUser: widget.currentUser)),
                      _actionIcon(Icons.delete_outline_rounded, Colors.red, () => 
                        InventoryDialogs.showConfirmDelete(context: context, ref: ref, name: data['name'] ?? "", currentUser: widget.currentUser)),
                    ],
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _actionIcon(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 17, color: color),
      ),
    );
  }
}
