import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../utils/save_helper_stub.dart'
    if (dart.library.html) '../utils/save_helper_web.dart'
    if (dart.library.io) '../utils/save_helper_mobile.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import '../widgets/report_widgets.dart';
import '../widgets/report_dialogs.dart';
import '../services/cafe_service.dart';
import '../services/report_service.dart';

class ReportPage extends StatefulWidget {
  final User currentUser;
  const ReportPage({super.key, required this.currentUser});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _endDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59);
  
  String currencySymbol = "₪";
  late String managerId;
  CafeSettings? _settings;
  StreamSubscription? _settingsSub;

  @override
  void initState() {
    super.initState();
    managerId = widget.currentUser.parentId ?? widget.currentUser.id;
    _initCafeSettings();
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    super.dispose();
  }

  void _initCafeSettings() {
    if (widget.currentUser.cafeId.isEmpty) return;
    _settingsSub = CafeService.streamCafeSettings(widget.currentUser.cafeId).listen((settings) {
      if (mounted) {
        setState(() {
          _settings = settings;
          currencySymbol = settings.currencySymbol;
        });
      }
    });
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2022),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    );
    if (picked != null) {
      setState(() {
        _startDate = DateTime(picked.start.year, picked.start.month, picked.start.day);
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'reports',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('التحليل المالي وكشف الحركة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: "التحليل الذكي",
              icon: const Icon(Icons.analytics_outlined),
              onPressed: () {
                ReportDialogs.showDailySummaryDialog(
                  context: context,
                  cafeId: widget.currentUser.cafeId,
                  managerId: managerId,
                  selectedDate: _startDate,
                  currencySymbol: currencySymbol,
                  onExport: (data, s, e) {},
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.date_range),
              onPressed: _selectDateRange,
            ),
          ],
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: ReportService.fetchReportData(widget.currentUser.cafeId, managerId, start: _startDate, end: _endDate)
              .then((data) => ReportService.calculateFullFinancialStatement(data)),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Center(child: Text("خطأ في التحميل: ${snapshot.error}"));
            if (!snapshot.hasData) return const Center(child: Text("لا توجد بيانات"));

            final stats = snapshot.data!;
            
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildHeaderCard(stats, primaryColor),
                  const SizedBox(height: 25),
                  _buildProfitAnalysis(stats),
                  const SizedBox(height: 25),
                  _buildDetailedLogSection(primaryColor),
                  const SizedBox(height: 25),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeaderCard(Map<String, dynamic> stats, Color primary) {
    final rangeStr = _startDate.day == _endDate.day && _startDate.month == _endDate.month 
        ? intl.DateFormat('EEEE, dd MMMM yyyy', 'ar').format(_startDate)
        : "من ${intl.DateFormat('MM/dd').format(_startDate)} إلى ${intl.DateFormat('MM/dd').format(_endDate)}";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primary, primary.withBlue(100)]),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: primary.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))]
      ),
      child: Column(
        children: [
          Text(rangeStr, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          const Text("صافي الربح الفعلي (السيولة)", style: TextStyle(color: Colors.white, fontSize: 16)),
          Text("${(stats['actualLiquidityProfit'] ?? 0).toStringAsFixed(1)} $currencySymbol", 
            style: const TextStyle(color: Colors.white, fontSize: 35, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
            child: Text("صافي الربح الدفتري (شامل الديون): ${stats['netProfit'].toStringAsFixed(1)} $currencySymbol", 
              style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitAnalysis(Map<String, dynamic> stats) {
    double cashSales = (stats['totalSales'] ?? 0) - (stats['totalNewDebts'] ?? 0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(
        children: [
          const Row(children: [Icon(Icons.analytics, color: Colors.blue), SizedBox(width: 10), Text("تحليل الدورة المالية للفترة", style: TextStyle(fontWeight: FontWeight.bold))]),
          const Divider(height: 30),
          _row("إجمالي المبيعات (كاش + تحويل + دين)", stats['totalSales'], Colors.black),
          _row("(-) مبيعات الديون", stats['totalNewDebts'], Colors.orange),
          _row("(=) المبيعات النقدية (السيولة)", cashSales, Colors.blue[900]!, isBold: true),
          const Divider(),
          _row("إجمالي تكلفة البضاعة المباعة", stats['totalCOGS'], Colors.orange[800]!),
          _row("إجمالي المصاريف التشغيلية", stats['totalExpenses'], Colors.red),
          const Divider(thickness: 2),
          _row("صافي الربح الدفتري", stats['netProfit'], Colors.blue, isBold: true),
          _row("صافي الربح الفعلي (بدون الديون)", stats['actualLiquidityProfit'], Colors.green[900]!, isBold: true, fontSize: 18),
        ],
      ),
    );
  }

  Widget _buildDetailedLogSection(Color primary) {
    return FutureBuilder<Map<String, List<QueryDocumentSnapshot>>>(
      future: ReportService.fetchReportData(widget.currentUser.cafeId, managerId, start: _startDate, end: _endDate),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final data = snapshot.data!;
        
        List<Map<String, dynamic>> log = [];
        for (var doc in data['sales']!) {
          final d = doc.data() as Map<String, dynamic>;
          bool isDebtPay = d['is_debt_payment'] == true;
          log.add({
            'time': (d['paid_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
            'title': isDebtPay ? "تحصيل دين: ${d['customer_name']}" : "مبيعات: ${d['customer_name'] ?? 'زبون عام'}",
            'subtitle': isDebtPay ? "دفع دين سابق" : "${(d['items'] as List? ?? []).length} أصناف",
            'amount': (d['total_amount'] ?? 0).toDouble(),
            'icon': isDebtPay ? Icons.person_pin : Icons.shopping_bag,
            'color': isDebtPay ? Colors.teal : Colors.green,
          });
        }
        for (var doc in data['expenses']!) {
          final d = doc.data() as Map<String, dynamic>;
          log.add({
            'time': (d['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
            'title': "مصروف: ${d['category'] ?? 'عام'}",
            'subtitle': d['note'] ?? "",
            'amount': -(d['amount'] ?? 0).toDouble(),
            'icon': Icons.money_off,
            'color': Colors.red,
          });
        }
        for (var doc in data['purchases']!) {
          final d = doc.data() as Map<String, dynamic>;
          log.add({
            'time': (d['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
            'title': "شراء مخزن: ${d['productName']}",
            'subtitle': "كمية: ${d['quantity']}",
            'amount': -(d['amount'] ?? 0).toDouble(),
            'icon': Icons.inventory,
            'color': Colors.blueGrey,
          });
        }
        log.sort((a, b) => b['time'].compareTo(a['time']));

        return Column(
          children: [
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Row(children: [Icon(Icons.history_edu, color: Colors.blueGrey), SizedBox(width: 10), Text("سجل التدفق المالي للفترة", style: TextStyle(fontWeight: FontWeight.bold))]),
                  ),
                  const Divider(height: 1),
                  if (log.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Text("لا توجد حركات مالية في هذه الفترة")),
                  ...log.take(50).map((m) => ListTile(
                    leading: CircleAvatar(backgroundColor: m['color'].withOpacity(0.1), child: Icon(m['icon'], color: m['color'], size: 20)),
                    title: Text(m['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text("${m['subtitle']} • ${intl.DateFormat('MM/dd hh:mm a').format(m['time'])}", style: const TextStyle(fontSize: 11)),
                    trailing: Text("${m['amount'] > 0 ? '+' : ''}${m['amount'].toStringAsFixed(1)} $currencySymbol", 
                      style: TextStyle(fontWeight: FontWeight.bold, color: m['amount'] >= 0 ? Colors.green[700] : Colors.red[700])),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 25),
            _buildZReport(data['sales']!, primary),
          ],
        );
      },
    );
  }

  Widget _buildZReport(List<QueryDocumentSnapshot> sales, Color primary) {
    Map<String, double> methodTotals = {};
    for (var doc in sales) {
      final d = doc.data() as Map;
      String method = d['payment_method'] ?? "كاش";
      methodTotals[method] = (methodTotals[method] ?? 0) + (d['total_amount'] ?? 0).toDouble();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(
        children: [
          const Row(children: [Icon(Icons.account_balance_wallet, color: Colors.purple), SizedBox(width: 10), Text("توزيع السيولة (حسب طريقة الدفع)", style: TextStyle(fontWeight: FontWeight.bold))]),
          const Divider(height: 30),
          ...methodTotals.entries.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(e.key), Text("${e.value.toStringAsFixed(1)} $currencySymbol", style: const TextStyle(fontWeight: FontWeight.bold))]),
          )).toList(),
        ],
      ),
    );
  }

  Widget _row(String label, double val, Color col, {bool isBold = false, double fontSize = 14}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: fontSize - 1)),
          Text("${val.toStringAsFixed(1)} $currencySymbol", style: TextStyle(fontWeight: FontWeight.bold, color: col, fontSize: fontSize)),
        ],
      ),
    );
  }
}
