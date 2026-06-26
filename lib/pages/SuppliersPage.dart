import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:excel/excel.dart' as excel_pkg;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/cafe_service.dart';
import '../widgets/supplier_dialogs.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import '../services/supplier_service.dart';

class SuppliersPage extends StatefulWidget {
  final User currentUser;
  const SuppliersPage({super.key, required this.currentUser});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String _activeFilter = "الكل";
  String _sortBy = "الأعلى ديناً";
  String? _expandedSupplierId;
  
  List<String> _paymentMethods = ["كاش"];
  StreamSubscription? _settingsSub;

  String get _managerId => widget.currentUser.parentId ?? widget.currentUser.id;
  String get _cafeId => widget.currentUser.cafeId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() { if (mounted) setState(() {}); });
    _listenToSettings();
  }

  void _listenToSettings() {
    if (_cafeId.isNotEmpty) {
      _settingsSub = CafeService.streamCafeSettings(_cafeId).listen((settings) {
        if (mounted) {
          setState(() {
            List<String> methods = ["كاش"];
            for (var m in settings.paymentMethods) {
              if (!m.contains("دين") && !m.contains("ديون") && m != "كاش") {
                methods.add(m);
              }
            }
            _paymentMethods = methods;
          });
        }
      });
    }
  }

  Future<void> _downloadSupplierReport(List<DocumentSnapshot> docs) async {
    try {
      var excelDoc = excel_pkg.Excel.createExcel();
      excel_pkg.Sheet sheetObject = excelDoc['كشف الموردين'];
      excelDoc.delete('Sheet1');

      sheetObject.appendRow([
        excel_pkg.TextCellValue('اسم المورد'),
        excel_pkg.TextCellValue('رصيد الدين (لنا)'),
        excel_pkg.TextCellValue('دفعات مسبقة (للمورد)'),
        excel_pkg.TextCellValue('إجمالي المدفوع'),
        excel_pkg.TextCellValue('رقم الهاتف'),
      ]);

      for (var doc in docs) {
        final d = doc.data() as Map<String, dynamic>;
        double bal = (d['totalBalance'] ?? 0.0).toDouble();
        sheetObject.appendRow([
          excel_pkg.TextCellValue(d['name'].toString()),
          excel_pkg.DoubleCellValue(bal > 0 ? bal : 0),
          excel_pkg.DoubleCellValue(bal < 0 ? bal.abs() : 0),
          excel_pkg.DoubleCellValue((d['totalPaid'] ?? 0.0).toDouble()),
          excel_pkg.TextCellValue(d['phone'] ?? "-"),
        ]);
      }

      final directory = await getTemporaryDirectory();
      final fileName = "كشف_الموردين_${intl.DateFormat('yyyy_MM_dd').format(DateTime.now())}.xlsx";
      final path = "${directory.path}/$fileName";
      final bytes = excelDoc.save();

      if (bytes != null) {
        await File(path).writeAsBytes(bytes);
        await Share.shareXFiles([XFile(path)], text: 'كشف مديونية الموردين - نظام سستم');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ في التصدير: $e")));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _settingsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.currentUser.canRead('suppliers')) {
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'suppliers',
        child: const Scaffold(body: Center(child: Text("عذراً، لا تملك صلاحية الوصول للموردين", style: TextStyle(fontWeight: FontWeight.bold)))),
      );
    }

    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'suppliers',
      floatingActionButton: widget.currentUser.canCreate('suppliers') ? FloatingActionButton.extended(
        onPressed: () => SupplierDialogs.showAddSupplierDialog(context: context, cafeId: _cafeId, managerId: _managerId),
        backgroundColor: Colors.orange[800],
        icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
        label: const Text("إضافة مورد", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ) : null,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('suppliers').where('cafeId', isEqualTo: _cafeId).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          
          final allDocs = snap.data!.docs.where((d) => (d.data() as Map)['parentId'] == _managerId).toList();
          
          var filteredDocs = allDocs.where((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final name = d['name'].toString().toLowerCase();
            final matchesSearch = name.contains(_searchQuery.toLowerCase());
            
            double bal = (d['totalBalance'] ?? 0.0).toDouble();
            bool matchesStatus = true;
            if (_activeFilter == "مديونون") matchesStatus = bal > 0;
            if (_activeFilter == "مسبق") matchesStatus = bal < 0;
            if (_activeFilter == "خالص") matchesStatus = bal == 0;
            
            return matchesSearch && matchesStatus;
          }).toList();

          if (_sortBy == "الأعلى ديناً") {
            filteredDocs.sort((a, b) => ((b.data() as Map)['totalBalance'] ?? 0.0).abs().compareTo(((a.data() as Map)['totalBalance'] ?? 0.0).abs()));
          } else {
            filteredDocs.sort((a, b) => (a.data() as Map)['name'].toString().compareTo((b.data() as Map)['name'].toString()));
          }

          return Column(
            children: [
              _buildStatDashboard(primaryColor, allDocs),
              _buildSearchAndSortBar(filteredDocs),
              _buildFilterChips(allDocs),
              _buildCustomTabBar(primaryColor),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: filteredDocs.length,
                      itemBuilder: (context, i) => _buildSupplierCard(filteredDocs[i], primaryColor),
                    ),
                    _PurchasesSimpleList(searchQuery: _searchQuery, managerId: _managerId, currentUser: widget.currentUser),
                  ],
                ),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildStatDashboard(Color primary, List<DocumentSnapshot> docs) {
    double totalDebt = 0, totalPrepaid = 0, totalPaid = 0;
    for (var d in docs) {
      double bal = ((d.data() as Map)['totalBalance'] ?? 0.0).toDouble();
      if (bal > 0) totalDebt += bal; else totalPrepaid += bal.abs();
      totalPaid += ((d.data() as Map)['totalPaid'] ?? 0.0).toDouble();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 25),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primary, primary.withBlue(100)]),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(35)),
        boxShadow: [BoxShadow(color: primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _statCard("إجمالي الديون", "${totalDebt.toStringAsFixed(1)} ₪", Icons.account_balance_wallet, Colors.red[100]!),
              const SizedBox(width: 10),
              _statCard("دفعات مسبقة (+)", "${totalPrepaid.toStringAsFixed(1)} ₪", Icons.stars_rounded, Colors.greenAccent),
              const SizedBox(width: 10),
              _statCard("إجمالي المدفوع", "${totalPaid.toStringAsFixed(1)} ₪", Icons.check_circle_outline, Colors.blue[100]!),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              _quickActionBtn(Icons.add_shopping_cart, "تسجيل فاتورة", Colors.orange[400]!, () => SupplierDialogs.showAddPurchaseDialog(context: context, currentUser: widget.currentUser, cafeId: _cafeId, managerId: _managerId)),
              const SizedBox(width: 10),
              _quickActionBtn(Icons.person_add_alt_1, "مورد جديد", Colors.blue[400]!, () => SupplierDialogs.showAddSupplierDialog(context: context, cafeId: _cafeId, managerId: _managerId)),
            ],
          )
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white24)),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          FittedBox(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 9)),
        ],
      ),
    ),
  );

  Widget _quickActionBtn(IconData icon, String label, Color color, VoidCallback onTap) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    ),
  );

  Widget _buildSearchAndSortBar(List<DocumentSnapshot> currentDocs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: "بحث عن مورد...",
                prefixIcon: const Icon(Icons.search, color: Colors.orange),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _iconToolBtn(Icons.file_download_outlined, () => _downloadSupplierReport(currentDocs)),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            icon: _iconToolBtn(Icons.sort_rounded, null),
            onSelected: (v) => setState(() => _sortBy = v),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: "الأعلى ديناً", child: Text("الأعلى ديناً")),
              const PopupMenuItem(value: "الاسم", child: Text("حسب الاسم")),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconToolBtn(IconData icon, VoidCallback? onTap) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
    child: IconButton(icon: Icon(icon, color: Colors.orange[800]), onPressed: onTap),
  );

  Widget _buildFilterChips(List<DocumentSnapshot> all) {
    int countDebtors = 0, countPrepaid = 0, countSettled = 0;
    for (var d in all) {
      double bal = ((d.data() as Map)['totalBalance'] ?? 0.0).toDouble();
      if (bal > 0) countDebtors++; 
      else if (bal < 0) countPrepaid++;
      else countSettled++;
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _filterChip("الكل", all.length),
          _filterChip("مديونون", countDebtors, color: Colors.red),
          _filterChip("مسبق", countPrepaid, color: Colors.green),
          _filterChip("خالص", countSettled, color: Colors.blueGrey),
        ],
      ),
    );
  }

  Widget _filterChip(String label, int count, {Color? color}) {
    bool isSelected = _activeFilter == label;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text("$label ($count)", style: TextStyle(color: isSelected ? Colors.white : (color ?? Colors.grey[700]), fontWeight: FontWeight.bold, fontSize: 11)),
        selected: isSelected,
        selectedColor: color ?? Colors.orange[800],
        onSelected: (v) => setState(() => _activeFilter = label),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        showCheckmark: false,
      ),
    );
  }

  Widget _buildCustomTabBar(Color primary) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
    child: TabBar(
      controller: _tabController,
      indicator: BoxDecoration(color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: primary, width: 1.5)),
      labelColor: primary, unselectedLabelColor: Colors.grey,
      indicatorSize: TabBarIndicatorSize.tab,
      tabs: const [Tab(text: "قائمة الموردين"), Tab(text: "سجل الفواتير")],
    ),
  );

  Widget _buildSupplierCard(DocumentSnapshot doc, Color primary) {
    final d = doc.data() as Map<String, dynamic>;
    double bal = (d['totalBalance'] ?? 0.0).toDouble();
    bool isExpanded = _expandedSupplierId == doc.id;
    bool isPrepaid = bal < 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isExpanded ? primary : Colors.grey.shade200)),
      child: InkWell(
        onTap: () => setState(() => _expandedSupplierId = isExpanded ? null : doc.id),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: [
                  CircleAvatar(backgroundColor: isPrepaid ? Colors.green[50] : (bal == 0 ? Colors.grey[100] : Colors.red[50]), radius: 25, child: Icon(Icons.business_center, color: isPrepaid ? Colors.green : (bal == 0 ? Colors.grey : Colors.red))),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(d['company'] ?? "شركة عامة", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("${bal.abs().toStringAsFixed(1)} ₪", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: isPrepaid ? Colors.green[700] : (bal == 0 ? Colors.grey[700] : Colors.red[700]))),
                      Text(isPrepaid ? "دفعة مسبقة (+)" : (bal == 0 ? "خالص" : "دين عليه"), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey),
                ],
              ),
            ),
            if (isExpanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _cardAction(Icons.add_shopping_cart, "فاتورة", Colors.orange[800]!, () => SupplierDialogs.showAddPurchaseDialog(context: context, currentUser: widget.currentUser, cafeId: _cafeId, managerId: _managerId, initialSupplierId: doc.id)),
                    _cardAction(Icons.payment, "سداد", Colors.green[700]!, () => SupplierDialogs.showPaySupplierDialog(context: context, sId: doc.id, sName: d['name'], currentUser: widget.currentUser, cafeId: _cafeId, managerId: _managerId)),
                    _cardAction(Icons.history_edu, "سجل", Colors.blue[700]!, () => SupplierDialogs.showSupplierHistory(context: context, sId: doc.id, sName: d['name'], openingBalance: (d['openingBalance'] ?? 0.0).toDouble())),
                    _cardAction(Icons.call, "واتساب", Colors.green[800]!, () => _sendSupplierWhatsApp(d)),
                    _cardAction(Icons.delete_forever, "حذف", Colors.red[900]!, () => _confirmDeleteSupplier(doc.id, d['name'])),
                  ],
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  void _confirmDeleteSupplier(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("تأكيد الحذف", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text("هل أنت متأكد من حذف المورد ($name)؟\nسيتم حذف كافة سجلاته نهائياً."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("إلغاء", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(ctx);
              await SupplierService.deleteSupplier(id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ تم حذف المورد بنجاح")));
              }
            },
            child: const Text("حذف نهائي", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _cardAction(IconData icon, String label, Color color, VoidCallback onTap) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    ),
  );

  void _sendSupplierWhatsApp(Map d) async {
    final phone = d['phone']?.toString() ?? "";
    if (phone.isEmpty) return;
    double bal = (d['totalBalance'] ?? 0.0).toDouble();
    String msg = "مرحباً ${d['name']}\nبخصوص حسابنا طرفكم، الرصيد الحالي هو: ${bal.abs().toStringAsFixed(1)} ₪ ${bal > 0 ? '(علينا لكم)' : '(لنا طرفكم - دفعة مسبقة)'}";
    final url = "whatsapp://send?phone=+972$phone&text=${Uri.encodeComponent(msg)}";
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url));
  }
}

