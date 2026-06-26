import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import 'activity_logger.dart';

class UserManagementPage extends StatefulWidget {
  final User user;
  const UserManagementPage({super.key, required this.user});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customRoleNameController = TextEditingController();

  UserRole _selectedRole = UserRole.waiter;
  String _dropdownValue = UserRole.waiter.name;
  String? _selectedCustomRoleName; 
  Map<String, dynamic> _selectedPermissions = {};
  List<Map<String, dynamic>> _customRoleTemplates = [];
  
  String _searchQuery = "";
  bool _isAddPanelVisible = false;
  late String managerId;

  final List<Map<String, String>> _systemPages = [
    {"id": "orders", "name": "الماركت والطلبات", "group": "العمليات الأساسية"},
    {"id": "transfers", "name": "الحوالات والتحويلات", "group": "العمليات الأساسية"},
    {"id": "debts", "name": "الديون والذمم", "group": "القسم المالي"},
    {"id": "expenses", "name": "المصاريف", "group": "القسم المالي"},
    {"id": "menu", "name": "المنيو والمنتجات", "group": "إعدادات المنتجات"},
    {"id": "inventory", "name": "المخزن المحلي", "group": "المخازن"},
    {"id": "purchases", "name": "فواتير المشتريات", "group": "المخازن"},
    {"id": "suppliers", "name": "إدارة الموردين", "group": "المخازن"},
    {"id": "external_warehouse", "name": "المخزن الرئيسي", "group": "المخازن"},
    {"id": "dashboard", "name": "لوحة التحليل", "group": "التقارير"},
    {"id": "reports", "name": "التقارير المالية", "group": "التقارير"},
    {"id": "profits", "name": "أرباح المنتجات", "group": "التقارير"},
    {"id": "users", "name": "إدارة الموظفين", "group": "الإدارة"},
    {"id": "logs", "name": "سجل النشاطات", "group": "الإدارة"},
    {"id": "settings", "name": "إعدادات المقهى", "group": "الإدارة"},
    {"id": "backups", "name": "النسخ الاحتياطي", "group": "الإدارة"},
    {"id": "kitchen", "name": "شاشة المطبخ", "group": "أخرى"},
    {"id": "attendance", "name": "سجل الدوام", "group": "أخرى"},
    {"id": "reminders", "name": "المهام والتنبيهات", "group": "أخرى"},
  ];

  @override
  void initState() {
    super.initState();
    managerId = widget.user.parentId ?? widget.user.id;
    _selectedPermissions = _getDefaultPermissionsForRole(_selectedRole);
    _loadCustomTemplates();
  }

