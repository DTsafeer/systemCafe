import 'package:cloud_firestore/cloud_firestore.dart';

class ReportService {
  static Future<Map<String, List<QueryDocumentSnapshot>>> fetchReportData(
    String cafeId, 
    String managerId, {
    required DateTime start,
    required DateTime end,
  }) async {
    // توحيد الوقت لضمان شمول اليوم بالكامل
    DateTime s = DateTime(start.year, start.month, start.day, 0, 0, 0);
    DateTime e = DateTime(end.year, end.month, end.day, 23, 59, 59);

    // تم تقليل الفلترة في الاستعلام لتقليل الحاجة للفهارس المركبة
    // نكتفي بفلترة cafeId فقط لجلب أقل قدر ممكن من البيانات ثم الفلترة في الكود
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

    // فلترة النتائج حسب managerId والتاريخ برمجياً
    final filteredSales = results[0].docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['parentId'] != managerId && doc.id != managerId) {
        // إذا كان النظام يعتمد على parentId للربط
        if (data['parentId'] != managerId) return false;
      }
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

  static Map<String, Map<String, dynamic>> calculateDailyFinance({
    required DateTime start,
    required DateTime end,
    required List<QueryDocumentSnapshot> sales,
    required List<QueryDocumentSnapshot> purchases,
    required List<QueryDocumentSnapshot> expenses,
    required List<QueryDocumentSnapshot> debtTx,
  }) {
    Map<String, Map<String, dynamic>> dailyFinance = {};
    
    // تهيئة كافة الأيام في الفترة المختارة لضمان ظهورها حتى لو كانت فارغة
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
        dailyFinance[key]!['sales'] += (d['total_amount'] ?? d['amount'] ?? 0).toDouble();
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
      
      // تدقيق إضافي للتاريخ
      if (dt.isBefore(start) || dt.isAfter(end.add(const Duration(seconds: 1)))) continue;

      for (var item in (d['items'] as List? ?? [])) {
        String name = item['name'] ?? "منتج";
        if (search.isEmpty || name.toLowerCase().contains(search)) {
          itemStats.putIfAbsent(name, () => {'qty': 0.0, 'total': 0.0});
          double qty = (item['quantity'] ?? 0).toDouble();
          double price = (item['price'] ?? item['amount'] ?? 0).toDouble();
          itemStats[name]!['qty'] += qty;
          itemStats[name]!['total'] += (qty * price);
        }
      }
    }
    return itemStats;
  }
}
