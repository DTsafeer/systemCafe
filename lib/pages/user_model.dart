enum UserRole { super_admin, admin, manager, cashier, waiter, kitchen, cleaner, custom }

class User {
  final String id;
  final String name;
  final String email; 
  final String password;
  final UserRole role;
  final String cafeId;
  final String? parentId; 
  final String? profileImageUrl;
  final Map<String, dynamic> permissions; // الهيكل الجديد: {"debts": {"r": true, "c": false, "u": false, "d": false}}
  final bool isOnline;
  final bool isActive;
  final String? deviceId; 
  final String? workStartTime;
  final String? workEndTime;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    required this.cafeId,
    this.parentId,
    this.profileImageUrl,
    this.permissions = const {},
    required this.isOnline,
    required this.isActive,
    this.deviceId,
    this.workStartTime,
    this.workEndTime,
  });

  // دالة فحص الصلاحيات الشاملة
  bool hasPermission(String page, String action) {
    if (role == UserRole.super_admin || role == UserRole.admin) return true;
    
    final pagePerms = permissions[page];
    if (pagePerms == null || pagePerms is! Map) return false;
    
    return pagePerms[action] == true;
  }

  // اختصارات CRUD
  bool canRead(String page) => hasPermission(page, 'r');
  bool canCreate(String page) => hasPermission(page, 'c');
  bool canUpdate(String page) => hasPermission(page, 'u');
  bool canDelete(String page) => hasPermission(page, 'd');

  // توافق مع الأكواد القديمة - ربط الجيترز القديمة بالنظام الجديد
  bool get canManageUsers => canUpdate('users') || canRead('users');
  bool get canViewReports => canRead('reports');
  bool get canViewInventory => canRead('inventory');
  bool get canViewDashboard => canRead('dashboard');
  bool get canEditMenu => canUpdate('menu');
  bool get canManageTables => canUpdate('tables');
  bool get canEditTable => canUpdate('tables');
  bool get canMakeOrders => canCreate('orders');
  bool get canPayOrders => canUpdate('orders');
  bool get canViewActiveOrders => canRead('orders');
  bool get canViewKitchen => canRead('kitchen');
  bool get canDeleteOrders => canDelete('orders');
  bool get canTransferOrders => canUpdate('orders');
  bool get canTransferItems => canUpdate('orders');
  bool get canManageSettings => canUpdate('settings');
  bool get canViewDebts => canRead('debts');
  bool get canManageDebts => canUpdate('debts') || canCreate('debts');

  factory User.fromMap(Map<String, dynamic> data, String documentId) {
    return User(
      id: documentId,
      cafeId: data['cafeId'] ?? '',
      parentId: data['parentId'],
      name: data['name'] ?? 'بدون اسم',
      email: data['username'] ?? data['email'] ?? '', 
      isActive: data['isActive'] ?? true,
      password: data['password'] ?? '',
      isOnline: data['isOnline'] ?? false,
      profileImageUrl: data['profileImageUrl'],
      deviceId: data['deviceId'],
      workStartTime: data['workStartTime'],
      workEndTime: data['workEndTime'],
      permissions: data['permissions'] is Map ? Map<String, dynamic>.from(data['permissions']) : {},
      role: UserRole.values.firstWhere(
            (e) => e.name == (data['role'] ?? 'waiter'),
        orElse: () => UserRole.waiter,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'username': email,
      'password': password,
      'role': role.name,
      'cafeId': cafeId,
      'parentId': parentId,
      'isActive': isActive,
      'isOnline': isOnline,
      'permissions': permissions,
      'profileImageUrl': profileImageUrl,
      'deviceId': deviceId,
      'workStartTime': workStartTime,
      'workEndTime': workEndTime,
    };
  }

  User copyWith({
    String? name,
    Map<String, dynamic>? permissions,
    String? cafeId,
    bool? isActive,
    bool? isOnline,
    UserRole? role,
  }) {
    return User(
      id: id,
      name: name ?? this.name,
      email: email,
      password: password,
      role: role ?? this.role,
      cafeId: cafeId ?? this.cafeId,
      permissions: permissions ?? this.permissions,
      parentId: parentId,
      isOnline: isOnline ?? this.isOnline,
      isActive: isActive ?? this.isActive,
      profileImageUrl: profileImageUrl,
      deviceId: deviceId,
      workStartTime: workStartTime,
      workEndTime: workEndTime,
    );
  }
}
