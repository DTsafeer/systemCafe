import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_model.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  UserRole _selectedRole = UserRole.waiter;
  String? _currentCafeId;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadCafeId();
  }

  Future<void> _loadCafeId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _currentCafeId = prefs.getString('cafe_id'));
    }
  }

  // ✅ تسجيل الأنشطة
  Future<void> _logAction(String action, String details) async {
    if (_currentCafeId == null) return;
    try {
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'cafeId': _currentCafeId,
        'userName': "المدير",
        'action': action,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error logging: $e");
    }
  }

  // ✅ شريط البحث
  Widget _buildSearchBar(ThemeData theme, Color primary) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'بحث عن موظف بالاسم أو البريد...',
          prefixIcon: Icon(Icons.search, color: primary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.cancel, color: Colors.grey),
            onPressed: () {
              _searchController.clear();
              setState(() => _searchQuery = "");
            },
          )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.grey.shade200)),
        ),
      ),
    );
  }

  // ✅ حفظ موظف جديد مع فحص دقيق للحقول
  Future<void> _saveUser() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passController.text.trim();

    if (name.isEmpty) {
      _showSnack('يرجى كتابة اسم الموظف ⚠️', Colors.orange);
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      _showSnack('يرجى كتابة بريد إلكتروني صحيح ⚠️', Colors.orange);
      return;
    }
    if (password.length < 6) {
      _showSnack('كلمة المرور قصيرة جداً (6 رموز كحد أدنى) ⚠️', Colors.orange);
      return;
    }
    if (_currentCafeId == null) {
      _showSnack('خطأ: لم يتم العثور على معرف الكافيه، يرجى إعادة الدخول ⚠️', Colors.red);
      return;
    }

    try {
      final docRef = FirebaseFirestore.instance.collection('users').doc(email);
      if ((await docRef.get()).exists) {
        _showSnack('هذا البريد مسجل لموظف آخر مسبقاً ⚠️', Colors.redAccent);
        return;
      }

      await docRef.set({
        'cafeId': _currentCafeId,
        'name': name,
        'email': email,
        'username': email,
        'password': password,
        'role': _selectedRole.name,
        'isActive': true,
        'isOnline': false,
        'currentSessionToken': "",
        'permissions': _getDefaultPermissions(_selectedRole),
        'created_at': FieldValue.serverTimestamp(),
      });

      await _logAction("إضافة موظف", "تم إضافة الموظف: $name برتبة ${_selectedRole.name}");
      _clearFields();
      _showSnack('تم إضافة الموظف بنجاح ✅', Colors.green);
    } catch (e) {
      _showSnack('خطأ أثناء الحفظ: $e', Colors.red);
    }
  }

  // ✅ قائمة الموظفين مع البحث والحذف المباشر
  Widget _buildUsersList(Color primary, ThemeData theme) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').where('cafeId', isEqualTo: _currentCafeId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final filteredDocs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final String name = (data['name'] ?? '').toString().toLowerCase();
          final String email = (data['email'] ?? '').toString().toLowerCase();
          return name.contains(_searchQuery) || email.contains(_searchQuery);
        }).toList();

        if (filteredDocs.isEmpty) {
          return const Padding(padding: EdgeInsets.all(30), child: Text("لا توجد نتائج تطابق بحثك 🔍"));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: filteredDocs.length,
          itemBuilder: (context, index) {
            final doc = filteredDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final perms = data['permissions'] ?? {};
            final bool isOnline = data['isOnline'] ?? false;
            final bool isActive = data['isActive'] ?? true;
            final String uName = data['name'] ?? 'موظف';

            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                leading: _buildUserAvatar(isOnline, isActive, primary),
                title: Text(uName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("الدور: ${data['role']} | ${isActive ? 'نشط' : 'محظور'}"),
                trailing: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 26),
                      onPressed: () => _confirmDelete(doc.id, uName),
                    ),
                    Switch(
                      value: isActive,
                      activeColor: Colors.green,
                      onChanged: (val) => _handleUserStatusToggle(doc.id, isActive, uName),
                    ),
                  ],
                ),
                children: [
                  const Divider(),
                  _permissionGroup("📊 الإدارة والتقارير", [
                    _pSwitch(doc.id, uName, "إدارة الموظفين", "canManageUsers", perms, primary),
                    _pSwitch(doc.id, uName, "عرض التقارير", "canViewReports", perms, primary),
                    _pSwitch(doc.id, uName, "لوحة الإحصائيات (Dashboard)", "canViewDashboard", perms, primary),
                  ]),
                  _permissionGroup("🍔 المنيو والطاولات", [
                    _pSwitch(doc.id, uName, "تعديل المنيو والأسعار", "canEditMenu", perms, primary),
                    _pSwitch(doc.id, uName, "إدارة الطاولات", "canManageTables", perms, primary),
                    _pSwitch(doc.id, uName, "تعديل بيانات الطاولات", "canEditTable", perms, primary),
                    _pSwitch(doc.id, uName, "حذف طاولة", "canDeleteTable", perms, primary),
                  ]),
                  _permissionGroup("📝 الطلبات والمالية", [
                    _pSwitch(doc.id, uName, "إنشاء طلبات جديدة", "canMakeOrders", perms, primary),
                    _pSwitch(doc.id, uName, "دفع الحساب", "canPayOrders", perms, primary),
                    _pSwitch(doc.id, uName, "عرض الطلبات النشطة", "canViewActiveOrders", perms, primary),
                    _pSwitch(doc.id, uName, "حذف الطلبات 🗑️", "canDeleteOrders", perms, primary),
                  ]),
                  _permissionGroup("📦 المخازن والأنظمة", [
                    _pSwitch(doc.id, uName, "إدارة المخزن", "canViewInventory", perms, primary),
                    _pSwitch(doc.id, uName, "شاشة المطبخ (KDS)", "canViewKitchen", perms, primary),
                  ]),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('إدارة الطاقم والصلاحيات', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeaderInput(theme, primary),
            _buildSearchBar(theme, primary),
            _buildUsersList(primary, theme),
          ],
        ),
      ),
    );
  }

  // --- دوال مساعدة (Helper Functions) ---

  Widget _buildHeaderInput(ThemeData theme, Color primary) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: primary,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      child: Column(
        children: [
          _modernTextField(_nameController, 'الاسم الكامل', Icons.person_outline),
          const SizedBox(height: 12),
          _modernTextField(_emailController, 'البريد الإلكتروني', Icons.email_outlined),
          const SizedBox(height: 12),
          _modernTextField(_passController, 'كلمة المرور', Icons.lock_outline, isPass: true),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
            child: DropdownButtonHideUnderline(
              child: DropdownButtonFormField<UserRole>(
                value: _selectedRole,
                items: UserRole.values.map((r) => DropdownMenuItem(value: r, child: Text(r.name.toUpperCase()))).toList(),
                onChanged: (v) => setState(() => _selectedRole = v!),
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saveUser,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, foregroundColor: primary,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: const Text('إضافة الموظف الآن', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildUserAvatar(bool online, bool active, Color primary) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        CircleAvatar(radius: 25, backgroundColor: active ? primary.withOpacity(0.1) : Colors.grey.shade200, child: Icon(Icons.person, color: active ? primary : Colors.grey)),
        Container(height: 15, width: 15, decoration: BoxDecoration(color: online && active ? Colors.green : Colors.grey, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
      ],
    );
  }

  Widget _permissionGroup(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
      ...children,
      const Divider(indent: 20, endIndent: 20),
    ]);
  }

  Widget _pSwitch(String id, String userName, String label, String key, Map perms, Color primary) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(fontSize: 13)),
      value: perms[key] ?? false,
      activeColor: primary,
      onChanged: (val) async {
        await FirebaseFirestore.instance.collection('users').doc(id).update({'permissions.$key': val});
        await _logAction("تعديل صلاحية", "تغيير صلاحية ($label) لـ $userName");
      },
      dense: true,
    );
  }

  Widget _modernTextField(TextEditingController controller, String label, IconData icon, {bool isPass = false}) {
    return TextField(controller: controller, obscureText: isPass, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)));
  }

  Future<void> _handleUserStatusToggle(String email, bool currentStatus, String userName) async {
    await FirebaseFirestore.instance.collection('users').doc(email).update({'isActive': !currentStatus, 'currentSessionToken': !currentStatus ? "" : FieldValue.delete(), 'isOnline': false});
    await _logAction(currentStatus ? "حظر" : "تفعيل", "تغيير حالة الموظف: $userName");
  }

  void _confirmDelete(String id, String name) {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("حذف نهائي"), content: Text("هل أنت متأكد من حذف حساب $name نهائياً؟"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")), TextButton(onPressed: () async { await FirebaseFirestore.instance.collection('users').doc(id).delete(); await _logAction("حذف حساب", "تم حذف حساب $name"); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text("حذف", style: TextStyle(color: Colors.red)))]));
  }

  Map<String, bool> _getDefaultPermissions(UserRole role) {
    return {'canDeleteOrders': role == UserRole.admin || role == UserRole.manager, 'canManageUsers': role == UserRole.admin, 'canViewReports': role == UserRole.admin, 'canViewInventory': role == UserRole.admin || role == UserRole.manager, 'canViewDashboard': role == UserRole.admin, 'canEditMenu': role == UserRole.admin, 'canManageTables': role == UserRole.admin, 'canEditTable': role == UserRole.admin || role == UserRole.manager, 'canMakeOrders': role != UserRole.cleaner && role != UserRole.kitchen, 'canPayOrders': role == UserRole.admin || role == UserRole.cashier, 'canViewActiveOrders': role != UserRole.cleaner, 'canViewKitchen': role == UserRole.kitchen || role == UserRole.admin};
  }

  void _clearFields() { _nameController.clear(); _emailController.clear(); _passController.clear(); }
  void _showSnack(String m, Color c) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c, behavior: SnackBarBehavior.floating));
}