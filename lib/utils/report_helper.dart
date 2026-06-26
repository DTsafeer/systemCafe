import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'save_helper_stub.dart'
    if (dart.library.html) 'save_helper_web.dart'
    if (dart.library.io) 'save_helper_mobile.dart';

class ReportHelper {
  static String _formatDate(dynamic date) {
    if (date == null) return "";
    if (date is Timestamp) return DateFormat('yyyy-MM-dd HH:mm').format(date.toDate());
    return date.toString();
  }

  static int _compareDates(dynamic a, dynamic b) {
    Timestamp? ta = a is Timestamp ? a : (a is DateTime ? Timestamp.fromDate(a) : null);
    Timestamp? tb = b is Timestamp ? b : (b is DateTime ? Timestamp.fromDate(b) : null);
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return ta.compareTo(tb);
  }

  static Future<String?> exportCombinedComprehensiveReport(String cafeId, String managerId) async {
    try {
      debugPrint("Reports: Starting Isolated Export for Cafe: $cafeId under Manager: $managerId");
      var excel = Excel.createExcel();
      String sheetName = 'التقرير الشامل';
      excel.rename(excel.getDefaultSheet()!, sheetName);
      Sheet sheet = excel[sheetName];

      // عزل البيانات بشكل صارم باستخدام cafeId
      final debtSnap = await FirebaseFirestore.instance.collection('debts')
          .where('cafeId', isEqualTo: cafeId).get();
      
      final paySnap = await FirebaseFirestore.instance.collection('payments')
          .where('cafeId', isEqualTo: cafeId).get();
          
      final expSnap = await FirebaseFirestore.instance.collection('expenses')
          .where('cafeId', isEqualTo: cafeId).get();

      final sortedPayments = paySnap.docs.toList()
        ..sort((a, b) => _compareDates(a.data()['paid_at'] ?? a.data()['date'], b.data()['paid_at'] ?? b.data()['date']));
      
      final sortedExpenses = expSnap.docs.toList()
        ..sort((a, b) => _compareDates(a.data()['date'], b.data()['date']));

      void writeCell(int col, int row, dynamic value, {bool isHeader = false}) {
        var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
        if (value is double) {
          cell.value = DoubleCellValue(value);
        } else if (value is int) {
          cell.value = IntCellValue(value);
        } else {
          cell.value = TextCellValue(value.toString());
        }
        if (isHeader) {
          cell.cellStyle = CellStyle(bold: true, horizontalAlign: HorizontalAlign.Center);
        }
      }

      int cDebt = 0;
      writeCell(cDebt, 0, "--- كشف الديون ---", isHeader: true);
      List<String> hDebt = ["اسم الزبون", "الهاتف", "الدين", "المدفوع", "الصافي"];
      for (int i = 0; i < hDebt.length; i++) writeCell(cDebt + i, 1, hDebt[i], isHeader: true);
      for (int r = 0; r < debtSnap.docs.length; r++) {
        var d = debtSnap.docs[r].data();
        double total = (d['totalDebt'] ?? 0).toDouble();
        double paid = (d['totalPaid'] ?? 0).toDouble();
        writeCell(cDebt, r + 2, d['customer'] ?? "");
        writeCell(cDebt + 1, r + 2, d['phone'] ?? "");
        writeCell(cDebt + 2, r + 2, total);
        writeCell(cDebt + 3, r + 2, paid);
        writeCell(cDebt + 4, r + 2, total - paid);
      }

      int cSales = 7;
      writeCell(cSales, 0, "--- سجل المبيعات ---", isHeader: true);
      List<String> hSales = ["التاريخ", "الطاولة", "المبلغ", "الطريقة"];
      for (int i = 0; i < hSales.length; i++) writeCell(cSales + i, 1, hSales[i], isHeader: true);
      int sRow = 2;
      for (var doc in sortedPayments) {
        var d = doc.data();
        if (d['table'] != null) {
          writeCell(cSales, sRow, _formatDate(d['paid_at'] ?? d['date']));
          writeCell(cSales + 1, sRow, d['table'].toString());
          writeCell(cSales + 2, sRow, (d['total_amount'] ?? d['amount'] ?? 0).toDouble());
          writeCell(cSales + 3, sRow, d['payment_method'] ?? d['method'] ?? "");
          sRow++;
        }
      }

      int cTrans = 12;
      writeCell(cTrans, 0, "--- سجل الحوالات ---", isHeader: true);
      List<String> hTrans = ["التاريخ", "الزبون", "المبلغ", "الطريقة", "الحالة"];
      for (int i = 0; i < hTrans.length; i++) writeCell(cTrans + i, 1, hTrans[i], isHeader: true);
      int tRow = 2;
      for (var doc in sortedPayments) {
        var d = doc.data();
        if (d['table'] == null || d['table'] == 'حوالة يدوية') {
          writeCell(cTrans, tRow, _formatDate(d['paid_at'] ?? d['date']));
          writeCell(cTrans + 1, tRow, d['customer_name'] ?? d['customer'] ?? "");
          writeCell(cTrans + 2, tRow, (d['total_amount'] ?? d['amount'] ?? 0).toDouble());
          writeCell(cTrans + 3, tRow, d['payment_method'] ?? d['method'] ?? "");
          writeCell(cTrans + 4, tRow, (d['is_received'] ?? false) ? "واصلة" : "قيد الانتظار");
          tRow++;
        }
      }

      int cExp = 19;
      writeCell(cExp, 0, "--- سجل المصاريف ---", isHeader: true);
      List<String> hExp = ["التاريخ", "البند", "المبلغ", "بواسطة"];
      for (int i = 0; i < hExp.length; i++) writeCell(cExp + i, 1, hExp[i], isHeader: true);
      for (int r = 0; r < sortedExpenses.length; r++) {
        var d = sortedExpenses[r].data();
        writeCell(cExp, r + 2, _formatDate(d['date']));
        writeCell(cExp + 1, r + 2, d['title'] ?? "");
        writeCell(cExp + 2, r + 2, (d['amount'] ?? 0).toDouble());
        writeCell(cExp + 3, r + 2, d['processedBy'] ?? "");
      }

      await _saveAndDownload(excel, "Comprehensive_Report");
      return null;
    } catch (e) {
      debugPrint("Full Report Error: $e");
      return e.toString();
    }
  }

