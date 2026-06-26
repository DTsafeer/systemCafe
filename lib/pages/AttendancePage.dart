import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:intl/date_symbol_data_local.dart';
import 'user_model.dart';
import 'CustomBottomNav.dart';
import 'MainLayout.dart';

class AttendancePage extends StatefulWidget {
  final User currentUser;
  final User? targetUser;

  const AttendancePage({
    super.key,
    required this.currentUser,
    this.targetUser,
  });

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  bool _isLoading = false;
  bool _isLocaleInitialized = false;
  User? _selectedUser;
  late String managerId;

  @override
  void initState() {
    super.initState();
    managerId = widget.currentUser.parentId ?? widget.currentUser.id;
    _initLocale();
    _selectedUser = widget.targetUser;
  }

  User get displayUser => _selectedUser ?? widget.currentUser;
  
  // صلاحية إدارة دوام الآخرين
  bool get canManageOthers => widget.currentUser.canUpdate('attendance') || widget.currentUser.role == UserRole.admin || widget.currentUser.role == UserRole.super_admin;

  TimeOfDay get _workStartTime {
    try {
      if (displayUser.workStartTime != null) {
        final parts = displayUser.workStartTime!.split(':');
        int hour = int.parse(parts[0].replaceAll(RegExp(r'[^0-9]'), ''));
        int minute = int.parse(parts[1].split(' ')[0]);
        if (displayUser.workStartTime!.contains('PM') && hour < 12) hour += 12;
        if (displayUser.workStartTime!.contains('AM') && hour == 12) hour = 0;
        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (e) {
      debugPrint("Error parsing workStartTime: $e");
    }
    return const TimeOfDay(hour: 8, minute: 0);
  }

  Future<void> _initLocale() async {
    await initializeDateFormatting('ar', null);
    if (mounted) {
      setState(() => _isLocaleInitialized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLocaleInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final primary = Theme.of(context).primaryColor;

    // فحص صلاحية القراءة العامة للدوام
    if (!widget.currentUser.canRead('attendance')) {
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'attendance',
        child: const Scaffold(
          body: Center(
            child: Text("عذراً، لا تملك صلاحية لعرض سجل الدوام", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'attendance',
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: Text(canManageOthers ? "لوحة تحكم الحضور" : "سجل الدوام الخاص بي", style: const TextStyle(fontSize: 16)),
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          toolbarHeight: 45,
          automaticallyImplyLeading: false,
        ),
        body: Column(
          children: [
            if (canManageOthers) _buildUserSelector(primary),
            _buildCompactHeader(primary),
            const Divider(height: 1),
            Expanded(child: _buildAttendanceList(primary)),
          ],
        ),
      ),
    );
  }

  Widget _buildUserSelector(Color primary) {
    return Container(
      height: 75,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('cafeId', isEqualTo: widget.currentUser.cafeId)
            .where('parentId', isEqualTo: managerId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox();
          final users = snapshot.data!.docs
              .map((d) => User.fromMap(d.data() as Map<String, dynamic>, d.id))
              .toList();

          return users.isEmpty 
            ? const Center(child: Text("لا يوجد موظفين", style: TextStyle(fontSize: 10, color: Colors.grey)))
            : ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index];
                  final isSelected = displayUser.id == user.id;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedUser = user),
                    child: Container(
                      width: 55,
                      margin: const EdgeInsets.only(right: 10),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: isSelected ? primary : Colors.grey[100],
                            child: Text(
                              user.name[0],
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.blueGrey,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.name.split(' ')[0],
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? primary : Colors.blueGrey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
        },
      ),
    );
  }

  Widget _buildCompactHeader(Color primary) {
    String name = displayUser.id == widget.currentUser.id ? "أنا" : displayUser.name;
    // يمكن للموظف تسجيل دوامه، أو للمسؤول تسجيل دوام الآخرين
    bool canRecord = displayUser.id == widget.currentUser.id || canManageOthers;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                intl.DateFormat('EEEE, d MMMM', 'ar').format(DateTime.now()),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              Text("الموظف: $name", style: TextStyle(color: primary, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          if (canRecord) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _actionButton("دخول", Icons.login, Colors.green),
                _actionButton("خروج", Icons.logout, Colors.redAccent),
                _actionButton("مؤقت", Icons.timer_outlined, Colors.blue),
                _actionButton("بدون إذن", Icons.warning_amber, Colors.orange),
                _actionButton("عودة", Icons.refresh, Colors.teal),
                _actionButton("غياب", Icons.event_busy, Colors.brown),
              ],
            ),
            const SizedBox(height: 8),
          ],
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('attendance')
                .where('userId', isEqualTo: displayUser.id)
                .snapshots(),
            builder: (context, snapshot) {
              int totalDays = 0;
              int delayDays = 0;
              int totalDelayMinutes = 0;
              Set<String> uniqueDays = {};

              if (snapshot.hasData) {
                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final ts = _getTimestamp(data).toDate();
                  final dayKey = intl.DateFormat('yyyy-MM-dd').format(ts);
                  if (data['type'] == 'checkIn' || (data['type'] == null && data['checkIn'] != null)) {
                    uniqueDays.add(dayKey);
                    if (data['isLate'] == true) {
                      delayDays++;
                      totalDelayMinutes += (data['delayMinutes'] as num? ?? 0).toInt();
                    }
                  }
                }
              }
              totalDays = uniqueDays.length;

              return Row(
                children: [
                  _statItem("دوام", totalDays.toString(), Colors.blue),
                  const SizedBox(width: 5),
                  _statItem("تأخير", delayDays.toString(), Colors.orange),
                  const SizedBox(width: 5),
                  _statItem("إجمالي", "${totalDelayMinutes}د", Colors.red),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("$label: ", style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold)),
            Text(value, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, Color color) {
    // التحقق من صلاحية الإضافة (التسجيل)
    bool canAdd = widget.currentUser.canCreate('attendance') || widget.currentUser.role == UserRole.admin || widget.currentUser.role == UserRole.super_admin;
    
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 60) / 3,
      child: InkWell(
        onTap: (canAdd && !_isLoading) ? () => _handleAction(label == "دخول" ? 'checkIn' : label == "خروج" ? 'checkOut' : label == "مؤقت" ? 'tempExit' : label == "بدون إذن" ? 'unpermittedExit' : label == "عودة" ? 'returnToWork' : 'absent') : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: (canAdd ? color : Colors.grey).withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: (canAdd ? color : Colors.grey).withOpacity(0.15)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: canAdd ? color : Colors.grey),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: canAdd ? color : Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceList(Color primary) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('attendance')
          .where('userId', isEqualTo: displayUser.id)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد سجلات", style: TextStyle(fontSize: 11)));

        final List<QueryDocumentSnapshot> docs = snapshot.data!.docs.toList();
        docs.sort((a, b) => _getTimestamp(b.data()).compareTo(_getTimestamp(a.data())));

        Map<String, List<QueryDocumentSnapshot>> grouped = {};
        for (var doc in docs) {
          final dateStr = intl.DateFormat('EEEE, d MMMM yyyy', 'ar').format(_getTimestamp(doc.data()).toDate());
          grouped.putIfAbsent(dateStr, () => []).add(doc);
        }
        final days = grouped.keys.toList();

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          itemCount: days.length,
          itemBuilder: (context, index) {
            final day = days[index];
            final dayLogs = grouped[day]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  margin: const EdgeInsets.only(bottom: 4),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(day, style: TextStyle(fontWeight: FontWeight.bold, color: primary, fontSize: 10)),
                ),
                ...dayLogs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final timestamp = _getTimestamp(data).toDate();
                  final type = data['type'] ?? 'checkIn';
                  final bool isLate = data['isLate'] ?? false;
                  final timeStr = intl.DateFormat('HH:mm:ss').format(timestamp);

                  String typeLabel = "غير معروف";
                  Color typeColor = Colors.grey;
                  IconData typeIcon = Icons.help_outline;

                  switch (type) {
                    case 'checkIn': typeLabel = "دخول"; typeColor = Colors.green; typeIcon = Icons.login; break;
                    case 'checkOut': typeLabel = "خروج"; typeColor = Colors.red; typeIcon = Icons.logout; break;
                    case 'tempExit': typeLabel = "مؤقت"; typeColor = Colors.blue; typeIcon = Icons.timer_outlined; break;
                    case 'unpermittedExit': typeLabel = "بدون إذن"; typeColor = Colors.orange; typeIcon = Icons.warning; break;
                    case 'returnToWork': typeLabel = "عودة"; typeColor = Colors.teal; typeIcon = Icons.refresh; break;
                    case 'absent': typeLabel = "غياب"; typeColor = Colors.brown; typeIcon = Icons.event_busy; break;
                  }

                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                    margin: const EdgeInsets.only(bottom: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey[100]!),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(typeIcon, color: typeColor, size: 12),
                              const SizedBox(width: 6),
                              Text(typeLabel, style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 11)),
                              if (isLate) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(3)),
                                  child: Text("تأخير ${data['delayMinutes']}د", style: const TextStyle(color: Colors.orange, fontSize: 7, fontWeight: FontWeight.bold)),
                                ),
                              ]
                            ],
                          ),
                        ),
                        Text(timeStr, style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 10)),
                        if (widget.currentUser.canDelete('attendance'))
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                            onPressed: () => _deleteAttendance(doc.reference),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                      ],
                    ),
                  );
                }).toList(),
                const SizedBox(height: 8),
              ],
            );
          },
        );
      },
    );
  }

  Timestamp _getTimestamp(dynamic data) {
    if (data is! Map) return Timestamp.now();
    var t = data['timestamp'] ?? data['checkIn'] ?? data['date'];
    if (t is Timestamp) return t;
    return Timestamp.now();
  }

  Future<void> _handleAction(String type) async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      Map<String, dynamic> entry = {
        'userId': displayUser.id,
        'userName': displayUser.name,
        'cafeId': displayUser.cafeId,
        'parentId': managerId,
        'timestamp': now,
        'type': type,
        'recordedBy': widget.currentUser.name,
      };

      if (type == 'checkIn') {
        final scheduledStart = DateTime(now.year, now.month, now.day, _workStartTime.hour, _workStartTime.minute);
        if (now.isAfter(scheduledStart)) {
          int delay = now.difference(scheduledStart).inMinutes;
          if (delay > 5) {
            entry['isLate'] = true;
            entry['delayMinutes'] = delay;
          }
        }
      }

      await FirebaseFirestore.instance.collection('attendance').add(entry);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تسجيل العملية بنجاح")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteAttendance(DocumentReference ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("حذف السجل"),
        content: const Text("هل أنت متأكد من حذف هذا السجل؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("حذف", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await ref.delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم الحذف بنجاح")));
    }
  }
}
