import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'MonthlyDashboardPage.dart';
import 'user_model.dart';

class DashboardPage extends StatefulWidget {
  final User currentUser;
  const DashboardPage({super.key, required this.currentUser});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String currencySymbol = "₪";
  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fetchSettings();
  }

  void _fetchSettings() async {
    try {
      final cafeDoc = await FirebaseFirestore.instance.collection('cafes').doc(widget.currentUser.cafeId).get();
      if (cafeDoc.exists && mounted) {
        setState(() => currencySymbol = cafeDoc.data()?['currency_symbol'] ?? "₪");
      }
    } catch (e) {
      debugPrint("Error fetching settings: $e");
    }
  }

  // ✅ دالة مركزية لتسجيل الأنشطة
  Future<void> _logAction(String action, String details) async {
    if (!mounted) return;
    try {
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'cafeId': widget.currentUser.cafeId,
        'userName': widget.currentUser.name, // جلب اسم المستخدم من الويدجت
        'action': action,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error logging action: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("التقارير المالية والأرباح", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) {
                return MonthlyDashboardPage(currentUser: widget.currentUser);
              }));
            },
            icon: const Icon(Icons.data_exploration),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => selectedDate = picked);
            },
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('payments')
            .where('cafeId', isEqualTo: widget.currentUser.cafeId)
            .where('year', isEqualTo: selectedDate.year)
            .where('month', isEqualTo: selectedDate.month)
            .where('day', isEqualTo: selectedDate.day)
            .snapshots(),
        builder: (context, paymentSnapshot) {
          return StreamBuilder<QuerySnapshot>(
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
              Set<String> activeTables = {};

              final payments = paymentSnapshot.data?.docs ?? [];
              for (var doc in payments) {
                final data = doc.data() as Map<String, dynamic>;
                double amount = (data['total_amount'] ?? 0).toDouble();
                totalSales += amount;
                if (data['table'] != null) activeTables.add(data['table'].toString());
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

              double totalExpenses = 0;
              final allExpenses = expenseSnapshot.data?.docs ?? [];
              for (var doc in allExpenses) {
                final expData = doc.data() as Map<String, dynamic>;
                if (expData['date'] == null) continue;
                DateTime expDate = (expData['date'] as Timestamp).toDate();
                if (expDate.year == selectedDate.year && expDate.month == selectedDate.month && expDate.day == selectedDate.day) {
                  totalExpenses += (expData['amount'] ?? 0).toDouble();
                }
              }

              double netProfit = totalSales - totalExpenses;
              var sortedProducts = productSalesCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
              String topProduct = sortedProducts.isNotEmpty ? sortedProducts.first.key : "لا يوجد";

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSectionTitle("ملخص يوم: ${DateFormat('yyyy-MM-dd').format(selectedDate)}"),
                  const SizedBox(height: 12),
                  _buildProfitCard(netProfit),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildStatCard("المبيعات", totalSales, Colors.green),
                      const SizedBox(width: 10),
                      _buildStatCard("المصاريف", totalExpenses, Colors.redAccent),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _infoStatCard("طاولات مخدومة", "${activeTables.length}", Colors.blue, Icons.table_restaurant)),
                      const SizedBox(width: 10),
                      Expanded(child: _infoStatCard("الأكثر مبيعاً", topProduct, Colors.orange, Icons.star)),
                    ],
                  ),
                  const SizedBox(height: 25),
                  if (totalSales > 0 || totalExpenses > 0) ...[
                    _buildSectionTitle("توزيع السيولة"),
                    _buildPieChart(totalSales, totalExpenses),
                    const SizedBox(height: 25),
                  ],
                  _buildSectionTitle("الأكثر مبيعاً اليوم"),
                  _buildTopProductsList(sortedProducts.take(5).toList()),
                  const SizedBox(height: 25),
                  _buildSectionTitle("إيرادات الموظفين"),
                  _buildWaiterPerformance(waiterPerformance),
                  const SizedBox(height: 100),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: "dashboard_fab",
        onPressed: () => _showAddExpenseDialog(context),
        label: const Text("إضافة مصروف"),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  // --- دوال بناء الواجهة ---

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
        const Text("صافي الربح", style: TextStyle(fontSize: 14, color: Colors.grey)),
        Text("${profit.toStringAsFixed(1)} $currencySymbol",
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: isPositive ? Colors.green : Colors.red)),
      ]),
    );
  }

  Widget _buildStatCard(String title, double value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
      ),
      child: Column(children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text("${value.toStringAsFixed(1)} $currencySymbol", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ]),
    ),
  );

  Widget _infoStatCard(String title, String value, Color color, IconData icon) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]),
    child: Row(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis),
      ])),
    ]),
  );

  Widget _buildPieChart(double sales, double expenses) => Container(
    height: 200,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
    child: PieChart(PieChartData(sections: [
      PieChartSectionData(value: sales, color: Colors.green, title: 'مبيعات', radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      PieChartSectionData(value: expenses, color: Colors.redAccent, title: 'مصاريف', radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    ])),
  );

  Widget _buildTopProductsList(List<MapEntry<String, int>> products) {
    if (products.isEmpty) return const Card(child: ListTile(title: Text("لا توجد مبيعات أصناف اليوم")));
    return Column(children: products.map((e) => Card(child: ListTile(title: Text(e.key), trailing: Text("${e.value} قطعة")))).toList());
  }

  Widget _buildWaiterPerformance(Map<String, double> performance) {
    if (performance.isEmpty) return const Card(child: ListTile(title: Text("لا توجد بيانات موظفين")));
    return Column(children: performance.entries.map((e) => Card(child: ListTile(leading: const Icon(Icons.person), title: Text(e.key), trailing: Text("${e.value.toStringAsFixed(1)} $currencySymbol")))).toList());
  }

  // ✅ --- دالة إضافة المصروف مع التتبع --- ✅
  void _showAddExpenseDialog(BuildContext context) {
    final rController = TextEditingController();
    final aController = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("إضافة مصروف"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: rController, decoration: const InputDecoration(labelText: "السبب")),
        TextField(controller: aController, decoration: const InputDecoration(labelText: "المبلغ"), keyboardType: TextInputType.number),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
        ElevatedButton(onPressed: () async {
          final double? amount = double.tryParse(aController.text);
          final String reason = rController.text.trim();
          if (amount != null && amount > 0) {
            await FirebaseFirestore.instance.collection('expenses').add({
              'cafeId': widget.currentUser.cafeId,
              'reason': reason.isEmpty ? "مصروف بدون سبب" : reason,
              'amount': amount,
              'date': FieldValue.serverTimestamp(),
              'added_by': widget.currentUser.name, // حفظ اسم الموظف الذي أضاف المصروف
            });

            // ✅ تسجيل الحركة في سجل النشاط
            await _logAction(
                "إضافة مصروف",
                "قام بإضافة مصروف بقيمة: $amount $currencySymbol. السبب: $reason"
            );

            if (mounted) Navigator.pop(ctx);
          }
        }, child: const Text("حفظ")),
      ],
    ));
  }
}
