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

class ReportPage extends StatefulWidget {
  final User currentUser;
  const ReportPage({super.key, required this.currentUser});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  DateTime _selectedDate = DateTime.now();
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

  Future<void> _exportDailySummaryToExcel(Map<String, Map<String, dynamic>> dailyData, DateTime start, DateTime end) async {
    if (!widget.currentUser.canRead('reports')) return;

    String csv = '\uFEFFاليوم,المبيعات,التكلفة,صافي الربح,المصاريف التشغيلية\n';
    dailyData.forEach((key, data) {
      csv += "${data['display']},${data['sales']},${data['cogs']},${data['profit']},${data['expenses']}\n";
    });
    try {
      final fileName = "Finance_Report_${intl.DateFormat('yyyyMMdd').format(start)}.csv";
      Uint8List bytes = Uint8List.fromList(utf8.encode(csv));
      await saveAndDownloadFile(bytes, fileName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ تم تصدير التقرير المالي بنجاح")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ خطأ أثناء التصدير: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    if (!widget.currentUser.canRead('reports')) {
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'reports',
        child: const Scaffold(body: Center(child: Text("لا تملك صلاحية عرض التقارير"))),
      );
    }

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'reports',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('التحليل المالي الدقيق', style: TextStyle(fontWeight: FontWeight.w900)),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.event),
              onPressed: () async {
                final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2022), lastDate: DateTime.now());
                if (picked != null) setState(() => _selectedDate = picked);
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildFinanceHeader(primaryColor),
              const SizedBox(height: 25),
              _buildAccountingSummary(primaryColor),
              const SizedBox(height: 25),
              _buildDailyZReport(primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinanceHeader(Color primary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primary, primary.withBlue(100)]),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        children: [
          const Text("تقرير الأداء المالي لليوم", style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Text(intl.DateFormat('EEEE, dd MMMM yyyy').format(_selectedDate), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAccountingSummary(Color primary) {
    final targetDateStr = intl.DateFormat('yyyyMMdd').format(_selectedDate);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('payments')
          .where('cafeId', isEqualTo: widget.currentUser.cafeId)
          .where('parentId', isEqualTo: managerId).snapshots(),
      builder: (context, salesSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('expenses')
              .where('cafeId', isEqualTo: widget.currentUser.cafeId)
              .where('parentId', isEqualTo: managerId).snapshots(),
          builder: (context, expSnap) {
            double totalSales = 0, totalCOGS = 0, operationalExpenses = 0;

            if (salesSnap.hasData) {
              for (var doc in salesSnap.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final date = (data['paid_at'] as Timestamp?)?.toDate() ?? DateTime.now();
                if (intl.DateFormat('yyyyMMdd').format(date) == targetDateStr) {
                  if (data['is_debt_payment'] != true) {
                    totalSales += (data['total_amount'] ?? 0).toDouble();
                    List items = data['items'] as List? ?? [];
                    for (var item in items) {
                      double cost = (item['costPriceAtSale'] ?? 0.0).toDouble();
                      double q = (item['quantity'] ?? 0.0).toDouble();
                      totalCOGS += (cost * q);
                    }
                  }
                }
              }
            }

            if (expSnap.hasData) {
              for (var doc in expSnap.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
                if (intl.DateFormat('yyyyMMdd').format(date) == targetDateStr) {
                  if (data['category'] != "مشتريات") {
                    operationalExpenses += (data['amount'] ?? 0).toDouble();
                  }
                }
              }
            }

            double grossProfit = totalSales - totalCOGS;
            double netProfit = grossProfit - operationalExpenses;

            return Column(
              children: [
                Row(children: [
                  Expanded(child: ReportInfoCard(title: "إجمالي المبيعات", value: totalSales, color: Colors.green, icon: Icons.trending_up, currencySymbol: currencySymbol)),
                  const SizedBox(width: 15),
                  Expanded(child: ReportInfoCard(title: "تكلفة المباع", value: totalCOGS, color: Colors.orange, icon: Icons.shopping_bag, currencySymbol: currencySymbol)),
                ]),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: ReportInfoCard(title: "مصاريف تشغيلية", value: operationalExpenses, color: Colors.redAccent, icon: Icons.money_off, currencySymbol: currencySymbol)),
                  const SizedBox(width: 15),
                  Expanded(child: ReportInfoCard(title: "صافي الأرباح", value: netProfit, color: Colors.blue, icon: Icons.account_balance_wallet, currencySymbol: currencySymbol, isBold: true)),
                ]),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDailyZReport(Color primary) {
    if (_settings == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('payments')
          .where('cafeId', isEqualTo: widget.currentUser.cafeId)
          .where('parentId', isEqualTo: managerId).snapshots(),
      builder: (context, snapshot) {
        Map<String, double> methodTotals = { for (var m in _settings!.paymentMethods) m: 0.0 };
        if (snapshot.hasData) {
          final targetDateStr = intl.DateFormat('yyyyMMdd').format(_selectedDate);
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map;
            final date = (data['paid_at'] as Timestamp?)?.toDate() ?? DateTime.now();
            if (intl.DateFormat('yyyyMMdd').format(date) == targetDateStr) {
              String method = data['payment_method'] ?? "";
              double amt = (data['total_amount'] ?? 0).toDouble();
              if (methodTotals.containsKey(method)) methodTotals[method] = methodTotals[method]! + amt;
            }
          }
        }

        return Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20)]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [Icon(Icons.point_of_sale, color: Colors.purple), SizedBox(width: 10), Text("تقرير طرق الدفع (Z-Report)", style: TextStyle(fontWeight: FontWeight.bold))]),
              const Divider(height: 30),
              ...methodTotals.entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(e.key), Text("${e.value.toStringAsFixed(1)} $currencySymbol", style: const TextStyle(fontWeight: FontWeight.bold))]),
              )).toList(),
            ],
          ),
        );
      },
    );
  }
}
