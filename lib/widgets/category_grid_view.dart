import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CategoryGridView extends StatelessWidget {
  final String category;
  final List<QueryDocumentSnapshot> allDocs;
  final ValueNotifier<String> searchNotifier;
  final ValueNotifier<Map<String, Map<String, dynamic>>> cartNotifier;
  final ValueNotifier<Map<String, double>> inventoryNotifier;
  final Function(String, Map<String, dynamic>, double) onProductTap;
  final Function(String, Map<String, dynamic>) onProductLongPress;

  const CategoryGridView({
    super.key,
    required this.category,
    required this.allDocs,
    required this.searchNotifier,
    required this.cartNotifier,
    required this.inventoryNotifier,
    required this.onProductTap,
    required this.onProductLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: searchNotifier,
      builder: (context, query, _) {
        final filtered = allDocs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final nameMatch = data['name'].toString().toLowerCase().contains(query.toLowerCase());
          final categoryMatch = category == "الكل" || data['category'] == category;
          return nameMatch && categoryMatch;
        }).toList();

        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            childAspectRatio: 0.8,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, i) {
            final data = filtered[i].data() as Map<String, dynamic>;
            final id = filtered[i].id;
            return ListenableBuilder(
              listenable: Listenable.merge([cartNotifier, inventoryNotifier]),
              builder: (context, _) {
                final double currentQty = (cartNotifier.value[id]?['quantity'] ?? 0).toDouble();
                return GestureDetector(
                  onTap: () => onProductTap(id, data, currentQty + 1),
                  onLongPress: () => onProductLongPress(id, data),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                                child: (data['imagePath'] != null && data['imagePath'].isNotEmpty)
                                    ? Image.network(data['imagePath'], fit: BoxFit.cover)
                                    : Container(
                                        color: Colors.grey[100],
                                        child: const Icon(Icons.fastfood, size: 40, color: Colors.grey),
                                      ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                children: [
                                  Text(
                                    data['name'],
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${data['price']} ₪",
                                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (currentQty > 0)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.blue[900],
                              child: Text(
                                "${currentQty.toInt()}",
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