  static Future<String?> exportDebtsToExcel(String cafeId, String managerId) async {
    try {
      var excel = Excel.createExcel();
      excel.rename(excel.getDefaultSheet()!, 'الديون');
      Sheet s = excel['الديون'];
      s.appendRow(["اسم الزبون", "الهاتف", "إجمالي الدين", "إجمالي المدفوع", "الصافي"].map((e) => TextCellValue(e)).toList());
      
      final snap = await FirebaseFirestore.instance.collection('debts')
          .where('cafeId', isEqualTo: cafeId).get();

      for (var doc in snap.docs) {
        var d = doc.data();
        double total = (d['totalDebt'] ?? 0).toDouble();
        double paid = (d['totalPaid'] ?? 0).toDouble();
        s.appendRow([TextCellValue(d['customer'] ?? ""), TextCellValue(d['phone'] ?? ""), DoubleCellValue(total), DoubleCellValue(paid), DoubleCellValue(total - paid)]);
      }
      await _saveAndDownload(excel, "Debt_Report");
      return null;
    } catch (e) { return e.toString(); }
  }

  static Future<String?> exportTransfersToExcel(String cafeId, String managerId) async {
    try {
      var excel = Excel.createExcel();
      excel.rename(excel.getDefaultSheet()!, 'الحوالات');
      Sheet s = excel['الحوالات'];
      s.appendRow(["التاريخ", "الزبون", "المبلغ", "الطريقة", "الحالة"].map((e) => TextCellValue(e)).toList());
      
      final snap = await FirebaseFirestore.instance.collection('payments')
          .where('cafeId', isEqualTo: cafeId).get();

      final sortedDocs = snap.docs.toList()
        ..sort((a, b) => _compareDates(a.data()['paid_at'] ?? a.data()['date'], b.data()['paid_at'] ?? b.data()['date']));
        
      for (var doc in sortedDocs) {
        var d = doc.data();
        if (d['table'] == null || d['table'] == 'حوالة يدوية') {
          s.appendRow([TextCellValue(_formatDate(d['paid_at'] ?? d['date'])), TextCellValue(d['customer_name'] ?? d['customer'] ?? ""), DoubleCellValue((d['total_amount'] ?? d['amount'] ?? 0).toDouble()), TextCellValue(d['payment_method'] ?? d['method'] ?? ""), TextCellValue((d['is_received'] ?? false) ? "واصلة" : "غير واصلة")]);
        }
      }
      await _saveAndDownload(excel, "Transfers_Report");
      return null;
    } catch (e) { return e.toString(); }
  }

  static Future<String?> exportFullFinancialReport(String cafeId, String managerId) async {
    try {
      var excel = Excel.createExcel();
      excel.rename(excel.getDefaultSheet()!, 'التقرير المالي');
      Sheet s = excel['التقرير المالي'];
      s.appendRow([TextCellValue("التاريخ"), TextCellValue("البيان"), TextCellValue("المبلغ")].toList());
      
      final pSnap = await FirebaseFirestore.instance.collection('payments')
          .where('cafeId', isEqualTo: cafeId).get();
      final eSnap = await FirebaseFirestore.instance.collection('expenses')
          .where('cafeId', isEqualTo: cafeId).get();
      
      List<Map<String, dynamic>> allItems = [];
      for(var doc in pSnap.docs) {
        var d = doc.data();
        if (d['table'] != null && d['table'] != 'حوالة يدوية') {
          allItems.add({
            'date': d['paid_at'] ?? d['date'],
            'title': "مبيعات: ${d['table']}",
            'amount': (d['total_amount'] ?? d['amount'] ?? 0).toDouble(),
          });
        }
      }
      for(var doc in eSnap.docs) {
        var d = doc.data();
        allItems.add({
          'date': d['date'],
          'title': "مصاريف: ${d['title'] ?? ""}",
          'amount': (d['amount'] ?? 0).toDouble(),
        });
      }
      
      allItems.sort((a, b) => _compareDates(a['date'], b['date']));

      for (var item in allItems) {
        s.appendRow([TextCellValue(_formatDate(item['date'])), TextCellValue(item['title']), DoubleCellValue(item['amount'])]);
      }
      
      await _saveAndDownload(excel, "Financial_Report");
      return null;
    } catch (e) { return e.toString(); }
  }

  static Future<void> _saveAndDownload(Excel excel, String fileNamePrefix) async {
    final dateStr = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
    final fileName = "${fileNamePrefix}_$dateStr.xlsx";
    var fileBytes = excel.save();
    if (fileBytes != null) {
      await saveAndDownloadFile(Uint8List.fromList(fileBytes), fileName);
    }
  }
}
