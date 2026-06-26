import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'CafeLogsPage.dart';

class CafeAccountsPage extends StatefulWidget {
  const CafeAccountsPage({super.key});

  @override
  State<CafeAccountsPage> createState() => _CafeAccountsPageState();
}

class _CafeAccountsPageState extends State<CafeAccountsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // دالة لإظهار حوار التأكيد لإلغاء الارتباط
  void _showUnlinkDialog(BuildContext context, String userId, String userName) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text("إلغاء ارتباط الجهاز"),
          content: Text("هل أنت متأكد من رغبتك في إلغاء ارتباط الجهاز الحالي بحساب الموظف ($userName)؟\n\nهذا الإجراء سيسمح للموظف بتسجيل الدخول من جهاز آخر."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("إلغاء"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                try {
                  await _firestore.collection('users').doc(userId).update({
                    'deviceId': FieldValue.delete(), // حذف معرف الجهاز نهائياً
                  });
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("تم إلغاء ارتباط جهاز الموظف $userName بنجاح")),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("حدث خطأ: $e")),
                    );
                  }
                }
              },
              child: const Text("إلغاء الارتباط الآن", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("حسابات المنشآت والموظفين"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_toggle_off),
            tooltip: "سجل عمليات الكافيهات",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CafeLogsPage()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('cafes').snapshots(),
        builder: (context, cafeSnapshot) {
          if (!cafeSnapshot.hasData) return const Center(child: CircularProgressIndicator());

          final cafes = cafeSnapshot.data!.docs;

          return ListView.builder(
            itemCount: cafes.length,
            itemBuilder: (context, index) {
              final cafe = cafes[index];
              final cafeData = cafe.data() as Map<String, dynamic>;
              final String cafeId = cafe.id;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ExpansionTile(
                  leading: const Icon(Icons.business, color: Colors.blue),
                  title: Text(
                    cafeData['cafeName'] ?? "بدون اسم",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text("كود المنشأة: $cafeId", style: const TextStyle(fontSize: 12)),
                  children: [
                    const Divider(),
                    StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection('users')
                          .where('cafeId', isEqualTo: cafeId)
                          .snapshots(),
                      builder: (context, userSnapshot) {
                        if (!userSnapshot.hasData) return const LinearProgressIndicator();

                        final users = userSnapshot.data!.docs;

                        if (users.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text("لا يوجد موظفين مسجلين حالياً"),
                          );
                        }

                        return Column(
                          children: users.map((userDoc) {
                            final userData = userDoc.data() as Map<String, dynamic>;
                            final bool isActive = userData['isActive'] ?? true;
                            final String role = userData['role'] ?? "موظف";
                            final String? deviceId = userData['deviceId'];

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: role == 'admin' ? Colors.orange[100] : Colors.blue[100],
                                child: Icon(
                                  role == 'admin' ? Icons.admin_panel_settings : Icons.person,
                                  size: 20,
                                  color: role == 'admin' ? Colors.orange : Colors.blue,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(userData['name'] ?? "بدون اسم"),
                                  if (deviceId != null)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8),
                                      child: Icon(Icons.phonelink_lock, size: 14, color: Colors.green),
                                    ),
                                ],
                              ),
                              subtitle: Text("الصلاحية: $role"),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // زر إلغاء الارتباط يظهر فقط إذا كان هناك جهاز مرتبط
                                  if (deviceId != null)
                                    IconButton(
                                      icon: const Icon(Icons.phonelink_erase, color: Colors.redAccent),
                                      tooltip: "إلغاء ارتباط الجهاز",
                                      onPressed: () => _showUnlinkDialog(context, userDoc.id, userData['name'] ?? "الموظف"),
                                    ),
                                  Switch(
                                    value: isActive,
                                    activeColor: Colors.green,
                                    onChanged: (val) {
                                      _firestore
                                          .collection('users')
                                          .doc(userDoc.id)
                                          .update({'isActive': val});
                                    },
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
