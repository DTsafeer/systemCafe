import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'user_model.dart';
import 'MainLayout.dart';
import '../services/cafe_service.dart';

class DailySalesPage extends StatefulWidget {
  final User currentUser;
  const DailySalesPage({super.key, required this.currentUser});

  @override
  State<DailySalesPage> createState() => _DailySalesPageState();
}

class _DailySalesPageState extends State<DailySalesPage> {
  String currencySymbol = "₪";
  late String managerId;

  // Pagination & Loading state
  final ScrollController _scrollController = ScrollController();
  List<DocumentSnapshot> _allDocs = [];
  bool _isLoading = false;
  bool _isMoreDataAvailable = true;
  DocumentSnapshot? _lastDocument;
  final int _pageSize = 20;

  // Date Filtering
  DateTimeRange? _selectedDateRange;

  // Grouped Data
  Map<String, Map<String, dynamic>> dailyGroups = {};

  @override
  void initState() {
    super.initState();
    managerId = widget.currentUser.parentId ?? widget.currentUser.id;
    _loadSettings();
    _fetchInitialSales();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _fetchMoreSales();
      }
    });
  }

  void _loadSettings() async {
    final settings = await CafeService.getCafeSettings(widget.currentUser.cafeId);
    if (mounted) setState(() => currencySymbol = settings.currencySymbol);
  }

  Future<void> _fetchInitialSales() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _allDocs.clear();
      dailyGroups.clear();
      _lastDocument = null;
      _isMoreDataAvailable = true;
    });

    try {
      Query query = FirebaseFirestore.instance
          .collection('payments')
          .where('cafeId', isEqualTo: widget.currentUser.cafeId)
          .where('parentId', isEqualTo: managerId)
          .orderBy('paid_at', descending: true);

      if (_selectedDateRange != null) {
        DateTime start = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day, 0, 0, 0);
        DateTime end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59);
        
        query = query
            .where('paid_at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('paid_at', isLessThanOrEqualTo: Timestamp.fromDate(end));
      }

      QuerySnapshot snapshot = await query.limit(_pageSize).get();
      
      if (snapshot.docs.isNotEmpty) {
        _lastDocument = snapshot.docs.last;
        _allDocs = snapshot.docs;
        _processDocs(snapshot.docs);
        if (snapshot.docs.length < _pageSize) _isMoreDataAvailable = false;
      } else {
        _isMoreDataAvailable = false;
      }
    } catch (e) {
      debugPrint("Error fetching sales: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMoreSales() async {
    if (_isLoading || !_isMoreDataAvailable || _lastDocument == null) return;
    setState(() => _isLoading = true);

    try {
      Query query = FirebaseFirestore.instance
          .collection('payments')
          .where('cafeId', isEqualTo: widget.currentUser.cafeId)
          .where('parentId', isEqualTo: managerId)
          .orderBy('paid_at', descending: true);

      if (_selectedDateRange != null) {
        DateTime start = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day, 0, 0, 0);
        DateTime end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59);
        query = query
            .where('paid_at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('paid_at', isLessThanOrEqualTo: Timestamp.fromDate(end));
      }

      QuerySnapshot snapshot = await query
          .startAfterDocument(_lastDocument!)
          .limit(_pageSize)
          .get();

      if (snapshot.docs.length < _pageSize) {
        _isMoreDataAvailable = false;
      }
      if (snapshot.docs.isNotEmpty) {
        _lastDocument = snapshot.docs.last;
        _allDocs.addAll(snapshot.docs);
        _processDocs(snapshot.docs);
      }
    } catch (e) {
      debugPrint("Error fetching more sales: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _processDocs(List<DocumentSnapshot> docs) {
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final timestamp = data['paid_at'] as Timestamp?;
      if (timestamp == null) continue;

      final date = timestamp.toDate();
      final dayKey = intl.DateFormat('yyyy-MM-dd').format(date);

      if (!dailyGroups.containsKey(dayKey)) {
        dailyGroups[dayKey] = {
          'date': date,
          'totalSales': 0.0,
          'totalCost': 0.0,
          'transactions': [],
        };
      }

      if (data['is_debt_payment'] != true) {
        double total = (data['total_amount'] ?? 0.0).toDouble();
        
        double txCost = 0.0;
        List items = data['items'] as List? ?? [];
        for (var item in items) {
          double cost = double.tryParse(item['costPriceAtSale']?.toString() ?? "") ??
              double.tryParse(item['costPrice']?.toString() ?? "0") ?? 0.0;
          double q = (item['quantity'] ?? 0.0).toDouble();
          txCost += (cost * q);
        }

        data['calculated_cost'] = txCost;
        data['calculated_profit'] = total - txCost;

        dailyGroups[dayKey]!['totalSales'] += total;
        dailyGroups[dayKey]!['totalCost'] += txCost;
        dailyGroups[dayKey]!['transactions'].add(data);
      }
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDateRange) {
      setState(() => _selectedDateRange = picked);
      _fetchInitialSales();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedDayKeys = dailyGroups.keys.toList()..sort((a, b) => b.compareTo(a));

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'daily_sales',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("سجل المبيعات اليومي",
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 0.5)),
          backgroundColor: theme.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(_selectedDateRange == null ? Icons.calendar_month : Icons.event_available, color: Colors.white),
              onPressed: _selectDateRange,
            ),
            if (_selectedDateRange != null)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () {
                  setState(() => _selectedDateRange = null);
                  _fetchInitialSales();
                },
              ),
          ],
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
        ),
        body: Column(
          children: [
            if (_selectedDateRange != null)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: theme.primaryColor.withOpacity(0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.date_range_rounded, size: 18, color: theme.primaryColor),
                    const SizedBox(width: 10),
                    Text(
                      "${intl.DateFormat('yyyy/MM/dd').format(_selectedDateRange!.start)}  -  ${intl.DateFormat('yyyy/MM/dd').format(_selectedDateRange!.end)}",
                      style: TextStyle(fontWeight: FontWeight.w800, color: theme.primaryColor, fontSize: 13),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchInitialSales,
                child: _allDocs.isEmpty && !_isLoading
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        itemCount: sortedDayKeys.length + 1,
                        itemBuilder: (context, index) {
                          if (index == sortedDayKeys.length) {
                            return _isMoreDataAvailable
                                ? const Center( child: CircularProgressIndicator())
                                : const Padding(
                                    padding: EdgeInsets.all(30),
                                    child: Center(child: Text("تم تحميل جميع البيانات", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
                                  );
                          }

                          final dayData = dailyGroups[sortedDayKeys[index]]!;
                          return _buildDayCard(dayData, theme.primaryColor);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
                child: Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey[300]),
              ),
              const SizedBox(height: 24),
              Text("لا توجد مبيعات في هذه الفترة",
                  style: TextStyle(color: Colors.grey[600], fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("حاول تغيير نطاق التاريخ أو سحب الشاشة للتحديث",
                  style: TextStyle(color: Colors.grey[400], fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayCard(Map<String, dynamic> dayData, Color primaryColor) {
    final double profit = dayData['totalSales'] - dayData['totalCost'];
    final dateStr = intl.DateFormat('EEEE, dd MMMM', 'ar').format(dayData['date']);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          title: Text(dateStr,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Colors.black87)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: Row(
              children: [
                _miniBadge("ربح: ${profit.toStringAsFixed(1)} $currencySymbol", Colors.blue[700]!),
                const SizedBox(width: 8),
                _miniBadge("مبيعات: ${dayData['totalSales'].toStringAsFixed(1)} $currencySymbol", Colors.green[700]!),
              ],
            ),
          ),
          children: [
            const Divider(height: 1, indent: 25, endIndent: 25, color: Color(0xFFEEEEEE)),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      _expandedStat("إجمالي المبيعات", dayData['totalSales'], Colors.green),
                      const SizedBox(width: 15),
                      _expandedStat("صافي الربح", profit, Colors.blue),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text("تفاصيل الحركات:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                  ),
                  const SizedBox(height: 10),
                  ... (dayData['transactions'] as List).map((tx) => _buildTransactionItem(tx)).toList(),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _miniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.1), width: 0.5),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }

  Widget _expandedStat(String label, double val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text("${val.toStringAsFixed(1)} $currencySymbol",
                style: TextStyle(fontSize: 18, color: color, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> tx) {
    final time = (tx['paid_at'] as Timestamp).toDate();
    final List items = tx['items'] as List? ?? [];
    final double profit = tx['calculated_profit'] ?? 0.0;
    final double cost = tx['calculated_cost'] ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.receipt_long_rounded, size: 18, color: Colors.blue[600]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx['customer_name'] ?? "زبون عام",
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(intl.DateFormat('hh:mm a').format(time),
                        style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("${tx['total_amount']} $currencySymbol",
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.green)),
                  Text("ربح: ${profit.toStringAsFixed(1)}",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.blue[600])),
                ],
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0),
            child: Divider(height: 1, color: Color(0xFFEEEEEE)),
          ),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(Icons.circle, size: 6, color: Colors.blue[200]),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "${item['name']} × ${item['quantity']}",
                    style: TextStyle(fontSize: 13, color: Colors.grey[800], fontWeight: FontWeight.w500),
                  ),
                ),
                Text(
                  "${(double.tryParse(item['price']?.toString() ?? "0") ?? 0.0) * (item['quantity'] ?? 1)} $currencySymbol",
                  style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w700),
                ),
              ],
            ),
          )).toList(),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("التكلفة الإجمالية:", style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                Text("${cost.toStringAsFixed(1)} $currencySymbol",
                    style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.bold)),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
