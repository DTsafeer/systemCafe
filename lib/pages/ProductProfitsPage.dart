import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:fl_chart/fl_chart.dart';
import 'package:rxdart/rxdart.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import '../services/cafe_service.dart';
import '../utils/save_helper_stub.dart'
    if (dart.library.html) '../utils/save_helper_web.dart'
    if (dart.library.io) '../utils/save_helper_mobile.dart';

class ProductProfitsPage extends StatefulWidget {
  final User currentUser;
  final String? initialSearchQuery; 

  const ProductProfitsPage({super.key, required this.currentUser, this.initialSearchQuery});

  @override
  State<ProductProfitsPage> createState() => _ProductProfitsPageState();
}

class _ProductProfitsPageState extends State<ProductProfitsPage> {
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59);
  
  final _searchController = TextEditingController();
  final ValueNotifier<String> _searchQuery = ValueNotifier("");
  String _selectedCategory = "الكل";
  List<String> _categories = ["الكل"];
  
  String currencySymbol = "₪";
  late String managerId;
  String? _activeCafeId;

  @override
  void initState() {
    super.initState();
    managerId = widget.currentUser.parentId ?? widget.currentUser.id;
    if (widget.initialSearchQuery != null) {
      _searchController.text = widget.initialSearchQuery!;
      _searchQuery.value = widget.initialSearchQuery!.toLowerCase();
    }
    _initPage();
  }

  Future<void> _initPage() async {
    String cid = widget.currentUser.cafeId;
    if (cid.isEmpty) {
      cid = await CafeService.getActiveCafeId();
    }
    if (mounted) {
      setState(() => _activeCafeId = cid);
      _loadCategories(cid);
      _loadCafeSettings(cid);
    }
  }

  void _loadCafeSettings(String cid) async {
    if (cid.isEmpty) return;
    final doc = await FirebaseFirestore.instance.collection('cafes').doc(cid).get();
    if (doc.exists && mounted) {
      setState(() => currencySymbol = doc.data()?['currency_symbol'] ?? "₪");
    }
  }

  void _loadCategories(String cid) async {
    if (cid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('categories')
          .where('cafeId', isEqualTo: cid).get();
      if (mounted) {
        setState(() {
          _categories = ["الكل", ...snap.docs
            .where((d) => (d.data())['parentId'] == managerId)
            .map((d) => d['name'].toString())];
        });
      }
    } catch (e) {
      debugPrint("Error loading categories: $e");
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    if (_activeCafeId == null) {
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'product_profits',
        child: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'product_profits',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("تحليل المبيعات والأرباح الفعلية", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.date_range_rounded),
              onPressed: _selectDateRange,
            ),
          ],
        ),
        body: Column(
          children: [
            _buildFiltersBar(primaryColor),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: _searchQuery,
                builder: (context, query, _) => _buildMainContent(query, primaryColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersBar(Color primary) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => _searchQuery.value = v.trim().toLowerCase(),
                  decoration: InputDecoration(
                    hintText: "بحث عن صنف...",
                    prefixIcon: Icon(Icons.search, color: primary),
                    filled: true, fillColor: Colors.grey[50],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  underline: const SizedBox(),
                  items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (v) => setState(() => _selectedCategory = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "الفترة من ${intl.DateFormat('yyyy/MM/dd').format(_startDate)} إلى ${intl.DateFormat('yyyy/MM/dd').format(_endDate)}",
            style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(String query, Color primary) {
    final paymentsStream = FirebaseFirestore.instance.collection('payments')
        .where('cafeId', isEqualTo: _activeCafeId)
        .snapshots();
        
    final debtTxStream = FirebaseFirestore.instance.collection('debt_transactions')
        .where('cafeId', isEqualTo: _activeCafeId)
        .snapshots();

    return StreamBuilder<List<QuerySnapshot>>(
      stream: Rx.combineLatest2(paymentsStream, debtTxStream, (a, b) => [a, b]),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("خطأ: ${snapshot.error}"));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final allPaymentDocs = snapshot.data![0].docs;
        final allDebtDocs = snapshot.data![1].docs;
        
        Map<String, Map<String, dynamic>> stats = {};
        double totalProf = 0, totalDebtRev = 0, totalAllRev = 0;

        DateTime startOfRange = DateTime(_startDate.year, _startDate.month, _startDate.day);
        DateTime endOfRange = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);

        void processDocs(List<QueryDocumentSnapshot> docs, bool isFromDebtCollection) {
          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['parentId'] != null && data['parentId'] != managerId) continue;
            
            if (data['is_debt_payment'] == true) continue;
            if (isFromDebtCollection && !(data['type']?.toString().contains("طلب") ?? false) && !(data['type']?.toString().contains("فاتورة") ?? false)) continue;

            Timestamp? dateTs = (data['paid_at'] ?? data['date']) as Timestamp?;
            if (dateTs == null) continue;
            DateTime dt = dateTs.toDate();
            if (dt.isBefore(startOfRange) || dt.isAfter(endOfRange)) continue;

            String method = data['payment_method']?.toString() ?? "كاش";
            bool isDebtSale = method.contains("دين") || method.contains("ديون") || isFromDebtCollection;

            final items = data['items'] as List? ?? [];
            for (var item in items) {
              String name = item['name'] ?? "صنف غير معروف";
              String cat = item['category'] ?? "عام";

              if (query.isNotEmpty && !name.toLowerCase().contains(query)) continue;
              if (_selectedCategory != "الكل" && cat != _selectedCategory) continue;

              double cost = double.tryParse(item['costPriceAtSale']?.toString() ?? "") ?? 
                            double.tryParse(item['costPrice']?.toString() ?? "0") ?? 0.0;
                            
              double qty = double.tryParse(item['quantity']?.toString() ?? "0") ?? 0.0;
              double revenue = double.tryParse(item['total']?.toString() ?? "0") ?? 0.0;
              double profit = revenue - (cost * qty);

              stats.update(name, (v) => {
                'qty': v['qty'] + qty,
                'revenue': v['revenue'] + revenue,
                'cost': v['cost'] + (cost * qty),
                'profit': v['profit'] + profit,
                'category': cat,
              }, ifAbsent: () => {'qty': qty, 'revenue': revenue, 'cost': cost * qty, 'profit': profit, 'category': cat});

              totalProf += profit;
              totalAllRev += revenue;
              if (isDebtSale) totalDebtRev += revenue;
            }
          }
        }

        processDocs(allPaymentDocs, false);
        processDocs(allDebtDocs, true);

        if (stats.isEmpty) return const Center(child: Text("لا توجد مبيعات في هذه الفترة", style: TextStyle(color: Colors.grey)));

        var sorted = stats.entries.toList()..sort((a, b) => b.value['profit'].compareTo(a.value['profit']));

        return ListView(
          padding: const EdgeInsets.all(15),
          children: [
            _buildSummaryRow(totalProf, totalDebtRev, totalAllRev),
            const SizedBox(height: 20),
            _buildChartSection(sorted.take(5).toList()),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("تفاصيل مبيعات المنتجات", style: TextStyle(fontWeight: FontWeight.bold)),
                TextButton.icon(onPressed: () => _exportToCSV(sorted), icon: const Icon(Icons.file_download_outlined), label: const Text("تصدير")),
              ],
            ),
            ...sorted.map((e) => _buildProductCard(e.key, e.value)),
          ],
        );
      },
    );
  }

  Widget _buildSummaryRow(double totalProf, double debtAmount, double totalRev) {
    double actualProfit = totalProf - debtAmount;
    return Column(
      children: [
        Row(
          children: [
            _statBox("إجمالي المبيعات", totalRev, Colors.purple),
            const SizedBox(width: 10),
            _statBox("إجمالي الأرباح", totalProf, Colors.blue),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _statBox("مبيعات الديون", debtAmount, Colors.orange),
            const SizedBox(width: 10),
            _statBox("الربح الفعلي (السيولة)", actualProfit, Colors.green),
          ],
        ),
      ],
    );
  }

  Widget _statBox(String t, double v, Color c, {bool isFullWidth = false}) {
    Widget content = Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(15), border: Border.all(color: c.withOpacity(0.2))),
      child: Column(
        children: [
          Text(t, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.bold)),
          Text("${v.toStringAsFixed(1)} $currencySymbol", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: c)),
        ],
      ),
    );
    return isFullWidth ? SizedBox(width: double.infinity, child: content) : Expanded(child: content);
  }

  Widget _buildChartSection(List<MapEntry<String, Map<String, dynamic>>> top) {
    return Container(
      height: 180, padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: BarChart(BarChartData(
        barGroups: top.asMap().entries.map((e) => BarChartGroupData(x: e.key, barRods: [BarChartRodData(toY: e.value.value['profit'].toDouble(), color: Colors.blue[800], width: 12)])).toList(),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 5), child: Text(top[v.toInt()].key.substring(0, top[v.toInt()].key.length > 4 ? 4 : top[v.toInt()].key.length), style: const TextStyle(fontSize: 8))))),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false), borderData: FlBorderData(show: false),
      )),
    );
  }

  Widget _buildProductCard(String name, Map<String, dynamic> s) {
    double margin = s['revenue'] > 0 ? (s['profit'] / s['revenue']) * 100 : 0;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(5)),
                  child: Text(s['category'], style: const TextStyle(fontSize: 10, color: Colors.blue)),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _miniStat("الكمية", "${s['qty'].toInt()}"),
                _miniStat("المبيعات", "${s['revenue'].toStringAsFixed(1)}"),
                _miniStat("التكلفة", "${s['cost'].toStringAsFixed(1)}"),
                _miniStat("الربح", "${s['profit'].toStringAsFixed(1)}", isBold: true),
                _miniStat("الهامش", "${margin.toStringAsFixed(1)}%"),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String l, String v, {bool isBold = false}) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text(v, style: TextStyle(fontWeight: isBold ? FontWeight.w900 : FontWeight.bold, fontSize: 13, color: isBold ? Colors.green[700] : Colors.black))]);

  Future<void> _selectDateRange() async {
    final p = await showDateRangePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime.now(), initialDateRange: DateTimeRange(start: _startDate, end: _endDate));
    if (p != null) setState(() { 
      _startDate = p.start; 
      _endDate = DateTime(p.end.year, p.end.month, p.end.day, 23, 59, 59); 
    });
  }

  Future<void> _exportToCSV(List<MapEntry<String, Map<String, dynamic>>> data) async {
    String csv = '\uFEFFالمنتج,التصنيف,الكمية,المبيعات,التكلفة,الربح\n';
    for (var e in data) {
      csv += "${e.key},${e.value['category']},${e.value['qty']},${e.value['revenue']},${e.value['cost']},${e.value['profit']}\n";
    }
    try {
      final bytes = Uint8List.fromList(utf8.encode(csv));
      await saveAndDownloadFile(bytes, "Profits_${intl.DateFormat('yyyyMMdd').format(_startDate)}.csv");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم تصدير التقرير")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ خطأ: $e")));
    }
  }
}
