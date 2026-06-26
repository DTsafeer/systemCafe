import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import '../services/report_service.dart';
import 'report_widgets.dart';

class ReportDialogs {
  static void showDailySummaryDialog({
    required BuildContext context,
    required String cafeId,
    required String managerId,
    required DateTime selectedDate,
    required String currencySymbol,
    required Function(Map<String, Map<String, dynamic>>, DateTime, DateTime) onExport,
  }) async {
    DateTime initialStart = DateTime(selectedDate.year, selectedDate.month, 1);
    DateTime initialEnd = DateTime(selectedDate.year, selectedDate.month + 1, 0, 23, 59, 59);

    showDialog(
      context: context,
      builder: (ctx) => _SmartAnalysisDialog(
        cafeId: cafeId,
        managerId: managerId,
        initialStart: initialStart,
        initialEnd: initialEnd,
        currencySymbol: currencySymbol,
        onExport: onExport,
      ),
    );
  }
}

class _SmartAnalysisDialog extends StatefulWidget {
  final String cafeId;
  final String managerId;
  final DateTime initialStart;
  final DateTime initialEnd;
  final String currencySymbol;
  final Function(Map<String, Map<String, dynamic>>, DateTime, DateTime) onExport;

  const _SmartAnalysisDialog({
    required this.cafeId,
    required this.managerId,
    required this.initialStart,
    required this.initialEnd,
    required this.currencySymbol,
    required this.onExport,
  });

  @override
  State<_SmartAnalysisDialog> createState() => _SmartAnalysisDialogState();
}

class _SmartAnalysisDialogState extends State<_SmartAnalysisDialog> {
  late DateTime startDate;
  late DateTime endDate;
  final TextEditingController searchController = TextEditingController();
  bool isLoading = true;
  String? errorMessage;
  Map<String, List<QueryDocumentSnapshot>>? data;

  @override
  void initState() {
    super.initState();
    startDate = widget.initialStart;
    endDate = widget.initialEnd;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final fetchedData = await ReportService.fetchReportData(
        widget.cafeId,
        widget.managerId,
        start: startDate,
        end: endDate,
      );
      if (mounted) {
        setState(() {
          data = fetchedData;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading report data: $e");
      if (mounted) {
        setState(() {
          isLoading = false;
          errorMessage = "فشل تحميل البيانات. تأكد من إعداد الفهارس (Indexes) في Firebase.";
        });
      }
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: startDate, end: endDate),
      firstDate: DateTime(2022),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
    );

    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    
    if (isLoading) {
      body = const Center(child: Padding(
        padding: EdgeInsets.all(50.0),
        child: CircularProgressIndicator(),
      ));
    } else if (errorMessage != null || data == null) {
      body = Center(child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),
            const SizedBox(height: 10),
            Text(errorMessage ?? "حدث خطأ غير متوقع", textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            TextButton(onPressed: _loadData, child: const Text("إعادة المحاولة")),
          ],
        ),
      ));
    } else {
      final dailyFinance = ReportService.calculateDailyFinance(
        start: startDate,
        end: endDate,
        sales: data!['sales']!,
        purchases: data!['purchases']!,
        expenses: data!['expenses']!,
        debtTx: data!['debtTransactions']!,
      );

      final itemStats = ReportService.calculateItemStats(
        start: startDate,
        end: endDate,
        sales: data!['sales']!,
        query: searchController.text,
      );

      final sortedItems = itemStats.entries.toList()..sort((a, b) => b.value['qty'].compareTo(a.value['qty']));

      body = SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 30,
            runSpacing: 30,
            children: [
              LuxuryTableContainer(
                title: "سجل التدفق المالي بالفترة",
                icon: Icons.calendar_view_day_rounded,
                color: Colors.blueAccent,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('اليوم', style: TextStyle(fontWeight: FontWeight.w900))),
                      DataColumn(label: Text('مبيعات', style: TextStyle(fontWeight: FontWeight.w900))),
                      DataColumn(label: Text('ديون', style: TextStyle(fontWeight: FontWeight.w900))),
                      DataColumn(label: Text('تحصيل', style: TextStyle(fontWeight: FontWeight.w900))),
                      DataColumn(label: Text('مشتريات', style: TextStyle(fontWeight: FontWeight.w900))),
                      DataColumn(label: Text('مصاريف', style: TextStyle(fontWeight: FontWeight.w900))),
                    ],
                    rows: dailyFinance.entries.map((entry) {
                      var d = entry.value;
                      return DataRow(cells: [
                        DataCell(Text(d['display'])),
                        DataCell(Text(d['sales'].toStringAsFixed(0))),
                        DataCell(Text(d['debts'].toStringAsFixed(0), style: const TextStyle(color: Colors.orange))),
                        DataCell(Text(d['collections'].toStringAsFixed(0), style: const TextStyle(color: Colors.teal))),
                        DataCell(Text(d['purchases'].toStringAsFixed(0), style: const TextStyle(color: Colors.redAccent))),
                        DataCell(Text(d['expenses'].toStringAsFixed(0), style: const TextStyle(color: Colors.purple))),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
              LuxuryTableContainer(
                title: "الأصناف الأكثر مبيعاً",
                icon: Icons.inventory_2_rounded,
                color: Colors.deepPurpleAccent,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: TextField(
                        controller: searchController,
                        onChanged: (v) => setState(() {}),
                        decoration: InputDecoration(
                            hintText: "بحث...",
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))
                        ),
                      ),
                    ),
                    DataTable(
                      columns: const [
                        DataColumn(label: Text('الصنف')),
                        DataColumn(label: Text('الكمية')),
                        DataColumn(label: Text('المجموع')),
                      ],
                      rows: sortedItems.map((entry) => DataRow(cells: [
                        DataCell(Text(entry.key)),
                        DataCell(Text(entry.value['qty'].toString())),
                        DataCell(Text("${entry.value['total'].toStringAsFixed(1)} ${widget.currencySymbol}")),
                      ])).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final dateRangeStr = "${intl.DateFormat('MM/dd').format(startDate)} - ${intl.DateFormat('MM/dd').format(endDate)}";

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
        backgroundColor: Colors.grey[50],
        titlePadding: EdgeInsets.zero,
        insetPadding: const EdgeInsets.all(10),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 25),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.blueGrey[900]!, Colors.blueGrey[800]!]),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_motion_rounded, color: Colors.amberAccent, size: 32),
                  const SizedBox(width: 20),
                  const Expanded(child: Text("التحليل الذكي", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900))),
                  if (!isLoading && data != null)
                    IconButton(
                      icon: const Icon(Icons.file_download_rounded, color: Colors.white, size: 30),
                      onPressed: () {
                        final dailyFinance = ReportService.calculateDailyFinance(
                          start: startDate,
                          end: endDate,
                          sales: data!['sales']!,
                          purchases: data!['purchases']!,
                          expenses: data!['expenses']!,
                          debtTx: data!['debtTransactions']!,
                        );
                        widget.onExport(dailyFinance, startDate, endDate);
                      },
                    )
                ],
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: _pickDateRange,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.date_range, color: Colors.white70, size: 18),
                      const SizedBox(width: 10),
                      Text("الفترة: $dateRangeStr", style: const TextStyle(color: Colors.white, fontSize: 14)),
                      const Icon(Icons.arrow_drop_down, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        content: Container(
          width: MediaQuery.of(context).size.width * 0.98,
          color: Colors.white,
          child: body,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إغلاق")),
        ],
      ),
    );
  }
}
