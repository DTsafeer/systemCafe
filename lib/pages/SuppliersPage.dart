import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import '../services/cafe_service.dart';
import '../widgets/supplier_dialogs.dart';
import 'user_model.dart';
import 'MainLayout.dart';

class SuppliersPage extends StatefulWidget {
  final User currentUser;
  const SuppliersPage({super.key, required this.currentUser});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>("");
  final ValueNotifier<String> _methodFilterNotifier = ValueNotifier<String>("الكل");
  
  List<String> _paymentMethods = ["كاش", "شبكة"];
  StreamSubscription? _settingsSub;

  String get _managerId => widget.currentUser.parentId ?? widget.currentUser.id;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() { if (mounted) setState(() {}); });
    _listenToSettings();
  }

  void _listenToSettings() {
    final cid = widget.currentUser.cafeId;
    if (cid.isNotEmpty) {
      _settingsSub = CafeService.streamCafeSettings(cid).listen((settings) {
        if (mounted) {
          setState(() {
            _paymentMethods = List<String>.from(settings.paymentMethods)..removeWhere((m) => m == "دين");
          });
        }
      });
    }
  }

  void _onSearchChanged(String query) {
    _searchQueryNotifier.value = query.trim().toLowerCase();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchQueryNotifier.dispose();
    _methodFilterNotifier.dispose();
    _settingsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.currentUser.canRead('suppliers')) {
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'suppliers',
        child: const Scaffold(
          body: Center(
            child: Text("عذراً، لا تملك صلاحية الوصول لصفحة الموردين", 
              style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'suppliers',
      floatingActionButton: widget.currentUser.canCreate('suppliers') ? FloatingActionButton.extended(
        onPressed: _showAddPurchaseDialog,
        backgroundColor: Colors.orange[800],
        icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
        label: const Text("فاتورة جديدة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ) : null,
      child: Column(
        children: [
          _buildStatDashboard(primaryColor),
          _buildCustomTabBar(primaryColor),
          _buildSearchBox(primaryColor),
          if (_tabController.index == 1) _buildMethodFilter(primaryColor),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: _searchQueryNotifier,
                  builder: (context, query, _) => _SuppliersList(searchQuery: query, managerId: _managerId, currentUser: widget.currentUser, primaryColor: primaryColor, onManage: _showSupplierOptions),
                ),
                ValueListenableBuilder<String>(
                  valueListenable: _searchQueryNotifier,
                  builder: (context, query, _) => ValueListenableBuilder<String>(
                    valueListenable: _methodFilterNotifier,
                    builder: (context, method, _) => _PurchasesSimpleList(searchQuery: query, methodFilter: method, managerId: _managerId, currentUser: widget.currentUser),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDashboard(Color primary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 25, 20, 35),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primary, primary.withBlue(100)]),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('suppliers').where('cafeId', isEqualTo: widget.currentUser.cafeId).snapshots(),
        builder: (context, snap) {
          double totalDebt = 0;
          double totalPaid = 0;
          if (snap.hasData) {
            for (var d in snap.data!.docs) {
              final Map<String, dynamic> data = d.data() as Map<String, dynamic>;
              if (data['parentId'] == _managerId) {
                totalDebt += (data['totalBalance'] ?? 0.0);
                totalPaid += (data['totalPaid'] ?? 0.0);
              }
            }
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("إحصائيات الموردين", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  if (widget.currentUser.canCreate('suppliers'))
                    IconButton(
                      onPressed: () => SupplierDialogs.showAddSupplierDialog(context: context, cafeId: widget.currentUser.cafeId, managerId: _managerId),
                      icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
                    )
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: _statBox("إجمالي الديون", "${totalDebt.toStringAsFixed(1)} ₪", Colors.red[100]!),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _statBox("إجمالي المدفوع", "${totalPaid.toStringAsFixed(1)} ₪", Colors.green[100]!),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statBox(String label, String value, Color color) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 5),
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
      ],
    ),
  );

  Widget _buildCustomTabBar(Color primary) {
    return Container(
      margin: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(12)),
        labelColor: Colors.white, unselectedLabelColor: Colors.grey,
        tabs: const [Tab(text: "قائمة الموردين"), Tab(text: "سجل الفواتير")],
      ),
    );
  }

  Widget _buildSearchBox(Color primary) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(hintText: "بحث...", prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
      ),
    );
  }

  Widget _buildMethodFilter(Color primary) {
    final filters = ["الكل", ..._paymentMethods, "آجل", "دين مورد", "مزيج"];
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        itemCount: filters.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(left: 8),
          child: ChoiceChip(
            label: Text(filters[i]),
            selected: _methodFilterNotifier.value == filters[i],
            onSelected: (v) { if(v) setState(() => _methodFilterNotifier.value = filters[i]); },
          ),
        ),
      ),
    );
  }

  void _showAddPurchaseDialog() {
    SupplierDialogs.showAddPurchaseDialog(context: context, currentUser: widget.currentUser, cafeId: widget.currentUser.cafeId, managerId: _managerId);
  }

  void _showSupplierOptions(String id, Map data) {
    SupplierDialogs.showSupplierOptions(context: context, id: id, data: data, currentUser: widget.currentUser, cafeId: widget.currentUser.cafeId, managerId: _managerId);
  }
}

