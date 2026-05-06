import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';

// -------------------------------------------------------------------------
// 1. ويدجت عداد الوقت المستقل (تم إضافة callback لتحديث السعر في الأب)
// -------------------------------------------------------------------------
class TimerTextWidget extends StatefulWidget {
  final Timestamp? startTime;
  final int accumulatedSeconds;
  final double hourlyRate;
  final String currencySymbol;
  final Function(double) onPriceChanged; // تحديث السعر لحظياً

  const TimerTextWidget({
    super.key,
    required this.startTime,
    required this.accumulatedSeconds,
    required this.hourlyRate,
    required this.currencySymbol,
    required this.onPriceChanged,
  });

  @override
  State<TimerTextWidget> createState() => _TimerTextWidgetState();
}

class _TimerTextWidgetState extends State<TimerTextWidget> {
  Timer? _timer;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _calculate();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(_calculate);
    });
  }

  void _calculate() {
    if (widget.startTime == null) {
      _duration = Duration(seconds: widget.accumulatedSeconds);
    } else {
      _duration = DateTime.now().difference(widget.startTime!.toDate()) +
          Duration(seconds: widget.accumulatedSeconds);
    }
    // حساب السعر وإرساله للأب
    double timePrice = (_duration.inSeconds / 3600) * widget.hourlyRate;
    widget.onPriceChanged(timePrice);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timePrice = (_duration.inSeconds / 3600) * widget.hourlyRate;
    String t(int n) => n.toString().padLeft(2, '0');
    String format = '${t(_duration.inHours)}:${t(_duration.inMinutes % 60)}:${t(_duration.inSeconds % 60)}';

    return Text(
      'وقت: $format (+${timePrice.toStringAsFixed(2)} ${widget.currencySymbol})',
      style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.bold),
    );
  }
}

// -------------------------------------------------------------------------
// 2. الصفحة الرئيسية للطلبات
// -------------------------------------------------------------------------
class CurrentOrdersPage extends StatefulWidget {
  final User currentUser;
  final String? tableFilter;

  const CurrentOrdersPage({super.key, required this.currentUser, this.tableFilter});

  @override
  State<CurrentOrdersPage> createState() => _CurrentOrdersPageState();
}

