import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

import 'LoginPage.dart';
import 'SuperAdminsManagementPage.dart';

class SuperAdminPage extends StatefulWidget {
  const SuperAdminPage({super.key});

  @override
  State<SuperAdminPage> createState() => _SuperAdminPageState();
}

class _SuperAdminPageState extends State<SuperAdminPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // دالة مساعدة لفتح أي نافذة بـ RTL موحد ومنع التكرار
  void _showRtlDialog(Widget child) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: child,
      ),
    );
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    String? currentEmail = prefs.getString('session_email');
    try {
      if (currentEmail != null) {
        final query = await _firestore.collection('users').where('username', isEqualTo: currentEmail).limit(1).get();
        if (query.docs.isNotEmpty) {
          await _firestore.collection('users').doc(query.docs.first.id).update({'isOnline': false, 'currentSessionToken': ""});
        }
      }
    } catch (e) { debugPrint("Logout error: $e"); }
    await prefs.clear();
    if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false);
  }

  void _openPackagesManagement() {
    _showRtlDialog(Scaffold(
      appBar: AppBar(title: const Text("إدارة حزم الاشتراك")),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('subscription_packages').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var pkgs = snapshot.data!.docs;
          return ListView.builder(
            itemCount: pkgs.length,
            itemBuilder: (context, i) {
              var data = pkgs[i].data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.all(10),
                child: ListTile(
                  title: Text(data['name'] ?? "حزمة بدون اسم", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("السعر: ${data['price'] ?? '0'} ₪ ${data['billingCycle'] ?? '/شهر'}\nالحد الأقصى للموظفين: ${data['maxEmployees'] ?? 'غير محدود'}"),
                  trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _editPackageDialog(pkgs[i].id, data)),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _editPackageDialog(null, {}),
      ),
    ));
  }

  void _editPackageDialog(String? docId, Map data) {
    final nameC = TextEditingController(text: data['name'] ?? "");
    final priceC = TextEditingController(text: data['price'] ?? "");
    final cycleC = TextEditingController(text: data['billingCycle'] ?? "/شهر");
    final oldPriceC = TextEditingController(text: data['oldPrice'] ?? "");
    final maxEmpC = TextEditingController(text: (data['maxEmployees'] ?? "10").toString());
    final featuresC = TextEditingController(text: (data['features'] as List?)?.join("\n") ?? "");
    
    Map<String, dynamic> perms = Map<String, dynamic>.from(data['permissions'] ?? {
      'canViewReports': true, 
      'canEditMenu': true, 
      'canManageTables': true, 
      'canViewInventory': true, 
      'canViewKitchen': true, 
      'canViewDashboard': true,
      'canUseGoogleSheets': false
    });

    final Map<String, String> labels = {
      'canViewReports': 'التقارير المالية', 'canEditMenu': 'تعديل المنيو', 'canManageTables': 'إدارة الطاولات',
      'canViewInventory': 'إدارة المخزن', 'canViewKitchen': 'نظام المطبخ', 'canViewDashboard': 'لوحة الإحصائيات',
      'canUseGoogleSheets': 'دعم Google Sheets ✅'
    };

    _showRtlDialog(StatefulBuilder(
      builder: (context, setS) => AlertDialog(
        title: Text(docId == null ? "إضافة حزمة" : "تعديل حزمة"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameC, decoration: const InputDecoration(labelText: "اسم الحزمة")),
              Row(children: [
                Expanded(child: TextField(controller: priceC, decoration: const InputDecoration(labelText: "السعر الحالي"))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: cycleC, decoration: const InputDecoration(labelText: "دورة الفوترة"))),
              ]),
              TextField(controller: maxEmpC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "الحد الأقصى للموظفين")),
              TextField(controller: oldPriceC, decoration: const InputDecoration(labelText: "السعر القديم")),
              TextField(controller: featuresC, maxLines: 3, decoration: const InputDecoration(labelText: "المميزات (سطر لكل ميزة)")),
              const Divider(),
              ...perms.keys.map((k) => CheckboxListTile(
                title: Text(labels[k] ?? k), value: perms[k], dense: true,
                onChanged: (v) => setS(() => perms[k] = v),
              )),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(onPressed: () async {
            var finalData = {
              'name': nameC.text, 'price': priceC.text, 'billingCycle': cycleC.text,
              'maxEmployees': int.tryParse(maxEmpC.text) ?? -1, 'oldPrice': oldPriceC.text,
              'features': featuresC.text.split("\n").where((s)=>s.isNotEmpty).toList(),
              'permissions': perms, 'colorValue': data['colorValue'] ?? Colors.brown.value,
            };
            if (docId == null) { await _firestore.collection('subscription_packages').add(finalData); }
            else { await _firestore.collection('subscription_packages').doc(docId).update(finalData); }
            if (mounted) Navigator.pop(context);
          }, child: const Text("حفظ")),
        ],
      ),
    ));
  }

  void _addCafeDialog() {
    final name = TextEditingController(), code = TextEditingController(), owner = TextEditingController();
    final address = TextEditingController(), phone = TextEditingController(), days = TextEditingController(text: "0");
    _showRtlDialog(AlertDialog(
      title: const Text("إضافة منشأة جديدة"),
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: "اسم الكافيه")),
            TextField(controller: owner, decoration: const InputDecoration(labelText: "اسم المالك")),
            TextField(controller: code, decoration: const InputDecoration(labelText: "كود التفعيل (Doc ID)")),
            TextField(controller: address, decoration: const InputDecoration(labelText: "العنوان")),
            TextField(controller: phone, decoration: const InputDecoration(labelText: "رقم الهاتف")),
            TextField(controller: days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "أيام الاشتراك المبدئية")),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
        ElevatedButton(onPressed: () async {
          if (name.text.isEmpty || code.text.isEmpty) return;
          String cafeId = code.text.trim().toUpperCase();
          await _firestore.collection('cafes').doc(cafeId).set({
            'cafeName': name.text, 'ownerName': owner.text, 'address': address.text, 'phone': phone.text,
            'isActive': false, 'expiryDate': Timestamp.fromDate(DateTime.now().add(Duration(days: int.tryParse(days.text) ?? 0))),
            'createdAt': FieldValue.serverTimestamp(),
            'features': {'inventory': true, 'reports': true, 'kitchen': true, 'dashboard': true},
          });
          await _createCafeLog(name.text, "إنشاء منشأة", "بكود: $cafeId");
          if (mounted) Navigator.pop(context);
        }, child: const Text("حفظ"))
      ],
    ));
  }

  Future<void> _createCafeLog(String cafeName, String action, String details) async {
    final prefs = await SharedPreferences.getInstance();
    await _firestore.collection('cafe_logs').add({
      'adminEmail': prefs.getString('session_email') ?? "مدير",
      'cafeName': cafeName, 'action': action, 'details': details, 'timestamp': FieldValue.serverTimestamp(),
    });
  }

  void _openMyProfileSettings() async {
    final prefs = await SharedPreferences.getInstance();
    String? currentEmail = prefs.getString('session_email');
    final query = await _firestore.collection('users').where('username', isEqualTo: currentEmail).limit(1).get();
    if (query.docs.isNotEmpty) {
      final data = query.docs.first.data();
      final nameC = TextEditingController(text: data['fullName']), emailC = TextEditingController(text: data['username']), passC = TextEditingController(text: data['password']);
      _showRtlDialog(AlertDialog(
        title: const Text("بيانات حسابي"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameC, decoration: const InputDecoration(labelText: "الاسم")),
          TextField(controller: emailC, decoration: const InputDecoration(labelText: "البريد")),
          TextField(controller: passC, decoration: const InputDecoration(labelText: "كلمة المرور")),
        ]),
        actions: [ElevatedButton(onPressed: () async {
          await _firestore.collection('users').doc(query.docs.first.id).update({'fullName': nameC.text, 'username': emailC.text, 'password': passC.text});
          await prefs.setString('session_email', emailC.text);
          if (mounted) Navigator.pop(context);
        }, child: const Text("حفظ"))],
      ));
    }
  }

  void _showFeaturesControl(String id, String name, Map data) {
    Map features = data['features'] ?? {'inventory': true, 'reports': true, 'kitchen': true, 'dashboard': true};
    _showRtlDialog(StatefulBuilder(builder: (context, setS) => AlertDialog(
      title: Text("ميزات: $name"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _fSwitch(id, "المخازن", "inventory", features, setS),
        _fSwitch(id, "التقارير", "reports", features, setS),
        _fSwitch(id, "المطبخ", "kitchen", features, setS),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("إغلاق"))],
    )));
  }

  Widget _fSwitch(String id, String label, String key, Map feat, StateSetter setS) {
    return SwitchListTile(title: Text(label), value: feat[key] ?? true, onChanged: (v) {
      setS(() => feat[key] = v);
      _firestore.collection('cafes').doc(id).update({'features.$key': v});
    });
  }

  void _toggleCafeStatus(String id, bool val, bool isExpired, String cafeName) {
    if (isExpired && val) { _showSnackBar("الاشتراك منتهي", Colors.red); return; }
    if (!val) {
      final reasonC = TextEditingController();
      _showRtlDialog(AlertDialog(title: const Text("سبب الحظر"), content: TextField(controller: reasonC), actions: [ElevatedButton(onPressed: () async {
        await _firestore.collection('cafes').doc(id).update({'isActive': false, 'blockReason': reasonC.text});
        await _createCafeLog(cafeName, "حظر", reasonC.text);
        if (mounted) Navigator.pop(context);
      }, child: const Text("حظر"))]));
    } else {
      _firestore.collection('cafes').doc(id).update({'isActive': true, 'blockReason': ""});
      _createCafeLog(cafeName, "تفعيل", "تنشيط يدوي");
    }
  }

  void _showAdvancedStopControl(String id, String name, Map data) {
    bool isManualStop = !(data['isActive'] ?? true);
    DateTime? scheduledStop = data['scheduledStopDate'] != null ? (data['scheduledStopDate'] as Timestamp).toDate() : null;
    final reasonC = TextEditingController(text: data['blockReason'] ?? "");

    _showRtlDialog(StatefulBuilder(
      builder: (context, setS) => AlertDialog(
        title: Text("تحكم التشغيل: $name"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(title: const Text("إيقاف يدوي فوري"), value: isManualStop, onChanged: (v) => setS(() => isManualStop = v)),
              const Divider(),
              const Text("جدولة إيقاف تلقائي", style: TextStyle(fontWeight: FontWeight.bold)),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(scheduledStop == null ? "تحديد موعد" : intl.DateFormat('yyyy-MM-dd HH:mm').format(scheduledStop!)),
                onTap: () async {
                  DateTime? date = await showDatePicker(context: context, initialDate: scheduledStop ?? DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (date != null && mounted) {
                    TimeOfDay? time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (time != null) setS(() => scheduledStop = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                  }
                },
              ),
              TextField(controller: reasonC, decoration: const InputDecoration(labelText: "رسالة للمستخدمين")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(onPressed: () async {
            await _firestore.collection('cafes').doc(id).update({'isActive': !isManualStop, 'blockReason': reasonC.text, 'scheduledStopDate': scheduledStop != null ? Timestamp.fromDate(scheduledStop!) : null});
            if (mounted) Navigator.pop(context);
          }, child: const Text("حفظ")),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title: const Text("إدارة المنشآت"), centerTitle: true,
          actions: [
            IconButton(icon: const Icon(Icons.card_membership, color: Colors.blue), tooltip: "إدارة الحزم", onPressed: _openPackagesManagement),
            IconButton(icon: const Icon(Icons.admin_panel_settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminsManagementPage()))),
            IconButton(icon: const Icon(Icons.manage_accounts), onPressed: _openMyProfileSettings),
            IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent), onPressed: _logout),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: _addCafeDialog, label: const Text("إضافة منشأة"), icon: const Icon(Icons.add), backgroundColor: Colors.blue),
        body: StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('cafes').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            var docs = snapshot.data!.docs;
            var filtered = docs.where((d) => (d.data() as Map)['cafeName'].toString().toLowerCase().contains(_searchQuery)).toList();

            return Column(children: [
              Padding(padding: const EdgeInsets.all(10), child: TextField(controller: _searchController, decoration: InputDecoration(hintText: "بحث باسم المنشأة...", prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)), onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()))),
              Expanded(child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  var doc = filtered[index], data = doc.data() as Map<String, dynamic>, id = doc.id;
                  DateTime expiry = (data['expiryDate'] as Timestamp).toDate();
                  bool isExp = DateTime.now().isAfter(expiry);
                  bool isManualStop = !(data['isActive'] ?? true);
                  bool active = (data['isActive'] ?? false) && !isExp;
                  
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: active ? Colors.green[100] : (isManualStop ? Colors.orange[100] : Colors.red[100]), child: Icon(isManualStop ? Icons.pause_circle_filled : (active ? Icons.store : Icons.block), color: isManualStop ? Colors.orange : (active ? Colors.green : Colors.red))),
                      title: Text(data['cafeName'] ?? "بدون اسم"),
                      subtitle: Text("ينتهي: ${intl.DateFormat('yyyy-MM-dd').format(expiry)}"),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Switch(value: active, activeColor: Colors.green, onChanged: (v) => _toggleCafeStatus(id, v, isExp, data['cafeName'] ?? "")),
                        PopupMenuButton<String>(onSelected: (val) {
                          if (val == 'status_control') _showAdvancedStopControl(id, data['cafeName'], data);
                          if (val == 'features') _showFeaturesControl(id, data['cafeName'], data);
                          if (val == 'time') _showAdjustmentDialog(id, data['cafeName']);
                          if (val == 'delete') _deleteCafe(id, data['cafeName']);
                        }, itemBuilder: (context) => [
                          const PopupMenuItem(value: 'status_control', child: Text("إيقاف يدوي/تلقائي")),
                          const PopupMenuItem(value: 'features', child: Text("⚙️ الميزات")),
                          const PopupMenuItem(value: 'time', child: Text("⏳ تعديل الوقت")),
                          const PopupMenuItem(value: 'delete', child: Text("🗑️ حذف")),
                        ]),
                      ]),
                    ),
                  );
                },
              )),
            ]);
          },
        ),
      ),
    );
  }

  void _showAdjustmentDialog(String id, String name) {
    bool isAdding = true;
    _showRtlDialog(StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: Text("تعديل اشتراك: $name"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          ChoiceChip(label: const Text("➕ زيادة"), selected: isAdding, onSelected: (v) => setDialogState(() => isAdding = true)),
          const SizedBox(width: 10),
          ChoiceChip(label: const Text("➖ خصم"), selected: !isAdding, onSelected: (v) => setDialogState(() => isAdding = false)),
        ]),
        const Divider(height: 30),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _buildTimeChip("ساعة", const Duration(hours: 1), id, name, isAdding),
          _buildTimeChip("يوم", const Duration(days: 1), id, name, isAdding),
          _buildTimeChip("أسبوع", const Duration(days: 7), id, name, isAdding),
          _buildTimeChip("شهر", const Duration(days: 30), id, name, isAdding),
        ]),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء"))],
    )));
  }

  Widget _buildTimeChip(String label, Duration dur, String id, String name, bool add) => ActionChip(label: Text(label), onPressed: () { Navigator.pop(context); _adjustSubscription(id, dur, name, add); });

  Future<void> _adjustSubscription(String id, Duration duration, String name, bool isAdding) async {
    DocumentSnapshot doc = await _firestore.collection('cafes').doc(id).get();
    var data = doc.data() as Map<String, dynamic>?;
    if (data == null) return;
    DateTime current = (data['expiryDate'] as Timestamp).toDate();
    if (isAdding && current.isBefore(DateTime.now())) current = DateTime.now();
    DateTime newDate = isAdding ? current.add(duration) : current.subtract(duration);
    await _firestore.collection('cafes').doc(id).update({'expiryDate': Timestamp.fromDate(newDate), if (isAdding) 'isActive': true});
  }

  void _deleteCafe(String id, String name) {
    _showRtlDialog(AlertDialog(title: const Text("حذف"), content: Text("حذف $name نهائياً؟"), actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () async {
        await _firestore.collection('cafes').doc(id).delete();
        if (mounted) Navigator.pop(context);
      }, child: const Text("حذف"))
    ]));
  }

  void _showSnackBar(String m, Color c) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c));
}
