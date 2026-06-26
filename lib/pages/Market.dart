import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'user_model.dart';
import 'MainLayout.dart';
import 'orderpage.dart';
import '../services/cafe_service.dart';
import '../services/debt_service.dart';
import '../widgets/app_components.dart';
import '../widgets/home_dialogs.dart';
import '../widgets/dashboard_dialogs.dart';

class Market extends StatefulWidget {
  final User currentUser;

  const Market({super.key, required this.currentUser});

  @override
  State<Market> createState() => _MarketState();
}

class _MarketState extends State<Market> {
  final TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> filteredCategories = [];
  CafeSettings? _settings;
  bool _isLoading = true;

  double _todaySales = 0.0;
  int _todayOrdersCount = 0;
  List<Map<String, String>> _existingCustomers = [];

  StreamSubscription? _settingsSub;
  StreamSubscription? _categoriesSub;
  StreamSubscription? _todaySalesSub;
  StreamSubscription? _customersSub;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _categoriesSub?.cancel();
    _todaySalesSub?.cancel();
    _customersSub?.cancel();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final String cid = widget.currentUser.cafeId;
    final String managerId = widget.currentUser.parentId ?? widget.currentUser.id;

    if (cid.isNotEmpty) {
      _settingsSub = CafeService.streamCafeSettings(cid).listen((settings) {
        if (mounted) setState(() => _settings = settings);
      });

      // جلب الأقسام (التصنيفات) بدلاً من الطاولات
      _categoriesSub = FirebaseFirestore.instance
          .collection('categories')
          .where('cafeId', isEqualTo: cid)
          .where('parentId', isEqualTo: managerId)
          .snapshots()
          .listen((snap) {
        if (mounted) {
          setState(() {
            categories = snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
            _isLoading = false;
            _applySearch();
          });
        }
      });

      final todayStart = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      _todaySalesSub = FirebaseFirestore.instance
          .collection('payments')
          .where('cafeId', isEqualTo: cid)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .snapshots()
          .listen((snap) {
        if (mounted) {
          double total = 0;
          for (var doc in snap.docs) {
            total += (doc.data()['amount'] ?? doc.data()['total_amount'] ?? 0.0).toDouble();
          }
          setState(() {
            _todaySales = total;
            _todayOrdersCount = snap.docs.length;
          });
        }
      });

      _customersSub = DebtService.streamDebts(cid, managerId).listen((data) {
        if (mounted) {
          setState(() {
            _existingCustomers = data.map((d) => {
              'id': d['id'].toString(),
              'name': d['customer'].toString(),
              'phone': d['phone']?.toString() ?? "",
              'debt': (d['netBalance'] as double).toStringAsFixed(1),
            }).toList();
          });
        }
      });
    }
  }

  void _applySearch() {
    final q = searchController.text.trim().toLowerCase();
    setState(() {
      filteredCategories = categories.where((c) {
        return c['name'].toString().toLowerCase().contains(q);
      }).toList();
    });
  }

  void _openOrderPage() {
    if (!widget.currentUser.canMakeOrders) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "OrderSheet",
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => Align(
        alignment: Alignment.centerLeft,
        child: Material(
          elevation: 25,
          child: Container(
            width: MediaQuery.of(context).size.width > 1200 ? 1100 : MediaQuery.of(context).size.width * 0.95,
            height: double.infinity,
            color: Colors.white,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: OrderPage(
                tableId: "takeaway",
                tableName: "نقطة بيع مباشر",
                currentUser: widget.currentUser,
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, anim1, anim2, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(-1, 0), end: const Offset(0, 0)).animate(anim1),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MainLayout(
      currentUser: widget.currentUser, currentPage: 'home',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: _isLoading ? const Center(child: CircularProgressIndicator()) : Column(children: [
          _buildHeader(theme),
          Expanded(child: _buildCategoryGrid()),
        ]),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openOrderPage(),
          backgroundColor: Colors.green[700],
          icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
          label: const Text("فاتورة جديدة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 12),
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [theme.primaryColor, theme.primaryColor.withBlue(100)]),
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(25), bottomRight: Radius.circular(25)),
          boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))]
      ),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("سوبر ماركت برو", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Text(intl.DateFormat('EEEE, d MMMM').format(DateTime.now()), style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
            IconButton(icon: const Icon(Icons.info_outline, color: Colors.white, size: 24), onPressed: _showAboutDialog, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _dashboardStat("الأقسام", "${categories.length}", Icons.category, Colors.white),
            _dashboardStat("طلبات اليوم", "$_todayOrdersCount", Icons.receipt_long, Colors.greenAccent),
            _dashboardStat("مبيعات اليوم", "${_todaySales.toStringAsFixed(0)} ${_settings?.currencySymbol ?? "₪"}", Icons.trending_up, Colors.orangeAccent),
          ]),
          const SizedBox(height: 15),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _quickActionBtn(Icons.bolt, "بيع مباشر", Colors.orange[400]!, () => _openOrderPage()),
              const SizedBox(width: 8),
              _quickActionBtn(Icons.add_card_rounded, "حوالة", Colors.teal[400]!, () {
                DashboardDialogs.showAddTransferDialog(
                  context: context,
                  currentUser: widget.currentUser,
                  paymentMethods: _settings?.paymentMethods ?? ["كاش", "شبكة"],
                  customerSuggestions: _existingCustomers,
                  managerId: widget.currentUser.parentId ?? widget.currentUser.id,
                );
              }),
              const SizedBox(width: 8),
              _quickActionBtn(Icons.person_add_alt_1, "دين جديد", Colors.red[400]!, () => HomeDialogs.showAddDebtDialog(context: context, currentUser: widget.currentUser, existingCustomers: _existingCustomers)),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: searchController,
            onChanged: (v) => _applySearch(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: "بحث عن قسم...",
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

  Widget _dashboardStat(String label, String value, IconData icon, Color col) {
    return Column(children: [
      Row(children: [Icon(icon, color: col, size: 14), const SizedBox(width: 4), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10))]),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _quickActionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
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
          Icon(Icons.shopping_basket, size: 50, color: Colors.blue),
          SizedBox(height: 10),
          Text("نظام سستم ماركت برو", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Text("الإصدار 3.0.0", style: TextStyle(color: Colors.grey)),
          SizedBox(height: 20),
          Text("واجهة احترافية مخصصة لإدارة السوبر ماركت والمحلات التجارية، تدعم الأقسام، الديون، والبيع المباشر.", textAlign: TextAlign.center),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("إغلاق"))]
    );
  }

  Widget _buildCategoryGrid() {
    if (filteredCategories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.category_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text("لا توجد أقسام مضافة حالياً", style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.1,
      ),
      itemCount: filteredCategories.length,
      itemBuilder: (context, i) {
        final cat = filteredCategories[i];
        return _buildCategoryCard(cat);
      },
    );
  }

  Widget _buildCategoryCard(Map<String, dynamic> cat) {
    final String name = cat['name'] ?? "بدون اسم";
    
    return InkWell(
      onTap: () => _openOrderPage(),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
          border: Border.all(color: Colors.grey[100]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.shopping_bag_outlined, color: Colors.blue[800], size: 30),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
