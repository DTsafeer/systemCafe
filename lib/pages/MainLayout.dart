import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'homepage.dart';
import 'user_model.dart';
import 'CurrentOrdersPage.dart';
import 'DashboardPage.dart';
import 'MenuPage.dart';
import 'SettingsPage.dart';
import 'KitchenPage.dart';
import 'InventoryPage.dart';
import 'HubPage.dart';
import 'ProfilePage.dart';
import 'LoginPage.dart';
import 'TransfersPage.dart';
import 'DebtsPage.dart';
import 'LogsPage.dart';
import 'ExpensesPage.dart';
import 'SuppliersPage.dart';
import 'ChecksPage.dart';
import 'ReportPage.dart'; 
import 'ExternalWarehousePage.dart';
import 'WarehouseTransfersPage.dart';
import 'AttendancePage.dart';
import 'UserManagementPage.dart';
import 'RemindersPage.dart';
import 'NotificationService.dart';
import 'AuthService.dart';
import 'PurchasesPage.dart';
import 'ProductProfitsPage.dart';
import 'DailySalesPage.dart';
import 'CategoryManagementPage.dart';
import 'orderpage.dart';
import '../widgets/calculator_widget.dart';

class UserDataProvider extends InheritedWidget {
  final User updatedUser;
  const UserDataProvider({super.key, required this.updatedUser, required super.child});

  static User of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<UserDataProvider>()!.updatedUser;
  }

  @override
  bool updateShouldNotify(UserDataProvider oldWidget) => updatedUser != oldWidget.updatedUser;
}

class MainLayout extends StatefulWidget {
  final Widget child;
  final User currentUser;
  final String currentPage;
  final Widget? floatingActionButton;

