import 'package:flutter/material.dart';
import '../pages/user_model.dart';

class SideNav extends StatelessWidget {
  final User user;
  final String currentPage;
  final bool isKitchenEnabled;
  final Function(Widget, String) onNavigate;
  final VoidCallback onLogout;

  const SideNav({
    super.key,
    required this.user,
    required this.currentPage,
    required this.isKitchenEnabled,
    required this.onNavigate,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    // سيتم استدعاء الصفحات هنا لاحقاً لتجنب الـ circular imports إذا لزم الأمر
    // أو تمرير الـ Widgets جاهزة من الخارج.
    
    return Column(
      children: [
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _SideNavItem(
                icon: Icons.home_outlined, 
                label: "الرئيسية", 
                id: "home", 
                activePage: currentPage, 
                theme: theme, 
                onTap: () => onNavigate(const SizedBox(), "home") // Placeholder
              ),
              // سيتم تمرير هذه القائمة بشكل ديناميكي لضمان نظافة الكود
            ],
          ),
        ),
        const Divider(height: 1),
        _SideNavItem(
          icon: Icons.logout, 
          label: "خروج", 
          id: "logout", 
          activePage: currentPage, 
          theme: theme, 
          onTap: onLogout
        ),
        const SizedBox(height: 15),
      ],
    );
  }
}

class _SideNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String id;
  final String activePage;
  final ThemeData theme;
  final VoidCallback onTap;

  const _SideNavItem({
    required this.icon,
    required this.label,
    required this.id,
    required this.activePage,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool active = activePage == id;
    final Color color = active ? theme.colorScheme.primary : (id == "logout" ? Colors.red : Colors.grey[600]!);
    
    return Material(
      color: active ? theme.colorScheme.primary.withOpacity(0.12) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
