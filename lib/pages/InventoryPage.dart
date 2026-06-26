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
      floatingActionButton: widget.currentUser.canCreate('inventory') ? FloatingActionButton.extended(
        onPressed: () => InventoryDialogs.showAddInventoryItem(context: context, currentUser: widget.currentUser),
        backgroundColor: theme.primaryColor,
        icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
        label: const Text("إضافة صنف مخزني", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ) : null,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey[100]!))),
            child: Row(
              children: [
                Text("مخزن المحل", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: AppComponents.fieldInput("بحث عن صنف...", Icons.search).copyWith(contentPadding: const EdgeInsets.symmetric(vertical: 0)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: _searchQueryNotifier,
              builder: (context, query, _) {
                return _InventoryGrid(searchQuery: query, managerId: managerId, currentUser: widget.currentUser, dbHelper: _dbHelper);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryGrid extends StatefulWidget {
  final String searchQuery;
  final String managerId;
  final User currentUser;
  final DatabaseHelper dbHelper;

  const _InventoryGrid({required this.searchQuery, required this.managerId, required this.currentUser, required this.dbHelper});

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

        if (docs.isEmpty) return const Center(child: Text("لا توجد نتائج"));

        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 250, childAspectRatio: 0.75, crossAxisSpacing: 15, mainAxisSpacing: 15),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _buildItemCard(docs[index].id, docs[index].reference, data);
          },
        );
      },
    );
  }

  Widget _buildItemCard(String docId, DocumentReference ref, Map<String, dynamic> data) {
    double qty = (data['quantity'] ?? 0.0).toDouble();
    bool isLow = qty <= (data['low_stock_threshold'] ?? 5.0).toDouble();
    
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isLow ? Colors.red.shade100 : Colors.grey[200]!)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: isLow ? Colors.red[50] : Colors.blue[50], shape: BoxShape.circle),
            child: Icon(Icons.inventory_2_rounded, size: 30, color: isLow ? Colors.red : Colors.blue),
          ),
          const SizedBox(height: 10),
          Text(data['name'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text("${qty} ${data['unit'] ?? ''}", style: TextStyle(color: isLow ? Colors.red[900] : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12)),
          const Divider(),
          // الأزرار التفاعلية - محمية بالصلاحيات
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // زر التحويل للمنيو (بيع الصنف)
              if (widget.currentUser.canUpdate('menu'))
                IconButton(
                  tooltip: "عرض للبيع في المنيو",
                  icon: const Icon(Icons.sell_outlined, color: Colors.orange, size: 20),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => AddProduct(
                      currentUser: widget.currentUser,
                      productToEdit: {
                        'id': docId,
                        'name': data['name'],
                        'costPrice': data['costPrice'] ?? 0.0,
                        'barcode': data['barcode'] ?? "",
                        'trackInventory': true,
                      },
                    )));
                  }
                ),
              if (widget.currentUser.canUpdate('inventory'))
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 18), 
                  onPressed: () => InventoryDialogs.showEditInventoryItem(context: context, ref: ref, data: data, currentUser: widget.currentUser)
                ),
              if (widget.currentUser.canDelete('inventory'))
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red), 
                  onPressed: () => InventoryDialogs.showConfirmDelete(context: context, ref: ref, name: data['name'] ?? "", currentUser: widget.currentUser)
                ),
            ],
          )
        ],
      ),
    );
  }
}
