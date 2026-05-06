import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

import 'FirebaseConfigPage.dart';
import 'LoginPage.dart';
import 'CafeAccountsPage.dart';
import 'SuperAdminsManagementPage.dart'; // تأكد من وجود الملف

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
  // ✅ [وظيفة]: تسجيل الخروج
  // ✅ [وظيفة]: تسجيل الخروج مع تحديث الحالة في الفيربيز
  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    String? currentEmail = prefs.getString('session_email');

    try {
      if (currentEmail != null) {
        // 1. البحث عن المستند الخاص بالمدير الحالي وتحديث حالته
        final query = await _firestore
            .collection('users')
            .where('username', isEqualTo: currentEmail)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          await _firestore.collection('users').doc(query.docs.first.id).update({
            'isOnline': false,
            'currentSessionToken': "", // إفراغ التوكن لزيادة الأمان
          });
        }
      }
    } catch (e) {
      debugPrint("خطأ أثناء تحديث حالة الخروج: $e");
    }

    // 2. مسح الجلسة المحلية
    await prefs.remove('session_email');
    await prefs.remove('session_password');
    await prefs.remove('session_token'); // إذا كنت تستخدم توكن

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
    }
  }



  void _addCafeDialog() {
    final name = TextEditingController(), code = TextEditingController(), owner = TextEditingController();
    final address = TextEditingController(), phone = TextEditingController(), days = TextEditingController(text: "0");

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            int initialDays = int.tryParse(days.text) ?? 0;

            await _firestore.collection('cafes').doc(cafeId).set({
              'cafeName': name.text,
              'ownerName': owner.text,
              'address': address.text,
              'phone': phone.text,
              'isActive': false,
              'blockReason': "بانتظار التفعيل",
              'expiryDate': Timestamp.fromDate(DateTime.now().add(Duration(days: initialDays))),
              'createdAt': FieldValue.serverTimestamp(),
              'features': {'inventory': true, 'reports': true, 'kitchen': true, 'dashboard': true},
            });

            // ✅ [إضافة كود التتبع هنا]
            await _createCafeLog(
                name.text,
                "إنشاء منشأة جديدة",
                "تمت الإضافة بكود: $cafeId مع اشتراك مبدئي: $initialDays يوم"
            );

            if (mounted) Navigator.pop(context);
            _showSnackBar("تم حفظ المنشأة كمسودة بنجاح", Colors.green);

          }, child: const Text("حفظ كمسودة"))
        ],
      ),
    );
  }
  // ✅ [وظيفة]: إضافة سوبر أدمن جديد
  // ✅ دالة حذف المنشأة نهائياً
  void _deleteCafe(String id, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("حذف منشأة"),
        content: Text("هل أنت متأكد من حذف '$name' نهائياً؟ لا يمكن التراجع عن هذا الإجراء."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              // 1. حذف المنشأة من Firebase
              await _firestore.collection('cafes').doc(id).delete();

              // 2. تسجيل العملية في التتبع
              await _createCafeLog(name, "حذف منشأة", "تم حذف المنشأة نهائياً من النظام");

              if (mounted) Navigator.pop(context);
              _showSnackBar("تم حذف المنشأة بنجاح", Colors.orange);
            },
            child: const Text("حذف نهائي", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  // ✅ [جديد]: وظيفة تسجيل تتبع الكافيهات
  Future<void> _createCafeLog(String cafeName, String action, String details) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? adminEmail = prefs.getString('session_email') ?? "مدير مجهول";

      await _firestore.collection('cafe_logs').add({
        'adminEmail': adminEmail,
        'cafeName': cafeName,
        'action': action,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("خطأ في تسجيل التتبع: $e");
    }
  }

  // ✅ [وظيفة]: إعدادات حسابي
  void _openMyProfileSettings() async {
    final prefs = await SharedPreferences.getInstance();
    String? currentEmail = prefs.getString('session_email');

    final query = await _firestore.collection('users')
        .where('username', isEqualTo: currentEmail)
        .limit(1).get();

    if (query.docs.isNotEmpty) {
      final docId = query.docs.first.id;
      final data = query.docs.first.data();

      final nameC = TextEditingController(text: data['fullName']);
      final emailC = TextEditingController(text: data['username']);
      final passC = TextEditingController(text: data['password']);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("تعديل بيانات حسابي"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameC, decoration: const InputDecoration(labelText: "الاسم الكامل", prefixIcon: Icon(Icons.person))),
                const SizedBox(height: 10),
                TextField(controller: emailC, decoration: const InputDecoration(labelText: "البريد الإلكتروني الجديد", prefixIcon: Icon(Icons.email))),
                const SizedBox(height: 10),
                TextField(controller: passC, decoration: const InputDecoration(labelText: "كلمة المرور الجديدة", prefixIcon: Icon(Icons.lock))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () async {
                String newEmail = emailC.text.trim().toLowerCase();
                String newPass = passC.text.trim();

                if (newEmail.isEmpty || newPass.isEmpty) return;

                await _firestore.collection('users').doc(docId).update({
                  'fullName': nameC.text.trim(),
                  'username': newEmail,
                  'password': newPass,
                });

                await prefs.setString('session_email', newEmail);
                await prefs.setString('session_password', newPass);

                if (mounted) {
                  Navigator.pop(context);
                  _showSnackBar("تم تحديث بياناتك بنجاح", Colors.green);
                }
              },
              child: const Text("حفظ التغييرات"),
            )
          ],
        ),
      );
    }
  }

  // ✅ [وظيفة]: تمديد الاشتراك (تم إضافة التتبع هنا)
  Future<void> _adjustSubscription(String id, Duration duration, String name, bool isAdding) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('cafes').doc(id).get();
      DateTime current = (doc.get('expiryDate') as Timestamp).toDate();
      if (isAdding && current.isBefore(DateTime.now())) current = DateTime.now();
      DateTime newDate = isAdding ? current.add(duration) : current.subtract(duration);

      await _firestore.collection('cafes').doc(id).update({
        'expiryDate': Timestamp.fromDate(newDate),
        if (isAdding) 'isActive': true,
        if (isAdding) 'blockReason': "",
      });

      // 📝 إضافة التتبع هنا
      String details = "${isAdding ? 'زيادة' : 'خصم'} مدة قدرها ${duration.inDays >= 1 ? '${duration.inDays} يوم' : '${duration.inHours} ساعة'}";
      await _createCafeLog(name, "تعديل اشتراك", details);

      _showSnackBar("تم تحديث اشتراك $name بنجاح", isAdding ? Colors.green : Colors.orange);
    } catch (e) { _showSnackBar("خطأ: $e", Colors.red); }
  }

  void _showAdjustmentDialog(String id, String name) {
    bool isAdding = true;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("تعديل اشتراك: $name"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                _buildTimeChip("سنة", const Duration(days: 365), id, name, isAdding),
              ]),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء"))],
        ),
      ),
    );
  }

  Widget _buildTimeChip(String label, Duration dur, String id, String name, bool add) {
    return ActionChip(label: Text(label), onPressed: () { Navigator.pop(context); _adjustSubscription(id, dur, name, add); });
  }

  // ✅ [وظيفة]: التحكم بالميزات
  void _showFeaturesControl(String id, String name, Map data) {
    Map features = data['features'] ?? {'inventory': true, 'reports': true, 'kitchen': true, 'dashboard': true};
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: Text("ميزات: $name"),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _fSwitch(id, "المخازن", "inventory", features, setS),
            _fSwitch(id, "التقارير", "reports", features, setS),
            _fSwitch(id, "المطبخ", "kitchen", features, setS),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("إغلاق"))],
        ),
      ),
    );
  }

  Widget _fSwitch(String id, String label, String key, Map feat, StateSetter setS) {
    return SwitchListTile(title: Text(label), value: feat[key] ?? true, onChanged: (v) {
      setS(() => feat[key] = v);
      _firestore.collection('cafes').doc(id).update({'features.$key': v});
    });
  }
