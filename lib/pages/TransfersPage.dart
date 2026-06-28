import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../services/transfer_service.dart';
import '../widgets/dashboard_dialogs.dart';
import 'user_model.dart';
import 'MainLayout.dart';

class TransfersPage extends StatefulWidget {
  final User currentUser;
  const TransfersPage({super.key, required this.currentUser});

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  Stream<QuerySnapshot>? _paymentsStream;
  String? _activeCafeId;
  List<String> _paymentMethods = ["كاش", "شبكة"];
  String _currencySymbol = "₪";
  StreamSubscription? _settingsSub;
  StreamSubscription? _customersSub;
  List<Map<String, String>> _existingCustomers = [];
  
  String _selectedMethod = "الكل"; 
  String _selectedStatus = "الكل"; 
  String _sortBy = "الأحدث"; 

  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _initCafeData();
  }

  Future<void> _initCafeData() async {
    String cid = widget.currentUser.cafeId;
    if (cid.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      cid = prefs.getString('cafe_id') ?? "";
    }
    if (mounted) {
      setState(() => _activeCafeId = cid);
      if (cid.isNotEmpty) {
        final managerId = widget.currentUser.parentId ?? widget.currentUser.id;
        _initStream(cid, managerId);
        _listenToCafeSettings(cid);
        _loadExistingCustomers(cid, managerId);
      }
    }
  }

  void _onSearchChanged(String v) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _searchQuery = v);
    });
  }

  void _loadExistingCustomers(String cid, String managerId) {
    _customersSub?.cancel();
    _customersSub = FirebaseFirestore.instance
        .collection('debts')
        .where('cafeId', isEqualTo: cid)
        .where('parentId', isEqualTo: managerId) 
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _existingCustomers = snapshot.docs.map((doc) {
              final d = doc.data();
              double net = (d['totalDebt'] ?? 0.0) - (d['totalPaid'] ?? 0.0) - (d['initialBalance'] ?? 0.0);
              return {
                'id': doc.id,
                'name': d['customer']?.toString() ?? "",
                'phone': d['phone']?.toString() ?? "",
                'debt': net.toStringAsFixed(1),
                'no': (d['debtNo'] ?? "").toString(),
              };
          }).toList();
        });
      }
    });
  }

  void _listenToCafeSettings(String cid) {
    _settingsSub = FirebaseFirestore.instance.collection('cafes').doc(cid).snapshots().listen((doc) {
      if (doc.exists && mounted) {
        setState(() {
          _paymentMethods = List<String>.from(doc.data()?['payment_methods'] ?? ["كاش", "شبكة"]);
          _currencySymbol = doc.data()?['currency_symbol'] ?? "₪";
        });
      }
    });
  }

  void _initStream(String cid, String managerId) {
    setState(() {
      Query query = FirebaseFirestore.instance
          .collection('payments')
          .where('cafeId', isEqualTo: cid)
          .where('parentId', isEqualTo: managerId);

      bool isAdmin = widget.currentUser.role == UserRole.admin || 
                     widget.currentUser.role == UserRole.super_admin || 
                     widget.currentUser.role == UserRole.manager;
      
      if (!isAdmin) {
        query = query.where('userId', isEqualTo: widget.currentUser.id);
      }

      _paymentsStream = query.snapshots();
    });
  }

  @override
  void dispose() {
    _settingsSub?.cancel(); _customersSub?.cancel();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  String _getDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final checkDate = DateTime(date.year, date.month, date.day);

    if (checkDate == today) return "اليوم";
    if (checkDate == yesterday) return "أمس";
    return DateFormat('yyyy/MM/dd').format(date);
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: (_startDate != null && _endDate != null) 
          ? DateTimeRange(start: _startDate!, end: _endDate!) 
          : null,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end.add(const Duration(hours: 23, minutes: 59, seconds: 59));
      });
    }
  }

  void _shareTransfer(Map d, {bool isWhatsApp = false}) async {
    final date = (d['paid_at'] as Timestamp?)?.toDate();
    final dateStr = date != null ? DateFormat('yyyy/MM/dd hh:mm a').format(date) : "غير محدد";
    final String cName = d['customer_name'] ?? "غير محدد";
    final String pName = d['payer_name'] ?? cName;
    
    final String receipt = """
📄 *إيصال*
----------------------------
👤 *المحول:* $pName
👥 *لحساب:* $cName
💰 *المبلغ:* ${d['total_amount']} $_currencySymbol
💳 *الطريقة:* ${d['payment_method']}
📅 *التاريخ:* $dateStr
✍️ *بواسطة:* ${d['processed_by']}
${(d['note'] ?? "").toString().isNotEmpty ? '📝 *ملاحظة:* ${d['note']}' : ''}
----------------------------
""";

    if (isWhatsApp) {
      String phone = d['customer_phone'] ?? "";
      if (phone.isNotEmpty) {
        phone = phone.replaceAll(RegExp(r'[^0-9]'), '');
        if (!phone.startsWith('97') && phone.length >= 9) {
          phone = "972${phone.startsWith('0') ? phone.substring(1) : phone}";
        }
        final url = "https://wa.me/$phone?text=${Uri.encodeComponent(receipt)}";
        if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        } else {
          if (mounted) Share.share(receipt);
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ لا يوجد رقم هاتف مسجل")));
        Share.share(receipt);
      }
    } else {
      Share.share(receipt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final managerId = widget.currentUser.parentId ?? widget.currentUser.id;
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 700;

    if (!widget.currentUser.canRead('transfers')) {
      return MainLayout(currentUser: widget.currentUser, currentPage: 'transfers', child: const Scaffold(body: Center(child: Text("عذراً، لا تملك صلاحية لعرض صفحة الحوالات", style: TextStyle(fontWeight: FontWeight.bold)))));
    }

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'transfers',
      child: Scaffold(
        backgroundColor: const Color(0xFFFDFBFA),
        body: _activeCafeId == null ? const Center(child: CircularProgressIndicator()) : Column(
          children: [
            _buildHeader(isMobile),
            StreamBuilder<QuerySnapshot>(
              stream: _paymentsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Expanded(child: Center(child: Text("خطأ في الاتصال")));
                if (!snapshot.hasData) return const Expanded(child: Center(child: CircularProgressIndicator()));
                
                List<QueryDocumentSnapshot> allDocs = snapshot.data!.docs;
                final baseFiltered = allDocs.where((d) {
                  final data = d.data() as Map;
                  final q = _searchQuery.toLowerCase();
                  final nameMatch = (data['customer_name'] ?? "").toString().toLowerCase().contains(q);
                  final payerMatch = (data['payer_name'] ?? "").toString().toLowerCase().contains(q);
                  final noteMatch = (data['note'] ?? "").toString().toLowerCase().contains(q);
                  final date = (data['paid_at'] as Timestamp?)?.toDate();
                  bool dateMatch = true;
                  if (_startDate != null && _endDate != null && date != null) {
                    dateMatch = date.isAfter(_startDate!) && date.isBefore(_endDate!);
                  }
                  return (nameMatch || payerMatch || noteMatch) && dateMatch;
                }).toList();

                Map<String, double> methodValues = {};
                Map<String, double> statusValues = {"الكل": 0, "غير واصل": 0, "واصل": 0, "الحوالات المعلقة": 0};
                double totalAllForStatus = 0;
                final visibleMethods = _paymentMethods.where((m) => !m.contains("ديون")).toList();

                for (var d in baseFiltered) {
                  final data = d.data() as Map;
                  final isPending = data['is_pending'] ?? false;
                  final isReceived = data['is_received'] ?? false;
                  final method = data['payment_method'] ?? "أخرى";
                  final amt = (data['total_amount'] ?? 0.0).toDouble();

                  if (isPending) {
                    statusValues["الحوالات المعلقة"] = (statusValues["الحوالات المعلقة"] ?? 0.0) + amt;
                  } else {
                    statusValues["الكل"] = (statusValues["الكل"] ?? 0.0) + amt;
                    if (isReceived) statusValues["واصل"] = (statusValues["واصل"] ?? 0.0) + amt;
                    else statusValues["غير واصل"] = (statusValues["غير واصل"] ?? 0.0) + amt;
                  }

                  bool matchesStatus = false;
                  if (_selectedStatus == "الكل") matchesStatus = !isPending;
                  else if (_selectedStatus == "واصل") matchesStatus = isReceived && !isPending;
                  else if (_selectedStatus == "غير واصل") matchesStatus = !isReceived && !isPending;
                  else if (_selectedStatus == "معلقة") matchesStatus = isPending;

                  if (matchesStatus) {
                    methodValues[method] = (methodValues[method] ?? 0.0) + amt;
                    totalAllForStatus += amt;
                  }
                }

                final finalDocs = baseFiltered.where((d) {
                  final data = d.data() as Map;
                  final method = data['payment_method'] ?? "أخرى";
                  final isPending = data['is_pending'] ?? false;
                  final isReceived = data['is_received'] ?? false;
                  bool mMatch = _selectedMethod == "الكل" || _selectedMethod == method;
                  bool sMatch = false;
                  if (_selectedStatus == "الكل") sMatch = !isPending;
                  else if (_selectedStatus == "واصل") sMatch = isReceived && !isPending;
                  else if (_selectedStatus == "غير واصل") sMatch = !isReceived && !isPending;
                  else if (_selectedStatus == "معلقة") sMatch = isPending;
                  return mMatch && sMatch;
                }).toList();

                finalDocs.sort((a, b) {
                  final d1 = a.data() as Map; final d2 = b.data() as Map;
                  final t1 = (d1['paid_at'] as Timestamp?)?.toDate() ?? DateTime(2000);
                  final t2 = (d2['paid_at'] as Timestamp?)?.toDate() ?? DateTime(2000);
                  if (_sortBy == "الأقدم") return t1.compareTo(t2);
                  if (_sortBy == "الأعلى مبلغاً") return (d2['total_amount'] ?? 0).compareTo(d1['total_amount'] ?? 0);
                  return t2.compareTo(t1); 
                });

                Map<String, List<QueryDocumentSnapshot>> groups = {};
                for (var doc in finalDocs) {
                  final date = ((doc.data() as Map)['paid_at'] as Timestamp?)?.toDate() ?? DateTime.now();
                  groups.putIfAbsent(_getDateHeader(date), () => []).add(doc);
                }

                return Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async => setState(() {}),
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: _buildSummarySection(finalDocs, isMobile)),
                        SliverToBoxAdapter(child: _buildDualFilters(visibleMethods, methodValues, totalAllForStatus, statusValues)),
                        if (finalDocs.isEmpty) const SliverFillRemaining(child: Center(child: Text("لا توجد نتائج"))),
                        ...groups.keys.map((header) => SliverMainAxisGroup(
                          slivers: [
                            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(24, 20, 24, 10), child: Text(header, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF634231))))),
                            SliverPadding(
                              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24),
                              sliver: SliverList(delegate: SliverChildBuilderDelegate((context, i) => _buildTransferItem(groups[header]![i], isMobile), childCount: groups[header]!.length)),
                            ),
                          ],
                        )),
                        const SliverToBoxAdapter(child: SizedBox(height: 100)),
                      ],
                    ),
                  ),
                );
              }
            ),
          ],
        ),
        floatingActionButton: (widget.currentUser.canCreate('transfers')) 
          ? FloatingActionButton.extended(
              onPressed: _activeCafeId == null ? null : () => _showNewTransferMenu(managerId),
              label: const Text("عملية جديدة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              icon: const Icon(Icons.add, color: Colors.white),
              backgroundColor: _activeCafeId == null ? Colors.grey : const Color(0xFF634231),
            )
          : null,
      ),
    );
  }

  void _showNewTransferMenu(String managerId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("اختر نوع الحوالة", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF634231))),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.add_shopping_cart, color: Colors.blue)),
                title: const Text("تسجيل مبيعات يدوية", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("بيع صنف أو خدمة وإضافتها للديون أو كاش"),
                onTap: () {
                  Navigator.pop(ctx);
                  DashboardDialogs.showManualSaleDialog(context: context, currentUser: widget.currentUser, paymentMethods: _paymentMethods, customerSuggestions: _existingCustomers, managerId: managerId);
                },
              ),
              const Divider(),
              ListTile(
                leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.brown[50], borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.payments_outlined, color: Color(0xFF634231))),
                title: const Text("تسجيل سداد دين", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("استلام مبلغ من زبون لتسديد مديونيته"),
                onTap: () {
                  Navigator.pop(ctx);
                  DashboardDialogs.showAddTransferDialog(context: context, currentUser: widget.currentUser, paymentMethods: _paymentMethods, customerSuggestions: _existingCustomers, managerId: managerId);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDualFilters(List<String> visibleMethods, Map<String, double> methodVals, double totalMethods, Map<String, double> statusVals) {
    return Column(
      children: [
        SizedBox(
          height: 85,
          child: ListView(
            scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 5), reverse: true,
            children: [
              _buildChip("الكل", totalMethods, _selectedMethod == "الكل", () => setState(() => _selectedMethod = "الكل")),
              ...visibleMethods.map((m) => _buildChip(m, methodVals[m] ?? 0.0, _selectedMethod == m, () => setState(() => _selectedMethod = m))),
            ],
          ),
        ),
        SizedBox(
          height: 85,
          child: ListView(
            scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 5), reverse: true,
            children: [
              _buildChip("الكل", statusVals["الكل"] ?? 0.0, _selectedStatus == "الكل", () => setState(() => _selectedStatus = "الكل")),
              _buildChip("غير واصل", statusVals["غير واصل"] ?? 0.0, _selectedStatus == "غير واصل", () => setState(() => _selectedStatus = "غير واصل")),
              _buildChip("واصل", statusVals["واصل"] ?? 0.0, _selectedStatus == "واصل", () => setState(() => _selectedStatus = "واصل")),
              _buildChip("الحوالات المعلقة", statusVals["الحوالات المعلقة"] ?? 0.0, _selectedStatus == "معلقة", () => setState(() => _selectedStatus = "معلقة")),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChip(String label, double amount, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(color: isSelected ? const Color(0xFF634231) : Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: isSelected ? const Color(0xFF634231) : Colors.grey[300]!)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 2),
          Text("${amount.toStringAsFixed(1)} $_currencySymbol", style: TextStyle(color: isSelected ? Colors.white70 : Colors.brown, fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _buildSummarySection(List<QueryDocumentSnapshot> docs, bool isMobile) {
    double t = 0; double r = 0; double p = 0;
    for (var d in docs) {
      final data = d.data() as Map;
      final amt = (data['total_amount'] ?? 0.0).toDouble();
      t += amt;
      if (data['is_received'] ?? false) r += amt; else p += amt;
    }
    return Padding(padding: const EdgeInsets.all(16), child: Row(children: [
      Expanded(child: _statCard("الإجمالي", t, docs.length, Colors.brown, isMobile)),
      const SizedBox(width: 8),
      Expanded(child: _statCard("واصلة", r, -1, Colors.green, isMobile)),
      const SizedBox(width: 8),
      Expanded(child: _statCard("متبقي", p, -1, Colors.red, isMobile)),
    ]));
  }

  Widget _statCard(String t, double v, int c, Color clr, bool isMobile) {
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 5)]), child: Column(children: [
      Text(t, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.bold)),
      FittedBox(child: Text("${v.toStringAsFixed(1)} $_currencySymbol", style: TextStyle(fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.w900, color: clr))),
      if (c != -1) Text("$c عملية", style: const TextStyle(fontSize: 9, color: Colors.grey)),
    ]));
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, isMobile ? 40 : 60, 24, 15),
      color: Colors.white,
      child: Row(children: [
        Expanded(child: TextField(controller: _searchController, onChanged: (v) => _onSearchChanged(v), textAlign: TextAlign.right, decoration: InputDecoration(hintText: "بحث...", suffixIcon: (_searchQuery.isNotEmpty || _startDate != null) ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { setState(() { _searchQuery = ""; _startDate = null; _endDate = null; _searchController.clear(); }); }) : const Icon(Icons.search), filled: true, fillColor: const Color(0xFFF8F8F8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
        IconButton(onPressed: _selectDateRange, icon: Icon(Icons.calendar_month, color: _startDate != null ? const Color(0xFF634231) : Colors.grey)),
        PopupMenuButton<String>(icon: const Icon(Icons.sort, color: Colors.brown), onSelected: (v) => setState(() => _sortBy = v), itemBuilder: (ctx) => [const PopupMenuItem(value: "الأحدث", child: Text("الأحدث")), const PopupMenuItem(value: "الأقدم", child: Text("الأقدم")), const PopupMenuItem(value: "الأعلى مبلغاً", child: Text("الأعلى مبلغاً"))]),
      ]),
    );
  }

  Widget _buildTransferItem(QueryDocumentSnapshot doc, bool isMobile) {
    final managerId = widget.currentUser.parentId ?? widget.currentUser.id;
    final d = doc.data() as Map;
    final bool r = d['is_received'] ?? false;
    final bool isP = d['is_pending'] ?? false;
    final bool isSale = !(d['is_debt_payment'] ?? true);
    final date = (d['paid_at'] as Timestamp?)?.toDate();
    final String n = d['note'] ?? "";
    final String customerName = d['customer_name'] ?? "زبون عام";

    return Dismissible(
      key: Key(doc.id), 
      direction: widget.currentUser.canDelete('transfers') ? DismissDirection.startToEnd : DismissDirection.none,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), decoration: BoxDecoration(color: Colors.red[100], borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.delete, color: Colors.red)),
      confirmDismiss: (dir) async => await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text("تأكيد الحذف"), content: const Text("هل تريد حذف هذه العملية؟"), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("إلغاء")), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("حذف", style: TextStyle(color: Colors.red)))])) ,
      onDismissed: (_) async => await TransferService.deleteTransfer(doc: doc, currentUser: widget.currentUser, activeCafeId: _activeCafeId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10)]),
        child: Row(children: [
            Expanded(
              child: InkWell(
                onTap: () => (widget.currentUser.canUpdate('transfers')) ? (isSale ? DashboardDialogs.showManualSaleDialog(context: context, currentUser: widget.currentUser, paymentMethods: _paymentMethods, customerSuggestions: _existingCustomers, managerId: managerId, editDoc: doc) : DashboardDialogs.showAddTransferDialog(context: context, currentUser: widget.currentUser, paymentMethods: _paymentMethods, customerSuggestions: _existingCustomers, managerId: managerId, editDoc: doc)) : null,
                borderRadius: const BorderRadius.only(topRight: Radius.circular(20), bottomRight: Radius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(
                      children: [
                        Text(customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(width: 8),
                        StatusChip(isSale: isSale),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text("${d['payment_method']}", style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                    if (n.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text("📝 $n", style: const TextStyle(color: Colors.brown, fontSize: 10, fontStyle: FontStyle.italic))),
                    Text(date != null ? DateFormat('hh:mm a').format(date) : '', style: TextStyle(color: Colors.grey[400], fontSize: 10)),
                  ]),
                ),
              ),
            ),
            IconButton(onPressed: () => _shareTransfer(d, isWhatsApp: true), icon: const Icon(Icons.send_to_mobile, size: 18, color: Colors.green)),
            IconButton(
              onPressed: (widget.currentUser.canUpdate('transfers')) ? () {
                if (isP) {
                  // إذا كانت معلقة: إظهار نافذة التأكيد والمعالجة
                  if (isSale) {
                    DashboardDialogs.showManualSaleDialog(context: context, currentUser: widget.currentUser, paymentMethods: _paymentMethods, customerSuggestions: _existingCustomers, managerId: managerId, editDoc: doc);
                  } else {
                    DashboardDialogs.showAddTransferDialog(context: context, currentUser: widget.currentUser, paymentMethods: _paymentMethods, customerSuggestions: _existingCustomers, managerId: managerId, editDoc: doc);
                  }
                } else {
                  // إذا كانت مؤكدة: إرجاعها للمعلقة مباشرة ومعالجة الرصيد
                  TransferService.performSave(
                    context: context,
                    editDoc: doc,
                    currentUser: widget.currentUser,
                    customerName: d['customer_name'] ?? "زبون عام",
                    payerName: d['payer_name'],
                    phone: d['customer_phone'] ?? "",
                    amt: (d['total_amount'] ?? 0.0).toDouble(),
                    method: d['payment_method'] ?? "كاش",
                    cafeId: _activeCafeId!,
                    isDebtPayment: !isSale,
                    isPending: true,
                    note: d['note'],
                    customDate: (d['paid_at'] as Timestamp?)?.toDate(),
                    table: d['table'] ?? 'حوالة',
                  );
                }
              } : null,
              icon: Icon(
                isP ? Icons.assignment_turned_in : Icons.assignment_return,
                size: 24,
                color: isP ? Colors.orange : Colors.blueGrey,
              ),
              tooltip: isP ? "تأكيد ومعالجة" : "إرجاع للمعلقة/تعديل",
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: (widget.currentUser.canUpdate('transfers')) ? () {
                HapticFeedback.lightImpact(); 
                doc.reference.update({'is_received': !r});
              } : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("${d['total_amount']} $_currencySymbol", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: isSale ? Colors.blue[900] : const Color(0xFF634231))),
                    const SizedBox(height: 5),
                    Icon(
                      isP ? Icons.report_problem_rounded : (r ? Icons.check_circle : Icons.hourglass_empty), 
                      color: isP ? Colors.orange : (r ? Colors.green : Colors.grey), 
                      size: 32
                    ),
                  ],
                ),
              ),
            ),
          ]),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final bool isSale;
  const StatusChip({super.key, required this.isSale});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: isSale ? Colors.blue[50] : Colors.brown[50], borderRadius: BorderRadius.circular(6)),
      child: Text(isSale ? "مبيعات" : "سداد", style: TextStyle(fontSize: 9, color: isSale ? Colors.blue[800] : Colors.brown, fontWeight: FontWeight.bold)),
    );
  }
}
