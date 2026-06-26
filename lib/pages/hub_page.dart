import 'package:flutter/material.dart';
import 'user_model.dart';
import 'homepage.dart';
import 'DashboardPage.dart';
import 'PurchasesPage.dart';
import 'DebtsPage.dart';
import 'MenuPage.dart';
import 'InventoryPage.dart';
import 'ExpensesPage.dart';
import 'UserManagementPage.dart';
import 'ReportPage.dart';
import '../widgets/app_components.dart';

class HubPage extends StatelessWidget {
  final User currentUser;
  const HubPage({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text("مركز الإدارة والتحكم", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 30),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: MediaQuery.of(context).size.width > 900 ? 4 : 2,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  childAspectRatio: 1.1,
                  children: [
                    AppComponents.hubCard(
                      context: context, 
                      title: "الصالة", 
                      subtitle: "إدارة الطاولات", 
                      icon: Icons.table_restaurant_rounded, 
                      color: Colors.blue, 
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HomePage(currentUser: currentUser)))
                    ),
                    AppComponents.hubCard(
                      context: context, 
                      title: "المنيو", 
                      subtitle: "تعديل المنتجات", 
                      icon: Icons.restaurant_menu_rounded, 
                      color: Colors.orange, 
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MenuPage(currentUser: currentUser)))
                    ),
                    AppComponents.hubCard(
                      context: context, 
                      title: "التحليل", 
                      subtitle: "إحصائيات المبيعات", 
                      icon: Icons.dashboard_customize_outlined, 
                      color: Colors.indigo, 
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DashboardPage(currentUser: currentUser)))
                    ),
                    AppComponents.hubCard(
                      context: context, 
                      title: "المخزن", 
                      subtitle: "مراقبة البضائع", 
                      icon: Icons.inventory_2_outlined, 
                      color: Colors.cyan, 
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InventoryPage(currentUser: currentUser)))
                    ),
                    AppComponents.hubCard(
                      context: context, 
                      title: "المصاريف", 
                      subtitle: "إدارة التكاليف", 
                      icon: Icons.payments_outlined, 
                      color: Colors.teal, 
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExpensesPage(currentUser: currentUser)))
                    ),
                    AppComponents.hubCard(
                      context: context, 
                      title: "الديون", 
                      subtitle: "حسابات الزبائن", 
                      icon: Icons.money_off_rounded, 
                      color: Colors.redAccent, 
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebtsPage(currentUser: currentUser)))
                    ),
                    AppComponents.hubCard(
                      context: context, 
                      title: "الموظفين", 
                      subtitle: "الصلاحيات والدوام", 
                      icon: Icons.people_alt_outlined, 
                      color: Colors.blueGrey, 
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserManagementPage(user: currentUser)))
                    ),
                    AppComponents.hubCard(
                      context: context, 
                      title: "التقارير", 
                      subtitle: "المحاسب المالي", 
                      icon: Icons.analytics_rounded, 
                      color: Colors.green, 
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportPage(currentUser: currentUser)))
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(30),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF232526), Color(0xFF414345)]), 
      borderRadius: BorderRadius.circular(25)
    ),
    child: const Row(
      children: [
        Icon(Icons.auto_awesome, color: Colors.amber, size: 40), 
        SizedBox(width: 20), 
        Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            Text("قمرة القيادة", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), 
            Text("وصول سريع لكافة أقسام النظام", style: TextStyle(color: Colors.white70, fontSize: 13))
          ]
        )
      ]
    ),
  );
}
