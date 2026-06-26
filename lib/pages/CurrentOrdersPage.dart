import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import '../services/cafe_service.dart';
import '../widgets/order_widgets.dart';

class CurrentOrdersPage extends StatefulWidget {
  final User currentUser;
  final String? tableFilter;

  const CurrentOrdersPage({super.key, required this.currentUser, this.tableFilter});

  @override
  State<CurrentOrdersPage> createState() => _CurrentOrdersPageState();
}

class _CurrentOrdersPageState extends State<CurrentOrdersPage> {
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  String? _activeCafeId;
  CafeSettings? _settings;
  StreamSubscription? _settingsSub;

  @override
  void initState() {
    super.initState();
    _searchQuery = widget.tableFilter ?? "";
    _searchController.text = _searchQuery;
    _initData();
  }

  Future<void> _initData() async {
    _activeCafeId = widget.currentUser.cafeId;
    if (_activeCafeId == null || _activeCafeId!.isEmpty) {
      _activeCafeId = await CafeService.getActiveCafeId();
    }
    
    if (_activeCafeId != null && _activeCafeId!.isNotEmpty) {
      _settingsSub = CafeService.streamCafeSettings(_activeCafeId!).listen((s) {
        if (mounted) setState(() => _settings = s);
      });
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _settingsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final String managerId = widget.currentUser.parentId ?? widget.currentUser.id;

    if (_activeCafeId == null || _activeCafeId!.isEmpty || _settings == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'orders',
      child: LayoutBuilder(
        builder: (context, constraints) {
          bool isWide = constraints.maxWidth > 800;

          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(isWide ? 40 : 25)),
                  ),
                  child: Column(
                    children: [
                      const Text("فواتير الطاولات النشطة", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Center(
                        child: SizedBox(
                          width: 600,
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            onChanged: (v) => setState(() => _searchQuery = v.trim()),
                            decoration: InputDecoration(
                              hintText: 'بحث باسم الطاولة...',
                              hintStyle: const TextStyle(color: Colors.white60),
                              prefixIcon: const Icon(Icons.search, color: Colors.white60, size: 20),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.15),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('orders')
                        .where('cafeId', isEqualTo: _activeCafeId)
                        .where('parentId', isEqualTo: managerId)
                        .where('paid', isEqualTo: false)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                      // تحويل الوثائق لقائمة لترتيبها برمجياً لتجنب الحاجة للفهارس
                      final docs = snapshot.data!.docs.toList();

                      // ترتيب الطلبات حسب الوقت (من الأقدم للأحدث)
                      docs.sort((a, b) {
                        final t1 = (a.data() as Map<String, dynamic>)['ordered_at'] as Timestamp?;
                        final t2 = (b.data() as Map<String, dynamic>)['ordered_at'] as Timestamp?;
                        if (t1 == null) return 1;
                        if (t2 == null) return -1;
                        return t1.compareTo(t2);
                      });

                      final Map<String, List<QueryDocumentSnapshot>> tablesData = {};
                      for (var d in docs) {
                        final table = (d['table'] ?? '؟').toString();
                        if (_searchQuery.isEmpty || table.contains(_searchQuery)) {
                          tablesData.putIfAbsent(table, () => []);
                          tablesData[table]!.add(d);
                        }
                      }

                      if (tablesData.isEmpty) {
                        return const Center(child: Text("لا توجد فواتير نشطة حالياً", style: TextStyle(color: Colors.grey)));
                      }

                      final keys = tablesData.keys.toList();
                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: isWide ? 550 : constraints.maxWidth,
                          mainAxisExtent: 450,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                        ),
                        itemCount: keys.length,
                        itemBuilder: (context, i) => ModernTableOrderCard(
                          tableName: keys[i],
                          orders: tablesData[keys[i]]!,
                          currentUser: widget.currentUser,
                          cafeId: _activeCafeId!,
                          currencySymbol: _settings!.currencySymbol,
                          hourlyRate: _settings!.hourlyRate,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }
}
