import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'user_model.dart'; // تأكد من استيراد موديل المستخدم الخاص بك

class ReportPage extends StatefulWidget {
  final User currentUser; // ✅ استلام المستخدم الحالي لضمان وجود cafeId
  const ReportPage({super.key, required this.currentUser});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final CollectionReference paymentsRef = FirebaseFirestore.instance.collection('payments');
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('ar', null); // تفعيل اللغة العربية للتواريخ
  }

  String formatDateWithDay(Timestamp timestamp) {
    final date = timestamp.toDate();
    final dayName = DateFormat.EEEE('ar').format(date);
    final formattedDate = DateFormat('yyyy-MM-dd', 'ar').format(date);
    return '$formattedDate - $dayName';
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final String cafeId = widget.currentUser.cafeId; // ✅ استخدام المعرف من الموديل مباشرة

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('التقارير اليومية'),
        backgroundColor: primaryColor,
        foregroundColor: theme.colorScheme.onPrimary,
        actions: [
          if (_selectedDate != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() => _selectedDate = null),
            ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () => _pickDate(context),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('cafes').doc(cafeId).snapshots(),
        builder: (context, cafeSnap) {
          String currencySymbol = "₪";
          if (cafeSnap.hasData && cafeSnap.data!.exists) {
            currencySymbol = (cafeSnap.data!.data() as Map<String, dynamic>)['currency_symbol'] ?? "₪";
          }

          return StreamBuilder<QuerySnapshot>(
            stream: paymentsRef
                .where('cafeId', isEqualTo: cafeId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('حدث خطأ: ${snapshot.error}'));
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('لا توجد مبيعات مسجلة حالياً'));

              // ترتيب البيانات يدوياً (الأحدث أولاً)
              final sortedDocs = snapshot.data!.docs.toList();
              sortedDocs.sort((a, b) {
                final dateA = (a.data() as Map)['paid_at'] as Timestamp?;
                final dateB = (b.data() as Map)['paid_at'] as Timestamp?;
                if (dateA == null || dateB == null) return 0;
                return dateB.compareTo(dateA);
              });

              // تصفية الفواتير حسب التاريخ المختار
              final payments = sortedDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                if (data['paid_at'] == null) return false;
                final paidAt = (data['paid_at'] as Timestamp).toDate();
                if (_selectedDate != null) {
                  return paidAt.year == _selectedDate!.year && paidAt.month == _selectedDate!.month && paidAt.day == _selectedDate!.day;
                }
                return true;
              }).toList();

              if (payments.isEmpty) return const Center(child: Text("لا توجد مبيعات في هذا التاريخ"));

              // تجميع الفواتير حسب اليوم
              final Map<String, List<QueryDocumentSnapshot>> groupedPayments = {};
              for (var doc in payments) {
                final data = doc.data() as Map<String, dynamic>;
                final dateKey = DateFormat('yyyy-MM-dd').format((data['paid_at'] as Timestamp).toDate());
                groupedPayments.putIfAbsent(dateKey, () => []).add(doc);
              }

              final sortedDates = groupedPayments.keys.toList()..sort((a, b) => b.compareTo(a));

              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemCount: sortedDates.length,
                itemBuilder: (context, index) {
                  final dateKey = sortedDates[index];
                  final dayPayments = groupedPayments[dateKey]!;

                  double dayTotal = 0;
                  for (var doc in dayPayments) {
                    dayTotal += ((doc.data() as Map)['total_amount'] ?? 0).toDouble();
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: ExpansionTile(
                        initiallyExpanded: _selectedDate != null,
                        title: Text(
                          formatDateWithDay((dayPayments.first.data() as Map<String, dynamic>)['paid_at']),
                          style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor),
                        ),
                        subtitle: Text(
                          'إجمالي المبيعات: ${dayTotal.toStringAsFixed(2)} $currencySymbol',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                        ),
                        children: dayPayments.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final table = data['table'] ?? 'غير معروف';
                          final total = (data['total_amount'] ?? 0).toDouble();
                          final time = DateFormat('hh:mm a').format((data['paid_at'] as Timestamp).toDate());

                          return ListTile(
                            leading: const Icon(Icons.receipt_long),
                            title: Text('طاولة: $table'),
                            subtitle: Text('الدفع: ${data['payment_method']} | $time'),
                            trailing: Text(
                              '${total.toStringAsFixed(2)} $currencySymbol',
                              style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}