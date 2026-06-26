import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import '../services/kitchen_service.dart';
import '../widgets/kitchen_widgets.dart';

class KitchenPage extends StatefulWidget {
  final User currentUser;
  const KitchenPage({super.key, required this.currentUser});

  @override
  State<KitchenPage> createState() => _KitchenPageState();
}

class _KitchenPageState extends State<KitchenPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String managerId = widget.currentUser.parentId ?? widget.currentUser.id;

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'kitchen',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LayoutBuilder(
          builder: (context, constraints) {
            bool isWide = constraints.maxWidth > 800;
            
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: KitchenService.streamActiveOrders(widget.currentUser.cafeId, managerId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final activeOrders = snapshot.data ?? [];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Text("طلبات المطبخ", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Chip(
                            label: Text("${activeOrders.length} طلبات نشطة"),
                            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: activeOrders.isEmpty
                        ? const Center(child: Text("لا توجد طلبات حالياً ☕", style: TextStyle(color: Colors.grey)))
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: isWide ? 400 : constraints.maxWidth,
                              mainAxisExtent: 350,
                              crossAxisSpacing: 15,
                              mainAxisSpacing: 15,
                            ),
                            itemCount: activeOrders.length,
                            itemBuilder: (context, i) => KitchenOrderCard(
                              orderId: activeOrders[i]['id'],
                              data: activeOrders[i],
                            ),
                          ),
                    ),
                  ],
                );
              },
            );
          }
        ),
      ),
    );
  }
}
