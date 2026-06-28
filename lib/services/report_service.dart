import 'package:cloud_firestore/cloud_firestore.dart';

class ReportService {
  static Future<Map<String, List<QueryDocumentSnapshot>>> fetchReportData(
    String cafeId, 
    String managerId, {
    required DateTime start,
    required DateTime end,
  }) async {
    DateTime s = DateTime(start.year, start.month, start.day, 0, 0, 0);
    DateTime e = DateTime(end.year, end.month, end.day, 23, 59, 59);

    final salesQuery = FirebaseFirestore.instance.collection('payments')
        .where('cafeId', isEqualTo: cafeId)
        .get();

    final purchaseQuery = FirebaseFirestore.instance.collection('purchases')
        .where('cafeId', isEqualTo: cafeId)
        .get();

    final expenseQuery = FirebaseFirestore.instance.collection('expenses')
        .where('cafeId', isEqualTo: cafeId)
        .get();

    final debtTxQuery = FirebaseFirestore.instance.collection('debt_transactions')
        .where('cafeId', isEqualTo: cafeId)
        .get();

    final results = await Future.wait([salesQuery, purchaseQuery, expenseQuery, debtTxQuery]);

    final filteredSales = results[0].docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['parentId'] != managerId && doc.id != managerId) return false;
      final ts = data['paid_at'] ?? data['date'];
      if (ts == null) return false;
      final dt = (ts is Timestamp) ? ts.toDate() : (DateTime.tryParse(ts.toString()) ?? DateTime(2000));
      return dt.isAfter(s.subtract(const Duration(seconds: 1))) && dt.isBefore(e.add(const Duration(seconds: 1)));
    }).toList();

    final filteredPurchases = results[1].docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['parentId'] != managerId) return false;
      final ts = data['date'];
      if (ts == null) return false;
      final dt = (ts is Timestamp) ? ts.toDate() : (DateTime.tryParse(ts.toString()) ?? DateTime(2000));
      return dt.isAfter(s.subtract(const Duration(seconds: 1))) && dt.isBefore(e.add(const Duration(seconds: 1)));
    }).toList();

    final filteredExpenses = results[2].docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['parentId'] != managerId) return false;
      final ts = data['date'];
      if (ts == null) return false;
      DateTime dt = (ts is Timestamp) ? ts.toDate() : (DateTime.tryParse(ts.toString()) ?? DateTime(2000));
      return dt.isAfter(s.subtract(const Duration(seconds: 1))) && dt.isBefore(e.add(const Duration(seconds: 1)));
    }).toList();

    final filteredDebtTx = results[3].docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['parentId'] != managerId) return false;
      final ts = data['date'];
      if (ts == null) return false;
      final dt = (ts is Timestamp) ? ts.toDate() : (DateTime.tryParse(ts.toString()) ?? DateTime(2000));
      return dt.isAfter(s.subtract(const Duration(seconds: 1))) && dt.isBefore(e.add(const Duration(seconds: 1)));
    }).toList();

    return {
      'sales': filteredSales,
      'purchases': filteredPurchases,
      'expenses': filteredExpenses,
      'debtTransactions': filteredDebtTx,
    };
  }

  static Map<String, dynamic> calculateFullFinancialStatement(Map<String, List<QueryDocumentSnapshot>> data) {
    double totalSales = 0;
    double totalCOGS = 0; 
    double totalPurchases = 0;
    double totalExpenses = 0;
    double totalDebtCollected = 0;
    double totalNewDebts = 0;

    for (var doc in data['sales']!) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['is_debt_payment'] == true) {
         totalDebtCollected += (d['total_amount'] ?? 0).toDouble();
      } else {
         final items = d['items'] as List? ?? [];
         double docItemRevenue = 0;
         for (var item in items) {
           double cost = double.tryParse(item['costPriceAtSale']?.toString() ?? "") ?? 
                         double.tryParse(item['costPrice']?.toString() ?? "0") ?? 0.0;
           double qty = (item['quantity'] ?? 0.0).toDouble();
           double revenue = double.tryParse(item['total']?.toString() ?? "0") ?? 0.0;
           
           totalCOGS += (cost * qty);
           docItemRevenue += revenue;
         }
         totalSales += (docItemRevenue > 0) ? docItemRevenue : (d['total_amount'] ?? 0).toDouble();
      }
    }

    for (var doc in data['debtTransactions']!) {
      final d = doc.data() as Map<String, dynamic>;
      final type = d['type']?.toString() ?? "";
      if (type.contains("طلب") || type.contains("باقي فاتورة")) {
        final items = d['items'] as List? ?? [];
        double docItemRevenue = 0;
        double docItemCost = 0;
        for (var item in items) {
          double cost = double.tryParse(item['costPriceAtSale']?.toString() ?? "") ?? 
                        double.tryParse(item['costPrice']?.toString() ?? "0") ?? 0.0;
          double qty = (item['quantity'] ?? 0.0).toDouble();
          double revenue = double.tryParse(item['total']?.toString() ?? "0") ?? 0.0;
          
          docItemCost += (cost * qty);
          docItemRevenue += revenue;
        }
        double finalDocRev = (docItemRevenue > 0) ? docItemRevenue : (d['amount'] ?? 0).toDouble();
        totalSales += finalDocRev;
        totalCOGS += docItemCost;
        totalNewDebts += finalDocRev;
      }
    }

    for (var doc in data['purchases']!) {
      final d = doc.data() as Map<String, dynamic>;
      totalPurchases += (d['amount'] ?? 0).toDouble();
    }

    for (var doc in data['expenses']!) {
      final d = doc.data() as Map<String, dynamic>;
      totalExpenses += (d['amount'] ?? 0).toDouble();
    }

    double grossProfit = totalSales - totalCOGS;
    double netProfit = grossProfit - totalExpenses;
    double actualLiquidityProfit = netProfit - totalNewDebts;

    return {
      'totalSales': totalSales,
      'totalCOGS': totalCOGS,
      'grossProfit': grossProfit,
      'totalExpenses': totalExpenses,
      'netProfit': netProfit,
      'totalNewDebts': totalNewDebts,
      'actualLiquidityProfit': actualLiquidityProfit,
      'totalPurchases': totalPurchases,
      'totalDebtCollected': totalDebtCollected,
    };
  }

  static Map<String, Map<String, dynamic>> calculateDailyFinance({
    required DateTime start,
    required DateTime end,
    required List<QueryDocumentSnapshot> sales,
    required List<QueryDocumentSnapshot> purchases,
    required List<QueryDocumentSnapshot> expenses,
    required List<QueryDocumentSnapshot> debtTx,
  }) {
    Map<String, Map<String, dynamic>> dailyFinance = {};
    int totalDays = end.difference(start).inDays;
    for (int i = 0; i <= totalDays; i++) {
      final date = start.add(Duration(days: i));
      final key = "${date.year}-${date.month}-${date.day}";
      dailyFinance[key] = {
        'sales': 0.0, 'purchases': 0.0, 'expenses': 0.0, 'debts': 0.0, 'collections': 0.0, 
        'display': "${date.day}/${date.month}"
      };
    }

    for (var doc in sales) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['is_debt_payment'] == true) continue;
      final ts = d['paid_at'] ?? d['date'];
      if (ts == null) continue;
      final dt = (ts is Timestamp) ? ts.toDate() : (DateTime.tryParse(ts.toString()) ?? DateTime(2000));
      final key = "${dt.year}-${dt.month}-${dt.day}";
      if (dailyFinance.containsKey(key)) {
        final items = d['items'] as List? ?? [];
        double docItemRevenue = 0;
        for (var item in items) {
          docItemRevenue += double.tryParse(item['total']?.toString() ?? "0") ?? 0.0;
        }
        dailyFinance[key]!['sales'] += (docItemRevenue > 0) ? docItemRevenue : (d['total_amount'] ?? 0).toDouble();
      }
    }

    for (var doc in debtTx) {
      final d = doc.data() as Map<String, dynamic>;
      final ts = d['date'];
      if (ts == null) continue;
      final dt = (ts is Timestamp) ? ts.toDate() : (DateTime.tryParse(ts.toString()) ?? DateTime(2000));
      final key = "${dt.year}-${dt.month}-${dt.day}";
      if (dailyFinance.containsKey(key)) {
        final type = d['type']?.toString() ?? "";
        final amount = (d['amount'] ?? 0).toDouble();
        if (type.contains("طلب") || type.contains("دين")) {
          dailyFinance[key]!['debts'] += amount;
          final items = d['items'] as List? ?? [];
          double docItemRevenue = 0;
          for (var item in items) {
            docItemRevenue += double.tryParse(item['total']?.toString() ?? "0") ?? 0.0;
          }
          dailyFinance[key]!['sales'] += (docItemRevenue > 0) ? docItemRevenue : amount;
        } else if (type.contains("سداد") || type.contains("تحصيل")) {
          dailyFinance[key]!['collections'] += amount;
        }
      }
    }

    for (var doc in purchases) {
      final d = doc.data() as Map<String, dynamic>;
      final ts = d['date'];
      if (ts == null) continue;
      final dt = (ts is Timestamp) ? ts.toDate() : (DateTime.tryParse(ts.toString()) ?? DateTime(2000));
      final key = "${dt.year}-${dt.month}-${dt.day}";
      if (dailyFinance.containsKey(key)) {
        dailyFinance[key]!['purchases'] += (d['amount'] ?? d['paidAmount'] ?? 0).toDouble();
      }
    }

    for (var doc in expenses) {
      final d = doc.data() as Map<String, dynamic>;
      final ts = d['date'];
      if (ts == null) continue;
      DateTime dt = (ts is Timestamp) ? ts.toDate() : (DateTime.tryParse(ts.toString()) ?? DateTime(2000));
      final key = "${dt.year}-${dt.month}-${dt.day}";
      if (dailyFinance.containsKey(key)) {
        dailyFinance[key]!['expenses'] += (d['amount'] ?? 0).toDouble();
      }
    }
    return dailyFinance;
  }

  static Map<String, Map<String, dynamic>> calculateItemStats({
    required DateTime start,
    required DateTime end,
    required List<QueryDocumentSnapshot> sales,
    String query = "",
  }) {
    Map<String, Map<String, dynamic>> itemStats = {};
    String search = query.toLowerCase().trim();

    for (var doc in sales) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['is_debt_payment'] == true) continue;
      final ts = d['paid_at'] ?? d['date'];
      if (ts == null) continue;
      final dt = (ts is Timestamp) ? ts.toDate() : (DateTime.tryParse(ts.toString()) ?? DateTime(2000));
      if (dt.isBefore(start) || dt.isAfter(end.add(const Duration(seconds: 1)))) continue;

      for (var item in (d['items'] as List? ?? [])) {
        String name = item['name'] ?? "منتج";
        if (search.isEmpty || name.toLowerCase().contains(search)) {
          itemStats.putIfAbsent(name, () => {'qty': 0.0, 'total': 0.0, 'count': 0});
          double qty = (item['quantity'] ?? 0).toDouble();
          double price = (item['price'] ?? item['amount'] ?? 0).toDouble();
          itemStats[name]!['qty'] += qty;
          itemStats[name]!['total'] += (qty * price);
          itemStats[name]!['count'] += 1;
        }
      }
    }
    return itemStats;
  }
}
