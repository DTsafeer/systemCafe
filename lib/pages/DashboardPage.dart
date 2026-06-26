import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../utils/database_helper.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/dashboard_dialogs.dart';
import '../widgets/dashboard_charts.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import 'orderpage.dart';
import 'DebtsPage.dart';

class DashboardPage extends StatefulWidget {
  final User currentUser;
  const DashboardPage({super.key, required this.currentUser});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String currencySymbol = "₪";
  int inactiveDaysThreshold = 15;
  DateTime selectedDate = DateTime.now();
  List<String> _paymentMethods = ["كاش", "شبكة", "دين"];
  List<Map<String, String>> _customerSuggestions = [];
  late String managerId;

  @override
  void initState() {
    super.initState();
    managerId = widget.currentUser.parentId ?? widget.currentUser.id;
    _fetchSettings();
    _loadExistingCustomers();
  }

  void _fetchSettings() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('cafes').doc(widget.currentUser.cafeId).get();
      if (doc.exists && mounted) {
        setState(() {
          final data = doc.data() as Map<String, dynamic>;
          currencySymbol = data['currency_symbol'] ?? "₪";
          inactiveDaysThreshold = data['inactive_days_threshold'] ?? 15;
          _paymentMethods = List<String>.from(data['payment_methods'] ?? ["كاش", "شبكة", "دين"]);
        });
      }
    } catch (e) { debugPrint(e.toString()); }
  }

  void _loadExistingCustomers() {
    FirebaseFirestore.instance
        .collection('debts')
        .where('cafeId', isEqualTo: widget.currentUser.cafeId)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          final docs = snapshot.docs.where((d) => d.get('parentId') == managerId);
          _customerSuggestions = docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            double netBalance = (d['totalDebt'] ?? 0.0) - (d['initialBalance'] ?? 0.0) - (d['totalPaid'] ?? 0.0);
            return {
              'id': doc.id,
              'name': d['customer']?.toString() ?? "",
              'phone': d['phone']?.toString() ?? "",
              'debt': netBalance.toStringAsFixed(1),
              'no': (d['debtNo'] ?? "").toString(),
            };
          }).toList();
        });
      }
    });
  }

  void _openTakeawayOrder() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => OrderPage(tableId: "takeaway", tableName: "طلب سفري", currentUser: widget.currentUser)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    if (!widget.currentUser.canRead('dashboard')) {
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'dashboard',
        child: const Scaffold(body: Center(child: Text("عذراً، لا تملك صلاحية لعرض لوحة التحكم الرئيسية"))),
      );
    }

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'dashboard',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("الرئيسية والتحليل", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: primaryColor, foregroundColor: Colors.white, elevation: 0,
          actions: [
            IconButton(icon: const Icon(Icons.group_outlined), tooltip: "سجل الديون", onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebtsPage(currentUser: widget.currentUser)))),
            IconButton(icon: const Icon(Icons.bolt, color: Colors.amber), tooltip: "بيع سريع (سفري)", onPressed: _openTakeawayOrder),
            IconButton(icon: const Icon(Icons.add_card_rounded), tooltip: "إضافة حوالة سريعة", onPressed: () => DashboardDialogs.showAddTransferDialog(context: context, currentUser: widget.currentUser, paymentMethods: _paymentMethods, customerSuggestions: _customerSuggestions, managerId: managerId)),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildDetailedNetProfit(primaryColor),
              const SizedBox(height: 20),
              Row(children: [
                DashboardQuickButton(title: "سجل الديون", icon: Icons.people_alt_rounded, color: Colors.red[400]!, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebtsPage(currentUser: widget.currentUser)))),
                const SizedBox(width: 15),
                DashboardQuickButton(title: "بيع سفري", icon: Icons.flash_on_rounded, color: Colors.orange[400]!, onTap: _openTakeawayOrder),
              ]),
              const SizedBox(height: 25),
              _buildInventoryValueRow(),
              const SizedBox(height: 15),
              _buildDebtStatsRow(),
              const SizedBox(height: 15),
              _buildExpensesStatsRow(),
              const SizedBox(height: 25),
              WeeklySalesChart(cafeId: widget.currentUser.cafeId, managerId: managerId, primaryColor: primaryColor, currencySymbol: currencySymbol),
              const SizedBox(height: 25),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _buildInactiveCustomersSection()),
                const SizedBox(width: 20),
                Expanded(child: ExpensesPieChart(cafeId: widget.currentUser.cafeId, managerId: managerId)),
              ]),
              const SizedBox(height: 25),
              _buildTopSellingSection(primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedNetProfit(Color primary) {
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
            double totalSales = 0;
            double totalCOGS = 0; // تكلفة البضاعة المباعة
            double otherExpenses = 0; // مصاريف تشغيلية (ليست مشتريات)

            if (salesSnap.hasData) {
              for (var d in salesSnap.data!.docs) {
                final data = d.data() as Map;
                DateTime dt = (data['paid_at'] as Timestamp? ?? Timestamp.now()).toDate();
                if (dt.month == selectedDate.month && dt.year == selectedDate.year) {
                  if (data['is_debt_payment'] != true) {
                    totalSales += (data['total_amount'] ?? 0).toDouble();
                    // حساب التكلفة من الأصناف المباعة
                    List items = data['items'] as List? ?? [];
                    for (var item in items) {
                      double cost = (item['costPriceAtSale'] ?? 0.0).toDouble();
                      double qty = (item['quantity'] ?? 0.0).toDouble();
                      totalCOGS += (cost * qty);
                    }
                  }
                }
              }
            }

            if (expSnap.hasData) {
              for (var d in expSnap.data!.docs) {
                final data = d.data() as Map;
                DateTime dt = (data['date'] as Timestamp? ?? Timestamp.now()).toDate();
                if (dt.month == selectedDate.month && dt.year == selectedDate.year) {
                  // نحسب فقط المصاريف التي ليست مشتريات لتجنب التكرار مع COGS
                  if (data['category'] != "مشتريات") {
                    otherExpenses += (data['amount'] ?? 0).toDouble();
                  }
                }
              }
            }

            double grossProfit = totalSales - totalCOGS;
            double netProfit = grossProfit - otherExpenses;

            return Container(
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [primary, primary.withBlue(100)]),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [BoxShadow(color: primary.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))]
              ),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    _profitStat("المبيعات", totalSales, Colors.white70),
                    _profitStat("التكلفة", totalCOGS, Colors.white70),
                    _profitStat("المصاريف", otherExpenses, Colors.white70),
                  ]),
                  const Divider(color: Colors.white24, height: 30),
                  const Text("صافي أرباح الشهر (التقديري)", style: TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(height: 5),
                  Text("${netProfit.toStringAsFixed(1)} $currencySymbol", style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                    child: Text("هامش الربح: ${totalSales > 0 ? ((grossProfit/totalSales)*100).toStringAsFixed(1) : 0}%", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _profitStat(String label, double val, Color color) => Column(children: [
    Text(label, style: TextStyle(color: color, fontSize: 11)),
    Text("${val.toInt()} $currencySymbol", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
  ]);

  Widget _buildInventoryValueRow() {
    return Row(children: [
      Expanded(child: _buildInventoryValueStat("بضاعة المحل", 'products', Colors.blue)), // استخدام 'products' بدلاً من 'inventory' لقيمة البيع
      const SizedBox(width: 15),
      Expanded(child: _buildInventoryValueStat("المخزن (مواد)", 'inventory', Colors.orange)),
      const SizedBox(width: 15),
      Expanded(child: _buildDebtTotalStat()),
    ]);
  }

  Widget _buildInventoryValueStat(String title, String collection, Color color) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection(collection).where('cafeId', isEqualTo: widget.currentUser.cafeId).snapshots(),
      builder: (context, snapshot) {
        double totalValue = 0;
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['parentId'] != managerId) continue;
            double qty = collection == 'products' ? (data['stockQuantity'] ?? 0).toDouble() : (data['quantity'] ?? 0).toDouble();
            totalValue += (qty * (data['costPrice'] ?? 0).toDouble());
          }
        }
        return DashboardStatBox(label: title, value: totalValue, color: color, currencySymbol: currencySymbol);
      },
    );
  }

  Widget _buildDebtTotalStat() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('debts').where('cafeId', isEqualTo: widget.currentUser.cafeId).snapshots(),
      builder: (context, snapshot) {
        double totalOwed = 0;
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['parentId'] != managerId) continue;
            double net = (data['totalDebt'] ?? 0.0) - (data['initialBalance'] ?? 0.0) - (data['totalPaid'] ?? 0.0);
            if (net > 0) totalOwed += net;
          }
        }
        return DashboardStatBox(label: "إجمالي الديون", value: totalOwed, color: Colors.redAccent, currencySymbol: currencySymbol);
      },
    );
  }

  Widget _buildDebtStatsRow() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('debts').where('cafeId', isEqualTo: widget.currentUser.cafeId).snapshots(),
      builder: (context, snapshot) {
        double daily = 0, weekly = 0, monthly = 0;
        if (snapshot.hasData) {
          final now = DateTime.now();
          final startOfDay = DateTime(now.year, now.month, now.day);
          final startOfWeek = startOfDay.subtract(Duration(days: now.weekday - 1));
          final startOfMonth = DateTime(now.year, now.month, 1);
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['parentId'] != managerId) continue;
            double net = (data['totalDebt'] ?? 0.0) - (data['initialBalance'] ?? 0.0) - (data['totalPaid'] ?? 0.0);
            if (net <= 0) continue;
            DateTime dt = (data['lastUpdate'] as Timestamp? ?? data['date'] as Timestamp? ?? Timestamp.now()).toDate();
            if (dt.isAfter(startOfDay)) daily += net;
            if (dt.isAfter(startOfWeek)) weekly += net;
            if (dt.isAfter(startOfMonth)) monthly += net;
          }
        }
        return Row(children: [
          Expanded(child: DashboardStatBox(label: "ديون اليوم", value: daily, color: Colors.redAccent.withOpacity(0.8), currencySymbol: currencySymbol)),
          const SizedBox(width: 15),
          Expanded(child: DashboardStatBox(label: "ديون الأسبوع", value: weekly, color: Colors.orangeAccent, currencySymbol: currencySymbol)),
          const SizedBox(width: 15),
          Expanded(child: DashboardStatBox(label: "ديون الشهر", value: monthly, color: Colors.purpleAccent, currencySymbol: currencySymbol)),
        ]);
      },
    );
  }

  Widget _buildExpensesStatsRow() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('expenses').where('cafeId', isEqualTo: widget.currentUser.cafeId).snapshots(),
      builder: (context, snapshot) {
        double daily = 0, weekly = 0, monthly = 0;
        if (snapshot.hasData) {
          final now = DateTime.now();
          final startOfDay = DateTime(now.year, now.month, now.day);
          final startOfWeek = startOfDay.subtract(Duration(days: now.weekday - 1));
          final startOfMonth = DateTime(now.year, now.month, 1);
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['parentId'] != managerId) continue;
            double amount = (data['amount'] ?? 0.0).toDouble();
            DateTime dt = (data['date'] as Timestamp? ?? Timestamp.now()).toDate();
            if (dt.isAfter(startOfDay)) daily += amount;
            if (dt.isAfter(startOfWeek)) weekly += amount;
            if (dt.isAfter(startOfMonth)) monthly += amount;
          }
        }
        return Row(children: [
          Expanded(child: DashboardStatBox(label: "مصاريف اليوم", value: daily, color: Colors.red[300]!, currencySymbol: currencySymbol)),
          const SizedBox(width: 15),
          Expanded(child: DashboardStatBox(label: "مصاريف الأسبوع", value: weekly, color: Colors.orange[300]!, currencySymbol: currencySymbol)),
          const SizedBox(width: 15),
          Expanded(child: DashboardStatBox(label: "مصاريف الشهر", value: monthly, color: Colors.purple[300]!, currencySymbol: currencySymbol)),
        ]);
      },
    );
  }

  Widget _buildInactiveCustomersSection() {
    return Container(
      padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("زبائن غائبون (>$inactiveDaysThreshold يوم)", style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('debts').where('cafeId', isEqualTo: widget.currentUser.cafeId).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final now = DateTime.now();
            final inactive = snapshot.data!.docs.where((doc) {
              final data = doc.data() as Map;
              if (data['parentId'] != managerId) return false;
              DateTime last = data['lastUpdate']?.toDate() ?? DateTime.now();
              return now.difference(last).inDays > inactiveDaysThreshold;
            }).toList();
            if (inactive.isEmpty) return const Text("الكل ملتزم بالدفع ✅", style: TextStyle(fontSize: 11, color: Colors.green));
            return Column(children: inactive.take(4).map((d) => ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text((d.data() as Map)['customer'] ?? ""), trailing: const Icon(Icons.call, color: Colors.green, size: 18))).toList());
          },
        )
      ]),
    );
  }

  Widget _buildTopSellingSection(Color primary) {
    return Container(
      padding: const EdgeInsets.all(25), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("الأصناف الأكثر طلباً", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('payments').where('cafeId', isEqualTo: widget.currentUser.cafeId).limit(200).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const LinearProgressIndicator();
            Map<String, int> counts = {};
            for (var d in snapshot.data!.docs) {
              final data = d.data() as Map;
              if (data['parentId'] != managerId) continue;
              if (data['is_debt_payment'] == true) continue;
              for (var item in (data['items'] as List? ?? [])) {
                String name = item['name'] ?? "منتج";
                counts[name] = (counts[name] ?? 0) + (item['quantity'] as num? ?? 0).toInt();
              }
            }
            var sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
            if (sorted.isEmpty) return const Text("لا توجد مبيعات بعد", style: TextStyle(color: Colors.grey, fontSize: 12));
            return Column(children: sorted.take(5).map((e) => ListTile(leading: CircleAvatar(backgroundColor: primary.withOpacity(0.1), child: Text("${sorted.indexOf(e)+1}")), title: Text(e.key), trailing: Text("${e.value} قطعة"))).toList());
          },
        )
      ]),
    );
  }
}
