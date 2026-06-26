import 'dart:async';
import 'dart:ui' as ui; 
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import 'activity_logger.dart';

class ChecksPage extends StatefulWidget {
  final User currentUser;
  const ChecksPage({super.key, required this.currentUser});

  @override
  State<ChecksPage> createState() => _ChecksPageState();
}

class _ChecksPageState extends State<ChecksPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>("");
  Timer? _debounce;
  late String managerId;

  @override
  void initState() {
    super.initState();
    managerId = widget.currentUser.parentId ?? widget.currentUser.id;
    _tabController = TabController(length: 2, vsync: this);
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchQueryNotifier.value = query.trim().toLowerCase();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchQueryNotifier.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.currentUser.canRead('checks')) {
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'checks',
        child: const Scaffold(
          body: Center(
            child: Text("عذراً، لا تملك صلاحية الوصول لصفحة الشيكات", 
              style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }

    final primaryColor = Theme.of(context).colorScheme.primary;

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'checks',
      floatingActionButton: widget.currentUser.canCreate('checks') ? FloatingActionButton.extended(
        onPressed: _showAddCheckDialog,
        backgroundColor: primaryColor,
        icon: const Icon(Icons.add_card_rounded, color: Colors.white),
        label: const Text("إضافة شيك", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ) : null,
      child: Column(
        children: [
          Container(
            color: primaryColor,
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: "شيكات صادرة (لنا)", icon: Icon(Icons.outbox_rounded)),
                Tab(text: "شيكات واردة (علينا)", icon: Icon(Icons.inbox_rounded)),
              ],
            ),
          ),
          _buildSearchField(primaryColor),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: _searchQueryNotifier,
                  builder: (context, query, _) => _ChecksList(
                    type: "صادر",
                    searchQuery: query,
                    managerId: managerId,
                    currentUser: widget.currentUser,
                  ),
                ),
                ValueListenableBuilder<String>(
                  valueListenable: _searchQueryNotifier,
                  builder: (context, query, _) => _ChecksList(
                    type: "وارد",
                    searchQuery: query,
                    managerId: managerId,
                    currentUser: widget.currentUser,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(Color primary) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(15), 
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: "بحث برقم الشيك أو الاسم...",
            prefixIcon: Icon(Icons.search, color: primary),
            border: InputBorder.none, 
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      ),
    );
  }

  void _showAddCheckDialog() {
    final noCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final bankCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 30));
    String type = _tabController.index == 0 ? "صادر" : "وارد";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text("إضافة شيك $type"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: InputDecoration(labelText: type == "صادر" ? "اسم المستفيد" : "اسم الساحب")),
                  TextField(controller: noCtrl, decoration: const InputDecoration(labelText: "رقم الشيك")),
                  TextField(controller: bankCtrl, decoration: const InputDecoration(labelText: "البنك")),
                  TextField(controller: amtCtrl, decoration: const InputDecoration(labelText: "المبلغ"), keyboardType: TextInputType.number),
                  const SizedBox(height: 15),
                  ListTile(
                    title: Text("تاريخ الاستحقاق: ${DateFormat('yyyy/MM/dd').format(selectedDate)}"),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () async {
                      final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                      if (picked != null) setDialogState(() => selectedDate = picked);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ElevatedButton(onPressed: () async {
                final amt = double.tryParse(amtCtrl.text) ?? 0.0;
                final name = nameCtrl.text.trim();
                final checkNo = noCtrl.text.trim();
                if (name.isNotEmpty && amt > 0) {
                  await FirebaseFirestore.instance.collection('checks').add({
                    'checkNo': checkNo,
                    'personName': name,
                    'bankName': bankCtrl.text.trim(),
                    'amount': amt,
                    'dueDate': Timestamp.fromDate(selectedDate),
                    'type': type,
                    'status': "انتظار",
                    'cafeId': widget.currentUser.cafeId,
                    'parentId': managerId,
                    'createdAt': FieldValue.serverTimestamp(),
                  });

                  await ActivityLogger.log(
                    cafeId: widget.currentUser.cafeId,
                    parentId: managerId,
                    userId: widget.currentUser.id,
                    userName: widget.currentUser.name,
                    action: "شيكات - إضافة",
                    details: "إضافة شيك $type رقم $checkNo بقيمة $amt ₪ للطرف: $name",
                  );

                  if (mounted) Navigator.pop(ctx);
                }
              }, child: const Text("حفظ")),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChecksList extends StatefulWidget {
  final String type;
  final String searchQuery;
  final String managerId;
  final User currentUser;

  const _ChecksList({required this.type, required this.searchQuery, required this.managerId, required this.currentUser});

  @override
  State<_ChecksList> createState() => _ChecksListState();
}

class _ChecksListState extends State<_ChecksList> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('checks')
          .where('cafeId', isEqualTo: widget.currentUser.cafeId)
          .where('parentId', isEqualTo: widget.managerId)
          .where('type', isEqualTo: widget.type)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final docs = snapshot.data!.docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          if (widget.searchQuery.isEmpty) return true;
          final checkNo = (data['checkNo'] ?? "").toString();
          final name = (data['personName'] ?? "").toString().toLowerCase();
          return checkNo.contains(widget.searchQuery) || name.contains(widget.searchQuery);
        }).toList();

        if (docs.isEmpty) return const Center(child: Text("لا توجد نتائج"));

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(15, 0, 15, 80),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final dueDate = (data['dueDate'] as Timestamp?)?.toDate() ?? DateTime.now();
            final status = data['status'] ?? "انتظار";
            
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey[200]!)),
              child: ListTile(
                title: Text(data['personName'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("رقم: ${data['checkNo']} | تاريخ: ${DateFormat('yyyy/MM/dd').format(dueDate)}"),
                trailing: Text("${data['amount']} ₪", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                onTap: widget.currentUser.canUpdate('checks') 
                    ? () => _showStatusDialog(context, docs[index].id, status, data['checkNo'] ?? "")
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  void _showStatusDialog(BuildContext context, String docId, String currentStatus, String checkNo) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: SimpleDialog(
          title: const Text("تغيير الحالة"),
          children: ["انتظار", "صرف", "مرتجع"].map((s) => SimpleDialogOption(
            onPressed: () async {
              if (s != currentStatus) {
                await FirebaseFirestore.instance.collection('checks').doc(docId).update({'status': s});
                
                await ActivityLogger.log(
                  cafeId: widget.currentUser.cafeId,
                  parentId: widget.managerId,
                  userId: widget.currentUser.id,
                  userName: widget.currentUser.name,
                  action: "شيكات - تعديل حالة",
                  details: "تعديل حالة الشيك رقم $checkNo من $currentStatus إلى $s",
                );
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(s),
          )).toList(),
        ),
      ),
    );
  }
}
