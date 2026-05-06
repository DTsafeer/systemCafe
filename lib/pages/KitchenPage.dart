import 'dart:async'; // ✅ إضافة هذا الاستيراد
import 'dart:io';    // ✅ إضافة هذا الاستيراد
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'NotificationService.dart';
import 'user_model.dart';

enum OrderKitchenStatus { pending, preparing, ready, delivered }

class KitchenPage extends StatefulWidget {
  final User currentUser;
  const KitchenPage({super.key, required this.currentUser});

  @override
  State<KitchenPage> createState() => _KitchenPageState();
}

class _KitchenPageState extends State<KitchenPage> {
  final CollectionReference ordersRef = FirebaseFirestore.instance.collection('orders');
  bool _isOffline = false; // ✅ متغير تتبع حالة الإنترنت

  @override
  void initState() {
    super.initState();
    _checkInternet(); // ✅ فحص أولي عند الفتح
    // ✅ فحص دوري كل 5 ثوانٍ لتحديث الحالة
    Timer.periodic(const Duration(seconds: 5), (t) => _checkInternet());
  }

  // ✅ دالة فحص اتصال الإنترنت
  Future<void> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      if (mounted) setState(() => _isOffline = result.isEmpty);
    } catch (_) {
      if (mounted) setState(() => _isOffline = true);
    }
  }

  Future<void> _updateOrderStatus(String orderId, OrderKitchenStatus newStatus, String tableName) async {
    // ✅ إزالة await للسماح بالتحديث المحلي الفوري (Offline Support)
    ordersRef.doc(orderId).update({
      'kitchen_status': newStatus.name,
    });

    if (newStatus == OrderKitchenStatus.ready) {
      _sendNotificationToWaiter(tableName);
    }
  }

  Future<void> _sendNotificationToWaiter(String tableName) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'cafeId': widget.currentUser.cafeId,
      'title': '🔔 طلب جاهز: $tableName',
      'body': 'تم تجهيز الطلبات الخاصة بطاولة $tableName',
      'targetRole': 'waiter',
      'isRead': false,
      'senderName': widget.currentUser.name,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  OrderKitchenStatus _getStatusFromString(String? status) {
    if (status == null) return OrderKitchenStatus.pending;
    return OrderKitchenStatus.values.firstWhere(
          (e) => e.name == status,
      orElse: () => OrderKitchenStatus.pending,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    if (!widget.currentUser.isActive || !widget.currentUser.canViewKitchen) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('شاشة المطبخ'),
          backgroundColor: Colors.grey,
          centerTitle: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_person_rounded, size: 80, color: Colors.redAccent),
              const SizedBox(height: 20),
              Text(
                !widget.currentUser.isActive
                    ? "عذراً، هذا الحساب معطل حالياً ❌"
                    : "غير مصرح لك بدخول المطبخ 🔒",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 10),
              const Text("يرجى مراجعة المسؤول للحصول على الصلاحيات",
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          actions: [
            NotificationBell(
                cafeId: widget.currentUser.cafeId,
                userRole: 'kitchen'
            ),
          ],
          // ✅ إضافة حالة الأوفلاين في العنوان
          title: Column(
            children: [
              const Text('المطبخ الذكي (KDS)'),
              if (_isOffline)
                const Text("وضع الأوفلاين نشط ⚠️", style: TextStyle(fontSize: 10, color: Colors.orangeAccent)),
            ],
          ),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          centerTitle: true,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            tabs: [
              Tab(text: 'إنتظار', icon: Icon(Icons.timer_outlined)),
              Tab(text: 'تحضير', icon: Icon(Icons.soup_kitchen_outlined)),
              Tab(text: 'جاهز', icon: Icon(Icons.done_all_outlined)),
            ],
          ),
        ),
        body: Column( // ✅ تغليف الـ View بـ Column لإضافة شريط تنبيه الأوفلاين
          children: [
            if (_isOffline)
              Container(
                width: double.infinity,
                color: Colors.orangeAccent,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: const Text(
                  "لن تصل طلبات جديدة حتى يتوفر الإنترنت 📶",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: ordersRef
                    .where('cafeId', isEqualTo: widget.currentUser.cafeId)
                    .where('paid', isEqualTo: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting)
                    return const Center(child: CircularProgressIndicator());

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                    return const Center(child: Text("لا توجد طلبات نشطة لهذا الكافيه."));

                  final docs = snapshot.data!.docs.toList();
                  docs.sort((a, b) {
                    final dateA = (a.data() as Map)['ordered_at'] as Timestamp?;
                    final dateB = (b.data() as Map)['ordered_at'] as Timestamp?;
                    if (dateA == null || dateB == null) return 0;
                    return dateB.compareTo(dateA);
                  });

                  final pending = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final s = data['kitchen_status'] ?? 'pending';
                    return _getStatusFromString(s) == OrderKitchenStatus.pending;
                  }).toList();

                  final preparing = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final s = data['kitchen_status'] ?? '';
                    return _getStatusFromString(s) == OrderKitchenStatus.preparing;
                  }).toList();

                  final ready = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final s = data['kitchen_status'] ?? '';
                    return _getStatusFromString(s) == OrderKitchenStatus.ready;
                  }).toList();

                  return TabBarView(
                    children: [
                      _buildOrdersList(pending, OrderKitchenStatus.pending, theme),
                      _buildOrdersList(preparing, OrderKitchenStatus.preparing, theme),
                      _buildOrdersList(ready, OrderKitchenStatus.ready, theme),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersList(List<QueryDocumentSnapshot> orders, OrderKitchenStatus status, ThemeData theme) {
    final ordersWithKitchenItems = orders.where((order) {
      final data = order.data() as Map<String, dynamic>;
      final List items = data['items'] ?? [];
      return items.any((item) => item['toKitchen'] == true);
    }).toList();

    if (ordersWithKitchenItems.isEmpty) {
      return const Center(child: Text("القائمة فارغة"));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: ordersWithKitchenItems.length,
      itemBuilder: (context, index) {
        final order = ordersWithKitchenItems[index];
        final data = order.data() as Map<String, dynamic>;

        return OrderCard(
          key: ValueKey(order.id),
          items: data['items'] ?? [],
          tableName: data['table'] ?? 'N/A',
          orderedAt: data['ordered_at'],
          currentStatus: status,
          onUpdateStatus: (newStatus) => _updateOrderStatus(order.id, newStatus, data['table'] ?? 'N/A'),
          theme: theme,
        );
      },
    );
  }
}

// OrderCard و ModernProductCard تبقى كما هي تماماً دون تغيير
class OrderCard extends StatelessWidget {
  final List items;
  final String tableName;
  final Timestamp? orderedAt;
  final OrderKitchenStatus currentStatus;
  final Function(OrderKitchenStatus) onUpdateStatus;
  final ThemeData theme;

  const OrderCard({
    super.key,
    required this.items,
    required this.tableName,
    required this.orderedAt,
    required this.currentStatus,
    required this.onUpdateStatus,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final String timeStr = orderedAt != null ? DateFormat('hh:mm a').format(orderedAt!.toDate()) : '--:--';

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.table_restaurant_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'طاولة: $tableName',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _showCancelDialog(context),
                      icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 24),
                      tooltip: 'إلغاء الطلب',
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeStr,
                      style: TextStyle(color: theme.disabledColor, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...items.where((item) => item['toKitchen'] == true).map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text("${item['quantity']}x",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['name'],
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 18)),
                            if (item['note'] != null &&
                                item['note'].toString().isNotEmpty)
                              Text("💡 ${item['note']}",
                                  style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
                const Divider(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _buildStatusButtons(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStatusButtons() {
    switch (currentStatus) {
      case OrderKitchenStatus.pending:
        return [
          _mainBtn('ابدأ التحضير', Icons.play_arrow, Colors.orange, () => onUpdateStatus(OrderKitchenStatus.preparing)),
        ];
      case OrderKitchenStatus.preparing:
        return [
          _mainBtn('إرجاع', Icons.undo, Colors.grey, () => onUpdateStatus(OrderKitchenStatus.pending)),
          const SizedBox(width: 10),
          _mainBtn('جاهز الآن', Icons.check, Colors.green, () => onUpdateStatus(OrderKitchenStatus.ready)),
        ];
      case OrderKitchenStatus.ready:
        return [
          _mainBtn('رجوع للتحضير', Icons.history, Colors.grey, () => onUpdateStatus(OrderKitchenStatus.preparing)),
          const SizedBox(width: 10),
          _mainBtn('تم التسليم ✅', Icons.done_all, theme.colorScheme.primary, () => onUpdateStatus(OrderKitchenStatus.delivered)),
        ];
      default:
        return [];
    }
  }

  Widget _mainBtn(String label, IconData icon, Color color, VoidCallback? onTap) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  void _showCancelDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("تنبيه"),
        content: const Text("هل تريد إلغاء هذا الطلب وإخفاءه من المطبخ؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("تراجع")),
          ElevatedButton(
            onPressed: () {
              onUpdateStatus(OrderKitchenStatus.delivered);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("نعم، إلغاء", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}