  void _loadCustomTemplates() {
    FirebaseFirestore.instance
        .collection('role_templates')
        .where('cafeId', isEqualTo: widget.user.cafeId)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _customRoleTemplates = snapshot.docs.map((d) => {"id": d.id, ...d.data()}).toList();
        });
      }
    });
  }

  Map<String, dynamic> _getDefaultPermissionsForRole(UserRole role) {
    Map<String, dynamic> perms = {};
    for (var page in _systemPages) {
      perms[page['id']!] = {"r": false, "c": false, "u": false, "d": false};
    }
    switch (role) {
      case UserRole.manager:
        for (var pageId in ['orders', 'transfers', 'debts', 'expenses', 'menu', 'inventory', 'purchases', 'suppliers', 'external_warehouse', 'reminders', 'attendance', 'kitchen']) {
          perms[pageId] = {"r": true, "c": true, "u": true, "d": false};
        }
        perms['dashboard'] = {"r": true, "c": false, "u": false, "d": false};
        perms['reports'] = {"r": true, "c": false, "u": false, "d": false};
        perms['users'] = {"r": true, "c": true, "u": false, "d": false};
        break;
      case UserRole.cashier:
        perms['orders'] = {"r": true, "c": true, "u": true, "d": false};
        perms['transfers'] = {"r": true, "c": true, "u": true, "d": false};
        perms['debts'] = {"r": true, "c": true, "u": true, "d": false};
        perms['expenses'] = {"r": true, "c": true, "u": false, "d": false};
        break;
      case UserRole.waiter:
        perms['orders'] = {"r": true, "c": true, "u": true, "d": false};
        perms['menu'] = {"r": true, "c": false, "u": false, "d": false};
        break;
      default: break;
    }
    return perms;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return MainLayout(
      currentUser: widget.user,
      currentPage: 'users',
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7FA),
        body: CustomScrollView(
          slivers: [
            _buildHeader(primary),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _buildSearchAndAdd(primary),
                  if (_isAddPanelVisible && widget.user.canCreate('users')) _buildAddUserCard(primary),
                ]),
              ),
            ),
            _buildUsersList(primary),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color primary) {
    return SliverAppBar(expandedHeight: 80, pinned: true, elevation: 0, backgroundColor: primary, automaticallyImplyLeading: false, flexibleSpace: const FlexibleSpaceBar(centerTitle: true, title: Text("إدارة فريق العمل", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white))));
  }

  Widget _buildSearchAndAdd(Color primary) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Row(children: [
        Expanded(child: TextField(controller: _searchController, onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()), decoration: const InputDecoration(hintText: "بحث عن موظف...", prefixIcon: Icon(Icons.search), border: InputBorder.none))),
        if (widget.user.canCreate('users')) IconButton(onPressed: () => setState(() => _isAddPanelVisible = !_isAddPanelVisible), icon: Icon(_isAddPanelVisible ? Icons.close : Icons.add, color: primary)),
      ]),
    );
  }

  Widget _buildAddUserCard(Color primary) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("إضافة موظف جديد", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 15),
        _buildInputField(_nameController, "الاسم الكامل", Icons.person_outline),
        const SizedBox(height: 10),
        _buildInputField(_usernameController, "اسم المستخدم", Icons.alternate_email),
        const SizedBox(height: 10),
        _buildInputField(_passController, "كلمة المرور", Icons.lock_outline, isPass: true),
        const SizedBox(height: 15),
        const Text("نوع الموظف:", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildRoleDropdown(primary),
        
        if (_selectedRole == UserRole.custom && _selectedCustomRoleName == null) ...[
          const SizedBox(height: 10),
          _buildInputField(_customRoleNameController, "مسمى الوظيفة/النوع (مثلاً: مراقب جودة)", Icons.badge_outlined),
        ],

        if (_selectedRole == UserRole.custom) ...[
          const SizedBox(height: 20),
          _buildPermissionsGrid(primary, _selectedPermissions, (newPerms) => setState(() => _selectedPermissions = newPerms)),
        ],
        
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saveUser, 
            style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), padding: const EdgeInsets.symmetric(vertical: 15)), 
            child: const Text("حفظ الموظف وتثبيت النوع", style: TextStyle(fontWeight: FontWeight.bold))
          ),
        ),
      ]),
    );
  }

  Widget _buildRoleDropdown(Color primary) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true, value: _dropdownValue,
                items: [
                  const DropdownMenuItem(enabled: false, child: Text("--- الأنواع الأساسية ---", style: TextStyle(fontSize: 11, color: Colors.blue))),
                  ...UserRole.values.where((r) => r != UserRole.super_admin).map((r) => DropdownMenuItem(value: r.name, child: Text(_getRoleName(r)))),
                  if (_customRoleTemplates.isNotEmpty) ...[
                    const DropdownMenuItem(enabled: false, child: Text("--- الأنواع المخصصة المضافة ---", style: TextStyle(fontSize: 11, color: Colors.orange))),
                    ..._customRoleTemplates.map((t) => DropdownMenuItem(value: "custom_${t['id']}", child: Row(children: [const Icon(Icons.copy_all, size: 16, color: Colors.orange), const SizedBox(width: 8), Text(t['name'])]))),
                  ],
                ],
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _dropdownValue = val;
                    if (val.startsWith("custom_")) {
                      final t = _customRoleTemplates.firstWhere((e) => "custom_${e['id']}" == val);
                      _selectedPermissions = Map<String, dynamic>.from(t['permissions']);
                      _selectedRole = UserRole.custom;
                      _selectedCustomRoleName = t['name'];
                      _customRoleNameController.text = t['name'];
                    } else {
                      _selectedRole = UserRole.values.firstWhere((e) => e.name == val);
                      _selectedPermissions = _getDefaultPermissionsForRole(_selectedRole);
                      _selectedCustomRoleName = null;
                      _customRoleNameController.clear();
                    }
                  });
                },
              ),
            ),
          ),
        ),
        if (_customRoleTemplates.isNotEmpty)
          IconButton(onPressed: _showTemplatesManagerDialog, icon: const Icon(Icons.settings_outlined, color: Colors.blueGrey), tooltip: "إدارة الأنواع"),
      ],
    );
  }

  Widget _buildPermissionsGrid(Color primary, Map<String, dynamic> perms, Function(Map<String, dynamic>) onUpdate) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: const Text("تخصيص الصلاحيات", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 20,
              columns: const [
                DataColumn(label: Text("القسم", style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text("عرض")), DataColumn(label: Text("إضافة")), DataColumn(label: Text("تعديل")), DataColumn(label: Text("حذف")),
              ],
              rows: _systemPages.map((page) {
                final String id = page['id']!;
                final p = perms[id] ?? {"r": false, "c": false, "u": false, "d": false};
                return DataRow(cells: [
                  DataCell(Text(page['name']!, style: const TextStyle(fontSize: 12))),
                  DataCell(_permCheck(p, 'r', (v) { p['r'] = v; onUpdate(perms); })),
                  DataCell(_permCheck(p, 'c', (v) { p['c'] = v; onUpdate(perms); })),
                  DataCell(_permCheck(p, 'u', (v) { p['u'] = v; onUpdate(perms); })),
                  DataCell(_permCheck(p, 'd', (v) { p['d'] = v; onUpdate(perms); })),
                ]);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permCheck(Map<String, dynamic> p, String key, Function(bool) onChanged) {
    return Checkbox(value: p[key] ?? false, visualDensity: VisualDensity.compact, onChanged: (v) => onChanged(v ?? false));
  }

  Widget _buildUsersList(Color primary) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').where('cafeId', isEqualTo: widget.user.cafeId).where('parentId', isEqualTo: managerId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        final docs = snapshot.data!.docs.where((d) => d['name'].toString().toLowerCase().contains(_searchQuery)).toList();
        return SliverPadding(padding: const EdgeInsets.all(16), sliver: SliverList(delegate: SliverChildBuilderDelegate((context, i) => _userCard(docs[i].id, docs[i].data() as Map<String, dynamic>, primary), childCount: docs.length)));
      },
    );
  }

  Widget _userCard(String id, Map<String, dynamic> data, Color primary) {
    bool isActive = data['isActive'] ?? true;
    String roleName = (data['role'] == 'custom' && data['customRoleName'] != null) ? data['customRoleName'] : _getRoleNameFromString(data['role'] ?? "");
    String? deviceId = data['deviceId'];

    return Card(margin: const EdgeInsets.only(bottom: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(
        leading: CircleAvatar(backgroundColor: isActive ? primary.withOpacity(0.1) : Colors.grey.shade200, child: Text(data['name'] != null && data['name'].isNotEmpty ? data['name'][0].toUpperCase() : "?", style: TextStyle(color: isActive ? primary : Colors.grey, fontWeight: FontWeight.bold))),
        title: Text(data['name'] ?? "", style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? Colors.black87 : Colors.grey)),
        subtitle: Text(roleName, style: TextStyle(color: isActive ? Colors.black54 : Colors.grey, fontSize: 12)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(onPressed: () => _showEditUserDialog(id, data), icon: const Icon(Icons.edit_note, color: Colors.blue)),
          if (deviceId != null)
            IconButton(
              onPressed: () => _unlinkDevice(id, data['name']),
              icon: const Icon(Icons.phonelink_erase, color: Colors.orange),
              tooltip: "إلغاء ربط الجهاز",
            ),
          Transform.scale(scale: 0.8, child: Switch(value: isActive, activeColor: Colors.green, onChanged: (val) async {
            await FirebaseFirestore.instance.collection('users').doc(id).update({'isActive': val, if (!val) 'isOnline': false});
          })),
          IconButton(onPressed: () => _confirmDeleteUser(id, data['name']), icon: const Icon(Icons.delete_forever, color: Colors.red)),
        ]),
    ));
  }

  Future<void> _unlinkDevice(String id, String name) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text("إلغاء ربط الجهاز"),
          content: Text("هل تريد السماح للموظف ($name) بالدخول من جهاز جديد؟"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("نعم، إلغاء الربط", style: TextStyle(color: Colors.orange)),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('users').doc(id).update({'deviceId': null});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم إلغاء ربط الجهاز بنجاح")));
      
      await ActivityLogger.log(
        cafeId: widget.user.cafeId,
        parentId: managerId,
        userId: widget.user.id,
        userName: widget.user.name,
        action: "إلغاء ربط جهاز",
        details: "تم إلغاء ربط جهاز الموظف: $name",
      );
    }
  }

  void _showEditUserDialog(String id, Map<String, dynamic> data) {
    final nameCtrl = TextEditingController(text: data['name']);
    final passCtrl = TextEditingController(text: data['password']);
    Map<String, dynamic> editPerms = Map<String, dynamic>.from(data['permissions'] ?? {});
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text("تعديل: ${data['name']}"),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildInputField(nameCtrl, "الاسم الكامل", Icons.person_outline),
                    const SizedBox(height: 10),
                    _buildInputField(passCtrl, "كلمة المرور", Icons.lock_outline, isPass: true),
                    const SizedBox(height: 20),
                    _buildPermissionsGrid(Theme.of(context).primaryColor, editPerms, (v) => setDialogState(() => editPerms = v)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ElevatedButton(
                onPressed: () async {
                  await FirebaseFirestore.instance.collection('users').doc(id).update({
                    'name': nameCtrl.text.trim(),
                    'password': passCtrl.text.trim(),
                    'permissions': editPerms,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text("حفظ التعديلات"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteUser(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text("حذف موظف"),
          content: Text("هل أنت متأكد من حذف حساب ($name) نهائياً؟"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
            ElevatedButton(onPressed: () async { Navigator.pop(ctx); await FirebaseFirestore.instance.collection('users').doc(id).delete(); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("حذف")),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(TextEditingController controller, String label, IconData icon, {bool isPass = false}) {
    return TextField(controller: controller, obscureText: isPass, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))));
  }

  String _getRoleName(UserRole role) {
    switch (role) { case UserRole.admin: return "مدير"; case UserRole.manager: return "مشرف"; case UserRole.cashier: return "محاسب"; case UserRole.waiter: return "نادل"; case UserRole.kitchen: return "مطبخ"; case UserRole.cleaner: return "عامل"; case UserRole.custom: return "مخصص"; default: return "موظف"; }
  }

  String _getRoleNameFromString(String role) { try { return _getRoleName(UserRole.values.firstWhere((e) => e.name == role)); } catch (_) { return "موظف"; } }

  void _showTemplatesManagerDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text("إدارة الأنواع المخصصة"),
          content: SizedBox(
            width: 400, height: 300,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('role_templates').where('cafeId', isEqualTo: widget.user.cafeId).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final templates = snapshot.data!.docs;
                if (templates.isEmpty) return const Center(child: Text("لا توجد أنواع مخصصة حالياً"));
                return ListView.builder(
                  itemCount: templates.length,
                  itemBuilder: (context, index) {
                    final t = templates[index];
                    return ListTile(
                      title: Text(t['name'] ?? ""),
                      trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => FirebaseFirestore.instance.collection('role_templates').doc(t.id).delete()),
                    );
                  },
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إغلاق"))],
        ),
      ),
    );
  }

  Future<void> _saveUser() async {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim().toLowerCase();
    final password = _passController.text.trim();

    if (name.isEmpty || username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ يرجى ملء جميع الحقول")));
      return;
    }
    
    String? finalRoleName = _selectedCustomRoleName;

    if (_selectedRole == UserRole.custom && _selectedCustomRoleName == null) {
      final customName = _customRoleNameController.text.trim();
      if (customName.isNotEmpty) {
        finalRoleName = customName;
        final existing = _customRoleTemplates.any((t) => t['name'].toString().toLowerCase() == customName.toLowerCase());
        if (!existing) {
          await FirebaseFirestore.instance.collection('role_templates').add({
            'name': customName,
            'cafeId': widget.user.cafeId,
            'permissions': _selectedPermissions,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ يرجى إدخال مسمى للوظيفة المخصصة")));
        return;
      }
    }

    // التحقق من تكرار اسم المستخدم
    final existingUser = await FirebaseFirestore.instance.collection('users').doc(username).get();
    if (existingUser.exists) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ اسم المستخدم موجود بالفعل")));
      return;
    }

    await FirebaseFirestore.instance.collection('users').doc(username).set({
      'name': name,
      'username': username,
      'password': password,
      'role': _selectedRole.name,
      'customRoleName': finalRoleName, 
      'cafeId': widget.user.cafeId,
      'parentId': managerId,
      'isActive': true,
      'permissions': _selectedPermissions,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await ActivityLogger.log(
      cafeId: widget.user.cafeId,
      parentId: managerId,
      userId: widget.user.id,
      userName: widget.user.name,
      action: "إضافة موظف",
      details: "تم إضافة الموظف: $name برتبة ${finalRoleName ?? _getRoleName(_selectedRole)}",
    );
    
    setState(() {
      _isAddPanelVisible = false;
      _dropdownValue = UserRole.waiter.name;
      _selectedRole = UserRole.waiter;
      _selectedCustomRoleName = null;
    });
    _nameController.clear(); _usernameController.clear(); _passController.clear(); _customRoleNameController.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم إضافة الموظف بنجاح")));
  }
}
