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

  Future<void> _exportTransfers(List<QueryDocumentSnapshot> docs) async {
    if (!widget.currentUser.canViewReports) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ لا تملك صلاحية تصدير التقارير")));
      return;
    }
    final List<QueryDocumentSnapshot> sortedDocs = List.from(docs);
    sortedDocs.sort((a, b) {
      final t1 = ((a.data() as Map)['paid_at'] as Timestamp?)?.toDate() ?? DateTime(2000);
      final t2 = ((b.data() as Map)['paid_at'] as Timestamp?)?.toDate() ?? DateTime(2000);
      return t1.compareTo(t2);
    });

    String csv = '\uFEFFالمحول,صاحب الحساب,المبلغ,الطريقة,التاريخ,بواسطة,الملاحظات\n';
    for (var doc in sortedDocs) {
      final d = doc.data() as Map;
      final date = (d['paid_at'] as Timestamp?)?.toDate();
      final pName = d['payer_name'] ?? d['customer_name'] ?? "زبون عام";
      final cName = d['customer_name'] ?? "غير محدد";
      csv += "$pName,$cName,${d['total_amount']},${d['payment_method']},${date != null ? DateFormat('yyyy/MM/dd HH:mm').format(date) : ''},${d['processed_by']},${d['note'] ?? ''}\n";
    }
    try {
      if (kIsWeb) {
        final url = "data:text/csv;charset=utf-8,${Uri.encodeComponent(csv)}";
        await launchUrl(Uri.parse(url));
      } else {
        final directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        final file = File("${directory.path}/Transfers_Export.csv");
        await file.writeAsString(csv);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم التصدير بنجاح"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ خطأ: $e"), backgroundColor: Colors.red));
    }
  }

  void _shareTransfer(Map d, {bool isWhatsApp = false}) async {
    final date = (d['paid_at'] as Timestamp?)?.toDate();
    final dateStr = date != null ? DateFormat('yyyy/MM/dd hh:mm a').format(date) : "غير محدد";
    final String cName = d['customer_name'] ?? "غير محدد";
    final String pName = d['payer_name'] ?? cName;
    
    final String receipt = """
📄 *إيصال سداد*
----------------------------
👤 *المحول:* $pName
👥 *لحساب:* $cName
💰 *المبلغ:* ${d['total_amount']} $_currencySymbol
💳 *الطريقة:* ${d['payment_method']}
📅 *التاريخ:* $dateStr
✍️ *بواسطة:* ${d['processed_by']}
${(d['note'] ?? "").toString().isNotEmpty ? '📝 *ملاحظة:* ${d['note']}' : ''}
----------------------------
شكراً لتعاملكم معنا ✨
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
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'transfers',
        child: const Scaffold(
          body: Center(
            child: Text("عذراً، لا تملك صلاحية لعرض صفحة الحوالات", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'transfers',
      child: Scaffold(
        backgroundColor: const Color(0xFFFDFBFA),
        body: _activeCafeId == null ? const Center(child: CircularProgressIndicator()) : Column(
          children: [
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
                  final phoneMatch = (data['customer_phone'] ?? "").toString().contains(q);
                  final noteMatch = (data['note'] ?? "").toString().toLowerCase().contains(q);
                  final date = (data['paid_at'] as Timestamp?)?.toDate();
                  bool dateMatch = true;
                  if (_startDate != null && _endDate != null && date != null) {
                    dateMatch = date.isAfter(_startDate!) && date.isBefore(_endDate!);
                  }
                  return (nameMatch || payerMatch || phoneMatch || noteMatch) && dateMatch;
                }).toList();

                Map<String, double> methodValues = {};
                double totalAllForStatus = 0;

                final visibleMethods = _paymentMethods.where((m) => !m.contains("ديون")).toList();

                for (var d in baseFiltered) {
                  final data = d.data() as Map;
                  final isReceived = data['is_received'] ?? false;
                  final isPending = data['is_pending'] ?? false;
                  final method = data['payment_method'] ?? "أخرى";
                  final amt = (data['total_amount'] ?? 0.0).toDouble();

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

                double statusAllVal = 0;
                double statusReceivedVal = 0;
                double statusPendingVal = 0;
                double statusSuspendedVal = 0;

                for (var d in baseFiltered) {
                  final data = d.data() as Map;
                  final method = data['payment_method'] ?? "أخرى";
                  final isReceived = data['is_received'] ?? false;
                  final isPending = data['is_pending'] ?? false;
                  final amt = (data['total_amount'] ?? 0.0).toDouble();

                  if (_selectedMethod == "الكل" || _selectedMethod == method) {
                    if (!isPending) {
                      statusAllVal += amt;
                      if (isReceived) statusReceivedVal += amt; else statusPendingVal += amt;
                    } else {
                      statusSuspendedVal += amt;
                    }
                  }
                }

                final finalDocs = baseFiltered.where((d) {
                  final data = d.data() as Map;
                  final method = data['payment_method'] ?? "أخرى";
                  final isReceived = data['is_received'] ?? false;
                  final isPending = data['is_pending'] ?? false;
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
                  child: Column(
                    children: [
                      _buildHeader(finalDocs, isMobile),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async => setState(() {}),
                          child: CustomScrollView(
                            slivers: [
                              SliverToBoxAdapter(child: _buildSummarySection(finalDocs, isMobile)),
                              SliverToBoxAdapter(child: _buildDualFilters(visibleMethods, methodValues, totalAllForStatus, statusAllVal, statusReceivedVal, statusPendingVal, statusSuspendedVal)),
                              if (finalDocs.isEmpty) const SliverFillRemaining(child: Center(child: Text("لا توجد نتائج"))),
                              ...groups.keys.map((header) => SliverMainAxisGroup(
                                slivers: [
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
                                      child: Text(header, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF634231))),
                                    ),
                                  ),
                                  SliverPadding(
                                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24),
                                    sliver: SliverList(
                                      delegate: SliverChildBuilderDelegate(
                                        (context, i) => _buildTransferItem(groups[header]![i], isMobile),
                                        childCount: groups[header]!.length,
                                      ),
                                    ),
                                  ),
                                ],
                              )),
                              const SliverToBoxAdapter(child: SizedBox(height: 100)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
            ),
          ],
        ),
        floatingActionButton: (widget.currentUser.canCreate('transfers')) 
          ? FloatingActionButton.extended(
              onPressed: _activeCafeId == null ? null : () => DashboardDialogs.showAddTransferDialog(context: context, currentUser: widget.currentUser, paymentMethods: _paymentMethods, customerSuggestions: _existingCustomers, managerId: managerId),
              label: const Text("عملية جديدة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              icon: const Icon(Icons.add, color: Colors.white),
              backgroundColor: _activeCafeId == null ? Colors.grey : const Color(0xFF634231),
            )
          : null,
      ),
    );
  }

  Widget _buildDualFilters(List<String> visibleMethods, Map<String, double> methodVals, double totalMethods, double sAll, double sRec, double sPend, double sSusp) {
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
              _buildChip("الكل", sAll, _selectedStatus == "الكل", () => setState(() => _selectedStatus = "الكل")),
              _buildChip("الواصل", sRec, _selectedStatus == "واصل", () => setState(() => _selectedStatus = "واصل")),
              _buildChip("الغير واصل", sPend, _selectedStatus == "غير واصل", () => setState(() => _selectedStatus = "غير واصل")),
              _buildChip("المعلقة", sSusp, _selectedStatus == "معلقة", () => setState(() => _selectedStatus = "معلقة")),
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
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF634231) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isSelected ? const Color(0xFF634231) : Colors.grey[300]!)
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            Text("${amount.toStringAsFixed(1)} $_currencySymbol", style: TextStyle(color: isSelected ? Colors.white70 : Colors.brown, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummarySection(List<QueryDocumentSnapshot> docs, bool isMobile) {
    double t = 0; double r = 0; double p = 0;
    for (var d in docs) {
      final data = d.data() as Map;
      final amt = data['total_amount'] ?? 0.0;
      t += amt;
      if (data['is_received'] ?? false) r += amt; else p += amt;
    }
    return Padding(padding: const EdgeInsets.all(16), child: Row(children: [
      Expanded(child: _statCard("الإجمالي", t, docs.length, Colors.brown, isMobile)),
      const SizedBox(width: 8),
      Expanded(child: _statCard(_selectedStatus == "معلقة" ? "معلقة" : "واصلة", r, -1, Colors.green, isMobile)),
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

  Widget _buildHeader(List<QueryDocumentSnapshot> filteredDocs, bool isMobile) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, isMobile ? 40 : 60, 24, 15),
      color: Colors.white,
      child: Row(children: [
        Expanded(child: TextField(controller: _searchController, onChanged: (v) => _onSearchChanged(v), textAlign: TextAlign.right, decoration: InputDecoration(hintText: "بحث...", suffixIcon: (_searchQuery.isNotEmpty || _startDate != null) ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { setState(() { _searchQuery = ""; _startDate = null; _endDate = null; _searchController.clear(); }); }) : const Icon(Icons.search), filled: true, fillColor: const Color(0xFFF8F8F8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
        IconButton(onPressed: _selectDateRange, icon: Icon(Icons.calendar_month, color: _startDate != null ? const Color(0xFF634231) : Colors.grey)),
        PopupMenuButton<String>(icon: const Icon(Icons.sort, color: Colors.brown), onSelected: (v) => setState(() => _sortBy = v), itemBuilder: (ctx) => [const PopupMenuItem(value: "الأحدث", child: Text("الأحدث")), const PopupMenuItem(value: "الأقدم", child: Text("الأقدم")), const PopupMenuItem(value: "الأعلى مبلغاً", child: Text("الأعلى مبلغاً"))]),
        IconButton(onPressed: () => _exportTransfers(filteredDocs), icon: const Icon(Icons.download, color: Colors.blue)),
      ]),
    );
  }

  Widget _buildTransferItem(QueryDocumentSnapshot doc, bool isMobile) {
    final d = doc.data() as Map;
    final bool r = d['is_received'] ?? false;
    final bool isPending = d['is_pending'] ?? false;
    final date = (d['paid_at'] as Timestamp?)?.toDate();
    final String p = d['customer_phone'] ?? "";
    final String n = d['note'] ?? "";
    
    final String customerName = d['customer_name'] ?? "زبون عام";
    final String? payerName = d['payer_name'];
    final bool hasDifferentPayer = payerName != null && payerName.isNotEmpty && payerName != customerName;

    return Dismissible(
      key: Key(doc.id), 
      direction: widget.currentUser.canDelete('transfers') ? DismissDirection.startToEnd : DismissDirection.none,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), decoration: BoxDecoration(color: Colors.red[100], borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.delete, color: Colors.red)),
      confirmDismiss: (dir) async => await _showDeleteConfirm(),
      onDismissed: (_) async => await TransferService.deleteTransfer(doc: doc, currentUser: widget.currentUser, activeCafeId: _activeCafeId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10)]),
        child: Row(children: [
            Expanded(
              child: InkWell(
                onTap: () => (widget.currentUser.canUpdate('transfers')) ? DashboardDialogs.showAddTransferDialog(context: context, currentUser: widget.currentUser, paymentMethods: _paymentMethods, customerSuggestions: _existingCustomers, managerId: widget.currentUser.parentId ?? widget.currentUser.id, editDoc: doc) : null,
                borderRadius: const BorderRadius.only(topRight: Radius.circular(20), bottomRight: Radius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(hasDifferentPayer ? payerName! : customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (hasDifferentPayer) ...[
                          Text("لحساب: $customerName", style: const TextStyle(color: Colors.blueGrey, fontSize: 11, fontWeight: FontWeight.bold)),
                          const Text(" • ", style: TextStyle(color: Colors.grey)),
                        ],
                        Text("${d['payment_method']}${p.isNotEmpty ? ' • $p' : ''}", style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                      ],
                    ),
                    if (n.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text("📝 $n", style: const TextStyle(color: Colors.brown, fontSize: 10, fontStyle: FontStyle.italic))),
                    Text(date != null ? DateFormat('hh:mm a').format(date) : '', style: TextStyle(color: Colors.grey[400], fontSize: 10)),
                  ]),
                ),
              ),
            ),
            IconButton(
              onPressed: widget.currentUser.canUpdate('transfers') ? () {
                HapticFeedback.mediumImpact();
                doc.reference.update({'is_pending': !isPending});
              } : null, 
              icon: Icon(isPending ? Icons.play_circle_outline : Icons.pending_actions_outlined, size: 20, color: Colors.orange[800])
            ),
            IconButton(onPressed: () => _shareTransfer(d), icon: const Icon(Icons.share, size: 18, color: Colors.blue)),
            if (p.isNotEmpty) IconButton(onPressed: () => _shareTransfer(d, isWhatsApp: true), icon: const Icon(Icons.send_to_mobile, size: 18, color: Colors.green)),
            
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
                    Text("${d['total_amount']} $_currencySymbol", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF634231))),
                    const SizedBox(height: 5),
                    Icon(r ? Icons.check_circle : (isPending ? Icons.pause_circle_filled : Icons.hourglass_empty), color: r ? Colors.green : (isPending ? Colors.orange : Colors.grey), size: 32),
                  ],
                ),
              ),
            ),
          ]),
      ),
    );
  }

  Future<bool?> _showDeleteConfirm() => showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text("تأكيد الحذف"), content: const Text("هل تريد حذف هذه العملية؟"), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("إلغاء")), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("حذف", style: TextStyle(color: Colors.red)))]));
}
