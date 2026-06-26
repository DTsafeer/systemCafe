import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'MainLayout.dart';
import 'RemindersPage.dart';

class NotificationService {
  static Future<void> send({
    required String cafeId,
    required String title,
    required String body,
    required String targetRole,
  }) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'cafeId': cafeId,
      'title': title,
      'body': body,
      'targetRole': targetRole,
      'isRead': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}

class NotificationBell extends StatefulWidget {
  final String cafeId;
  final String userRole;

  static _NotificationBellState? _activeState;
  
  static void showLocalHint(String title, String body) {
    if (_activeState != null) {
      _activeState!._playNotificationSound();
      _activeState!._showWebHint(title, body);
    }
  }

  const NotificationBell({super.key, required this.cafeId, required this.userRole});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> with SingleTickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  int _lastUnreadCount = 0; 
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    NotificationBell._activeState = this;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  void _showWebHint(String title, String body) {
    if (!mounted || !kIsWeb) return;
    
    _removeOverlay();

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 320,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(55, 12),
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  alignment: Alignment.topRight,
                  child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
                );
              },
              child: _buildFancyHint(title, body),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    Future.delayed(const Duration(seconds: 8), () => _removeOverlay());
  }

  Widget _buildFancyHint(String title, String body) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange[800]!, Colors.redAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(5),
          topRight: Radius.circular(25),
          bottomLeft: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
          const BoxShadow(color: Colors.white24, blurRadius: 2, spreadRadius: 1, offset: Offset(0, -2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              GestureDetector(
                onTap: _removeOverlay,
                child: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
              )
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              body,
              style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text("انقر على الجرس للتفاصيل 🔔", style: TextStyle(color: Colors.white60, fontSize: 10)),
          )
        ],
      ),
    );
  }

  void _removeOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
  }

  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('lib/assets/audio/notification.mp3'));
      _triggerFastShake();
    } catch (e) {
      debugPrint("Sound Error: $e");
    }
  }

  void _triggerFastShake() {
    _animationController.repeat(period: const Duration(milliseconds: 100));
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        _animationController.repeat(reverse: true, period: const Duration(milliseconds: 1500));
      }
    });
  }

  Future<void> _deleteAllNotifications(List<QueryDocumentSnapshot> docs) async {
    final batch = FirebaseFirestore.instance.batch();
    for (var doc in docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  @override
  void dispose() {
    if (NotificationBell._activeState == this) NotificationBell._activeState = null;
    _removeOverlay();
    _audioPlayer.dispose();
    _animationController.dispose();
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
        if (snapshot.hasData) {
          final docs = snapshot.data!.docs;
          int currentCount = docs.length;

          if (currentCount > _lastUnreadCount) {
            final latestData = docs.isNotEmpty ? docs.first.data() as Map<String, dynamic> : null;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _playNotificationSound();
              if (kIsWeb && latestData != null) {
                _showWebHint(latestData['title'] ?? "تنبيه جديد", latestData['body'] ?? "");
              }
            });
          }
          _lastUnreadCount = currentCount;

          return CompositedTransformTarget(
            link: _layerLink,
            child: ScaleTransition(
              scale: currentCount > 0 ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      currentCount > 0 ? Icons.notifications_active : Icons.notifications_none_outlined,
                      size: 28,
                      color: currentCount > 0 ? Colors.yellowAccent : Colors.white,
                    ),
                    onPressed: () {
                      _removeOverlay();
                      final sortedDocs = docs.toList();
                      sortedDocs.sort((a, b) {
                        final t1 = (a.data() as Map)['timestamp'] as Timestamp? ?? Timestamp.now();
                        final t2 = (b.data() as Map)['timestamp'] as Timestamp? ?? Timestamp.now();
                        return t2.compareTo(t1);
                      });
                      _showNotificationsDialog(context, sortedDocs);
                    },
                  ),
                  if (currentCount > 0)
                    Positioned(
                      right: 8,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, spreadRadius: 1)],
                        ),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text(
                          '$currentCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
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
    final currentUser = UserDataProvider.of(context);
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
                  const Text("🔔 الإشعارات", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (docs.isNotEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                      onPressed: () async {
                        final List<QueryDocumentSnapshot> tempDocs = List.from(docs);
                        setDialogState(() { docs.clear(); });
                        await _deleteAllNotifications(tempDocs);
                        if (mounted) setState(() { _lastUnreadCount = 0; });
                        if (context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.delete_sweep),
                      label: const Text("حذف الكل"),
                    ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: docs.isEmpty
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.notifications_off_outlined, size: 40, color: Colors.grey),
                          const SizedBox(height: 10),
                          const Text("لا توجد إشعارات حالياً"),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => RemindersPage(currentUser: currentUser)));
                            },
                            icon: const Icon(Icons.alarm_add),
                            label: const Text("ضبط منبهات تذكيرية"),
                          )
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
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.bolt, color: Colors.orange, size: 20),
                            ),
                            title: Text(data['title'] ?? "تنبيه", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Text(data['body'] ?? "", style: const TextStyle(fontSize: 12)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.copy_all, color: Colors.blue, size: 20),
                                  onPressed: () {
                                    NotificationService.send(
                                      cafeId: widget.cafeId,
                                      title: data['title'] ?? "تنبيه",
                                      body: data['body'] ?? "",
                                      targetRole: data['targetRole'] ?? widget.userRole,
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم تكرار الإشعار")));
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                                  onPressed: () async {
                                    final String docId = docs[index].id;
                                    await FirebaseFirestore.instance.collection('notifications').doc(docId).delete();
                                    setDialogState(() { docs.removeAt(index); });
                                    if (docs.isEmpty && context.mounted) Navigator.pop(context);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => RemindersPage(currentUser: currentUser)));
                  },
                  child: const Text("إدارة المنبهات ⏰"),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("إغلاق")),
              ],
            );
          },
        );
      },
    );
  }
}
