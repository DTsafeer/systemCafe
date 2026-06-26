import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import '../widgets/modern_table_card.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import 'orderpage.dart';
import '../services/table_service.dart';
import '../services/cafe_service.dart';
import '../widgets/app_components.dart';
import '../widgets/home_dialogs.dart';
import '../widgets/dashboard_dialogs.dart';
import '../widgets/calculator_widget.dart'; 

class HomePage extends StatefulWidget {
  final User currentUser;
  const HomePage({super.key, required this.currentUser});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> tables = [];
  List<Map<String, dynamic>> filteredTables = [];
  final TextEditingController searchController = TextEditingController();
  String _statusFilter = "الكل";
  double _todaySales = 0.0;
  List<Map<String, String>> _existingCustomers = [];
  CafeSettings? _settings;
  StreamSubscription? _settingsSub;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    searchController.dispose();
    super.dispose();
  }

  void _initData() async {
    final String cafeId = widget.currentUser.cafeId;
    _settingsSub = CafeService.streamCafeSettings(cafeId).listen((s) {
      if (mounted) setState(() => _settings = s);
    });
    _loadTables();
    _loadTodaySales();
    _loadCustomers();
  }

  void _loadTables() {
    final String mid = widget.currentUser.parentId ?? widget.currentUser.id;
    TableService.streamTables(widget.currentUser.cafeId, mid).listen((data) {
      if (mounted) {
        setState(() {
          tables = data;
          _applySearch();
        });
      }
    });
  }

  void _loadTodaySales() {
    final String cafeId = widget.currentUser.cafeId;
    final now = DateTime.now();
    FirebaseFirestore.instance.collection('payments')
        .where('cafeId', isEqualTo: cafeId)
        .where('day', isEqualTo: now.day)
        .where('month', isEqualTo: now.month)
        .where('year', isEqualTo: now.year)
        .snapshots().listen((snap) {
          double total = 0;
          for (var doc in snap.docs) {
            total += (doc.data()['total_amount'] ?? 0).toDouble();
          }
          if (mounted) setState(() => _todaySales = total);
        });
  }

  void _loadCustomers() {
    final String mid = widget.currentUser.parentId ?? widget.currentUser.id;
    FirebaseFirestore.instance.collection('debts')
        .where('cafeId', isEqualTo: widget.currentUser.cafeId)
        .where('parentId', isEqualTo: mid)
        .snapshots().listen((snap) {
          if (mounted) {
            setState(() {
              _existingCustomers = snap.docs.map((d) {
                final data = d.data();
                return {
                  'id': d.id,
                  'name': data['customer']?.toString() ?? "",
                  'phone': data['phone']?.toString() ?? "",
                  'debt': (data['remainingAmount'] ?? 0.0).toString(),
                  'no': (data['debtNo'] ?? "").toString(),
                };
              }).toList();
            });
          }
        });
  }

  void _applySearch() {
    String q = searchController.text.toLowerCase();
    setState(() {
      List<Map<String, dynamic>> results = tables.where((t) {
        bool matchSearch = t['name'].toString().toLowerCase().contains(q);
        bool matchStatus = true;
        if (_statusFilter == "متاحة") matchStatus = t['is_open'] != true;
        else if (_statusFilter == "مشغولة") matchStatus = t['is_open'] == true;
        return matchSearch && matchStatus;
      }).toList();

      results.sort((a, b) {
        bool isOpenA = a['is_open'] == true;
        bool isOpenB = b['is_open'] == true;
        if (isOpenA != isOpenB) return isOpenA ? -1 : 1;
        
        String nameA = a['name'].toString();
        String nameB = b['name'].toString();
        int? numA = int.tryParse(nameA.replaceAll(RegExp(r'[^0-9]'), ''));
        int? numB = int.tryParse(nameB.replaceAll(RegExp(r'[^0-9]'), ''));

        if (numA != null && numB != null) return numA.compareTo(numB);
        return nameA.compareTo(nameB);
      });
      filteredTables = results;
    });
  }

  void _openOrderPage(String id, String name) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => OrderPage(currentUser: widget.currentUser, tableId: id, tableName: name)));
  }

  void _showCalculator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CalculatorWidget(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MainLayout(
      currentUser: widget.currentUser, currentPage: 'home',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: tables.isEmpty && searchController.text.isEmpty ? const Center(child: CircularProgressIndicator()) : Column(children: [
          _buildHeader(theme),
          Expanded(child: _buildTableGrid()),
        ]),
        floatingActionButton: widget.currentUser.canCreate('tables') ? FloatingActionButton.extended(
          onPressed: () => HomeDialogs.showAddTableDialog(context: context, currentUser: widget.currentUser),
          backgroundColor: theme.primaryColor,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text("طاولة جديدة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ) : null,
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    int total = tables.length;
    int busy = tables.where((t) => t['is_open'] == true).length;
    int available = total - busy;

    final bool isNotWaiter = widget.currentUser.role != UserRole.waiter;
    final bool canAccessFinance = isNotWaiter && widget.currentUser.canPayOrders;
    final bool canAccessDebts = isNotWaiter && widget.currentUser.canManageDebts;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [theme.primaryColor, theme.primaryColor.withBlue(100)]),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
        boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))]
      ),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("إدارة الكافيه", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              Text(intl.DateFormat('EEEE, d MMMM').format(DateTime.now()), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.calculate_outlined, color: Colors.white, size: 26), onPressed: _showCalculator, tooltip: "الآلة الحاسبة"),
              const SizedBox(width: 10),
              IconButton(icon: const Icon(Icons.info_outline, color: Colors.white, size: 26), onPressed: _showAboutDialog),
            ]),
          ]),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _StatButton(label: "الإجمالي", value: "$total", icon: Icons.grid_view, col: Colors.white, isSelected: _statusFilter == "الكل", onTap: () {
              setState(() { _statusFilter = "الكل"; _applySearch(); });
            }),
            _StatButton(label: "المتاحة", value: "$available", icon: Icons.check_circle, col: Colors.greenAccent, isSelected: _statusFilter == "متاحة", onTap: () {
              setState(() { _statusFilter = "متاحة"; _applySearch(); });
            }),
            _StatButton(label: "المشغولة", value: "$busy", icon: Icons.restaurant, col: Colors.orangeAccent, isSelected: _statusFilter == "مشغولة", onTap: () {
              setState(() { _statusFilter = "مشغولة"; _applySearch(); });
            }),
            if (widget.currentUser.canViewReports)
              _StatButton(label: "المبيعات", value: "${_todaySales.toStringAsFixed(0)}", icon: Icons.trending_up, col: Colors.blueAccent, isSelected: false, onTap: () {}),
          ]),
          const SizedBox(height: 20),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              if (canAccessFinance)
                _quickActionBtn(Icons.bolt, "كاشير", Colors.orange[400]!, () => _openOrderPage("takeaway", "طلب سفري")),
              if (canAccessFinance) const SizedBox(width: 8),
              
              if (canAccessFinance)
                _quickActionBtn(Icons.add_card_rounded, "سداد", Colors.teal[400]!, () {
                  // استخدام الحوار الموحد الآن في الصفحة الرئيسية أيضاً
                  DashboardDialogs.showAddTransferDialog(
                    context: context,
                    currentUser: widget.currentUser,
                    paymentMethods: _settings?.paymentMethods ?? ["كاش", "شبكة"],
                    customerSuggestions: _existingCustomers,
                    managerId: widget.currentUser.parentId ?? widget.currentUser.id,
                  );
                }),
              if (canAccessFinance) const SizedBox(width: 8),
              
              if (canAccessDebts)
                _quickActionBtn(Icons.person_add_alt_1, "دين جديد", Colors.red[400]!, () => HomeDialogs.showAddDebtDialog(context: context, currentUser: widget.currentUser, existingCustomers: _existingCustomers)),
            ]),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: searchController,
            onChanged: (v) => _applySearch(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: "بحث سريع عن طاولة...",
              hintStyle: const TextStyle(color: Colors.white60),
              prefixIcon: const Icon(Icons.search, color: Colors.white60, size: 20),
              filled: true,
              fillColor: Colors.white.withOpacity(0.15),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10)
        ),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ]),
      ),
    );
  }

  void _showAboutDialog() {
    AppComponents.showAppDialog(
      context: context,
      title: "حول النظام",
      content: const Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.coffee, size: 50, color: Colors.brown),
        SizedBox(height: 10),
        Text("نظام سستم كافيه برو", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        Text("الإصدار 2.5.0", style: TextStyle(color: Colors.grey)),
        SizedBox(height: 20),
        Text("نظام متكامل لإدارة الكافيهات والمطاعم، يدعم تعدد الطاولات، إدارة المخزون، والديون والتقارير المالية.", textAlign: TextAlign.center),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("إغلاق"))]
    );
  }

  Widget _buildTableGrid() {
    final bool canPay = widget.currentUser.role != UserRole.waiter && widget.currentUser.canPayOrders;

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.7),
      itemCount: filteredTables.length,
      itemBuilder: (context, i) {
        final t = filteredTables[i];
        return ModernTableCard(
          tableData: t, 
          currentUser: widget.currentUser,
          isKitchenEnabled: _settings?.isKitchenEnabled ?? true,
          showTimeCounter: _settings?.showTimeCounter ?? true,
          hourlyRate: _settings?.hourlyRate ?? 0.0,
          currencySymbol: _settings?.currencySymbol ?? "₪",
          onTap: () => _openOrderPage(t['id'], t['name']),
          onPayTap: canPay ? () => _openOrderPage(t['id'], t['name']) : null,
          onDelete: widget.currentUser.canManageTables ? () => HomeDialogs.confirmDeleteTable(context: context, table: t) : null,
          onClose: (unpaid) {
            if (unpaid) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ توجد طلبات لم يتم دفع حسابها!")));
            } else {
              if (widget.currentUser.canEditTable) {
                TableService.updateTableStatus(t['id'], false);
              }
            }
          },
        );
      },
    );
  }
}

