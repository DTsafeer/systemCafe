import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'DashboardPage.dart';
import 'InventoryPage.dart';
import 'KitchenPage.dart';
import 'NotificationService.dart';
import 'user_model.dart';
import 'user_database.dart';
import 'LoginPage.dart';
import 'ProfilePage.dart';
import 'SettingsPage.dart';
import 'UserManagementPage.dart';
import 'orderpage.dart';
import 'addproduct.dart';
import 'ReportPage.dart';
import 'CurrentOrdersPage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class Homepage extends StatefulWidget {
  final User currentUser;
  final String? tableFilter;

  const Homepage({super.key, required this.currentUser, this.tableFilter});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> with WidgetsBindingObserver {
  TextEditingController searchController = TextEditingController();
  List<Map<String, dynamic>> tables = [];
  bool _isOffline = false;
  List<Map<String, dynamic>> filteredTables = [];

  // ✅ تحسين: إزالة التايمر من الهوم بيج لأنه يسبب ثقل عند إعادة بناء كل العناصر
  // التايمر الآن موجود داخل كل بطاقة طاولة بشكل مستقل

  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  String cafeName = "جاري التحميل...";
  String currencySymbol = "₪";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UserDatabase.updateOnlineStatus(widget.currentUser.id, true);

    _listenToSessionSecurity();

    _scrollController.addListener(() {
      if (mounted)
        setState(() => _showBackToTop = _scrollController.offset > 300);
    });

    _checkInternet();
    Timer.periodic(const Duration(seconds: 10), (t) => _checkInternet());

    _listenToTables();
    _listenToCafeSettings();

    searchController.addListener(() => _applySearch());
  }

  static Future<void> updateFcmToken(String userId) async {
    String? token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'fcmToken': token,
      });
    }
  }

  Future<void> _logAction(String action, String details) async {
    if (!mounted) return;
    try {
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'cafeId': widget.currentUser.cafeId,
        'userName': widget.currentUser.name,
        'action': action,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error logging action: $e");
    }
  }

  void _listenToSessionSecurity() {
    FirebaseFirestore.instance
        .collection('users')
        .doc(widget.currentUser.id)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.exists && mounted) {
        final userData = snapshot.data() as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        String? localToken = prefs.getString('session_token');
        String? serverToken = userData['currentSessionToken'];
        bool isActiveOnServer = userData['isOnline'] ?? false;

        if (localToken != null && serverToken != null && localToken != serverToken) {
          _handleForceLogout("تم تسجيل الخروج");
        } else if (!isActiveOnServer) {
          _handleForceLogout("انتهت صلاحية الجلسة الحالية.");
        }
      }
    });
  }

  void _handleForceLogout(String message) async {
    await UserDatabase.updateOnlineStatus(widget.currentUser.id, false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_email');
    await prefs.remove('session_password');
    await prefs.remove('current_session_token');

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, textAlign: TextAlign.center),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _listenToCafeSettings() {
    FirebaseFirestore.instance
        .collection('cafes')
        .doc(widget.currentUser.cafeId)
        .snapshots()
        .listen((doc) {
      if (doc.exists && doc.data() != null && mounted) {
        setState(() {
          cafeName = doc.data()!['cafe_name'] ?? "اسم الكافيه";
          currencySymbol = doc.data()!['currency_symbol'] ?? "₪";
        });
      }
    });
  }

  void _listenToTables() {
    String cafeId = widget.currentUser.cafeId;
    FirebaseFirestore.instance
        .collection('tables')
        .where('cafe_id', isEqualTo: cafeId)
        .snapshots()
        .listen(
          (snapshot) {
        if (!mounted) return;

        DateTime? safeToDateTime(dynamic value) {
          if (value is Timestamp) return value.toDate();
          return null;
        }

        List<Map<String, dynamic>> fetchedTables = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'name': data['name'] ?? 'بدون اسم',
            'is_open': data['is_open'] ?? false,
            'start_time': safeToDateTime(data['start_time']),
            'expiry_time': safeToDateTime(data['expiry_time']),
            'accumulated_seconds': data['accumulated_seconds'] ?? 0,
            'created_at': data['created_at'],
          };
        }).toList();

        fetchedTables.sort((a, b) {
          if (a['is_open'] != b['is_open']) return a['is_open'] ? -1 : 1;
          var dateA = a['created_at'] as Timestamp?;
          var dateB = b['created_at'] as Timestamp?;
          if (dateA == null || dateB == null) return 0;
          return dateB.compareTo(dateA);
        });

        setState(() {
          tables = fetchedTables;
          _applySearch();
        });
      },
      onError: (error) {
        print("خطأ في جلب الطاولات: $error");
      },
    );
  }

  void _applySearch() {
    final q = searchController.text.toLowerCase();
    setState(() {
      filteredTables = tables
          .where((t) => t['name'].toString().toLowerCase().contains(q))
          .toList();
    });
  }

  // --- بقية الدوال (addTable, editTable, delete, reset, close) تبقى كما هي بالملي ---
  // (قمت باختصارها هنا لعدم الإطالة ولكنها يجب أن تظل في الكود الخاص بك)

  void addTable() async {
    final String cafeId = widget.currentUser.cafeId;
    final c = TextEditingController();
    bool isOpening = false;
    TimeOfDay? pickedStartTime;
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: theme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            title: Row(
              children: [
                Icon(Icons.add_business_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                const Text('إضافة طاولة جديدة'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: c,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'اسم الطاولة',
                      prefixIcon: Icon(Icons.table_bar, color: theme.colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: const Text('فتح الطاولة فوراً؟'),
                    secondary: Icon(
                      Icons.play_circle_fill,
                      color: isOpening ? Colors.green : Colors.grey,
                    ),
                    value: isOpening,
                    onChanged: (v) => setDialogState(() {
                      isOpening = v;
                      if (!v) pickedStartTime = null;
                    }),
                  ),
                  if (isOpening) ...[
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        Icons.access_time,
                        color: pickedStartTime != null ? Colors.orange : Colors.grey,
                      ),
                      title: const Text("تحديد وقت البدء يدوياً", style: TextStyle(fontSize: 14)),
                      subtitle: Text(
                        pickedStartTime == null
                            ? "سيبدأ التايمر من 00:00:00"
                            : "سيبدأ من الساعة: ${pickedStartTime!.format(context)}",
                      ),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (time != null) setDialogState(() => pickedStartTime = time);
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () async {
                  final String tableName = c.text.trim();
                  if (tableName.isEmpty) return;

                  DateTime now = DateTime.now();
                  DateTime? finalStartTime;
                  String logDetails;

                  if (isOpening) {
                    if (pickedStartTime != null) {
                      finalStartTime = DateTime(now.year, now.month, now.day, pickedStartTime!.hour, pickedStartTime!.minute);
                      logDetails = "قام بإضافة وفتح طاولة '$tableName' مع بدء التوقيت يدوياً.";
                    } else {
                      finalStartTime = null;
                      logDetails = "قام بإضافة وفتح طاولة '$tableName' مع تايمر يبدأ من الصفر.";
                    }
                  } else {
                    finalStartTime = null;
                    logDetails = "قام بإضافة طاولة جديدة (مغلقة) باسم: '$tableName'.";
                  }

                  await FirebaseFirestore.instance.collection('tables').add({
                    'cafe_id': cafeId,
                    'name': tableName,
                    'is_open': isOpening,
                    'start_time': finalStartTime,
                    'accumulated_seconds': 0,
                    'expiry_time': null,
                    'created_at': FieldValue.serverTimestamp(),
                  });

                  await FirebaseFirestore.instance.collection('activity_logs').add({
                    'cafeId': widget.currentUser.cafeId,
                    'userName': widget.currentUser.name,
                    'action': "إضافة طاولة",
                    'details': logDetails,
                    'timestamp': FieldValue.serverTimestamp(),
                  });

                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('حفظ وإضافة'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditTableDialog(String id, String currentName) {
    final editController = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل اسم الطاولة'),
        content: TextField(controller: editController, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final newName = editController.text.trim();
              if (newName.isEmpty || newName == currentName) return;
              await FirebaseFirestore.instance.collection('tables').doc(id).update({'name': newName});
              await _logAction("تعديل طاولة", "تغيير اسم الطاولة من '$currentName' إلى '$newName'");
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الطاولة؟'),
        content: Text('هل أنت متأكد من حذف "$name"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('tables').doc(id).delete();
              await _logAction("حذف طاولة", "قام بحذف الطاولة: '$name'");
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmReset(String id, String tableName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تصفير الوقت'),
        content: const Text('هل تريد إعادة عداد الوقت للصفر؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('tables').doc(id).update({
                'start_time': null,
                'accumulated_seconds': 0,
                'expiry_time': null,
              });
              await _logAction("تصفير عداد", "تصفير عداد وقت الطاولة: '$tableName'");
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('تصفير'),
          ),
        ],
      ),
    );
  }

  Future<void> _closeTableWithCheck(String tableId, String tableName) async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection('orders')
        .where('cafeId', isEqualTo: widget.currentUser.cafeId)
        .where('table', isEqualTo: tableName)
        .where('paid', isEqualTo: false)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تنبيه: طلبات نشطة'),
          content: Text('الطاولة "$tableName" بها طلبات غير مدفوعة.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => CurrentOrdersPage(currentUser: widget.currentUser, tableFilter: tableName)));
              },
              child: const Text('عرض الطلبات'),
            ),
          ],
        ),
      );
    } else {
      FirebaseFirestore.instance.collection('tables').doc(tableId).update({
        'is_open': false,
        'start_time': null,
        'accumulated_seconds': 0,
        'expiry_time': null,
      });
    }
  }

  void _scrollToTop() => _scrollController.animateTo(0, duration: const Duration(milliseconds: 600), curve: Curves.fastOutSlowIn);
  void _scrollToBottom() => _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 600), curve: Curves.fastOutSlowIn);

  Future<void> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      if (mounted) setState(() => _isOffline = result.isEmpty || result[0].rawAddress.isEmpty);
    } catch (_) {
      if (mounted) setState(() => _isOffline = true);
    }
  }

  @override
  void dispose() {
    UserDatabase.updateOnlineStatus(widget.currentUser.id, false);
    WidgetsBinding.instance.removeObserver(this);
    searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(widget.currentUser.id).snapshots(),
      builder: (context, userSnap) {
        User liveUser = widget.currentUser;
        if (userSnap.hasData && userSnap.data!.exists) {
          final userData = userSnap.data!.data() as Map<String, dynamic>;
          if (userData['isActive'] == false) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _handleForceLogout("حساب الموظف غير نشط"));
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          liveUser = User.fromMap(userData, userSnap.data!.id);
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('cafes').doc(liveUser.cafeId).snapshots(),
          builder: (context, cafeSnap) {
            if (cafeSnap.hasData && cafeSnap.data!.exists) {
              final cafeData = cafeSnap.data!.data() as Map<String, dynamic>;
              if (!(cafeData['isActive'] ?? false)) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _handleForceLogout("تم إيقاف صلاحية المنشأة"));
              }
            }

            return Scaffold(
              backgroundColor: theme.scaffoldBackgroundColor,
              appBar: AppBar(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cafeName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('أهلاً، ${liveUser.name}', style: const TextStyle(fontSize: 12)),
                  ],
                ),
                actions: [
                  NotificationBell(cafeId: widget.currentUser.cafeId, userRole: widget.currentUser.role.name),
                  if (liveUser.canViewDashboard) IconButton(icon: const Icon(Icons.dashboard), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DashboardPage(currentUser: liveUser)))),
                  if (liveUser.canViewInventory) IconButton(icon: const Icon(Icons.inventory_2_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InventoryPage(currentUser: liveUser)))),
                  IconButton(icon: const Icon(Icons.person), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(user: liveUser)))),
                  IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(user: liveUser)))),
                ],
              ),
              floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
              floatingActionButton: widget.currentUser.permissions['canManageTables'] == true
                  ? FloatingActionButton(onPressed: () => addTable(), backgroundColor: theme.colorScheme.primary, child: const Icon(Icons.add, size: 30, color: Colors.white))
                  : null,
              bottomNavigationBar: BottomAppBar(
                shape: const CircularNotchedRectangle(),
                notchMargin: 8.0,
                color: theme.colorScheme.primary,
                child: SizedBox(
                  height: 60,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          if (liveUser.canViewActiveOrders) _bottomAction(Icons.receipt_long, "الطلبات", () => Navigator.push(context, MaterialPageRoute(builder: (_) => CurrentOrdersPage(currentUser: liveUser)))),
                          if (liveUser.permissions['canViewReports'] == true) _bottomAction(Icons.bar_chart, "التقارير", () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportPage(currentUser: liveUser)))),
                          if (liveUser.canViewKitchen) _bottomAction(Icons.soup_kitchen_rounded, "المطبخ", () => Navigator.push(context, MaterialPageRoute(builder: (_) => KitchenPage(currentUser: liveUser)))),
                        ],
                      ),
                      Row(
                        children: [
                          if (liveUser.permissions['canEditMenu'] == true) _bottomAction(Icons.restaurant_menu, "الأصناف", () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddProduct(currentUser: liveUser)))),
                          if (liveUser.permissions['canManageUsers'] == true) _bottomAction(Icons.people, "الأعضاء", () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementPage()))),
                          _bottomAction(Icons.logout, "خروج", () async {
                            await FirebaseFirestore.instance.collection('users').doc(widget.currentUser.id).update({'isOnline': false, 'currentSessionToken': ""});
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.clear();
                            if (context.mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
                          }, color: Colors.orangeAccent),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              body: Stack(
                children: [
                  Column(
                    children: [
                      if (_isOffline) Container(width: double.infinity, height: 25, color: Colors.redAccent, alignment: Alignment.center, child: const Text("وضع الأوفلاين نشط", style: TextStyle(color: Colors.white, fontSize: 11))),
                      _searchBar(theme),
                      Expanded(
                        child: GridView.builder(
                          controller: _scrollController,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 110),
                          itemCount: filteredTables.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.75),
                          itemBuilder: (context, i) {
                            final t = filteredTables[i];

                            final cafeData = cafeSnap.data!.data() as Map<String, dynamic>;
                            bool showTime = cafeData['show_time_counter'] ?? true;
                            bool showTimer = cafeData['show_timer_feature'] ?? true;
                            return TableCard(
                              key: ValueKey(t['id']),
                              id: t['id'],
                              name: t['name'],
                              isOpen: t['is_open'],
                              startTime: t['start_time'],
                              expiryTime: t['expiry_time'],
                              accSeconds: t['accumulated_seconds'],
                              currentUser: liveUser,
                              theme: theme,
                              showTimeCounter: showTime,
                              showTimerFeature: showTimer,
                              currencySymbol: currencySymbol,
                              onDelete: (liveUser.permissions['canDeleteTable'] == true) ? () => _confirmDelete(t['id'], t['name']) : null,
                              onEdit: (liveUser.permissions['canEditTable'] == true) ? () => _showEditTableDialog(t['id'], t['name']) : null,
                              onReset: () => _confirmReset(t['id'], t['name']),
                              onClose: () => _closeTableWithCheck(t['id'], t['name']),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    bottom: 85,
                    left: 15,
                    child: Column(
                      children: [
                        if (_showBackToTop) FloatingActionButton.small(heroTag: "btnTop", onPressed: _scrollToTop, backgroundColor: theme.colorScheme.primary, child: const Icon(Icons.arrow_upward, color: Colors.white)),
                        const SizedBox(height: 10),
                        FloatingActionButton.small(heroTag: "btnBottom", onPressed: _scrollToBottom, backgroundColor: theme.colorScheme.primary, child: const Icon(Icons.arrow_downward, color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _searchBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30))),
      child: TextField(
        controller: searchController,
        style: TextStyle(color: theme.colorScheme.onPrimary),
        decoration: InputDecoration(
          hintText: 'بحث عن طاولة...',
          hintStyle: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.6)),
          prefixIcon: Icon(Icons.search, color: theme.colorScheme.onPrimary.withOpacity(0.6)),
          suffixIcon: searchController.text.isNotEmpty ? IconButton(icon: Icon(Icons.cancel, color: theme.colorScheme.onPrimary), onPressed: () { searchController.clear(); setState(() {}); }) : null,
          filled: true,
          fillColor: theme.colorScheme.onPrimary.withOpacity(0.1),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _bottomAction(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color ?? Colors.white, size: 22),
            Text(
              label,
              style: TextStyle(
                color: color ?? Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TableCard extends StatefulWidget {
  final String id, name, currencySymbol;
  final bool isOpen;
  final DateTime? startTime;
  final DateTime? expiryTime;
  final int accSeconds;
  final User currentUser;
  final ThemeData theme;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback onReset, onClose;
  final bool showTimeCounter; // ممررة من الهوم بيج
  final bool showTimerFeature; // ممررة من الهوم بيج

  const TableCard({
    super.key,
    required this.id,
    required this.name,
    required this.currencySymbol,
    required this.isOpen,
    this.startTime,
    this.expiryTime,
    required this.accSeconds,
    required this.currentUser,
    required this.theme,
    required this.showTimeCounter,
    required this.showTimerFeature,
    this.onDelete,
    this.onEdit,
    required this.onReset,
    required this.onClose,
  });

  @override
  State<TableCard> createState() => _TableCardState();
}

class _TableCardState extends State<TableCard> {
  // دالة تشغيل/إيقاف الوقت
  void _togglePauseResume() async {
    if (widget.startTime != null) {
      int passed = DateTime.now().difference(widget.startTime!).inSeconds;
      await FirebaseFirestore.instance.collection('tables').doc(widget.id).update({
        'accumulated_seconds': widget.accSeconds + passed,
        'start_time': null,
      });
    } else {
      await FirebaseFirestore.instance.collection('tables').doc(widget.id).update({
        'start_time': FieldValue.serverTimestamp(),
      });
    }
  }

  // دالة تحديد وقت يدوي
  void _setManualTime() async {
    TimeOfDay? picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) {
      final now = DateTime.now();
      final manualDate = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
      await FirebaseFirestore.instance.collection('tables').doc(widget.id).update({
        'start_time': manualDate,
        'accumulated_seconds': 0,
      });
    }
  }

  Widget _circleBtn(IconData icon, Color color, VoidCallback onTap, String tooltip) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5), // تصغير البادينج قليلاً
        decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 18), // تصغير الأيقونة قليلاً
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Stack(
        children: [
          // 1. طبقة اللمس الأساسية لفتح صفحة الطلبات
          Positioned.fill(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                if (widget.isOpen && widget.currentUser.canMakeOrders) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => OrderPage(tableName: widget.name, currentUser: widget.currentUser)));
                }
              },
            ),
          ),

          // 2. زر الحذف (أعلى اليمين) - يظهر فقط لمن لديه صلاحية
          Positioned(
            top: 0,
            right: 0,
            child: widget.onDelete != null
                ? IconButton(
              icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 18),
              onPressed: widget.onDelete,
              tooltip: "حذف الطاولة",
            )
                : const SizedBox(),
          ),

          // 3. زر التعديل (أعلى اليسار) - يظهر فقط لمن لديه صلاحية
          Positioned(
            top: 0,
            left: 0,
            child: widget.onEdit != null
                ? IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 18),
              onPressed: widget.onEdit,
              tooltip: "تعديل الاسم",
            )
                : const SizedBox(),
          ),

          // 4. المحتوى الوسطي (أيقونة الطاولة + الاسم + الوقت + السعر)
          IgnorePointer(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.isOpen ? Icons.table_bar : Icons.table_bar_outlined,
                      color: widget.isOpen ? Colors.green : Colors.grey, size: 28),
                  Text(widget.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (widget.isOpen)
                    _TimeAndBillSection(
                      id: widget.id,
                      name: widget.name,
                      startTime: widget.startTime,
                      expiryTime: widget.expiryTime,
                      accSeconds: widget.accSeconds,
                      currentUser: widget.currentUser,
                      currencySymbol: widget.currencySymbol,
                      showTimeCounter: widget.showTimeCounter,
                    ),
                ],
              ),
            ),
          ),

          // 5. أزرار التحكم السفلية (تصفير، إيقاف، إنهاء، يدوي، مؤقت)
          Positioned(
            bottom: 8,
            left: 5,
            right: 5,
            child: widget.isOpen
                ? FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.showTimeCounter) ...[
                    _circleBtn(Icons.refresh, Colors.orange, widget.onReset, "تصفير"),
                    const SizedBox(width: 4),
                    _circleBtn(widget.startTime == null ? Icons.play_arrow : Icons.pause,
                        widget.startTime == null ? Colors.green : Colors.blueGrey,
                            () => _togglePauseResume(), "إيقاف/تشغيل"),
                    const SizedBox(width: 4),
                  ],
                  _circleBtn(Icons.close, Colors.red, widget.onClose, "إنهاء"),
                  if (widget.showTimeCounter) ...[
                    const SizedBox(width: 4),
                    _circleBtn(Icons.edit_calendar_outlined, Colors.purple, () => _setManualTime(), "يدوي"),
                  ],

                ],
              ),
            )
                : Center(
              child: Text("طاولة مغلقة", style: TextStyle(fontSize: 10, color: Colors.grey)),
            ),
          ),
        ],
      ),
    );
  }}