// دالة لتغيير رقم الواتساب الخاص باستقبال الطلبات
  void _changeSupportWhatsapp() async {
    final prefs = await SharedPreferences.getInstance();
    String currentNum = prefs.getString('admin_whatsapp') ?? "972592623701";
    final controller = TextEditingController(text: currentNum);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("تعديل رقم واتساب الطلبات"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("أدخل الرقم بالصيغة الدولية بدون أصفار أو (+)",
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: "رقم الواتساب",
                prefixIcon: Icon(Icons.call, color: Colors.green),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await prefs.setString('admin_whatsapp', controller.text.trim());
                if (mounted) {
                  Navigator.pop(context);
                  _showSnackBar("تم تحديث رقم استقبال الطلبات بنجاح", Colors.green);
                }
              }
            },
            child: const Text("حفظ"),
          )
        ],
      ),
    );
  }
  // ✅ [وظيفة]: تغيير حالة الكافيه (تم إضافة التتبع هنا)
  void _toggleCafeStatus(String id, bool val, bool isExpired, String cafeName) {
    if (isExpired && val) { _showSnackBar("الاشتراك منتهي", Colors.red); return; }
    if (!val) {
      final reasonC = TextEditingController();
      showDialog(context: context, builder: (context) => AlertDialog(
        title: const Text("سبب الحظر"),
        content: TextField(controller: reasonC),
        actions: [ElevatedButton(onPressed: () async {
          await _firestore.collection('cafes').doc(id).update({'isActive': false, 'blockReason': reasonC.text});

          // 📝 إضافة التتبع هنا
          await _createCafeLog(cafeName, "حظر منشأة", "السبب: ${reasonC.text}");

          Navigator.pop(context);
        }, child: const Text("حظر"))],
      ));
    } else {
      _firestore.collection('cafes').doc(id).update({'isActive': true, 'blockReason': ""});

      // 📝 إضافة التتبع هنا
      _createCafeLog(cafeName, "تفعيل منشأة", "إعادة التنشيط اليدوي");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("إدارة المنشآت"), centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings),
            tooltip: "إدارة المدراء",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SuperAdminsManagementPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.cloud_sync, color: Colors.amber, size: 28),
            tooltip: "إعدادات Firebase الجديدة",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FirebaseConfigPage()),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.manage_accounts), onPressed: _openMyProfileSettings, tooltip: "إعدادات حسابي"),
          IconButton(icon: const Icon(Icons.people_alt_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CafeAccountsPage())), tooltip: "الحسابات الفرعية"),
          IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent), onPressed: _logout, tooltip: "خروج"),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCafeDialog, // ✅ استدعاء الدالة هنا
        label: const Text("إضافة منشأة"),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.blue,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('cafes').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var docs = snapshot.data!.docs;
          var filtered = docs.where((d) => d.get('cafeName').toString().toLowerCase().contains(_searchQuery)).toList();
          int activeCount = docs.where((d) => d.get('isActive') == true && (d.get('expiryDate') as Timestamp).toDate().isAfter(DateTime.now())).length;

          return Column(children: [






            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: "بحث...",
                  prefixIcon: const Icon(Icons.search),
                  // إضافة زر الحذف (suffixIcon)
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      setState(() {
                        _searchController.clear(); // مسح النص من المتحكم
                        _searchQuery = ""; // إعادة تعيين متغير البحث
                      });
                    },
                  )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              ),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
              _buildStatCard("الإجمالي", docs.length.toString(), Colors.blue),
              _buildStatCard("نشط", activeCount.toString(), Colors.green),
              _buildStatCard("متوقف", (docs.length - activeCount).toString(), Colors.red),
            ])),
            const SizedBox(height: 10),
            Expanded(child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                var doc = filtered[index], data = doc.data() as Map<String, dynamic>, id = doc.id;
                DateTime expiry = (data['expiryDate'] as Timestamp).toDate();
                bool isExp = DateTime.now().isAfter(expiry), active = (data['isActive'] ?? false) && !isExp;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: active ? Colors.green[100] : Colors.red[100], child: Icon(Icons.store, color: active ? Colors.green : Colors.red)),
                    title: Text(data['cafeName'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("ينتهي: ${DateFormat('yyyy-MM-dd').format(expiry)}", style: TextStyle(color: isExp ? Colors.red : Colors.blue, fontSize: 11)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      // ✅ تم تعديل استدعاء الدالة لتمرير اسم الكافيه للتتبع
                      Switch(value: active, activeColor: Colors.green, onChanged: (v) => _toggleCafeStatus(id, v, isExp, data['cafeName'] ?? "")),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (val) {
                          if (val == 'features') _showFeaturesControl(id, data['cafeName'], data);
                          if (val == 'time') _showAdjustmentDialog(id, data['cafeName']);

                          // ✅ تم التعديل هنا لتفعيل الحذف
                          if (val == 'delete') {
                            _deleteCafe(id, data['cafeName'] ?? "منشأة");
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'features', child: Text("⚙️ الميزات")),
                          const PopupMenuItem(value: 'time', child: Text("⏳ تعديل الوقت")),
                          const PopupMenuItem(value: 'delete', child: Text("🗑️ حذف")),
                        ],
                      ),
                    ]),
                  ),
                );
              },
            )),
          ]);
        },
      ),
    );
  }

  Widget _buildStatCard(String label, String val, Color color) {
    return Expanded(child: Card(color: color, child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
      Text(val, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
    ]))));
  }

  void _showSnackBar(String m, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c, behavior: SnackBarBehavior.floating));
  }
}