class _StatButton extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color col;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatButton({required this.label, required this.value, required this.icon, required this.col, required this.isSelected, required this.onTap});

  @override
  State<_StatButton> createState() => _StatButtonState();
}

class _StatButtonState extends State<_StatButton> {
  double _scale = 1.0;
  @override
  Widget build(BuildContext context) {
    return Expanded(child: GestureDetector(onTapDown: (_) => setState(() => _scale = 0.94), onTapUp: (_) => setState(() => _scale = 1.0), onTapCancel: () => setState(() => _scale = 1.0), child: AnimatedScale(scale: _scale, duration: const Duration(milliseconds: 100), child: Container(margin: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: widget.isSelected ? Colors.white.withOpacity(0.25) : Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(15), border: Border.all(color: widget.isSelected ? Colors.white.withOpacity(0.4) : Colors.white.withOpacity(0.1), width: 1.5)), child: Material(color: Colors.transparent, child: InkWell(onTap: widget.onTap, borderRadius: BorderRadius.circular(15), splashColor: Colors.white24, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(widget.icon, color: widget.col, size: 20), const SizedBox(height: 6), Text(widget.label, style: TextStyle(color: widget.isSelected ? Colors.white : Colors.white70, fontSize: 11, fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.normal)), const SizedBox(height: 4), Text(widget.value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]))))))));
  }
}
