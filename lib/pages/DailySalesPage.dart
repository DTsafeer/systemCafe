import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'user_model.dart';
import 'MainLayout.dart';
import '../services/cafe_service.dart';

class DailySalesPage extends StatefulWidget {
  final User currentUser;
  const DailySalesPage({super.key, required this.currentUser});

  @override
  State<DailySalesPage> createState() => _DailySalesPageState();
}

class _DailySalesPageState extends State<DailySalesPage> {
  String currencySymbol = "₪";
  late String managerId;

  @override
  void initState() {
    super.initState();
    managerId = widget.currentUser.parentId ?? widget.currentUser.id;
    _loadSettings();
  }

  void _loadSettings() async {
    final settings = await CafeService.getCafeSettings(widget.currentUser.cafeId);
    if (mounted) setState(() => currencySymbol = settings.currencySymbol);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'daily_sales',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("سجل المبيعات اليومي", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: theme.primaryColor,
          foregroundColor: Colors.white,
        ),
        body: StreamBuilder<QuerySnapshot>(
          // تم حذف orderBy لتجنب الحاجة للفهارس (Indexes)
          stream: FirebaseFirestore.instance
              .collection('payments')
              .where('cafeId', isEqualTo: widget.currentUser.cafeId)
              .where('parentId', isEqualTo: managerId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد مبيعات مسجلة"));

            // ترتيب البيانات يدوياً حسب التاريخ (الأحدث أولاً)
            final docs = snapshot.data!.docs.toList();
            docs.sort((a, b) {
              final t1 = (a.data() as Map)['paid_at'] as Timestamp?;
              final t2 = (b.data() as Map)['paid_at'] as Timestamp?;
              if (t1 == null) return 1;
              if (t2 == null) return -1;
              return t2.compareTo(t1);
            });

            Map<String, Map<String, dynamic>> dailyGroups = {};

            for (var doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              final timestamp = data['paid_at'] as Timestamp?;
              if (timestamp == null) continue;

              final date = timestamp.toDate();
              final dayKey = intl.DateFormat('yyyy-MM-dd').format(date);

              if (!dailyGroups.containsKey(dayKey)) {
                dailyGroups[dayKey] = {
                  'date': date,
                  'totalSales': 0.0,
                  'totalCost': 0.0,
                  'transactions': [],
                };
              }

              if (data['is_debt_payment'] != true) {
                double total = (data['total_amount'] ?? 0.0).toDouble();
                dailyGroups[dayKey]!['totalSales'] += total;
                dailyGroups[dayKey]!['transactions'].add(data);

                List items = data['items'] as List? ?? [];
                for (var item in items) {
                  double cost = (item['costPriceAtSale'] ?? 0.0).toDouble();
                  double q = (item['quantity'] ?? 0.0).toDouble();
                  dailyGroups[dayKey]!['totalCost'] += (cost * q);
                }
              }
            }

            final sortedDays = dailyGroups.keys.toList(); // مرتبة أصلاً لأننا رتبنا الـ docs

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sortedDays.length,
              itemBuilder: (context, index) {
                final dayData = dailyGroups[sortedDays[index]]!;
                final double profit = dayData['totalSales'] - dayData['totalCost'];

                return Card(
                  margin: const EdgeInsets.only(bottom: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: ExpansionTile(
                    title: Text(intl.DateFormat('EEEE, dd MMMM yyyy', 'ar').format(dayData['date']), style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("صافي الربح: ${profit.toStringAsFixed(1)} $currencySymbol", style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.w600)),
                    trailing: Text("${dayData['totalSales'].toStringAsFixed(1)} $currencySymbol", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            _buildStatRow("إجمالي المبيعات", dayData['totalSales'], Colors.green),
                            _buildStatRow("إجمالي التكلفة", dayData['totalCost'], Colors.orange),
                            const Divider(),
                            ... (dayData['transactions'] as List).map((tx) => ListTile(
                              dense: true,
                              title: Text(tx['customer_name'] ?? "زبون عام"),
                              subtitle: Text(intl.DateFormat('hh:mm a').format((tx['paid_at'] as Timestamp).toDate())),
                              trailing: Text("${tx['total_amount']} $currencySymbol", style: const TextStyle(fontWeight: FontWeight.bold)),
                            )).toList(),
                          ],
                        ),
                      )
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, double val, Color col) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text("${val.toStringAsFixed(1)} $currencySymbol", style: TextStyle(color: col, fontWeight: FontWeight.bold))]),
  );
}
