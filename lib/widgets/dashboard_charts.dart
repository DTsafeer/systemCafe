import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WeeklySalesChart extends StatelessWidget {
  final String cafeId;
  final String managerId;
  final Color primaryColor;
  final String currencySymbol;

  const WeeklySalesChart({
    super.key,
    required this.cafeId,
    required this.managerId,
    required this.primaryColor,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, spreadRadius: 2)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("إجمالي المبيعات (آخر 7 أيام)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Icon(Icons.bar_chart_rounded, color: primaryColor, size: 20),
            ],
          ),
          const SizedBox(height: 25),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // الاكتفاء بفلتر واحد فقط لضمان العمل بدون فهارس (Indices)
              stream: FirebaseFirestore.instance.collection('payments')
                  .where('cafeId', isEqualTo: cafeId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text("خطأ في الاتصال"));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                Map<String, double> dailyTotals = {};
                DateTime now = DateTime.now();
                DateTime startOfToday = DateTime(now.year, now.month, now.day);
                DateTime sevenDaysAgo = startOfToday.subtract(const Duration(days: 7));
                
                for (int i = 0; i < 7; i++) {
                  DateTime date = startOfToday.subtract(Duration(days: i));
                  String key = DateFormat('yyyy-MM-dd').format(date);
                  dailyTotals[key] = 0.0;
                }

                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data['is_debt_payment'] == true) continue;

                  dynamic paidAt = data['paid_at'];
                  if (paidAt is! Timestamp) continue;
                  
                  DateTime dt = paidAt.toDate();
                  // فلترة محلية لآخر 7 أيام لضمان السرعة وعدم الحاجة لفهارس
                  if (dt.isBefore(sevenDaysAgo)) continue;

                  String key = DateFormat('yyyy-MM-dd').format(dt);
                  if (dailyTotals.containsKey(key)) {
                    double amt = double.tryParse(data['total_amount']?.toString() ?? "0") ?? 0.0;
                    dailyTotals[key] = (dailyTotals[key] ?? 0.0) + amt;
                  }
                }

                List<DateTime> last7Days = List.generate(7, (i) => startOfToday.subtract(Duration(days: 6 - i)));
                List<BarChartGroupData> groups = [];
                double maxVal = 100;
                
                for (int i = 0; i < 7; i++) {
                  DateTime d = last7Days[i];
                  String key = DateFormat('yyyy-MM-dd').format(d);
                  double val = dailyTotals[key] ?? 0.0;
                  if (val > maxVal) maxVal = val;
                  groups.add(
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: val,
                          color: primaryColor,
                          width: 22,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          gradient: LinearGradient(colors: [primaryColor, primaryColor.withOpacity(0.7)], begin: Alignment.bottomCenter, end: Alignment.topCenter),
                        )
                      ],
                    )
                  );
                }

                return BarChart(
                  BarChartData(
                    barGroups: groups,
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxVal * 1.2,
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            int idx = value.toInt();
                            if (idx < 0 || idx >= 7) return const SizedBox();
                            return Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(DateFormat('E', 'ar').format(last7Days[idx]), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                  )
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ExpensesPieChart extends StatelessWidget {
  final String cafeId;
  final String managerId;

  const ExpensesPieChart({super.key, required this.cafeId, required this.managerId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("توزيع المصاريف", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          SizedBox(
            height: 180,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('expenses')
                  .where('cafeId', isEqualTo: cafeId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                Map<String, double> cats = {};
                for (var d in snapshot.data!.docs) {
                  final data = d.data() as Map<String, dynamic>;
                  String c = data['category'] ?? "أخرى";
                  double amt = double.tryParse(data['amount']?.toString() ?? "0") ?? 0.0;
                  cats[c] = (cats[c] ?? 0) + amt;
                }
                if (cats.isEmpty) return const Center(child: Text("لا توجد بيانات", style: TextStyle(fontSize: 10)));
                
                return PieChart(PieChartData(
                  sectionsSpace: 4,
                  centerSpaceRadius: 35,
                  sections: cats.entries.map((e) {
                    final index = cats.keys.toList().indexOf(e.key);
                    final color = Colors.primaries[index % Colors.primaries.length];
                    return PieChartSectionData(
                      value: e.value,
                      title: "${e.value.round()}",
                      radius: 45,
                      titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                      color: color,
                    );
                  }).toList()
                ));
              },
            ),
          )
        ],
      ),
    );
  }
}
