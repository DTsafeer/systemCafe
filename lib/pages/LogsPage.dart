import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import '../utils/database_helper.dart';
import '../widgets/log_widgets.dart';
import 'user_model.dart';
import 'MainLayout.dart';

class LogsPage extends StatefulWidget {
  final User currentUser;
  const LogsPage({super.key, required this.currentUser});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _searchController = TextEditingController();
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>("");
  final ValueNotifier<String> _filterCategoryNotifier = ValueNotifier<String>("الكل");
  final ValueNotifier<DateTime?> _selectedDateNotifier = ValueNotifier<DateTime?>(null);
  
  Timer? _debounce;
  bool _showLocalLogs = false;
  late String managerId;

  final List<Map<String, dynamic>> _filters = [
    {'label': 'الكل', 'icon': Icons.apps_rounded},
    {'label': 'حذف', 'icon': Icons.delete_outline_rounded},
    {'label': 'مبيعات', 'icon': Icons.receipt_long_rounded},
    {'label': 'مخزن', 'icon': Icons.inventory_2_rounded},
    {'label': 'تعديل', 'icon': Icons.edit_rounded},
    {'label': 'ديون', 'icon': Icons.money_off_rounded},
  ];

  @override
  void initState() {
    super.initState();
    managerId = widget.currentUser.parentId ?? widget.currentUser.id;
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _searchQueryNotifier.value = query.trim().toLowerCase();
      }
    });
    setState(() {});
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateNotifier.value ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      locale: const Locale('ar', 'SA'),
    );
    if (picked != null) {
      _selectedDateNotifier.value = picked;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchQueryNotifier.dispose();
    _filterCategoryNotifier.dispose();
    _selectedDateNotifier.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'logs',
      child: Column(
        children: [
          _buildModernHeader(primaryColor),
          _buildFilterBar(primaryColor),
          Expanded(
            child: ValueListenableBuilder3<String, String, DateTime?>(
              first: _searchQueryNotifier,
              second: _filterCategoryNotifier,
              third: _selectedDateNotifier,
              builder: (context, query, filter, date, _) {
                return _showLocalLogs 
                  ? _LocalLogsList(searchQuery: query, category: filter, selectedDate: date, cafeId: widget.currentUser.cafeId) 
                  : _CloudLogsList(
                      searchQuery: query, 
                      category: filter, 
                      selectedDate: date,
                      cafeId: widget.currentUser.cafeId, 
                      managerId: managerId,
                      primaryColor: primaryColor
                    );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernHeader(Color primaryColor) {
    final startOfDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    return Container(
      padding: const EdgeInsets.fromLTRB(25, 45, 25, 25),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, primaryColor.withBlue(140)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
        boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.security_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("مركز الرقابة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
                    Text(_showLocalLogs ? "سجلات الجهاز (بدون إنترنت)" : "مراقبة الأنشطة المباشرة", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
                  ],
                ),
              ),
              _buildToggleBtn(),
            ],
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              Expanded(child: _buildSearchBar()),
              const SizedBox(width: 12),
              ValueListenableBuilder<DateTime?>(
                valueListenable: _selectedDateNotifier,
                builder: (context, date, _) {
                  return IconButton(
                    onPressed: _pickDate,
                    icon: Icon(date == null ? Icons.calendar_today_outlined : Icons.calendar_today, color: Colors.white),
                    tooltip: "تحديد التاريخ",
                    style: IconButton.styleFrom(
                      backgroundColor: date != null ? Colors.amber.withOpacity(0.3) : Colors.white.withOpacity(0.1),
                    ),
                  );
                }
              ),
              const SizedBox(width: 12),
              if (!_showLocalLogs)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('activity_logs')
                      .where('cafeId', isEqualTo: widget.currentUser.cafeId)
                      .where('parentId', isEqualTo: managerId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    int count = 0;
                    if (snapshot.hasData) {
                      count = snapshot.data!.docs.where((doc) {
                        final ts = (doc.data() as Map)['timestamp'] as Timestamp?;
                        return ts != null && ts.toDate().isAfter(startOfDay);
                      }).length;
                    }
                    return _buildStatBadge("$count", "نشاط اليوم");
                  },
                ),
            ],
          ),
          ValueListenableBuilder<DateTime?>(
            valueListenable: _selectedDateNotifier,
            builder: (context, date, _) {
              if (date == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 15),
                child: Chip(
                  label: Text(intl.DateFormat('yyyy-MM-dd').format(date), style: const TextStyle(color: Colors.white)),
                  backgroundColor: Colors.white.withOpacity(0.2),
                  deleteIcon: const Icon(Icons.close, size: 18, color: Colors.white),
                  onDeleted: () => _selectedDateNotifier.value = null,
                ),
              );
            }
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)),
      child: Column(children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9)),
      ]),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15)]),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: "بحث عن مستخدم أو عملية...",
          prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[400]),
          suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.cancel_rounded, size: 18), onPressed: () { 
            if (mounted) {
              _searchController.clear(); 
              _onSearchChanged(""); 
            }
          }) : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
    );
  }

  Widget _buildFilterBar(Color primaryColor) {
    return Container(
      height: 70,
      child: ValueListenableBuilder<String>(
        valueListenable: _filterCategoryNotifier,
        builder: (context, selectedFilter, _) {
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            itemCount: _filters.length,
            itemBuilder: (context, index) {
              final filter = _filters[index];
              final isSelected = selectedFilter == filter['label'];
              return Padding(
                padding: const EdgeInsets.only(left: 10),
                child: FilterChip(
                  selected: isSelected,
                  label: Text(filter['label']),
                  avatar: Icon(filter['icon'], size: 16, color: isSelected ? Colors.white : Colors.blueGrey),
                  onSelected: (v) => _filterCategoryNotifier.value = filter['label'],
                  backgroundColor: Colors.white,
                  selectedColor: primaryColor,
                  labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.withOpacity(0.1))),
                  showCheckmark: false,
                  elevation: isSelected ? 4 : 0,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildToggleBtn() {
    return InkWell(
      onTap: () => setState(() => _showLocalLogs = !_showLocalLogs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)),
        child: Row(children: [
          Icon(_showLocalLogs ? Icons.storage_rounded : Icons.cloud_done_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(_showLocalLogs ? "محلي" : "سحابي", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}

class ValueListenableBuilder3<A, B, C> extends StatelessWidget {
  final ValueListenable<A> first;
  final ValueListenable<B> second;
  final ValueListenable<C> third;
  final Widget Function(BuildContext context, A a, B b, C c, Widget? child) builder;
  final Widget? child;
  const ValueListenableBuilder3({super.key, required this.first, required this.second, required this.third, required this.builder, this.child});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<A>(valueListenable: first, builder: (context, a, _) => ValueListenableBuilder<B>(valueListenable: second, builder: (context, b, _) => ValueListenableBuilder<C>(valueListenable: third, builder: (context, c, _) => builder(context, a, b, c, child))));
}

class _CloudLogsList extends StatefulWidget {
  final String searchQuery;
  final String category;
  final DateTime? selectedDate;
  final String cafeId;
  final String managerId;
  final Color primaryColor;
  const _CloudLogsList({required this.searchQuery, required this.category, this.selectedDate, required this.cafeId, required this.managerId, required this.primaryColor});
  @override
  State<_CloudLogsList> createState() => _CloudLogsListState();
}

class _CloudLogsListState extends State<_CloudLogsList> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  void _showLogDetails(Map<String, dynamic> data, DateTime ts) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Row(children: [
          Icon(Icons.info_outline_rounded, color: widget.primaryColor),
          const SizedBox(width: 10),
          const Text("تفاصيل النشاط", style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow("المستخدم:", data['userName'] ?? "غير معروف"),
            _buildDetailRow("العملية:", data['action'] ?? ""),
            _buildDetailRow("التوقيت:", intl.DateFormat('yyyy/MM/dd - hh:mm a').format(ts)),
            const Divider(height: 30),
            const Text("الوصف الكامل:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
            const SizedBox(height: 8),
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
              child: Text(data['details'] ?? "لا توجد تفاصيل إضافية", style: const TextStyle(fontSize: 13, height: 1.5)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إغلاق")),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('activity_logs')
          .where('cafeId', isEqualTo: widget.cafeId)
          .where('parentId', isEqualTo: widget.managerId)
          .limit(300)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("خطأ: ${snapshot.error}"));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        
        final List<DocumentSnapshot> docs = snapshot.data!.docs.toList();
        docs.sort((a, b) {
          final tsA = (a.data() as Map)['timestamp'] as Timestamp?;
          final tsB = (b.data() as Map)['timestamp'] as Timestamp?;
          if (tsA == null) return 1;
          if (tsB == null) return -1;
          return tsB.compareTo(tsA);
        });

        final filteredDocs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final ts = (data['timestamp'] as Timestamp?)?.toDate();
          
          // فلتر التاريخ
          if (widget.selectedDate != null) {
            if (ts == null) return false;
            if (ts.year != widget.selectedDate!.year || 
                ts.month != widget.selectedDate!.month || 
                ts.day != widget.selectedDate!.day) return false;
          }

          final action = data['action']?.toString().toLowerCase() ?? "";
          if (widget.category != "الكل" && !action.contains(widget.category.toLowerCase())) return false;
          if (widget.searchQuery.isEmpty) return true;
          final s = widget.searchQuery;
          return data['userName'].toString().toLowerCase().contains(s) ||
                 action.contains(s) || data['details'].toString().toLowerCase().contains(s);
        }).toList();

        if (filteredDocs.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.history_toggle_off_rounded, size: 70, color: Colors.grey[200]),
            Text(widget.selectedDate != null ? "لا توجد سجلات في هذا التاريخ" : "لا توجد سجلات مطابقة", style: const TextStyle(color: Colors.grey))
          ]));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: filteredDocs.length,
          itemBuilder: (context, index) {
            final data = filteredDocs[index].data() as Map<String, dynamic>;
            final ts = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
            bool showHeader = index == 0 || ts.day != ((filteredDocs[index-1].data() as Map)['timestamp'] as Timestamp?)?.toDate().day;
            
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (showHeader) _buildDateHeader(ts),
              GestureDetector(
                onTap: () => _showLogDetails(data, ts),
                child: ActivityLogCard(
                  user: data['userName'] ?? "مستخدم", 
                  action: data['action'] ?? "", 
                  details: data['details'] ?? "", 
                  timestamp: ts, 
                  color: widget.primaryColor
                ),
              ),
            ]);
          },
        );
      },
    );
  }

  Widget _buildDateHeader(DateTime date) {
    String label = intl.DateFormat('EEEE, d MMMM').format(date);
    if (date.day == DateTime.now().day && date.month == DateTime.now().month && date.year == DateTime.now().year) label = "اليوم";
    return Padding(padding: const EdgeInsets.only(top: 25, bottom: 15, right: 10), child: Row(children: [
      Container(width: 4, height: 18, decoration: BoxDecoration(color: widget.primaryColor.withOpacity(0.5), borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(fontWeight: FontWeight.w900, color: Colors.blueGrey[800], fontSize: 14)),
    ]));
  }
}

class _LocalLogsList extends StatelessWidget {
  final String searchQuery;
  final String category;
  final DateTime? selectedDate;
  final String cafeId;
  const _LocalLogsList({required this.searchQuery, required this.category, this.selectedDate, required this.cafeId});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper().getLocalLogs(cafeId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final logs = snapshot.data!.where((log) {
          final tsStr = log['timestamp']?.toString();
          final ts = tsStr != null ? DateTime.tryParse(tsStr) : null;

          // فلتر التاريخ
          if (selectedDate != null) {
            if (ts == null) return false;
            if (ts.year != selectedDate!.year || 
                ts.month != selectedDate!.month || 
                ts.day != selectedDate!.day) return false;
          }

          final action = log['action']?.toString().toLowerCase() ?? "";
          if (category != "الكل" && !action.contains(category.toLowerCase())) return false;
          final s = searchQuery;
          return s.isEmpty || log['userName'].toString().toLowerCase().contains(s) || action.contains(s) || log['details'].toString().toLowerCase().contains(s);
        }).toList();

        if (logs.isEmpty) return Center(child: Text(selectedDate != null ? "لا توجد سجلات محلية في هذا التاريخ" : "لا توجد سجلات محلية"));
        
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), 
          itemCount: logs.length, 
          itemBuilder: (context, index) {
            final data = logs[index];
            return ActivityLogCard(
              user: data['userName'] ?? "مستخدم", 
              action: data['action'] ?? "", 
              details: data['details'] ?? "", 
              timestamp: DateTime.tryParse(data['timestamp'] ?? "") ?? DateTime.now(), 
              icon: Icons.storage_rounded, 
              color: Colors.blueGrey
            );
          }
        );
      },
    );
  }
}
