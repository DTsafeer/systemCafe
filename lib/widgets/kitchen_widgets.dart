import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/kitchen_service.dart';

class KitchenOrderCard extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> data;

  const KitchenOrderCard({super.key, required this.orderId, required this.data});

  void _confirmCancel(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text("إلغاء الطلب"),
          content: const Text("هل تريد إلغاء هذا الطلب وحذفه نهائياً من الطاولة؟"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("تراجع")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                KitchenService.deleteOrder(orderId);
                Navigator.pop(ctx);
              },
              child: const Text("نعم، إلغاء", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    List items = data['items'] ?? [];
    String status = data['kitchen_status'] ?? 'pending';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: status == 'preparing' ? Colors.orange : theme.colorScheme.primary,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("طاولة ${data['table']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.cancel_outlined, color: Colors.white70, size: 20),
                  onPressed: () => _confirmCancel(context),
                  tooltip: "إلغاء الطلب",
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) => ListTile(
                dense: true,
                leading: CircleAvatar(radius: 12, child: Text("${items[i]['quantity']}")),
                title: Text(items[i]['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => KitchenService.updateOrderStatus(orderId, status),
                style: ElevatedButton.styleFrom(
                  backgroundColor: status == 'preparing' ? Colors.green : Colors.orangeAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(status == 'pending' ? "بدء التحضير" : "تم التجهيز"),
              ),
            ),
          )
        ],
      ),
    );
  }
}