  const MainLayout({
    super.key,
    required this.child,
    required this.currentUser,
    required this.currentPage,
    this.floatingActionButton,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> with SingleTickerProviderStateMixin {
  static String? _cachedCafeId;
  static bool? _cachedKitchenEnabled;
  static String? _cachedCafeName;

  bool isKitchenEnabled = _cachedKitchenEnabled ?? true;
  String cafeName = _cachedCafeName ?? "Flora Cafe POS";
  String userName = "";
  Map<String, dynamic> userPermissions = {};

  StreamSubscription? _cafeSub;
  StreamSubscription? _userSub;
  Timer? _scheduledStopTimer;
  Timer? _warningTimer;
  String? _safeCafeId = _cachedCafeId;
  bool _hasShownWarning = false;

  // Scanner detection logic
  bool _isScannerActive = false;
  DateTime? _lastKeyEventTime;
  int _fastKeyCount = 0;
  String _barcodeBuffer = "";
  late AnimationController _scannerPulseController;

  @override
  void initState() {
    super.initState();
    userName = widget.currentUser.name;
    userPermissions = widget.currentUser.permissions;
    _safeCafeId = widget.currentUser.cafeId.isNotEmpty ? widget.currentUser.cafeId : _cachedCafeId;
    _initSafeData();
    _listenToUpdates();

    _scannerPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final now = DateTime.now();
      
      if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        if (_barcodeBuffer.isNotEmpty && _fastKeyCount > 3) {
          _handleExternalBarcodeScan(_barcodeBuffer);
        }
        _barcodeBuffer = "";
        _fastKeyCount = 0;
        return false;
      }

      if (event.character != null && event.character!.isNotEmpty) {
        if (_lastKeyEventTime != null) {
          final diff = now.difference(_lastKeyEventTime!).inMilliseconds;
          if (diff < 50) {
            _fastKeyCount++;
            _barcodeBuffer += event.character!;
          } else {
            _barcodeBuffer = event.character!;
            _fastKeyCount = 0;
          }
        } else {
          _barcodeBuffer = event.character!;
        }
        _lastKeyEventTime = now;
      }

      if (_fastKeyCount > 5 && !_isScannerActive) {
        setState(() => _isScannerActive = true);
        _resetScannerStatusAfterDelay();
      }
    }
    return false;
  }

  void _handleExternalBarcodeScan(String code) {
    debugPrint("🚀 تم رصد باركود من الخارج: $code");
    
    // التعديل: لا ننتقل لصفحة الكاشير إذا كنا في صفحة "المنيو" أو "المخزن"
    // لكي نسمح للمستخدم بإضافة الباركود للمنتجات الجديدة بسلام
    List<String> ignorePages = ["menu", "inventory", "external_warehouse", "purchases"];
    
    if (widget.currentPage != "orders" && !ignorePages.contains(widget.currentPage)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OrderPage(
            currentUser: widget.currentUser,
            tableId: "takeaway",
            tableName: "سفري (سريع)",
            restoreData: {
              'initial_barcode': code
            },
          ),
        ),
      );
    }
  }

  void _resetScannerStatusAfterDelay() {
    Timer(const Duration(minutes: 1), () {
      if (mounted) setState(() => _isScannerActive = false);
    });
  }

  Future<void> _initSafeData() async {
    if (_safeCafeId == null || _safeCafeId!.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      String? savedId = prefs.getString('cafe_id');
      if (savedId != null && mounted) {
        setState(() {
          _safeCafeId = savedId;
          _cachedCafeId = savedId;
        });
        _listenToUpdates();
      }
    }
  }

  void _listenToUpdates() {
    if (_safeCafeId != null && _safeCafeId!.isNotEmpty) {
      _cafeSub?.cancel();
      _cafeSub = FirebaseFirestore.instance.collection('cafes').doc(_safeCafeId).snapshots().listen((doc) {
        if (doc.exists && mounted) {
          final data = doc.data()!;

          if (widget.currentUser.role != UserRole.super_admin) {
            bool isActive = data['isActive'] ?? true;
            if (!isActive) {
              _handleSystemStop(data['blockReason'] ?? "تم إيقاف عمل المنشأة من قبل الإدارة");
              return;
            }
          }

          setState(() {
            isKitchenEnabled = (data['features'] != null) ? (data['features']['kitchen'] ?? true) : true;
            _cachedKitchenEnabled = isKitchenEnabled;
            cafeName = data['cafeName'] ?? data['cafe_name'] ?? "Flora Cafe POS";
            _cachedCafeName = cafeName;
          });
        }
      });
    }

    _userSub?.cancel();
    _userSub = FirebaseFirestore.instance.collection('users').doc(widget.currentUser.id).snapshots().listen((doc) {
      if (!doc.exists) {
        _handleSystemStop("عذراً، تم حذف حسابك من قبل الإدارة");
        return;
      }
      
      if (mounted) {
        final data = doc.data()!;
        bool isActive = data['isActive'] ?? true;
        
        if (!isActive && widget.currentUser.role != UserRole.super_admin && widget.currentUser.role != UserRole.admin) {
          _handleSystemStop("تم تعليق عمل حسابك بشكل مؤقت من قبل الإدارة");
          return;
        }

        setState(() {
          userName = data['name'] ?? widget.currentUser.name;
          userPermissions = Map<String, dynamic>.from(data['permissions'] ?? {});
        });
      }
    });
  }

  void _handleSystemStop(String reason) {
    _cafeSub?.cancel();
    _userSub?.cancel();
    
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 30),
              SizedBox(width: 10),
              Text("تنبيه أمني", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(reason, style: const TextStyle(fontSize: 16)),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: () => _logout(),
                child: const Text("الخروج من النظام"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _scannerPulseController.dispose();
    _cafeSub?.cancel();
    _userSub?.cancel();
    _scheduledStopTimer?.cancel();
    _warningTimer?.cancel();
    super.dispose();
  }

  Future<void> _logout() async {
    _cachedCafeId = null;
    _cachedKitchenEnabled = null;
    _cachedCafeName = null;
    await AuthService.logout(currentUser: widget.currentUser);
    if (mounted) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false);
    }
  }

  void _showCalculator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CalculatorWidget(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final updatedUser = widget.currentUser.copyWith(
      name: userName,
      permissions: userPermissions,
      cafeId: _safeCafeId ?? widget.currentUser.cafeId,
    );

    return UserDataProvider(
      updatedUser: updatedUser,
      child: LayoutBuilder(
        builder: (context, constraints) {
          bool isMobile = constraints.maxWidth < 850;
          final theme = Theme.of(context);
          final primaryColor = theme.colorScheme.primary;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: Scaffold(
                floatingActionButton: widget.floatingActionButton,
                appBar: AppBar(
                  elevation: 0.5,
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  title: _buildAppBarContent(isMobile, updatedUser, Colors.white),
                  leading: isMobile ? Builder(builder: (context) => IconButton(icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(context).openDrawer())) : null,
                  actions: [
                    _buildScannerStatus(),
                    IconButton(icon: const Icon(Icons.calculate_outlined), onPressed: _showCalculator, tooltip: "الآلة الحاسبة"),
                    if (_safeCafeId != null)
                      NotificationBell(cafeId: _safeCafeId!, userRole: widget.currentUser.role.name),
                    const SizedBox(width: 8),
                  ],
                ),
                drawer: isMobile ? Drawer(child: _buildSideNav(theme, primaryColor, updatedUser, true)) : null,
                body: (_safeCafeId == null || _safeCafeId!.isEmpty)
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      children: [
                        if (!isMobile) _buildSideNav(theme, primaryColor, updatedUser, false),
                        Expanded(child: Container(color: const Color(0xFFF8F9FA), child: widget.child)),
                      ],
                    ),
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildScannerStatus() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Tooltip(
        message: _isScannerActive ? "تم رصد نشاط للماسح" : "بانتظار استخدام الماسح",
        child: AnimatedBuilder(
          animation: _scannerPulseController,
          builder: (context, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.barcode_reader,
                  size: 18,
                  color: _isScannerActive ? Colors.greenAccent : Colors.white24,
                ),
                if (_isScannerActive)
                  Container(
                    width: 6, height: 6,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.greenAccent.withOpacity(0.5 + 0.5 * _scannerPulseController.value),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.greenAccent.withOpacity(0.3),
                          blurRadius: 5,
                          spreadRadius: 2,
                        )
                      ]
                    ),
                  ),
                const SizedBox(width: 4),
                Text(
                  _isScannerActive ? "نشط" : "جاهز",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _isScannerActive ? Colors.greenAccent : Colors.white24,
                  ),
                )
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppBarContent(bool isMobile, User user, Color iconColor) {
    return Row(
      children: [
        if (!isMobile) IconButton(icon: const Icon(Icons.grid_view_rounded), color: iconColor, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HubPage(currentUser: user)))),
        const SizedBox(width: 10),
        Text(cafeName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const Spacer(),
        _buildUserInfo(iconColor, user),
      ],
    );
  }

  Widget _buildUserInfo(Color iconColor, User user) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(user: user))),
      child: Row(children: [
        Text(user.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(width: 10),
        CircleAvatar(radius: 14, backgroundColor: Colors.white.withOpacity(0.2), child: const Icon(Icons.person, size: 18, color: Colors.white))
      ]),
    );
  }

  Widget _buildSideNav(ThemeData theme, Color primaryColor, User user, bool isDrawer) {
    return Container(
      width: isDrawer ? null : 110, 
      decoration: BoxDecoration(
        color: Colors.white,
        border: isDrawer ? null : Border(left: BorderSide(color: Colors.grey[200]!))
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: _getMenuItems(theme, user, isDrawer),
            ),
          ),
          const Divider(height: 1),
          _SideNavItem(icon: Icons.logout, label: "خروج", id: "logout", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: _logout),
          const SizedBox(height: 15),
        ],
      ),
    );
  }

  List<Widget> _getMenuItems(ThemeData theme, User user, bool isDrawer) {
    return [
      _SideNavItem(icon: Icons.home_outlined, label: "الرئيسية", id: "home", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(HomePage(currentUser: user), "home")),
      if (user.canRead('orders')) _SideNavItem(icon: Icons.receipt_long_outlined, label: "الكاشير", id: "orders", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(CurrentOrdersPage(currentUser: user), "orders")),
      if (user.canRead('transfers')) _SideNavItem(icon: Icons.history, label: "حوالات", id: "transfers", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(TransfersPage(currentUser: user), "transfers")),
      if (user.canRead('debts')) _SideNavItem(icon: Icons.account_balance_wallet_outlined, label: "الديون", id: "debts", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(DebtsPage(currentUser: user), "debts")),
      if (user.canEditMenu) ...[
        _SideNavItem(icon: Icons.restaurant_menu_rounded, label: "المنتجات", id: "menu", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(MenuPage(currentUser: user), "menu")),
        _SideNavItem(icon: Icons.category_outlined, label: "الأقسام", id: "categories", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(CategoryManagementPage(currentUser: user), "categories")),
      ],

      const Divider(height: 20, indent: 20, endIndent: 20),
      if (isKitchenEnabled && user.canViewKitchen) _SideNavItem(icon: Icons.soup_kitchen_outlined, label: "المطبخ", id: "kitchen", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(KitchenPage(currentUser: user), "kitchen")),
      if (user.canRead('attendance')) _SideNavItem(icon: Icons.access_time_rounded, label: "سجل الدوام", id: "attendance", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(AttendancePage(currentUser: user), "attendance")),
      if (user.canRead('suppliers')) _SideNavItem(icon: Icons.business_rounded, label: "الموردين", id: "suppliers", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(SuppliersPage(currentUser: user), "suppliers")),
      if (user.canRead('purchases')) _SideNavItem(icon: Icons.shopping_cart_checkout_rounded, label: "المشتريات", id: "purchases", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(PurchasesPage(currentUser: user), "purchases")),
      if (user.canRead('expenses')) _SideNavItem(icon: Icons.payments_outlined, label: "المصاريف", id: "expenses", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(ExpensesPage(currentUser: user), "expenses")),
      if (user.canRead('checks')) _SideNavItem(icon: Icons.style_outlined, label: "الشيكات", id: "checks", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(ChecksPage(currentUser: user), "checks")),

      const Divider(height: 20, indent: 20, endIndent: 20),
      if (user.canRead('inventory')) ...[
        _SideNavItem(icon: Icons.inventory_2_outlined, label: "المخزن", id: "inventory", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(InventoryPage(currentUser: user), "inventory")),
        _SideNavItem(icon: Icons.warehouse_rounded, label: "المخزن الرئيسي", id: "external_warehouse", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(ExternalWarehousePage(currentUser: user), "external_warehouse")),
        if (user.canRead('warehouse_transfers')) _SideNavItem(icon: Icons.history_edu_rounded, label: "سجل النقل", id: "warehouse_transfers", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(WarehouseTransfersPage(currentUser: user), "warehouse_transfers")),
      ],

      const Divider(height: 20, indent: 20, endIndent: 20),
      if (user.canRead('reminders')) _SideNavItem(icon: Icons.notification_important_outlined, label: "تنبيهات", id: "reminders", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(RemindersPage(currentUser: user), "reminders")),
      
      if (user.canViewDashboard) ...[
        _SideNavItem(icon: Icons.dashboard_customize_outlined, label: "التحليل", id: "dashboard", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(DashboardPage(currentUser: user), "dashboard")),
        _SideNavItem(icon: Icons.pie_chart_outline_rounded, label: "أرباح الأصناف", id: "product_profits", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(ProductProfitsPage(currentUser: user), "product_profits")),
        _SideNavItem(icon: Icons.view_day_outlined, label: "المبيعات اليومية", id: "daily_sales", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(DailySalesPage(currentUser: user), "daily_sales")),
      ],

      if (user.canViewReports) 
        _SideNavItem(icon: Icons.analytics_outlined, label: "التقارير", id: "reports", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(ReportPage(currentUser: user), "reports")),
      
      if (user.role == UserRole.admin || user.role == UserRole.super_admin)
        _SideNavItem(icon: Icons.security_outlined, label: "الرقابة", id: "logs", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(LogsPage(currentUser: user), "logs")),

      if (user.canManageUsers) 
        _SideNavItem(icon: Icons.people_alt_outlined, label: "الموظفين", id: "users", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(UserManagementPage(user: user), "users")),
      
      _SideNavItem(icon: Icons.settings_outlined, label: "الإعدادات", id: "settings", activePage: widget.currentPage, theme: theme, isDrawer: isDrawer, onTap: () => _nav(SettingsPage(user: user), "settings")),
    ];
  }

  void _nav(Widget page, String key) {
    if (widget.currentPage == key) return;
    if (!mounted) return;
    Navigator.pushReplacement(context, PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 150),
    ));
  }
}

class _SideNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String id;
  final String activePage;
  final ThemeData theme;
  final VoidCallback onTap;
  final bool isDrawer;

  const _SideNavItem({
    required this.icon,
    required this.label,
    required this.id,
    required this.activePage,
    required this.theme,
    required this.onTap,
    this.isDrawer = false,
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
              Icon(icon, color: color, size: 24), 
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13, 
                  fontWeight: active ? FontWeight.bold : FontWeight.w600,
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

extension UserExtension on User {
  User copyWith({String? name, Map<String, dynamic>? permissions, String? cafeId}) {
    return User(id: id, name: name ?? this.name, email: email, password: password, role: role, cafeId: cafeId ?? this.cafeId, permissions: permissions ?? this.permissions, parentId: parentId, isOnline: isOnline, isActive: isActive, profileImageUrl: profileImageUrl, deviceId: deviceId);
  }
}