class _PurchasesSimpleList extends StatelessWidget {
  final String searchQuery;
  final String methodFilter;
  final String managerId;
  final User currentUser;

  const _PurchasesSimpleList({required this.searchQuery, required this.methodFilter, required this.managerId, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('purchases').where('cafeId', isEqualTo: currentUser.cafeId).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        
        final docs = snap.data!.docs.where((doc) {
          final Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          if (data['parentId'] != managerId) return false;
          
          String m = data['method'] ?? "";
          if (methodFilter != "الكل") {
            if (methodFilter == "آجل" && m != "دين مورد") return false;
            if (methodFilter != "آجل" && m != methodFilter) return false;
          }
          if (searchQuery.isNotEmpty) {
            final name = (data['supplierName'] ?? "").toString().toLowerCase();
            final prod = (data['productName'] ?? "").toString().toLowerCase();
            if (!name.contains(searchQuery) && !prod.contains(searchQuery)) return false;
          }
          return true;
        }).toList();

        docs.sort((a, b) {
          final d1 = a.data() as Map<String, dynamic>;
          final d2 = b.data() as Map<String, dynamic>;
          Timestamp t1 = d1['date'] ?? Timestamp.now();
          Timestamp t2 = d2['date'] ?? Timestamp.now();
          return t2.compareTo(t1);
        });

        if (docs.isEmpty) return const Center(child: Text("لا توجد سجلات حالياً", style: TextStyle(color: Colors.grey)));

        return ListView.builder(
          padding: const EdgeInsets.all(15),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final Map<String, dynamic> data = docs[i].data() as Map<String, dynamic>;
            final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
            final String method = data['method'] ?? "كاش";
            
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: ExpansionTile(
                leading: CircleAvatar(backgroundColor: Colors.orange.withOpacity(0.1), child: const Icon(Icons.receipt_long, color: Colors.orange)),
                title: Text(data['productName'] ?? "فاتورة مورد", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text("${data['supplierName']} | ${intl.DateFormat('yyyy/MM/dd').format(date)} | $method", style: const TextStyle(fontSize: 11)),
                trailing: Text("${(data['amount'] ?? data['totalAmount'] ?? 0)} ₪", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 15),
                    child: Column(
                      children: [
                        const Divider(),
                        _detailRow("رقم الفاتورة", data['invoiceNo'] ?? "-"),
                        _detailRow("طريقة الدفع", method),
                        _detailRow("الكمية", "${data['quantity'] ?? '-'} ${data['unit'] ?? ''}"),
                        _detailRow("المبلغ المسدد", "${data['paidAmount'] ?? data['amount'] ?? 0} ₪", isGreen: true),
                        if (data['remaining'] != null && data['remaining'] > 0)
                          _detailRow("المبلغ المتبقي (دين)", "${data['remaining']} ₪", isRed: true),
                        _detailRow("الموظف", data['processedBy'] ?? "-"),
                      ],
                    ),
                  )
                ],
              ),
            );
          },
        );
      }
    );
  }

  Widget _detailRow(String label, String value, {bool isRed = false, bool isGreen = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isRed ? Colors.red : (isGreen ? Colors.green : Colors.black87))),
      ],
    ),
  );
}

class _SuppliersList extends StatelessWidget {
  final String searchQuery;
  final String managerId;
  final User currentUser;
  final Color primaryColor;
  final Function(String, Map<String, dynamic>) onManage;

  const _SuppliersList({required this.searchQuery, required this.managerId, required this.currentUser, required this.primaryColor, required this.onManage});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('suppliers').where('cafeId', isEqualTo: currentUser.cafeId).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        
        final docs = snap.data!.docs.where((d) {
          final Map<String, dynamic> data = d.data() as Map<String, dynamic>;
          if (data['parentId'] != managerId) return false;
          return data['name'].toString().toLowerCase().contains(searchQuery);
        }).toList();
        
        if (docs.isEmpty) return const Center(child: Text("لا يوجد موردين حالياً", style: TextStyle(color: Colors.grey)));

        return ListView.builder(
          padding: const EdgeInsets.all(15),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final Map<String, dynamic> data = docs[i].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: ListTile(
                onTap: () => onManage(docs[i].id, data),
                leading: CircleAvatar(backgroundColor: primaryColor.withOpacity(0.1), child: Icon(Icons.person, color: primaryColor)),
                title: Text(data['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("المدفوع: ${(data['totalPaid'] ?? 0.0).toStringAsFixed(1)} ₪", style: const TextStyle(color: Colors.green, fontSize: 11)),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("${(data['totalBalance'] ?? 0.0).toStringAsFixed(1)} ₪", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                    const Text("رصيد الدين", style: TextStyle(fontSize: 9, color: Colors.grey)),
                  ],
                ),
              ),
            );
          },
        );
      }
    );
  }
}
