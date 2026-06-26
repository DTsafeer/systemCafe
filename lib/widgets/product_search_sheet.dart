import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProductSearchSheet extends StatelessWidget {
  final String activeCafeId;
  final String managerId;
  final Function(String id, String name, double quantity, String unit) onItemSelected;

  const ProductSearchSheet({
    super.key,
    required this.activeCafeId,
    required this.managerId,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      builder: (context, scrollController) => StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('inventory')
            .where('cafeId', isEqualTo: activeCafeId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text("خطأ: ${snap.error}"));
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allItems = snap.data?.docs ?? [];
          final items = allItems.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['parentId'] == managerId;
          }).toList();

          if (items.isEmpty) {
            return const Center(child: Text("لا توجد أصناف في المخزن الرئيسي"));
          }

          return ListView.builder(
            controller: scrollController,
            itemCount: items.length,
            itemBuilder: (context, i) {
              final data = items[i].data() as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(data['name']),
                subtitle: Text("المتوفر حالياً: ${data['quantity']} ${data['unit']}"),
                onTap: () {
                  onItemSelected(
                    items[i].id,
                    data['name'],
                    (data['quantity'] ?? 0.0).toDouble(),
                    data['unit'] ?? '',
                  );
                  Navigator.pop(context);
                },
              );
            },
          );
        },
      ),
    );
  }
}
