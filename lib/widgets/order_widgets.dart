import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import '../pages/user_model.dart';
import '../services/order_service.dart';
import 'app_components.dart';

class ModernTableOrderCard extends StatefulWidget {
  final String tableName;
  final List<QueryDocumentSnapshot> orders;
  final User currentUser;
  final String cafeId;
  final String currencySymbol;
  final double hourlyRate;

  const ModernTableOrderCard({
    super.key,
    required this.tableName,
    required this.orders,
    required this.currentUser,
    required this.cafeId,
    required this.currencySymbol,
    required this.hourlyRate,
  });

  @override
  State<ModernTableOrderCard> createState() => _ModernTableOrderCardState();
}

class _ModernTableOrderCardState extends State<ModernTableOrderCard> {
  double _timerPrice = 0.0;
  StreamSubscription? _tableSub;
  Timer? _refreshTimer;
  Map<String, dynamic>? _tableData;

  @override
  void initState() {
    super.initState();
    _listenToTableStatus();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) _calculateTimerPrice();
    });
  }

  void _listenToTableStatus() {
    _tableSub = FirebaseFirestore.instance
        .collection('tables')
        .where('cafe_id', isEqualTo: widget.cafeId)
        .where('name', isEqualTo: widget.tableName)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (mounted && snap.docs.isNotEmpty) {
        setState(() {
          _tableData = snap.docs.first.data();
          _calculateTimerPrice();
        });
      }
    });
  }

  void _calculateTimerPrice() {
    if (_tableData == null || widget.hourlyRate <= 0) return;
    final Timestamp? startTime = _tableData!['start_time'];
    final int accumulatedSeconds = _tableData!['accumulated_seconds'] ?? 0;
    int totalSeconds = accumulatedSeconds;
    if (startTime != null) {
      totalSeconds += DateTime.now().difference(startTime.toDate()).inSeconds;
    }
    if (mounted) {
      setState(() {
        _timerPrice = ((totalSeconds / 3600) * widget.hourlyRate).roundToDouble();
      });
    }
  }

  @override
  void dispose() {
    _tableSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double ordersTotal = 0.0;
    try {
      ordersTotal = widget.orders.fold(0.0, (sum, doc) {
        final data = doc.data() as Map<String, dynamic>?;
        return sum + (data?['total'] as num? ?? 0.0).toDouble();
      });
    } catch (e) {
      debugPrint("Error calculating orders total: $e");
    }

    double grandTotal = ordersTotal + _timerPrice;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade800,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.tableName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                          overflow: TextOverflow.ellipsis),
                      if (_timerPrice > 0.01)
                        Text("رسوم الوقت: ${_timerPrice.round()} ${widget.currencySymbol}",
                            style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
                Text("${grandTotal.round()} ${widget.currencySymbol}",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: widget.orders.length,
              itemBuilder: (context, index) {
                final order = widget.orders[index];
                final data = order.data() as Map<String, dynamic>;
                final List items = data['items'] as List? ?? [];
                final String orderId = order.id;
                final double orderTotal = (data['total'] as num? ?? 0.0).toDouble();
                final String summary = items.map((it) => "${it['quantity'] ?? 0}x ${it['name'] ?? 'صنف'}").join("، ");
                final Timestamp? ts = data['ordered_at'] as Timestamp?;
                final String timeStr = ts != null ? intl.DateFormat('hh:mm a').format(ts.toDate()) : '';

                return ListTile(
                  title: Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  subtitle: Text("بواسطة: ${data['waiter_name'] ?? '؟'} | $timeStr", style: const TextStyle(fontSize: 11)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("${orderTotal.round()} ${widget.currencySymbol}",
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.move_up_rounded, color: Colors.blue, size: 20),
                        tooltip: "نقل أصناف",
                        onPressed: () => _showTransferItemsDialog(context, orderId, items),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () => _confirmDeleteOrder(context, orderId, orderTotal, summary),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showTransferItemsDialog(BuildContext context, String orderId, List items) {
    List<Map<String, dynamic>> selectedItems = [];
    String? selectedTargetTable;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text("نقل أصناف لطاولة أخرى"),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('tables')
                        .where('cafe_id', isEqualTo: widget.cafeId)
                        .snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                      
                      final docs = snap.data!.docs;
                      final tables = docs.where((d) {
                        final data = d.data() as Map;
                        return data['name'] != widget.tableName;
                      }).toList();

                      if (tables.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text("لا توجد طاولات أخرى متاحة"),
                        );
                      }
                      
                      return DropdownButtonFormField<String>(
                        value: selectedTargetTable,
                        isExpanded: true,
                        decoration: AppComponents.fieldInput("اختر الطاولة الهدف", Icons.table_restaurant),
                        items: tables.map((t) {
                          final name = (t.data() as Map)['name'].toString();
                          return DropdownMenuItem(value: name, child: Text(name));
                        }).toList(),
                        onChanged: (v) => setDialogState(() => selectedTargetTable = v),
                      );
                    },
                  ),
                  const SizedBox(height: 15),
                  const Text("اختر الأصناف المراد نقلها:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (c, i) {
                        final item = Map<String, dynamic>.from(items[i]);
                        final String itemId = item['id'] ?? item['name'];
                        final int existingIdx = selectedItems.indexWhere((it) => (it['id'] ?? it['name']) == itemId);
                        bool isChecked = existingIdx != -1;
                        double qty = isChecked ? selectedItems[existingIdx]['quantity'] : 0.0;
                        double maxQty = (item['quantity'] as num).toDouble();

                        return CheckboxListTile(
                          title: Text(item['name']),
                          subtitle: isChecked ? Row(
                            children: [
                              IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: qty > 1 ? () => setDialogState(() {
                                selectedItems[existingIdx]['quantity'] -= 1;
                                selectedItems[existingIdx]['total'] = selectedItems[existingIdx]['quantity'] * (item['price'] as num).toDouble();
                              }) : null),
                              Text(qty.toStringAsFixed(0)),
                              IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: qty < maxQty ? () => setDialogState(() {
                                selectedItems[existingIdx]['quantity'] += 1;
                                selectedItems[existingIdx]['total'] = selectedItems[existingIdx]['quantity'] * (item['price'] as num).toDouble();
                              }) : null),
                              Text("من $maxQty"),
                            ],
                          ) : Text("الكمية: $maxQty"),
                          value: isChecked,
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                selectedItems.add({
                                  ...item,
                                  'quantity': 1.0,
                                  'total': (item['price'] as num).toDouble(),
                                });
                              } else {
                                selectedItems.removeAt(existingIdx);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ElevatedButton(
                onPressed: (selectedTargetTable != null && selectedItems.isNotEmpty) ? () async {
                  try {
                    Navigator.pop(ctx);
                    await OrderService.transferItems(
                      sourceOrderId: orderId,
                      targetTableName: selectedTargetTable!,
                      itemsToTransfer: selectedItems,
                      currentUser: widget.currentUser,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم نقل الأصناف بنجاح"), backgroundColor: Colors.green));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ خطأ: $e"), backgroundColor: Colors.red));
                  }
                } : null,
                child: const Text("تأكيد النقل"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteOrder(BuildContext context, String orderId, double amount, String summary) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 10),
              Text("تأكيد الحذف"),
            ],
          ),
          content: Text(
              "هل أنت متأكد من حذف هذا الطلب؟\nسيتم إرجاع جميع الأصناف للمخزن تلقائياً.\nالمبلغ: ${amount.round()} ${widget.currencySymbol}"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                try {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("جاري حذف الطلب وإعادة الكميات للمخزن...")),
                  );
                  await OrderService.deleteSingleOrder(
                    orderId: orderId,
                    tableName: widget.tableName,
                    amount: amount,
                    itemsSummary: summary,
                    currentUser: widget.currentUser,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("✅ تم الحذف وتحديث المخزن بنجاح"), backgroundColor: Colors.green),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("❌ خطأ أثناء الحذف: $e"), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text("حذف وإرجاع للمخزن", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