class _CurrentOrdersPageState extends State<CurrentOrdersPage> {
  final CollectionReference ordersRef = FirebaseFirestore.instance.collection('orders');
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchQuery = widget.tableFilter ?? "";
    _searchController.text = _searchQuery;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.currentUser.permissions['canViewActiveOrders'] != true) {
      return Scaffold(body: const Center(child: Text("لا تملك صلاحية الوصول ❌")));
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('cafes').doc(widget.currentUser.cafeId).snapshots(),
      builder: (context, cafeSnap) {
        String currency = "₪";
        if (cafeSnap.hasData && cafeSnap.data!.exists) {
          currency = (cafeSnap.data!.data() as Map)['currency_symbol'] ?? "₪";
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.tableFilter != null ? 'حساب: ${widget.tableFilter}' : 'الطلبات الحالية'),
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'بحث باسم الطاولة...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: theme.cardColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: ordersRef.where('cafeId', isEqualTo: widget.currentUser.cafeId).where('paid', isEqualTo: false).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                    final Map<String, List<QueryDocumentSnapshot>> tablesData = {};
                    for (var d in snapshot.data!.docs) {
                      final table = (d['table'] ?? '؟').toString();
                      if (_searchQuery.isEmpty || table.contains(_searchQuery)) {
                        tablesData.putIfAbsent(table, () => []);
                        tablesData[table]!.add(d);
                      }
                    }

                    if (tablesData.isEmpty) return const Center(child: Text("لا توجد طلبات نشطة"));

                    final keys = tablesData.keys.toList();
                    return ListView.builder(
                      itemCount: keys.length,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 80),
                      itemBuilder: (context, i) => TableCard(
                        key: ValueKey(keys[i]),
                        tableName: keys[i],
                        orders: tablesData[keys[i]]!,
                        currentUser: widget.currentUser,
                        theme: theme,
                        currencySymbol: currency,
                        initiallyExpanded: widget.tableFilter == keys[i] || _searchQuery.isNotEmpty,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------------------
// 3. بطاقة الطاولة (تم إضافة طرق الدفع وجمع قيمة الوقت)
// -------------------------------------------------------------------------
class TableCard extends StatefulWidget {
  final String tableName;
  final List<QueryDocumentSnapshot> orders;
  final User currentUser;
  final bool initiallyExpanded;
  final ThemeData theme;
  final String currencySymbol;

  const TableCard({
    super.key,
    required this.tableName,
    required this.orders,
    required this.currentUser,
    required this.initiallyExpanded,
    required this.theme,
    required this.currencySymbol,
  });

  @override
  State<TableCard> createState() => _TableCardState();
}

class _TableCardState extends State<TableCard> {
  double discount = 0.0;
  double increase = 0.0;
  double currentTimePrice = 0.0; // تخزين سعر الوقت لحظياً
  String paymentMethod = 'كاش';
  final List<String> paymentOptions = ['كاش', 'بنك', 'محفظة', 'مسبق'];

  double _sD(dynamic v) => (v is num) ? v.toDouble() : (double.tryParse(v?.toString() ?? '0') ?? 0.0);

  Future<void> _deleteSingleItem(DocumentReference orderRef, Map item) async {
    final batch = FirebaseFirestore.instance.batch();
    String identifier = (item['id'] ?? item['name'] ?? '').toString();

    if (identifier.isNotEmpty) {
      batch.set(FirebaseFirestore.instance.collection('inventory').doc(identifier), {
        'quantity': FieldValue.increment(_sD(item['quantity'] ?? 1)),
      }, SetOptions(merge: true));
    }

    final doc = await orderRef.get(const GetOptions(source: Source.serverAndCache));
    if (doc.exists) {
      List items = List.from((doc.data() as Map)['items'] ?? []);
      items.removeWhere((i) => i['name'] == item['name'] && i['price'] == item['price']);
      items.isEmpty ? batch.delete(orderRef) : batch.update(orderRef, {'items': items});
    }
    batch.commit();
  }

  Future<void> _processFirestorePayment(double amount, bool closeTable) async {
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final batch = FirebaseFirestore.instance.batch();
    final String paymentId = FirebaseFirestore.instance.collection('payments').doc().id;
    List<Map<String, dynamic>> allPaymentItems = [];

    try {
      // إضافة تكلفة الوقت كبند في الفاتورة النهائية
      if (currentTimePrice > 0) {
        allPaymentItems.add({
          'name': 'رسوم وقت الطاولة',
          'quantity': 1,
          'price': double.parse(currentTimePrice.toStringAsFixed(2)),
        });
      }

      for (var o in widget.orders) {
        batch.update(o.reference, {'paid': true, 'paid_at': FieldValue.serverTimestamp()});
        final data = o.data() as Map<String, dynamic>;
        for (var item in (data['items'] as List? ?? [])) {
          String id = (item['id'] ?? item['name'] ?? '').toString();
          allPaymentItems.add({
            'name': item['name'],
            'quantity': _sD(item['quantity']),
            'price': _sD(item['price']),
          });
          batch.set(FirebaseFirestore.instance.collection('inventory').doc(id), {
            'quantity': FieldValue.increment(-_sD(item['quantity'] ?? 1)),
          }, SetOptions(merge: true));
        }
      }

      batch.set(FirebaseFirestore.instance.collection('payments').doc(paymentId), {
        'payment_id': paymentId,
        'cafeId': widget.currentUser.cafeId,
        'table': widget.tableName,
        'total_amount': double.parse(amount.toStringAsFixed(2)),
        'items': allPaymentItems,
        'payment_method': paymentMethod,
        'processed_by': widget.currentUser.name,
        'paid_at': FieldValue.serverTimestamp(),
        'day': DateTime.now().day,
        'month': DateTime.now().month,
        'year': DateTime.now().year,
      });

      if (closeTable) _closeTableOffline();

      await batch.commit();

      if (mounted) {
        navigator.pop();
        scaffoldMessenger.showSnackBar(const SnackBar(content: Text("تم الدفع بنجاح ✅"), backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint("Payment Error: $e");
    }
  }

  void _closeTableOffline() {
    FirebaseFirestore.instance.collection('tables')
        .where('cafe_id', isEqualTo: widget.currentUser.cafeId)
        .where('name', isEqualTo: widget.tableName).limit(1).get()
        .then((q) {
      if (q.docs.isNotEmpty) q.docs.first.reference.update({'is_open': false, 'start_time': null, 'accumulated_seconds': 0});
    });
  }

  @override
  Widget build(BuildContext context) {
    double ordersTotal = 0;
    List<Widget> itemsWidgets = [];

    for (var o in widget.orders) {
      for (var item in ((o.data() as Map)['items'] as List? ?? [])) {
        double p = _sD(item['price']);
        int q = _sD(item['quantity']).toInt();
        ordersTotal += (p * q);

        itemsWidgets.add(ListTile(
          dense: true,
          title: Text("${item['name']} × $q", style: const TextStyle(fontWeight: FontWeight.bold)),
          trailing: IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
            onPressed: () => _deleteSingleItem(o.reference, item),
          ),
        ));
      }
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('cafes').doc(widget.currentUser.cafeId).snapshots(),
      builder: (context, cafeSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('tables')
              .where('cafe_id', isEqualTo: widget.currentUser.cafeId)
              .where('name', isEqualTo: widget.tableName).limit(1).snapshots(),
          builder: (context, tableSnap) {
            double hourlyRate = 0;
            bool isOpen = false;
            Timestamp? start;
            int acc = 0;

            if (cafeSnap.hasData) hourlyRate = _sD((cafeSnap.data!.data() as Map?)?['hourly_rate']);
            if (tableSnap.hasData && tableSnap.data!.docs.isNotEmpty) {
              var d = tableSnap.data!.docs.first.data() as Map;
              isOpen = d['is_open'] ?? false;
              start = d['start_time'];
              acc = d['accumulated_seconds'] ?? 0;
            }

            // المجموع = (الطلبات + سعر الوقت) - الخصم + الزيادة
            double totalFinal = (ordersTotal + currentTimePrice - discount + increase).clamp(0.0, 999999.0);

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: ExpansionTile(
                initiallyExpanded: widget.initiallyExpanded,
                title: Text('طاولة: ${widget.tableName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isOpen) TimerTextWidget(
                      startTime: start,
                      accumulatedSeconds: acc,
                      hourlyRate: hourlyRate,
                      currencySymbol: widget.currencySymbol,
                      onPriceChanged: (price) {
                        if (currentTimePrice != price) {
                          Future.delayed(Duration.zero, () {
                            if (mounted) setState(() => currentTimePrice = price);
                          });
                        }
                      },
                    ),
                    Text('إجمالي الفاتورة: ${totalFinal.toStringAsFixed(2)} ${widget.currencySymbol}',
                        style: TextStyle(color: widget.theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                  ],
                ),
                children: [
                  ...itemsWidgets,
                  const Divider(),
                  // واجهة اختيار طرق الدفع
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      children: paymentOptions.map((option) => ChoiceChip(
                        label: Text(option, style: TextStyle(color: paymentMethod == option ? Colors.white : Colors.black, fontSize: 12)),
                        selected: paymentMethod == option,
                        selectedColor: widget.theme.colorScheme.primary,
                        onSelected: (s) => setState(() => paymentMethod = option),
                      )).toList(),
                    ),
                  ),
                  _paymentUI(totalFinal),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _paymentUI(double total) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _counter("خصم (-)", discount, (v) => setState(() => discount = v)),
              _counter("زيادة (+)", increase, (v) => setState(() => increase = v)),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            ),
            onPressed: () => _confirmPayment(total),
            child: Text('إتمام الدفع ($paymentMethod)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _counter(String l, double v, Function(double) onC) => Column(children: [
    Text(l, style: const TextStyle(fontSize: 11)),
    Row(children: [
      IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => onC((v - 1).clamp(0, 999))),
      Text(v.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: () => onC(v + 1)),
    ])
  ]);

  void _confirmPayment(double total) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('تأكيد الدفع 💰'),
      content: Text('المبلغ: ${total.toStringAsFixed(2)} ${widget.currencySymbol}\nطريقة الدفع: $paymentMethod\n\nهل تريد إغلاق الطاولة وتصفير الوقت؟'),
      actions: [
        TextButton(onPressed: () { Navigator.pop(ctx); _processFirestorePayment(total, false); }, child: const Text('دفع فقط')),
        ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () { Navigator.pop(ctx); _processFirestorePayment(total, true); },
            child: const Text('دفع وإغلاق', style: TextStyle(color: Colors.white))
        ),
      ],
    ));
  }
}