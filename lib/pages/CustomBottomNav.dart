import 'package:flutter/material.dart';
import 'homepage.dart';
import 'CurrentOrdersPage.dart';
import 'DashboardPage.dart';
import 'addproduct.dart';
import 'UserManagementPage.dart';
import 'SettingsPage.dart';
import 'AttendancePage.dart';
import 'user_model.dart';

class CustomBottomNav extends StatelessWidget {
  final User currentUser;
  final String currentPage;

  const CustomBottomNav({
    super.key,
    required this.currentUser,
    required this.currentPage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: BottomAppBar(
        height: 75,
        elevation: 0,
        color: Colors.transparent,
        padding: EdgeInsets.zero,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(context, Icons.home_rounded, "الرئيسية", 'home', primary, () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomePage(currentUser: currentUser)));
                }),
                _navItem(context, Icons.receipt_long_rounded, "الطلبات", 'orders', primary, () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CurrentOrdersPage(currentUser: currentUser)));
                }),
                _navItem(context, Icons.analytics_rounded, "التحليل", 'reports', primary, () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardPage(currentUser: currentUser)));
                }),
                
                if (currentUser.canRead('attendance'))
                  _navItem(context, Icons.access_time_rounded, "الدوام", 'attendance', primary, () {
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AttendancePage(currentUser: currentUser)));
                  }),
                
                if (currentUser.canEditMenu)
                  _navItem(context, Icons.restaurant_menu_rounded, "المنيو", 'menu', primary, () {
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AddProduct(currentUser: currentUser)));
                  }),

                if (currentUser.canManageUsers)
                  _navItem(context, Icons.people_alt_rounded, "الموظفين", 'users', primary, () {
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => UserManagementPage(user: currentUser)));
                  }),

                _navItem(context, Icons.settings_rounded, "الإعدادات", 'settings', primary, () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SettingsPage(user: currentUser)));
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, IconData icon, String label, String key, Color primary, VoidCallback onTap) {
    final isActive = currentPage == key;
    
    return SizedBox(
      width: 65,
      child: InkWell(
        onTap: isActive ? null : onTap,
        splashColor: primary.withOpacity(0.1),
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? primary.withOpacity(0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isActive ? primary : Colors.blueGrey[300],
                size: 22,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                color: isActive ? primary : Colors.blueGrey[400],
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
