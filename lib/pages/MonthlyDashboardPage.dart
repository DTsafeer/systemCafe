import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'user_model.dart';

class MonthlyDashboardPage extends StatefulWidget {
  final User currentUser;
  const MonthlyDashboardPage({super.key, required this.currentUser});

  @override
  State<MonthlyDashboardPage> createState() => _MonthlyDashboardPageState();
}

class _MonthlyDashboardPageState extends State<MonthlyDashboardPage> {
  String currencySymbol = "₪";
  DateTime selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fetchSettings();
  }

  // جلب إعدادات العملة الخاصة بالكافيه الحالي
  void _fetchSettings() async {
    try {
      var doc = await FirebaseFirestore.instance
          .collection('cafes')
          .doc(widget.currentUser.cafeId)
          .get();
      if (doc.exists && mounted) {
        setState(() => currencySymbol = doc.data()?['currency_symbol'] ?? "₪");
      }
    } catch (e) {
      debugPrint("Error fetching currency: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("التقرير المالي الشهري", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_view_month),
            onPressed: () => _selectMonth(context),
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        // ✅ التعديل: فلترة المبيعات حسب الكافيه الحالي فقط
        stream: FirebaseFirestore.instance
            .collection('payments')
            .where('cafeId', isEqualTo: widget.currentUser.cafeId)
            .where('year', isEqualTo: selectedMonth.year)
            .where('month', isEqualTo: selectedMonth.month)
            .snapshots(),
        builder: (context, paymentSnapshot) {
          return StreamBuilder<QuerySnapshot>(
            // ✅ التعديل: فلترة المصروفات حسب الكافيه الحالي فقط
            stream: FirebaseFirestore.instance
                .collection('expenses')
                .where('cafeId', isEqualTo: widget.currentUser.cafeId)
                .snapshots(),
            builder: (context, expenseSnapshot) {

              if (paymentSnapshot.hasError) return Center(child: Text("خطأ: ${paymentSnapshot.error}"));
              if (paymentSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

              double totalSales = 0;
              Map<String, int> productSalesCount = {};
              Map<String, double> waiterPerformance = {};

              // --- معالجة مبيعات الشهر ---
              final payments = paymentSnapshot.data?.docs ?? [];
              for (var doc in payments) {
                final data = doc.data() as Map<String, dynamic>;
                double amount = (data['total_amount'] ?? 0).toDouble();
                totalSales += amount;

                String waiter = data['processed_by'] ?? "غير معروف";
                waiterPerformance[waiter] = (waiterPerformance[waiter] ?? 0) + amount;

                if (data.containsKey('items') && data['items'] is List) {
                  for (var item in data['items']) {
                    String pName = item['name'] ?? "صنف";
                    int qty = (item['quantity'] ?? 1).toInt();
                    productSalesCount[pName] = (productSalesCount[pName] ?? 0) + qty;
                  }
                }
              }

              // --- معالجة مصروفات الشهر ---
              double totalExpenses = 0;
              final allExpenses = expenseSnapshot.data?.docs ?? [];
              for (var doc in allExpenses) {
                final expData = doc.data() as Map<String, dynamic>;
                if (expData['date'] == null) continue;

                DateTime expDate = (expData['date'] as Timestamp).toDate();
                // التحقق من مطابقة السنة والشهر يدوياً في الكود
                if (expDate.year == selectedMonth.year && expDate.month == selectedMonth.month) {
                  totalExpenses += (expData['amount'] ?? 0).toDouble();
                }
              }

              double netProfit = totalSales - totalExpenses;
              var sortedProducts = productSalesCount.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSectionTitle("ملخص شهر: ${DateFormat('MMMM yyyy', 'ar').format(selectedMonth)}"),
                  const SizedBox(height: 12),
                  _buildProfitCard(netProfit),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildStatCard("إجمالي المبيعات", "$totalSales", Colors.green),
                      const SizedBox(width: 10),
                      _buildStatCard("إجمالي المصاريف", "$totalExpenses", Colors.redAccent),
                    ],
                  ),
                  const SizedBox(height: 25),

                  // الرسم البياني يظهر فقط إذا كانت هناك بيانات
                  if (totalSales > 0 || totalExpenses > 0) ...[
                    _buildSectionTitle("توزيع السيولة الشهري"),
                    _buildPieChart(totalSales, totalExpenses),
                    const SizedBox(height: 25),
                  ],

                  _buildSectionTitle("الأصناف الأكثر مبيعاً في الشهر"),
                  _buildTopProductsList(sortedProducts.take(10).toList()),

                  const SizedBox(height: 25),
                  _buildSectionTitle("أداء الموظفين (إجمالي الشهر)"),
                  _buildWaiterPerformance(waiterPerformance),
                  const SizedBox(height: 100),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // دالة اختيار التاريخ (تم تحديثها لتكون أكثر دقة)
  Future<void> _selectMonth(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: "اختر الشهر المطلوب",
    );
    if (picked != null && picked != selectedMonth) {
      setState(() => selectedMonth = picked);
    }
  }

  // --- Widgets البناء مع الحفاظ على التصميم الأصلي ---

  Widget _buildSectionTitle(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
  );

  Widget _buildProfitCard(double profit) {
    bool isPositive = profit >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isPositive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isPositive ? Colors.green : Colors.red, width: 2),
      ),
      child: Column(children: [
        const Text("صافي ربح الشهر", style: TextStyle(fontSize: 14, color: Colors.grey)),
        Text("${profit.toStringAsFixed(1)} $currencySymbol",
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: isPositive ? Colors.green : Colors.red)),
      ]),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
      ),
      child: Column(children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text("$value $currencySymbol", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ]),
    ),
  );

  Widget _buildPieChart(double sales, double expenses) {
    // منع حدوث خطأ إذا كانت القيم صفرية في الرسم البياني
    double sVal = sales == 0 && expenses == 0 ? 1 : sales;
    double eVal = expenses;

    return Container(
      height: 200,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: PieChart(PieChartData(sections: [
        PieChartSectionData(value: sVal, color: Colors.green, title: 'مبيعات', radius: 55, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        PieChartSectionData(value: eVal, color: Colors.redAccent, title: 'مصاريف', radius: 55, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      ])),
    );
  }

  Widget _buildTopProductsList(List<MapEntry<String, int>> products) {
    if (products.isEmpty) return const Card(child: ListTile(title: Text("لا توجد مبيعات في هذا الشهر")));
    return Column(children: products.map((e) => Card(child: ListTile(title: Text(e.key), trailing: Text("${e.value} قطعة")))).toList());
  }

  Widget _buildWaiterPerformance(Map<String, double> performance) {
    if (performance.isEmpty) return const Card(child: ListTile(title: Text("لا توجد بيانات")));
    return Column(children: performance.entries.map((e) => Card(child: ListTile(leading: const Icon(Icons.person), title: Text(e.key), trailing: Text("${e.value.toStringAsFixed(1)} $currencySymbol")))).toList());
  }
}