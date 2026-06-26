import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';
import 'Market.dart';
import 'DashboardPage.dart';
import 'DebtsPage.dart';
import 'MenuPage.dart';
import 'InventoryPage.dart';
import 'ExpensesPage.dart';
import 'UserManagementPage.dart';
import 'ReportPage.dart';
import 'TransfersPage.dart';
import 'MainLayout.dart';
import 'ExternalWarehousePage.dart';
import 'RemindersPage.dart';
import 'PurchasesPage.dart';
import 'LogsPage.dart';
import 'ChecksPage.dart';
import 'AttendancePage.dart';
import 'KitchenPage.dart';
import 'WarehouseTransfersPage.dart';
import 'ProductProfitsPage.dart';
import 'DailySalesPage.dart';
import 'SettingsPage.dart';
import 'SuppliersPage.dart';
import '../widgets/calculator_widget.dart';

class HubPage extends StatelessWidget {
  final User currentUser;
  const HubPage({super.key, required this.currentUser});

  void _showCalculator(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CalculatorWidget(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MainLayout(
      currentUser: currentUser,
      currentPage: 'hub',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildModernHeader(context, theme),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(right: 5, bottom: 12),
                child: Row(
                  children: [
                    Container(width: 4, height: 16, decoration: BoxDecoration(color: theme.primaryColor, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Text(
                      "الأقسام المتاحة لك",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]),
                    ),
                  ],
                ),
              ),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: MediaQuery.of(context).size.width > 1200 ? 6 : (MediaQuery.of(context).size.width > 800 ? 4 : 2),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.15,
                children: [
                  if (currentUser.canRead('orders'))
                    _hubCard(
                        context: context,
                        title: "الكاشير",
                        subtitle: "نظام البيع",
                        icon: Icons.shopping_basket_rounded,
                        color: const Color(0xFF1A73E8),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Market(currentUser: currentUser)))
                    ),
                  if (currentUser.canRead('kitchen'))
                    _hubCard(
                        context: context,
                        title: "المطبخ",
                        subtitle: "تجهيز الطلبات",
                        icon: Icons.soup_kitchen_outlined,
                        color: Colors.orange[800]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => KitchenPage(currentUser: currentUser)))
                    ),
                  if (currentUser.canEditMenu)
                    _hubCard(
                        context: context,
                        title: "المنتجات",
                        subtitle: "إدارة الأصناف",
                        icon: Icons.restaurant_menu_rounded,
                        color: Colors.orange[700]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MenuPage(currentUser: currentUser)))
                    ),
                  if (currentUser.canRead('suppliers'))
                    _hubCard(
                        context: context,
                        title: "الموردين",
                        subtitle: "حسابات الموردين",
                        icon: Icons.business_rounded,
                        color: Colors.blueGrey[600]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SuppliersPage(currentUser: currentUser)))
                    ),
                  if (currentUser.canRead('purchases'))
                    _hubCard(
                        context: context,
                        title: "المشتريات",
                        subtitle: "تزويد المخزون",
                        icon: Icons.add_shopping_cart_rounded,
                        color: Colors.pink[700]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurchasesPage(currentUser: currentUser)))
                    ),
                  if (currentUser.canRead('inventory')) ...[
                    _hubCard(
                        context: context,
                        title: "المخزن",
                        subtitle: "مراقبة البضائع",
                        icon: Icons.inventory_2_rounded,
                        color: Colors.cyan[700]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InventoryPage(currentUser: currentUser)))
                    ),
                    _hubCard(
                        context: context,
                        title: "المخزن الرئيسي",
                        subtitle: "التوريدات الكبرى",
                        icon: Icons.home_work_rounded,
                        color: Colors.brown[600]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExternalWarehousePage(currentUser: currentUser)))
                    ),
                  ],
                  if (currentUser.canRead('warehouse_transfers'))
                    _hubCard(
                        context: context,
                        title: "سجل النقل",
                        subtitle: "حركة المخزون",
                        icon: Icons.history_edu_rounded,
                        color: Colors.blueGrey[800]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WarehouseTransfersPage(currentUser: currentUser)))
                    ),
                  if (currentUser.canRead('debts'))
                    _hubCard(
                        context: context,
                        title: "الديون",
                        subtitle: "حسابات الزبائن",
                        icon: Icons.money_off_rounded,
                        color: Colors.redAccent[700]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebtsPage(currentUser: currentUser)))
                    ),
                  if (currentUser.canRead('expenses'))
                    _hubCard(
                        context: context,
                        title: "المصاريف",
                        subtitle: "إدارة التكاليف",
                        icon: Icons.payments_outlined,
                        color: Colors.teal[600]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExpensesPage(currentUser: currentUser)))
                    ),
                  if (currentUser.canRead('checks'))
                    _hubCard(
                        context: context,
                        title: "الشيكات",
                        subtitle: "الصادرة والواردة",
                        icon: Icons.style_outlined,
                        color: Colors.blue[800]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChecksPage(currentUser: currentUser)))
                    ),
                  if (currentUser.canRead('transfers'))
                    _hubCard(
                        context: context,
                        title: "الحوالات",
                        subtitle: "سجل السداد",
                        icon: Icons.history,
                        color: Colors.deepPurple[600]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransfersPage(currentUser: currentUser)))
                    ),
                  if (currentUser.canRead('attendance'))
                    _hubCard(
                        context: context,
                        title: "سجل الدوام",
                        subtitle: "الحضور والانصراف",
                        icon: Icons.access_time_rounded,
                        color: Colors.blueAccent[700]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttendancePage(currentUser: currentUser)))
                    ),
                  if (currentUser.canViewDashboard) ...[
                    _hubCard(
                        context: context,
                        title: "التحليل",
                        subtitle: "إحصائيات المبيعات",
                        icon: Icons.dashboard_customize_outlined,
                        color: Colors.green[600]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DashboardPage(currentUser: currentUser)))
                    ),
                    _hubCard(
                        context: context,
                        title: "أرباح الأصناف",
                        subtitle: "تحليل الربحية",
                        icon: Icons.pie_chart_outline_rounded,
                        color: Colors.orange[800]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductProfitsPage(currentUser: currentUser)))
                    ),
                    _hubCard(
                        context: context,
                        title: "المبيعات اليومية",
                        subtitle: "كشف يومي",
                        icon: Icons.view_day_outlined,
                        color: Colors.green[800]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DailySalesPage(currentUser: currentUser)))
                    ),
                  ],
                  if (currentUser.canRead('reminders'))
                    _hubCard(
                        context: context,
                        title: "التنبيهات",
                        subtitle: "المواعيد والمهام",
                        icon: Icons.notifications_active_rounded,
                        color: Colors.pink[600]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RemindersPage(currentUser: currentUser)))
                    ),
                  if (currentUser.canManageUsers)
                    _hubCard(
                        context: context,
                        title: "الموظفين",
                        subtitle: "إدارة الصلاحيات",
                        icon: Icons.people_alt_outlined,
                        color: Colors.blueGrey[700]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserManagementPage(user: currentUser)))
                    ),
                  if (currentUser.canViewReports)
                    _hubCard(
                        context: context,
                        title: "التقارير",
                        subtitle: "المحاسب المالي",
                        icon: Icons.analytics_rounded,
                        color: Colors.indigo[700]!,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportPage(currentUser: currentUser)))
                    ),
                  if (currentUser.role == UserRole.admin || currentUser.role == UserRole.super_admin)
                    _hubCard(
                        context: context,
                        title: "الرقابة",
                        subtitle: "سجل العمليات",
                        icon: Icons.security_outlined,
                        color: Colors.black,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LogsPage(currentUser: currentUser)))
                    ),
                  _hubCard(
                      context: context,
                      title: "الإعدادات",
                      subtitle: "تخصيص النظام",
                      icon: Icons.settings_outlined,
                      color: Colors.blueGrey[400]!,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(user: currentUser)))
                  ),
                  _hubCard(
                    context: context,
                    title: "الحاسبة",
                    subtitle: "حسابات سريعة",
                    icon: Icons.calculate_rounded,
                    color: Colors.deepOrange[600]!,
                    onTap: () => _showCalculator(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernHeader(BuildContext context, ThemeData theme) {
    final startOfDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final bool canViewStats = currentUser.role == UserRole.super_admin || currentUser.role == UserRole.admin;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.primaryColor, theme.primaryColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(color: theme.primaryColor.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.auto_awesome, color: Colors.amber, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("أهلاً بك، ${currentUser.name}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const Text("لوحة التحكم السريعة", style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          if (canViewStats) ...[
            const SizedBox(height: 15),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('payments')
                  .where('cafeId', isEqualTo: currentUser.cafeId)
                  .where('paid_at', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
                  .snapshots(),
              builder: (context, snapshot) {
                double todayTotal = 0;
                int ordersCount = 0;
                if (snapshot.hasData) {
                  ordersCount = snapshot.data!.docs.length;
                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>?;
                    if (data != null) {
                      todayTotal += (data['total_amount'] ?? data['amount'] ?? 0.0).toDouble();
                    }
                  }
                }
                return Row(
                  children: [
                    _headerStat("مبيعات اليوم", "${todayTotal.toInt()} ₪", Icons.trending_up),
                    const SizedBox(width: 12),
                    _headerStat("طلبات اليوم", "$ordersCount", Icons.receipt_long),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _headerStat(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9)),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hubCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.withOpacity(0.08), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withOpacity(0.08), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87), textAlign: TextAlign.center),
              Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 9), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
