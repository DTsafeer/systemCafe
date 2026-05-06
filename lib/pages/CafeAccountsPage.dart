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
        // جلب جميع الكافيهات
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
                margin: const EdgeInsets.all(8.0),
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
                    // جلب المستخدمين التابعين لهذا الكافيه فقط
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
                            padding: EdgeInsets.all(8.0),
                            child: Text("لا يوجد موظفين مسجلين حالياً"),
                          );
                        }

                        return Column(
                          children: users.map((userDoc) {
                            final userData = userDoc.data() as Map<String, dynamic>;
                            final bool isActive = userData['isActive'] ?? true;
                            final String role = userData['role'] ?? "موظف";

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: role == 'admin' ? Colors.orange[100] : Colors.blue[100],
                                child: Icon(
                                  role == 'admin' ? Icons.admin_panel_settings : Icons.person,
                                  size: 20,
                                  color: role == 'admin' ? Colors.orange : Colors.blue,
                                ),
                              ),
                              title: Text(userData['name'] ?? "بدون اسم"),
                              subtitle: Text("الصلاحية: $role"),
                              trailing: Switch(
                                value: isActive,
                                activeColor: Colors.green,
                                onChanged: (val) {
                                  // تحديث حالة الموظف في الفايربيز
                                  _firestore
                                      .collection('users')
                                      .doc(userDoc.id)
                                      .update({'isActive': val});
                                },
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