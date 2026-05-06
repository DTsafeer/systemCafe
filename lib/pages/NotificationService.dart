import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';

class NotificationBell extends StatefulWidget {
  final String cafeId;
  final String userRole;

  const NotificationBell({super.key, required this.cafeId, required this.userRole});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  int _lastUnreadCount = 0;

  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('audio/notification.mp3'));
    } catch (e) {
      debugPrint("خطأ في تشغيل صوت الإشعار: $e");
    }
  }

  // ✅ دالة لحذف جميع الإشعارات نهائياً بدلاً من مجرد القراءة
  Future<void> _deleteAllNotifications(List<QueryDocumentSnapshot> docs) async {
    final batch = FirebaseFirestore.instance.batch();
    for (var doc in docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('cafeId', isEqualTo: widget.cafeId)
          .where('targetRole', isEqualTo: widget.userRole)
          .where('isRead', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _lastUnreadCount == 0) {
          return const IconButton(
            icon: Icon(Icons.notifications_none_outlined, size: 28, color: Colors.white54),
            onPressed: null,
          );
        }

        if (snapshot.hasData) {
          final docs = snapshot.data!.docs;
          int currentCount = docs.length;

          if (currentCount > _lastUnreadCount) {
            _playNotificationSound();
          }
          _lastUnreadCount = currentCount;

          return Stack(
            alignment: Alignment.center,
            key: ValueKey('bell_$currentCount'),
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none_outlined, size: 28, color: Colors.white),
                onPressed: currentCount > 0
                    ? () {
                  final sortedDocs = docs.toList();
                  sortedDocs.sort((a, b) {
                    final t1 = (a.data() as Map)['timestamp'] as Timestamp? ?? Timestamp.now();
                    final t2 = (b.data() as Map)['timestamp'] as Timestamp? ?? Timestamp.now();
                    return t2.compareTo(t1);
                  });
                  _showNotificationsDialog(context, sortedDocs);
                }
                    : null,
              ),
              if (currentCount > 0)
                Positioned(
                  right: 8,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      '$currentCount',
                      key: ValueKey('count_$currentCount'),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          );
        }
        return const IconButton(
          icon: Icon(Icons.notifications_none_outlined, size: 28, color: Colors.white54),
          onPressed: null,
        );
      },
    );
  }

  void _showNotificationsDialog(BuildContext context, List<QueryDocumentSnapshot> docs) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("🔔 الإشعارات", style: TextStyle(fontSize: 18)),
                  if (docs.isNotEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                      onPressed: () async {
                        // 1. نسخ القائمة قبل الحذف لتجنب مشاكل المزامنة
                        final List<QueryDocumentSnapshot> tempDocs = List.from(docs);

                        // 2. تحديث الواجهة المحلية فوراً
                        setDialogState(() {
                          docs.clear();
                        });

                        // 3. الحذف من قاعدة البيانات
                        await _deleteAllNotifications(tempDocs);

                        // 4. تحديث العداد الرئيسي في الصفحة
                        if (mounted) {
                          setState(() {
                            _lastUnreadCount = 0;
                          });
                        }

                        // 5. إغلاق النافذة مع رسالة تأكيد
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("تم حذف جميع الإشعارات بنجاح ✅"), behavior: SnackBarBehavior.floating),
                          );
                        }
                      },
                      icon: const Icon(Icons.delete_sweep),
                      label: const Text("حذف الكل", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: docs.isEmpty
                    ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_off_outlined, size: 40, color: Colors.grey),
                    SizedBox(height: 10),
                    Text("لا توجد إشعارات حالياً"),
                  ],
                )
                    : ListView.separated(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.info_outline, color: Colors.orange),
                      title: Text(data['title'] ?? "تنبيه", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(data['body'] ?? "", style: const TextStyle(fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.done, color: Colors.green),
                        onPressed: () async {
                          final String docId = docs[index].id;
                          await FirebaseFirestore.instance.collection('notifications').doc(docId).delete();
                          setDialogState(() {
                            docs.removeAt(index);
                          });
                          if (docs.isEmpty && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("إغلاق"),
                ),
              ],
            );
          },
        );
      },
    );
  }
}