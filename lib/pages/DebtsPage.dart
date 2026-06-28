import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:excel/excel.dart' as excel_pkg;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import '../services/debt_service.dart';
import '../services/cafe_service.dart';
import '../widgets/app_components.dart';
import '../widgets/dashboard_dialogs.dart';

class DebtsPage extends StatefulWidget {
  final User currentUser;
  const DebtsPage({super.key, required this.currentUser});

  @override
  State<DebtsPage> createState() => _DebtsPageState();
}

class _DebtsPageState extends State<DebtsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String? _expandedDebtId;
  String _activeFilter = "الكل";
  String _sortBy = "الأعلى ديناً";
  late Stream<List<Map<String, dynamic>>> _debtsStream;
  CafeSettings? _settings;
  List<Map<String, String>> _customerSuggestions = [];

  String get _managerId => widget.currentUser.parentId ?? widget.currentUser.id;
  String get _cafeId => widget.currentUser.cafeId;

  @override
  void initState() {
    super.initState();
    _debtsStream = DebtService.streamDebts(_cafeId, _managerId);
    _loadSettings();
  }

  void _loadSettings() async {
    final settings = await CafeService.getCafeSettings(_cafeId);
    if (mounted) setState(() => _settings = settings);
  }

  Future<void> _downloadDebtReport(List<Map<String, dynamic>> debts) async {
    try {
      var excelDoc = excel_pkg.Excel.createExcel();
      excel_pkg.Sheet sheetObject = excelDoc['كشف الديون'];
      excelDoc.delete('Sheet1');

      sheetObject.appendRow([
        excel_pkg.TextCellValue('اسم الزبون'),
        excel_pkg.TextCellValue('له (رصيد / دائن)'),
        excel_pkg.TextCellValue('عليه (دين / مدين)'),
        excel_pkg.TextCellValue('رقم الهاتف'),
      ]);

      for (var d in debts) {
        double bal = (d['netBalance'] as num).toDouble();
        double credit = bal < 0 ? bal.abs() : 0;
        double debit = bal > 0 ? bal : 0;

        sheetObject.appendRow([
          excel_pkg.TextCellValue(d['customer'].toString()),
          excel_pkg.DoubleCellValue(credit),
          excel_pkg.DoubleCellValue(debit),
          excel_pkg.TextCellValue(d['phone'] ?? "-"),
        ]);
      }

      final directory = await getTemporaryDirectory();
      final fileName = "كشف_الديون_${intl.DateFormat('yyyy_MM_dd').format(DateTime.now())}.xlsx";
      final path = "${directory.path}/$fileName";
      final file = File(path);
      final bytes = excelDoc.save();

      if (bytes != null) {
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([XFile(path)], text: 'كشف الديون - نظام كافيه');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم إنشاء كشف الديون بنجاح")));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ خطأ في تصدير الملف: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.currentUser.canRead('debts')) {
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'debts',
        child: const Scaffold(
          body: Center(
            child: Text("عذراً، لا تملك صلاحية لعرض صفحة الديون", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'debts',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: widget.currentUser.canCreate('debts')
            ? FloatingActionButton.extended(
          onPressed: () => _showAddCustomerDialog(context),
          backgroundColor: const Color(0xFFEA4335),
          foregroundColor: Colors.white,
          label: const Text("إضافة زبون", style: TextStyle(fontWeight: FontWeight.bold)),
          icon: const Icon(Icons.person_add_rounded),
        )
            : null,
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _debtsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text("حدث خطأ في تحميل البيانات: ${snapshot.error}"));
            }
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final allDebts = snapshot.data ?? [];
            _customerSuggestions = allDebts.map((d) => {
              'id': d['id'].toString(),
              'name': d['customer'].toString(),
              'phone': d['phone']?.toString() ?? "",
              'debt': (d['netBalance'] as num).toStringAsFixed(1),
            }).toList();

            var filteredDebts = allDebts.where((d) {
              final name = d['customer'].toString().toLowerCase();
              final phone = d['phone']?.toString() ?? "";
              final matchesSearch = name.contains(_searchQuery.toLowerCase()) || phone.contains(_searchQuery);

              double bal = (d['netBalance'] as num).toDouble();
              bool matchesStatus = true;
              if (_activeFilter == "مديونون") matchesStatus = bal > 0;
              if (_activeFilter == "دائنون") matchesStatus = bal < 0;
              if (_activeFilter == "خالص") matchesStatus = bal == 0;

              return matchesSearch && matchesStatus;
            }).toList();

            if (_sortBy == "الأعلى ديناً") {
              filteredDebts.sort((a, b) => (b['netBalance'] as num).toDouble().abs().compareTo((a['netBalance'] as num).toDouble().abs()));
            } else if (_sortBy == "الاسم") {
              filteredDebts.sort((a, b) => a['customer'].toString().compareTo(b['customer'].toString()));
            }

            return Column(
              children: [
                _buildDebtStatsHeader(allDebts),
                _buildSearchAndSortBar(filteredDebts),
                _buildFilterChips(allDebts),
                const SizedBox(height: 10),
                Expanded(
                  child: filteredDebts.isEmpty
                      ? _buildEmptyState(isSearch: allDebts.isNotEmpty)
                      : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: filteredDebts.length,
                    itemBuilder: (context, index) => _buildCustomerDebtCard(filteredDebts[index]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDebtStatsHeader(List<Map<String, dynamic>> debts) {
    double totalDebt = 0;
    int debtorsCount = 0;
    for (var d in debts) {
      double bal = (d['netBalance'] as num).toDouble();
      if (bal > 0) {
        totalDebt += bal;
        debtorsCount++;
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 25),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFEA4335), Color(0xFFB71C1C)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(35), bottomRight: Radius.circular(35)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _statCard("إجمالي الديون", "${totalDebt.toStringAsFixed(1)} ₪", Icons.account_balance_rounded, "مديونون"),
              const SizedBox(width: 15),
              _statCard("عدد المدينين", "$debtorsCount", Icons.people_alt_rounded, "مديونون"),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _quickActionBtn(Icons.add_card_rounded, "سداد سريع", Colors.teal[400]!, () {
                if (_settings == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى الانتظار لتحميل الإعدادات...")));
                  return;
                }
                DashboardDialogs.showAddTransferDialog(
                  context: context,
                  currentUser: widget.currentUser,
                  paymentMethods: _settings!.paymentMethods,
                  customerSuggestions: _customerSuggestions,
                  managerId: _managerId,
                );
              }),
              const SizedBox(width: 10),
              _quickActionBtn(Icons.person_add_alt_1, "إضافة زبون", Colors.orange[400]!, () => _showAddCustomerDialog(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickActionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white24)
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, String filterTarget) {
    bool isActive = _activeFilter == filterTarget;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeFilter = isActive ? "الكل" : filterTarget),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
          decoration: BoxDecoration(
            color: isActive ? Colors.white.withOpacity(0.3) : Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isActive ? Colors.white : Colors.white24, width: isActive ? 2 : 1),
          ),
          child: Column(
            children: [
              Icon(icon, color: isActive ? Colors.amber : Colors.white, size: 26),
              const SizedBox(height: 8),
              FittedBox(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
              Text(title, style: TextStyle(color: isActive ? Colors.white : Colors.white70, fontSize: 11, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndSortBar(List<Map<String, dynamic>> currentDebts) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: "بحث عن زبون...",
                prefixIcon: const Icon(Icons.search, color: Color(0xFFEA4335)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
            child: IconButton(
              onPressed: () => _downloadDebtReport(currentDebts),
              icon: const Icon(Icons.file_download_outlined, color: Color(0xFFEA4335)),
              tooltip: "تنزيل كشف Excel",
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
            child: PopupMenuButton<String>(
              tooltip: "ترتيب حسب",
              icon: const Icon(Icons.sort_rounded, color: Color(0xFFEA4335)),
              onSelected: (v) => setState(() => _sortBy = v),
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: "الأعلى ديناً", child: Text("الأعلى ديناً")),
                const PopupMenuItem(value: "الاسم", child: Text("حسب الاسم")),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(List<Map<String, dynamic>> allDebts) {
    int countDebtors = 0;
    int countCreditors = 0;
    int countSettled = 0;

    for (var d in allDebts) {
      double bal = (d['netBalance'] as num).toDouble();
      if (bal > 0) countDebtors++;
      else if (bal < 0) countCreditors++;
      else countSettled++;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _filterChip("الكل", allDebts.length),
          const SizedBox(width: 8),
          _filterChip("مديونون", countDebtors, color: Colors.red),
          const SizedBox(width: 8),
          _filterChip("دائنون", countCreditors, color: Colors.green),
          const SizedBox(width: 8),
          _filterChip("خالص", countSettled, color: Colors.blueGrey),
        ],
      ),
    );
  }

  Widget _filterChip(String label, int count, {Color? color}) {
    bool isSelected = _activeFilter == label;
    return ChoiceChip(
      label: Text("$label ($count)", style: TextStyle(color: isSelected ? Colors.white : (color ?? Colors.grey[700]), fontWeight: FontWeight.bold, fontSize: 11)),
      selected: isSelected,
      selectedColor: color ?? const Color(0xFFEA4335),
      backgroundColor: Colors.white,
      onSelected: (v) => setState(() => _activeFilter = label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade200),
      showCheckmark: false,
    );
  }

  Widget _buildCustomerDebtCard(Map<String, dynamic> debt) {
    double balance = (debt['netBalance'] as num).toDouble();
    double limit = (debt['debtLimit'] as num? ?? 0.0).toDouble();
    bool isExpanded = _expandedDebtId == debt['id'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isExpanded ? Colors.red.shade300 : Colors.grey.shade200, width: isExpanded ? 1.2 : 1),
      ),
      child: InkWell(
        onTap: () => setState(() => _expandedDebtId = isExpanded ? null : debt['id']),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 400),
          curve: Curves.fastOutSlowIn,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: balance > 0 ? Colors.red[50] : (balance < 0 ? Colors.green[50] : Colors.grey[100]),
                      radius: 25,
                      child: Icon(Icons.person_rounded, color: balance > 0 ? Colors.red[700] : (balance < 0 ? Colors.green[700] : Colors.grey)),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(debt['customer'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                          Text(debt['phone'] ?? "لا يوجد هاتف", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                          if (limit > 0)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8)),
                              child: Text("الحد: $limit ₪", style: TextStyle(color: Colors.orange[900], fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("${balance.abs().toStringAsFixed(1)} ₪",
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: balance > 0 ? Colors.red[700] : (balance < 0 ? Colors.green[700] : Colors.grey[700]))),
                        Text(balance > 0 ? "دين عليه" : (balance < 0 ? "رصيد له" : "خالص"), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Icon(isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                  ],
                ),
              ),
              if (isExpanded) ...[
                const Divider(height: 1, indent: 15, endIndent: 15),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      if (widget.currentUser.canUpdate('debts')) ...[
                        _horizontalAction(Icons.add_moderator_rounded, "دين عليه", Colors.red[700]!, () => _showTransactionPopup(debt, "دين")),
                        _horizontalAction(Icons.account_balance_wallet_rounded, "سداد له", Colors.green[700]!, () {
                          if (_settings == null) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى الانتظار لتحميل الإعدادات...")));
                            return;
                          }
                          DashboardDialogs.showAddTransferDialog(
                            context: context,
                            currentUser: widget.currentUser,
                            paymentMethods: _settings!.paymentMethods,
                            customerSuggestions: _customerSuggestions,
                            managerId: _managerId,
                            initialName: debt['customer'],
                            initialPhone: debt['phone'],
                            initialCustomerId: debt['id'],
                          );
                        }),
                      ],
                      _horizontalAction(Icons.history_edu_rounded, "سجل", Colors.blue[700]!, () => _showHistoryBottomSheet(debt)),
                      _horizontalAction(Icons.call, "واتساب", Colors.green[800]!, () => _confirmWhatsAppMessage(debt)),
                      if (widget.currentUser.canUpdate('debts'))
                        _horizontalAction(Icons.edit_rounded, "تعديل", Colors.orange[800]!, () => _showEditCustomerDialog(debt)),
                      if (widget.currentUser.canDelete('debts'))
                        _horizontalAction(Icons.delete_forever_rounded, "حذف", Colors.red[900]!, () => _confirmDeleteCustomer(debt)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _horizontalAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddCustomerDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final debtCtrl = TextEditingController(text: "0");
    final creditCtrl = TextEditingController(text: "0");
    final limitCtrl = TextEditingController(text: "0");
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("إضافة زبون دين جديد"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "اسم الزبون")),
                  TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "رقم الهاتف (اختياري)"), keyboardType: TextInputType.phone),
                  TextField(controller: debtCtrl, decoration: const InputDecoration(labelText: "دين سابق (عليه)"), keyboardType: TextInputType.number),
                  TextField(controller: creditCtrl, decoration: const InputDecoration(labelText: "رصيد سابق (له)"), keyboardType: TextInputType.number),
                  TextField(controller: limitCtrl, decoration: const InputDecoration(labelText: "الحد الائتماني (0 = بلا حد)"), keyboardType: TextInputType.number),
                  if (isLoading) const Padding(padding: EdgeInsets.only(top: 15), child: CircularProgressIndicator()),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: isLoading ? null : () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ElevatedButton(
                onPressed: isLoading ? null : () async {
                  if (nameCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال اسم الزبون")));
                    return;
                  }
                  setDialogState(() => isLoading = true);
                  try {
                    await DebtService.addDebtCustomer(
                      cafeId: _cafeId,
                      managerId: _managerId,
                      currentUser: widget.currentUser,
                      name: nameCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      initialDebt: double.tryParse(debtCtrl.text) ?? 0,
                      initialCredit: double.tryParse(creditCtrl.text) ?? 0,
                      debtLimit: double.tryParse(limitCtrl.text) ?? 0,
                    );
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تمت الإضافة")));
                    }
                  } catch (e) {
                    setDialogState(() => isLoading = false);
                    if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
                  }
                },
                child: const Text("إضافة"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTransactionPopup(Map<String, dynamic> debt, String type) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(type == "دين" ? "تسجيل دين جديد" : "تسجيل عملية سداد"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: "المبلغ"), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: "ملاحظة (اختياري)")),
                  if (isLoading) const Padding(padding: EdgeInsets.only(top: 15), child: CircularProgressIndicator()),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: isLoading ? null : () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ElevatedButton(
                onPressed: isLoading ? null : () async {
                  double val = double.tryParse(amountCtrl.text) ?? 0;
                  if (val <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال مبلغ صحيح")));
                    return;
                  }

                  if (type == "دين") {
                    double currentBal = (debt['netBalance'] as num).toDouble();
                    double limit = (debt['debtLimit'] as num? ?? 0.0).toDouble();
                    if (limit > 0 && (currentBal + val) > limit) {
                      bool? allow = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text("⚠️ تجاوز الحد"),
                          content: Text("هذا الزبون سيتجاوز الحد المسموح به ($limit ₪).\nالمجموع سيصبح: ${currentBal + val} ₪.\nهل تريد المتابعة؟"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("إلغاء")),
                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("نعم، متابعة")),
                          ],
                        ),
                      );
                      if (allow != true) return;
                    }
                  }

                  setDialogState(() => isLoading = true);
                  try {
                    await DebtService.addDebtTransaction(
                      debtId: debt['id'],
                      customerName: debt['customer'],
                      type: type,
                      amount: val,
                      currentUser: widget.currentUser,
                      note: noteCtrl.text.isNotEmpty ? noteCtrl.text : null,
                    );
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم الحفظ")));
                    }
                  } catch (e) {
                    setDialogState(() => isLoading = false);
                    if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
                  }
                },
                child: const Text("حفظ"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHistoryBottomSheet(Map<String, dynamic> debt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: const EdgeInsets.all(15),
          height: MediaQuery.of(context).size.height * 0.9,
          child: Column(
            children: [
              Container(
                width: 40, height: 4, margin: const EdgeInsets.only(bottom: 15),
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("الصفحة الشخصية للديون: ${debt['customer']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
              const Divider(),
              Table(
                border: TableBorder.all(color: Colors.black45, width: 1),
                columnWidths: const {
                  0: FlexColumnWidth(1.2), // له
                  1: FlexColumnWidth(1.2), // عليه
                  2: FlexColumnWidth(1.5), // تفاصيل
                  3: FlexColumnWidth(1.2), // صافي
                  4: FlexColumnWidth(1.2), // تاريخ
                },
                children: [
                  TableRow(

                    children: [
                      _buildHeaderCell("الدفع التي دفعها الزبون"),
                      _buildHeaderCell("المبالغ المدانة"),
                      _buildHeaderCell("تفاصيل الدين"),
                      _buildHeaderCell("المبلغ الصافي"),
                      _buildHeaderCell("تاريخ اليوم"),
                    ],
                  ),
                ],
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('debt_transactions')
                      .where('debtId', isEqualTo: debt['id']).snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) return Center(child: Text("خطأ: ${snap.error}"));
                    if (!snap.hasData && snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                    final List<DocumentSnapshot> docs = List.from(snap.data?.docs ?? []);
                    docs.sort((a, b) {
                      Timestamp t1 = (a.data() as Map)['date'] as Timestamp? ?? Timestamp.now();
                      Timestamp t2 = (b.data() as Map)['date'] as Timestamp? ?? Timestamp.now();
                      return t1.compareTo(t2);
                    });

                    // البدء من الرصيد الافتتاحي (له) - يكون سالباً في حساب المديونية
                    double runningBalance = - (debt['initialBalance'] as num? ?? 0.0).toDouble();

                    Map<String, List<Map<String, dynamic>>> groupedData = {};
                    List<String> sortedDateKeys = [];

                    // إضافة الرصيد الافتتاحي كسطر إذا وجد
                    if (runningBalance != 0) {
                       String dateKey = "رصيد سابق";
                       groupedData[dateKey] = [{
                         'data': {'note': 'رصيد مسبق (افتتاحي)', 'type': 'رصيد'},
                         'isDebt': false,
                         'amount': runningBalance.abs(),
                         'netBalance': runningBalance,
                       }];
                       sortedDateKeys.add(dateKey);
                    }

                    for (var doc in docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
                      final dateKey = intl.DateFormat('yyyy/MM/dd').format(date);

                      final double amount = (data['amount'] as num).toDouble();
                      final String type = data['type'].toString();

                      // تصحيح المنطق: الدين هو "دين" أو "طلب" حصراً
                      // السداد أو الرصيد يطرح من المديونية
                      final bool isDebt = (type == "دين" || type.contains("طلب")) && !type.contains("سداد") && !type.contains("رصيد");

                      if (isDebt) runningBalance += amount; else runningBalance -= amount;

                      if (!groupedData.containsKey(dateKey)) {
                        groupedData[dateKey] = [];
                        sortedDateKeys.add(dateKey);
                      }

                      groupedData[dateKey]!.add({
                        'data': data,
                        'isDebt': isDebt,
                        'amount': amount,
                        'netBalance': runningBalance,
                      });
                    }

                    if (sortedDateKeys.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("لا توجد حركات مسجلة")));

                    final displayDateKeys = sortedDateKeys.reversed.toList();

                    return ListView.builder(
                      itemCount: displayDateKeys.length,
                      padding: const EdgeInsets.only(bottom: 50),
                      itemBuilder: (context, dateIndex) {
                        String dateKey = displayDateKeys[dateIndex];
                        List<Map<String, dynamic>> dayRows = groupedData[dateKey]!.reversed.toList();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 15),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black, width: 1.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Table(
                            border: const TableBorder(verticalInside: BorderSide(color: Colors.black, width: 1)),
                            columnWidths: const {
                              0: FlexColumnWidth(1.2),
                              1: FlexColumnWidth(1.2),
                              2: FlexColumnWidth(1.5),
                              3: FlexColumnWidth(1.2),
                              4: FlexColumnWidth(1.2),
                            },
                            children: dayRows.asMap().entries.map((entry) {
                              int i = entry.key;
                              var row = entry.value;
                              final data = row['data'];
                              final bool isDebt = row['isDebt'];
                              final double netBal = row['netBalance'];
                              final date = (data['date'] as Timestamp?)?.toDate();

                              String prepaid = isDebt ? "0" : row['amount'].toStringAsFixed(1);
                              String debtStr = isDebt ? "${date != null ? intl.DateFormat('hh:mm a').format(date) : ''}\n${row['amount'].toStringAsFixed(1)}" : "0";
                              String netDisplay = netBal >= 0 ? "عليه: ${netBal.abs().toStringAsFixed(1)}" : "له: ${netBal.abs().toStringAsFixed(1)}";

                              return TableRow(
                                decoration: BoxDecoration(color: i % 2 == 0 ? Colors.white : Colors.grey[50]),
                                children: [
                                  _buildDataCell(prepaid, color: isDebt ? Colors.black : Colors.green[800]),
                                  _buildDataCell(debtStr, color: isDebt ? Colors.red[800] : Colors.black),
                                  _buildDataCell(data['note'] ?? "-", isSmall: true),
                                  _buildDataCell(netDisplay, fontWeight: FontWeight.bold, color: netBal > 0 ? Colors.red[900] : (netBal < 0 ? Colors.green[900] : Colors.blueGrey)),
                                  _buildDataCell(i == 0 ? dateKey : ""),
                                ],
                              );
                            }).toList(),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String text) => Container(
    height: 50, alignment: Alignment.center,
    padding: const EdgeInsets.all(4.0),
    child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
  );

  Widget _buildDataCell(String text, {Color? color, FontWeight? fontWeight, bool isSmall = false}) => Container(
    height: 45, alignment: Alignment.center,
    padding: const EdgeInsets.all(6.0),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontWeight: fontWeight,
        fontSize: isSmall ? 10 : 11,
      ),
    ),
  );

  void _confirmDeleteTransaction(String transId, Map<String, dynamic> debt, Map<String, dynamic> transData) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("حذف الحركة"),
        content: const Text("هل أنت متأكد من حذف هذه الحركة؟ سيتم استعادة المبلغ في رصيد الزبون."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          TextButton(
              onPressed: () async {
                try {
                  Navigator.pop(ctx);
                  await DebtService.deleteTransaction(transId, debt['id'], transData['type'], (transData['amount'] as num).toDouble(), widget.currentUser);
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم الحذف")));
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ أثناء الحذف: $e")));
                }
              },
              child: const Text("حذف", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }

  void _showEditCustomerDialog(Map<String, dynamic> debt) {
    final nameCtrl = TextEditingController(text: debt['customer']);
    final phoneCtrl = TextEditingController(text: debt['phone']);
    final limitCtrl = TextEditingController(text: (debt['debtLimit'] ?? 0).toString());
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("تعديل بيانات الزبون"),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "الاسم")),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "الهاتف")),
            TextField(controller: limitCtrl, decoration: const InputDecoration(labelText: "الحد الائتماني"), keyboardType: TextInputType.number),
            if (isLoading) const Padding(padding: EdgeInsets.only(top: 10), child: CircularProgressIndicator()),
          ]),
          actions: [
            TextButton(onPressed: isLoading ? null : () => Navigator.pop(ctx), child: const Text("إلغاء")),
            TextButton(onPressed: isLoading ? null : () async {
              if (nameCtrl.text.isEmpty) return;
              setDialogState(() => isLoading = true);
              try {
                await DebtService.updateDebtCustomer(debt['id'], {
                  'customer': nameCtrl.text,
                  'phone': phoneCtrl.text,
                  'debtLimit': double.tryParse(limitCtrl.text) ?? 0,
                }, widget.currentUser);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم التعديل")));
                }
              } catch (e) {
                setDialogState(() => isLoading = false);
                if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
              }
            }, child: const Text("تحديث")),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteCustomer(Map<String, dynamic> debt) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("حذف الزبون"),
        content: Text("هل أنت متأكد من حذف ${debt['customer']} وكافة سجلاته نهائياً؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          TextButton(onPressed: () async {
            try {
              Navigator.pop(ctx);
              await DebtService.deleteDebtCustomer(debt['id'], widget.currentUser);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم الحذف بنجاح")));
            } catch (e) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ أثناء الحذف: $e")));
            }
          }, child: const Text("حذف", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  void _confirmWhatsAppMessage(Map<String, dynamic> debt) {
    final String phone = debt['phone']?.toString() ?? "";
    if (phone.isEmpty || phone == "لا يوجد هاتف") {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ لا يوجد رقم هاتف مسجل")));
      return;
    }
    _sendWhatsAppMessage(debt);
  }

  Future<void> _sendWhatsAppMessage(Map<String, dynamic> debt) async {
    try {
      final balance = (debt['netBalance'] as num).toDouble();
      final String phone = debt['phone']?.toString() ?? "";
      String msg = "مرحباً ${debt['customer']}\nرصيد حسابك الحالي في كافيه هو: ${balance.abs()} ₪ ${balance > 0 ? '(عليك)' : '(لك)'}";
      final url = "whatsapp://send?phone=+972$phone&text=${Uri.encodeComponent(msg)}";
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ لا يمكن فتح واتساب")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("⚠️ خطأ في فتح واتساب: $e")));
    }
  }

  Widget _buildEmptyState({bool isSearch = false}) => Center(child: Text(isSearch ? "لا توجد نتائج مطابقة" : "لا يوجد زبائن مضافون بعد"));
}
