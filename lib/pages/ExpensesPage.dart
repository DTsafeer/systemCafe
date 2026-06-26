import 'dart:async';
import 'dart:ui' as ui; 
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import 'activity_logger.dart';

class ExpensesPage extends StatefulWidget {
  final User currentUser;
  const ExpensesPage({super.key, required this.currentUser});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final _searchController = TextEditingController();
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>("");
  Timer? _debounce;
  late String managerId;

  @override
  void initState() {
    super.initState();
    managerId = widget.currentUser.parentId ?? widget.currentUser.id;
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchQueryNotifier.value = query.trim().toLowerCase();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchQueryNotifier.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    if (!widget.currentUser.canRead('expenses')) {
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'expenses',
        child: const Scaffold(
          body: Center(
            child: Text("عذراً، لا تملك صلاحية لعرض صفحة المصاريف", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'expenses',
      floatingActionButton: widget.currentUser.canCreate('expenses') ? FloatingActionButton.extended(
        onPressed: _showAddExpenseDialog,
        backgroundColor: primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("مصروف جديد", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ) : null,
      child: Column(
        children: [
          _buildExpenseSummary(primaryColor),
          _buildSearchField(primaryColor),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: _searchQueryNotifier,
              builder: (context, query, _) {
                return _ExpensesList(
                  searchQuery: query,
                  managerId: managerId,
                  currentUser: widget.currentUser,
                  primaryColor: primaryColor,
                  onDelete: _deleteExpense,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseSummary(Color primary) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('expenses')
          .where('cafeId', isEqualTo: widget.currentUser.cafeId)
          .snapshots(),
      builder: (context, snapshot) {
        double totalMonth = 0;
        if (snapshot.hasData) {
          final now = DateTime.now();
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['parentId'] != managerId) continue;
            final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
            if (date.month == now.month && date.year == now.year) {
              totalMonth += (data['amount'] ?? 0.0).toDouble();
            }
          }
        }
        return Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(color: primary, borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(40))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("إجمالي مصاريف الشهر", style: TextStyle(color: Colors.white70, fontSize: 14)),
                  Text("${totalMonth.toStringAsFixed(1)} ₪", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                ],
              ),
              const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 45),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchField(Color primary) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: "بحث في المصاريف...",
          prefixIcon: Icon(Icons.search_rounded, color: primary),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  void _showAddExpenseDialog() {
    if (!widget.currentUser.canCreate('expenses')) return;

    final titleCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    String category = "أخرى";
    bool isLoading = false;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            title: const Text("مصروف جديد"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "البيان")),
                  TextField(controller: amtCtrl, decoration: const InputDecoration(labelText: "المبلغ"), keyboardType: TextInputType.number),
                  const SizedBox(height: 10),
                  DropdownButton<String>(
                    value: category,
                    isExpanded: true,
                    items: ["رواتب", "إيجار", "كهرباء", "مياه", "إنترنت", "صيانة", "مواد تنظيف", "أخرى"].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setDialogState(() => category = v!),
                  ),
                  if (isLoading) const Padding(padding: EdgeInsets.only(top: 15), child: CircularProgressIndicator()),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: isLoading ? null : () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ElevatedButton(onPressed: isLoading ? null : () async {
                final amt = double.tryParse(amtCtrl.text) ?? 0.0;
                final title = titleCtrl.text.trim();
                if (title.isNotEmpty && amt > 0) {
                  setDialogState(() => isLoading = true);
                  
                  // Firestore handles offline persistence
                  FirebaseFirestore.instance.collection('expenses').add({
                    'cafeId': widget.currentUser.cafeId,
                    'parentId': managerId,
                    'title': title,
                    'amount': amt,
                    'category': category,
                    'date': FieldValue.serverTimestamp(),
                    'processedBy': widget.currentUser.name,
                  });

                  ActivityLogger.log(
                    cafeId: widget.currentUser.cafeId,
                    parentId: managerId,
                    userId: widget.currentUser.id,
                    userName: widget.currentUser.name,
                    action: "مصاريف - إضافة",
                    details: "إضافة مصروف: $title بقيمة $amt ₪ ($category)",
                  );

                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم إضافة المصروف")));
                  }
                }
              }, child: const Text("حفظ")),
            ],
          ),
        ),
      ),
    );
  }

  void _deleteExpense(String id, String title) {
    if (!widget.currentUser.canDelete('expenses')) return;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text("حذف"),
          content: Text("حذف $title؟"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
            TextButton(onPressed: () async { 
              // Immediate delete locally
              FirebaseFirestore.instance.collection('expenses').doc(id).delete(); 

              ActivityLogger.log(
                cafeId: widget.currentUser.cafeId,
                parentId: managerId,
                userId: widget.currentUser.id,
                userName: widget.currentUser.name,
                action: "مصاريف - حذف",
                details: "حذف مصروف: $title",
              );

              if (mounted) {
                Navigator.pop(ctx); 
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم الحذف")));
              }
            }, child: const Text("حذف", style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }
}

class _ExpensesList extends StatefulWidget {
  final String searchQuery;
  final String managerId;
  final User currentUser;
  final Color primaryColor;
  final Function(String, String) onDelete;

  const _ExpensesList({required this.searchQuery, required this.managerId, required this.currentUser, required this.primaryColor, required this.onDelete});

  @override
  State<_ExpensesList> createState() => _ExpensesListState();
}

class _ExpensesListState extends State<_ExpensesList> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('expenses')
          .where('cafeId', isEqualTo: widget.currentUser.cafeId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        
        final docs = (snapshot.data?.docs ?? []).where((d) {
          final data = d.data() as Map<String, dynamic>;
          if (data['parentId'] != widget.managerId) return false;
          final title = (data['title'] ?? "").toString().toLowerCase();
          return title.contains(widget.searchQuery);
        }).toList();

        docs.sort((a, b) {
          final t1 = (a.data() as Map)['date'] as Timestamp? ?? Timestamp.now();
          final t2 = (b.data() as Map)['date'] as Timestamp? ?? Timestamp.now();
          return t2.compareTo(t1);
        });

        if (docs.isEmpty) return const Center(child: Text("لا توجد مصاريف مطابقة"));

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(15, 0, 15, 80),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
            
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey[200]!)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: widget.primaryColor.withOpacity(0.1), 
                  child: const Icon(Icons.payments_outlined)
                ),
                title: Text(data['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(DateFormat('yyyy/MM/dd | HH:mm').format(date)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("${data['amount']} ₪", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                    if (widget.currentUser.canDelete('expenses'))
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () => widget.onDelete(docs[index].id, data['title']),
                      ),
                  ],
                ),
                onLongPress: widget.currentUser.canDelete('expenses') ? () => widget.onDelete(docs[index].id, data['title']) : null,
              ),
            );
          },
        );
      },
    );
  }
}
