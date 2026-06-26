import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'user_model.dart';
import 'MainLayout.dart';

class WarehouseTransfersPage extends StatefulWidget {
  final User currentUser;
  const WarehouseTransfersPage({super.key, required this.currentUser});

  @override
  State<WarehouseTransfersPage> createState() => _WarehouseTransfersPageState();
}

class _WarehouseTransfersPageState extends State<WarehouseTransfersPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String? _selectedMethodFilter;
  late Stream<List<QueryDocumentSnapshot>> _transfersStream;
  
  DateTime? _startDate;
  DateTime? _endDate;
  
  String get _managerId => widget.currentUser.parentId ?? widget.currentUser.id;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  void _initStream() {
    // Firestore persistence handle offline automatically
    _transfersStream = FirebaseFirestore.instance.collection('warehouse_transfers')
        .where('cafeId', isEqualTo: widget.currentUser.cafeId)
        .where('parentId', isEqualTo: _managerId)
        .snapshots()
        .map((snapshot) {
          final List<QueryDocumentSnapshot> docs = List.from(snapshot.docs);
          docs.sort((a, b) {
            final t1 = (a.data() as Map)['transferredAt'] as Timestamp?;
            final t2 = (b.data() as Map)['transferredAt'] as Timestamp?;
            return (t2 ?? Timestamp.now()).compareTo(t1 ?? Timestamp.now());
          });
          return docs;
        });
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: (_startDate != null && _endDate != null) 
          ? DateTimeRange(start: _startDate!, end: _endDate!) 
          : null,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: Theme.of(context).primaryColor),
          ),
          child: Directionality(textDirection: ui.TextDirection.rtl, child: child!),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end.add(const Duration(hours: 23, minutes: 59));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    if (!widget.currentUser.canRead('warehouse_transfers')) {
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'warehouse_transfers',
        child: const Scaffold(
          body: Center(
            child: Text("عذراً، لا تملك صلاحية لعرض سجل التحويلات", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'warehouse_transfers',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: primary,
          elevation: 0,
          foregroundColor: Colors.white,
          centerTitle: true,
          title: const Text("سجل تحويلات المخازن", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: Column(
          children: [
            _buildDateFilterBar(primary),
            _buildSearchBar(primary),
            _buildMethodChips(primary),
            
            Expanded(
              child: StreamBuilder<List<QueryDocumentSnapshot>>(
                stream: _transfersStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return const Center(child: Text("حدث خطأ في الاتصال بقاعدة البيانات"));
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final List<QueryDocumentSnapshot> managerDocs = snapshot.data ?? [];
                  
                  final filteredDocs = managerDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    
                    if (_searchQuery.isNotEmpty) {
                      final name = (data['itemName'] ?? '').toString().toLowerCase();
                      if (!name.contains(_searchQuery.toLowerCase())) return false;
                    }

                    if (_startDate != null && _endDate != null) {
                      final date = (data['transferredAt'] as Timestamp?)?.toDate();
                      if (date == null || date.isBefore(_startDate!) || date.isAfter(_endDate!)) return false;
                    }

                    if (_selectedMethodFilter != null) {
                      final method = data['transferMethod'] ?? '';
                      if (method != _selectedMethodFilter) return false;
                    }
                    
                    return true;
                  }).toList();

                  if (filteredDocs.isEmpty) return _buildEmptyState();

                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final doc = filteredDocs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final date = (data['transferredAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                      return _buildTransferCard(data, date, primary, doc.reference);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateFilterBar(Color primary) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: InkWell(
        onTap: _selectDateRange,
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, color: primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("فلترة حسب التاريخ (من - إلى)", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(
                    _startDate == null 
                      ? "إختر الفترة الزمنية للبحث" 
                      : "${DateFormat('yyyy/MM/dd').format(_startDate!)}  ←  ${DateFormat('yyyy/MM/dd').format(_endDate!)}",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _startDate != null ? primary : Colors.black87),
                  ),
                ],
              ),
            ),
            if (_startDate != null)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red, size: 20),
                onPressed: () => setState(() { _startDate = null; _endDate = null; }),
              )
            else
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(Color primary) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val),
        decoration: InputDecoration(
          hintText: "بحث عن صنف معين...",
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildMethodChips(Color primary) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          _methodChip("الكل", null, primary),
          _methodChip("تحويل من المخزن", "تحويل من المخزن الخارجي", primary),
          _methodChip("تالف", "تالف", primary),
          _methodChip("مرتجع", "مرتجع", primary),
        ],
      ),
    );
  }

  Widget _methodChip(String label, String? value, Color primary) {
    bool selected = _selectedMethodFilter == value;
    return GestureDetector(
      onTap: () {
        if (_selectedMethodFilter == value) return;
        setState(() => _selectedMethodFilter = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? primary : Colors.grey[200]!),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.black87, fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _buildTransferCard(Map<String, dynamic> data, DateTime date, Color primary, DocumentReference ref) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey[100]!)),
      child: ListTile(
        title: Text(data['itemName'] ?? "صنف غير معروف", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${DateFormat('yyyy/MM/dd | HH:mm').format(date)}\nبواسطة: ${data['processedBy'] ?? 'مجهول'}"),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("${data['quantity']} ${data['unit'] ?? ''}", style: TextStyle(fontWeight: FontWeight.bold, color: primary, fontSize: 16)),
                Text(data['transferMethod']?.replaceFirst("تحويل من المخزن الخارجي", "للمحل") ?? "", style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
              ],
            ),
            if (widget.currentUser.canDelete('warehouse_transfers')) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("تأكيد الحذف"),
                      content: const Text("هل تريد حذف هذا السجل؟ (لن يؤثر على الكميات الحالية)"),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("حذف", style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    try {
                      // Firestore handles offline deletion
                      ref.delete(); 
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم الحذف")));
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ أثناء الحذف: $e")));
                    }
                  }
                },
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 10),
          const Text("لا توجد تحويلات في هذه الفترة", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
