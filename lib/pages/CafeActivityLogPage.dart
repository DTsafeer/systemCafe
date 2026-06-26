import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'user_model.dart';

class CafeActivityLogPage extends StatefulWidget {
  final User currentUser;

  const CafeActivityLogPage({super.key, required this.currentUser});

  @override
  State<CafeActivityLogPage> createState() => _CafeActivityLogPageState();
}

class _CafeActivityLogPageState extends State<CafeActivityLogPage> {
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  DateTime? _selectedDate;

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar', 'SA'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String managerId = widget.currentUser.parentId ?? widget.currentUser.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل نشاط العمليات'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_selectedDate != null)
            IconButton(
              icon: const Icon(Icons.calendar_today_outlined),
              onPressed: () => setState(() => _selectedDate = null),
              tooltip: "عرض الكل",
            ),
          IconButton(
            icon: Icon(_selectedDate == null ? Icons.filter_alt_outlined : Icons.filter_alt, color: _selectedDate == null ? Colors.white : Colors.amber),
            onPressed: _pickDate,
            tooltip: "فلترة حسب التاريخ",
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
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
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
                  ),
                ),
                if (_selectedDate != null) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(DateFormat('yyyy-MM-dd').format(_selectedDate!)),
                    onDeleted: () => setState(() => _selectedDate = null),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                  ),
                ]
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('activity_logs')
                  .where('cafeId', isEqualTo: widget.currentUser.cafeId)
                  .where('parentId', isEqualTo: managerId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text("حدث خطأ: ${snapshot.error}"));
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = snapshot.data!.docs;

                // الترتيب من الأحدث للأقدم
                docs.sort((a, b) {
                  Timestamp timeA = a['timestamp'] ?? Timestamp.now();
                  Timestamp timeB = b['timestamp'] ?? Timestamp.now();
                  return timeB.compareTo(timeA);
                });

                // تطبيق فلتر التاريخ
                if (_selectedDate != null) {
                  docs = docs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final DateTime logTime = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
                    return logTime.year == _selectedDate!.year &&
                           logTime.month == _selectedDate!.month &&
                           logTime.day == _selectedDate!.day;
                  }).toList();
                }

                // تطبيق فلتر البحث
                if (_searchQuery.isNotEmpty) {
                  docs = docs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final userName = (data['userName'] ?? "").toString().toLowerCase();
                    final action = (data['action'] ?? "").toString().toLowerCase();
                    return userName.contains(_searchQuery) || action.contains(_searchQuery);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.history_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(_selectedDate != null ? "لا توجد عمليات في هذا التاريخ" : "لا توجد سجلات نشاط حالياً", style: const TextStyle(color: Colors.grey)),
                      ],
                    )
                  );
                }

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
                            DateFormat('HH:mm').format(time),
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
                          if (_selectedDate == null) 
                             Text(DateFormat('yyyy-MM-dd').format(time), style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
    if (action.contains("تعديل")) return Icons.edit_note;
    return Icons.info_outline;
  }

  Color _getIconColor(String action) {
    if (action.contains("حذف")) return Colors.red;
    if (action.contains("دفع")) return Colors.green;
    if (action.contains("صلاحية")) return Colors.orange;
    if (action.contains("تعديل")) return Colors.blue;
    return Colors.blueGrey;
  }
}