class _PurchasesSimpleList extends StatelessWidget {
  final String searchQuery;
  final String managerId;
  final User currentUser;

  const _PurchasesSimpleList({required this.searchQuery, required this.managerId, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('purchases').where('cafeId', isEqualTo: currentUser.cafeId).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['parentId'] != managerId) return false;
          if (searchQuery.isNotEmpty) {
            final name = (data['supplierName'] ?? "").toString().toLowerCase();
            if (!name.contains(searchQuery.toLowerCase())) return false;
          }
          return true;
        }).toList();

        docs.sort((a, b) => ((b.data() as Map)['date'] as Timestamp? ?? Timestamp.now()).compareTo((a.data() as Map)['date'] as Timestamp? ?? Timestamp.now()));

        if (docs.isEmpty) return const Center(child: Text("لا توجد فواتير مسجلة", style: TextStyle(color: Colors.grey)));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: ExpansionTile(
                leading: const CircleAvatar(backgroundColor: Colors.orangeAccent, child: Icon(Icons.receipt_long, color: Colors.white, size: 20)),
                title: Text(data['productName'] ?? "فاتورة مورد", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text("${data['supplierName']} | ${intl.DateFormat('yyyy/MM/dd').format(date)}", style: const TextStyle(fontSize: 11)),
                trailing: Text("${data['amount']} ₪", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      children: [
                        _detailItem("طريقة الدفع", data['method'] ?? "كاش"),
                        _detailItem("المبلغ المسدد", "${data['paidAmount'] ?? data['amount']} ₪", isGreen: true),
                        if (data['remaining'] != null && data['remaining'] > 0)
                          _detailItem("المبلغ المتبقي (دين)", "${data['remaining']} ₪", isRed: true),
                        _detailItem("الموظف", data['processedBy'] ?? "-"),
                      ],
                    ),
                  )
                ],
              ),
            );
          },
        );
      }
    );
  }

  Widget _detailItem(String l, String v, {bool isRed = false, bool isGreen = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      Text(v, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isRed ? Colors.red : (isGreen ? Colors.green : Colors.black87))),
    ]),
  );
}