class _TimeAndBillSection extends StatefulWidget {
  final String id, name, currencySymbol;
  final DateTime? startTime, expiryTime;
  final int accSeconds;
  final User currentUser;
  final bool showTimeCounter; // ✅ أضف هذا السطر
  const _TimeAndBillSection({
    required this.id, required this.name, required this.currencySymbol,
    this.startTime, this.expiryTime, required this.accSeconds, required this.currentUser
  ,  required this.showTimeCounter, // ✅ أضف هذا السطر
  });

  @override
  State<_TimeAndBillSection> createState() => _TimeAndBillSectionState();
}


class _TimeAndBillSectionState extends State<_TimeAndBillSection> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // دالة عرض إجمالي الطلبات فقط بدون تكلفة وقت
  Widget _buildOnlyOrdersTotal() {
    return _buildOrdersContent(0.0);
  }

  // ويدجت داخلي لجلب الطلبات من Firestore وعرضها
  Widget _buildOrdersContent(double timeCost) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders')
          .where('cafeId', isEqualTo: widget.currentUser.cafeId)
          .where('table', isEqualTo: widget.name)
          .where('paid', isEqualTo: false).snapshots(),
      builder: (context, orderSnap) {
        double ordersTotal = 0;
        if (orderSnap.hasData) {
          for (var doc in orderSnap.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            List items = data['items'] ?? [];
            for (var item in items) {
              ordersTotal += (item['price'] ?? 0) * (item['quantity'] ?? 1);
            }
          }
        }

        double finalTotal = ordersTotal + timeCost;

        return Column(
          children: [
            Text('${finalTotal.toStringAsFixed(2)} ${widget.currencySymbol}',
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            if (timeCost > 0.05 && widget.showTimeCounter)
              Text("+${timeCost.toStringAsFixed(2)} وقت",
                  style: TextStyle(fontSize: 9, color: Colors.blueGrey.withOpacity(0.7))),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // إذا كان العداد معطلاً، نعرض الطلبات فقط
    if (!widget.showTimeCounter) {
      return _buildOnlyOrdersTotal();
    }

    // حساب الوقت المنقضي
    Duration duration;
    if (widget.expiryTime != null) {
      duration = widget.expiryTime!.difference(DateTime.now());
      if (duration.isNegative) duration = Duration.zero;
    } else {
      duration = (widget.startTime == null)
          ? Duration(seconds: widget.accSeconds)
          : DateTime.now().difference(widget.startTime!) + Duration(seconds: widget.accSeconds);
    }

    String t(int n) => n.toString().padLeft(2, '0');
    String timeStr = '${t(duration.inHours)}:${t(duration.inMinutes % 60)}:${t(duration.inSeconds % 60)}';

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('cafes').doc(widget.currentUser.cafeId).snapshots(),
      builder: (context, cafeSnap) {
        double hourlyRate = 0.0;
        if (cafeSnap.hasData && cafeSnap.data!.exists) {
          final data = cafeSnap.data!.data() as Map<String, dynamic>;
          hourlyRate = (data['table_hourly_rate'] ?? data['hourly_rate'] ?? 0).toDouble();
        }

        double timeCost = (duration.inSeconds / 3600) * hourlyRate;

        return Column(
          children: [
            Text(timeStr, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.bold)),
            _buildOrdersContent(timeCost),
          ],
        );
      },
    );
  }
}
