import 'dart:async'; // تم إضافة هذا الاستيراد للمراقبة
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'AuditLogsPage.dart';
import 'LoginPage.dart';

class SuperAdminsManagementPage extends StatefulWidget {
  const SuperAdminsManagementPage({super.key});

  @override
  State<SuperAdminsManagementPage> createState() => _SuperAdminsManagementPageState();
}

class _SuperAdminsManagementPageState extends State<SuperAdminsManagementPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _currentLoggedInEmail;
  StreamSubscription<QuerySnapshot>? _statusSubscription; // مراقب الحالة

  @override
  void initState() {
    super.initState();
    _loadCurrentEmail();
    _startStatusListener(); // بدء مراقبة حالة الحساب فوراً
  }

  @override
  void dispose() {
    _statusSubscription?.cancel(); // إغلاق المراقبة عند الخروج من الصفحة
    super.dispose();
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
  // ✅ مراقبة حالة الحساب لحظياً للطرد الفوري
  void _startStatusListener() async {
    final prefs = await SharedPreferences.getInstance();
    String? email = prefs.getString('session_email');

    if (email != null) {
      _statusSubscription = _firestore
          .collection('users')
          .where('username', isEqualTo: email)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          bool isActive = snapshot.docs.first.data()['isActive'] ?? true;
          if (!isActive) {
            _forceLogout();
          }
        }
      });
    }
  }

  // ✅ تنفيذ الخروج الإجباري
  void _forceLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _statusSubscription?.cancel();

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم تعطيل حسابك.. تسجيل خروج فوري"), backgroundColor: Colors.red),
      );
    }
  }

  void _loadCurrentEmail() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentLoggedInEmail = prefs.getString('session_email');
    });
  }

  // ✅ [جديد] دالة تسجيل العمليات في السجل (Audit Logs)
  Future<void> _createLog(String action, String targetName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? adminEmail = prefs.getString('session_email') ?? "مدير مجهول";

      await _firestore.collection('audit_logs').add({
        'adminEmail': adminEmail,
        'action': action,
        'target': targetName,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("خطأ في تسجيل السجل: $e");
    }
  }

  // ✅ نافذة إضافة مدير جديد مع زر إلغاء واضح
  void _addNewAdminDialog() {
    final nameC = TextEditingController();
    final emailC = TextEditingController();
    final passC = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.person_add, color: Colors.blue),
            SizedBox(width: 10),
            Text("إضافة سوبر أدمن"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameC, decoration: const InputDecoration(labelText: "الاسم الكامل", prefixIcon: Icon(Icons.badge))),
            const SizedBox(height: 8),
            TextField(controller: emailC, decoration: const InputDecoration(labelText: "البريد الإلكتروني", prefixIcon: Icon(Icons.email))),
            const SizedBox(height: 8),
            TextField(controller: passC, obscureText: true, decoration: const InputDecoration(labelText: "كلمة المرور", prefixIcon: Icon(Icons.lock))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("إلغاء", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              String email = emailC.text.trim().toLowerCase();
              if (email.isEmpty || passC.text.isEmpty || nameC.text.isEmpty) {
                _showSnackBar("يرجى ملء كافة الحقول", Colors.red);
                return;
              }

              final check = await _firestore.collection('users').where('username', isEqualTo: email).get();
              if (check.docs.isNotEmpty) {
                _showSnackBar("هذا البريد مسجل مسبقاً!", Colors.red);
                return;
              }

              await _firestore.collection('users').add({
                'fullName': nameC.text.trim(),
                'username': email,
                'password': passC.text.trim(),
                'role': 'super_admin',
                'isOwner': false,
                'isActive': true,
                'createdAt': FieldValue.serverTimestamp(),
              });

              // 📝 تسجيل في السجل
              await _createLog("إضافة مدير جديد", nameC.text.trim());

              if (mounted) Navigator.pop(context);
              _showSnackBar("تمت إضافة المدير الجديد بنجاح", Colors.green);
            },
            child: const Text("إنشاء الحساب", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ✅ دالة نقل الملكية
  void _setAsMainAdmin(String newAdminDocId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("نقل الملكية الكاملة"),
        content: Text("هل أنت متأكد من جعل '$name' هو المدير الرئيسي؟ ستقوم بالتنازل عن صلاحياتك له."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[800]),
            onPressed: () async {
              WriteBatch batch = _firestore.batch();
              var currentOwnerQuery = await _firestore.collection('users').where('isOwner', isEqualTo: true).get();
              for (var doc in currentOwnerQuery.docs) {
                batch.update(doc.reference, {'isOwner': false});
              }
              batch.update(_firestore.collection('users').doc(newAdminDocId), {'isOwner': true});
              await batch.commit();

              // 📝 تسجيل في السجل
              await _createLog("نقل ملكية النظام", name);

              if (mounted) Navigator.pop(context);
              _showSnackBar("تم نقل الملكية بنجاح إلى $name", Colors.green);
            },
            child: const Text("تأكيد النقل"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          actions: [
            IconButton(icon: Icon(Icons.call),
              onPressed:() {
                _changeSupportWhatsapp();

              } ,
            ),
            IconButton(
              icon: const Icon(Icons.assignment_outlined),
              tooltip: "سجل العمليات",
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditLogsPage()));
              },
            ),
          ],
          title: const Text("إدارة المدراء والملكية")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNewAdminDialog,
        label: const Text("إضافة مدير"),
        icon: const Icon(Icons.add_moderator),
        backgroundColor: Colors.blue,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('users').where('role', isEqualTo: 'super_admin').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var admins = snapshot.data!.docs;

          if (admins.isEmpty) {
            return const Center(child: Text("لا يوجد مدراء. اضغط على الزر لإضافة أول مدير."));
          }

          return ListView.builder(
            itemCount: admins.length,
            itemBuilder: (context, index) {
              var admin = admins[index].data() as Map<String, dynamic>;
              String docId = admins[index].id;
              bool isOwner = admin['isOwner'] ?? false;
              bool isActive = admin['isActive'] ?? true;
              String email = admin['username'] ?? "";

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isOwner ? Colors.amber : (isActive ? Colors.blue : Colors.grey),
                    child: Icon(isOwner ? Icons.star : Icons.person, color: Colors.white),
                  ),
                  title: Text(
                    admin['fullName'] ?? "",
                    style: TextStyle(
                      decoration: isActive ? TextDecoration.none : TextDecoration.lineThrough,
                      color: isActive ? Colors.black : Colors.grey,
                    ),
                  ),
                  subtitle: Text(email),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isOwner)
                        Switch(
                          value: isActive,
                          activeColor: Colors.green,
                          onChanged: (bool newValue) async {
                            await _firestore.collection('users').doc(docId).update({
                              'isActive': newValue,
                            });

                            // 📝 تسجيل في السجل
                            await _createLog(newValue ? "تفعيل حساب" : "تعطيل حساب", admin['fullName'] ?? email);

                            _showSnackBar(
                              newValue ? "تم تفعيل حساب المدير" : "تم إيقاف حساب المدير مؤقتاً",
                              newValue ? Colors.green : Colors.orange,
                            );
                          },
                        ),
                      if (isOwner) const Icon(Icons.verified_user, color: Colors.amber),
                      if (!isOwner)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _confirmDelete(docId, admin['fullName'] ?? "مدير"),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _confirmDelete(String id, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("حذف مدير"),
        content: Text("هل أنت متأكد من حذف $name؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                await _firestore.collection('users').doc(id).delete();

                // 📝 تسجيل في السجل
                await _createLog("حذف مدير نهائياً", name);

                if (mounted) Navigator.pop(context);
                _showSnackBar("تم الحذف", Colors.orange);
              },
              child: const Text("حذف", style: TextStyle(color: Colors.white)))
        ],
      ),
    );
  }

  void _showSnackBar(String m, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c));
  }
}