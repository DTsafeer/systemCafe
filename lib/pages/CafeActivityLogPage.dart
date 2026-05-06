import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'user_model.dart'; // تأكد من استيراد موديل المستخدم

class CafeActivityLogPage extends StatefulWidget {
  final User currentUser;

  const CafeActivityLogPage({super.key, required this.currentUser});

  @override
  State<CafeActivityLogPage> createState() => _CafeActivityLogPageState();
}

class _CafeActivityLogPageState extends State<CafeActivityLogPage> {
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل نشاط العمليات'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'بحث باسم الموظف أو العملية...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[200],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // 👈 **التعديل الأول: إزالة .orderBy() من هنا**
              // نطلب البيانات مفلترة بالكافيه فقط
              stream: FirebaseFirestore.instance
                  .collection('activity_logs')
                  .where('cafeId', isEqualTo: widget.currentUser.cafeId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text("حدث خطأ: ${snapshot.error}"));
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = snapshot.data!.docs;

                // 👈 **التعديل الثاني: الترتيب يتم هنا في الكود**
                docs.sort((a, b) {
                  Timestamp timeA = a['timestamp'] ?? Timestamp.now();
                  Timestamp timeB = b['timestamp'] ?? Timestamp.now();
                  // b.compareTo(a) للترتيب من الأحدث إلى الأقدم
                  return timeB.compareTo(timeA);
                });

                // فلترة النتائج حسب البحث (تبقى كما هي)
                if (_searchQuery.isNotEmpty) {
                  docs = docs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final userName = (data['userName'] ?? "").toString().toLowerCase();
                    final action = (data['action'] ?? "").toString().toLowerCase();
                    return userName.contains(_searchQuery) || action.contains(_searchQuery);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return const Center(child: Text("لا توجد سجلات نشاط حالياً"));
                }

                // باقي الكود يبقى كما هو بدون تغيير
                return ListView.separated(
                  itemCount: docs.length,
                  padding: const EdgeInsets.all(10),
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final DateTime time = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
                    final String action = data['action'] ?? "عملية غير معروفة";
                    final String userName = data['userName'] ?? "موظف";
                    final String details = data['details'] ?? "";

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _getIconColor(action).withOpacity(0.1),
                        child: Icon(_getIcon(action), color: _getIconColor(action), size: 20),
                      ),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(
                            DateFormat('yyyy-MM-dd | HH:mm').format(time),
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(action, style: TextStyle(color: _getIconColor(action), fontWeight: FontWeight.w600)),
                          Text(details, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIcon(String action) {
    if (action.contains("حذف")) return Icons.delete_forever;
    if (action.contains("دفع")) return Icons.payments;
    if (action.contains("صلاحية")) return Icons.security;
    return Icons.info_outline;
  }

  Color _getIconColor(String action) {
    if (action.contains("حذف")) return Colors.red;
    if (action.contains("دفع")) return Colors.green;
    if (action.contains("صلاحية")) return Colors.orange;
    return Colors.blue;
  }
}
