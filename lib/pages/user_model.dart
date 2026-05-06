enum UserRole { admin, manager, cashier, waiter, kitchen, cleaner }

class User {
  final String id;
  final String name;
  final String email;
   final String password;
  final UserRole role;
  final String cafeId; // معرف الكافيه التابع له المستخدم
  final String? profileImageUrl;
  final Map<String, dynamic> permissions;
  final bool isOnline;
  final bool isActive;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    required this.cafeId, // الحقل المطلوب
    this.profileImageUrl,
    this.permissions = const {},
    required this.isOnline,
    required this.isActive,
  });

  // --- الصلاحيات الذكية (التحكم في الظهور والإخفاء بناءً على الرتبة أو الصلاحيات الممنوحة) ---

  // الإدارة العامة والتقارير والداشبورد
  bool get canManageUsers => _check(permissions['canManageUsers']) || role == UserRole.admin;
  bool get canViewReports => _check(permissions['canViewReports']) || role == UserRole.admin;

  // صلاحية المخزن
  bool get canViewInventory => permissions['canViewInventory'] == true;

  // صلاحية الداشبورد (لوحة الإحصائيات)
  bool get canViewDashboard => permissions['canViewDashboard'] == true;

  // المنيو والطاولات
  bool get canEditMenu => _check(permissions['canEditMenu']) || role == UserRole.admin;
  bool get canManageTables => _check(permissions['canManageTables']) || role == UserRole.admin;
  bool get canEditTable => _check(permissions['canEditTable']) || role == UserRole.admin || role == UserRole.manager;

  // الطلبات والمطبخ
  bool get canMakeOrders => _check(permissions['canMakeOrders']) || (role != UserRole.cleaner && role != UserRole.kitchen);
  bool get canPayOrders => _check(permissions['canPayOrders']) || role == UserRole.admin || role == UserRole.cashier;
  bool get canViewActiveOrders => _check(permissions['canViewActiveOrders']) || role != UserRole.cleaner;
  bool get canViewKitchen => permissions['canViewKitchen'] == true;

  // دالة مساعدة للتأكد من القيمة المنطقية وتجنب الـ null
  bool _check(dynamic value) => value == true;

  factory User.fromMap(Map<String, dynamic> data, String documentId) {
    return User(
      id: documentId,
      cafeId: data['cafeId'] ?? '', // ✅ جلب الـ cafeId من Firestore
      name: data['name'] ?? 'بدون اسم',
      email: data['email'] ?? '',
      isActive: data['isActive'] ?? true,
      password: data['password'] ?? '',
      isOnline: data['isOnline'] ?? false,
      profileImageUrl: data['profileImageUrl'],
      // التأكد من تحويل الصلاحيات لخريطة بشكل آمن
      permissions: data['permissions'] is Map ? Map<String, dynamic>.from(data['permissions']) : {},
      role: UserRole.values.firstWhere(
            (e) => e.name == (data['role'] ?? 'waiter'),
        orElse: () => UserRole.waiter,
      ),
    );
  }
}