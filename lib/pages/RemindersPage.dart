import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reminder_model.dart';
import '../services/reminder_service.dart';
import 'user_model.dart';
import 'MainLayout.dart';

class RemindersPage extends StatefulWidget {
  final User currentUser;
  const RemindersPage({super.key, required this.currentUser});

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  List<Reminder> _reminders = [];
  bool _isLoading = true;
  bool _hasExactAlarmPermission = true;

  @override
  void initState() {
    super.initState();
    _loadReminders();
    _checkPermissions();
  }

  // فحص الصلاحيات الضرورية للتفاعل في الوقت المحدد
  Future<void> _checkPermissions() async {
    bool hasPermission = await ReminderService.hasExactAlarmPermission();
    if (mounted) {
      setState(() {
        _hasExactAlarmPermission = hasPermission;
      });
    }
  }

  Future<void> _loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> list = prefs.getStringList('local_reminders') ?? [];
    setState(() {
      _reminders = list.map((e) => Reminder.fromJson(e)).toList();
      _isLoading = false;
    });
  }

  Future<void> _saveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _reminders.map((e) => e.toJson()).toList();
    await prefs.setStringList('local_reminders', list);

    await ReminderService.cancelAll();
    for (var r in _reminders) {
      if (r.isEnabled) {
        await ReminderService.scheduleNotification(
          id: r.id.hashCode,
          title: r.title,
          body: r.body,
          time: r.time,
          days: r.days,
        );
      }
    }
  }

  void _duplicateReminder(Reminder reminder) {
    if (!widget.currentUser.canCreate('reminders')) return;
    
    final newReminder = Reminder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: "${reminder.title} (نسخة)",
      body: reminder.body,
      time: reminder.time,
      days: List.from(reminder.days),
      isEnabled: reminder.isEnabled,
    );
    setState(() {
      _reminders.add(newReminder);
    });
    _saveReminders();
    _addOrEditReminder(newReminder);
  }

  void _addOrEditReminder([Reminder? reminder]) async {
    final isEdit = reminder != null;
    
    // فحص الصلاحية قبل الفتح
    if (isEdit) {
      if (!widget.currentUser.canUpdate('reminders')) return;
    } else {
      if (!widget.currentUser.canCreate('reminders')) return;
    }

    String title = reminder?.title ?? "";
    String body = reminder?.body ?? "";
    TimeOfDay time = reminder?.time ?? TimeOfDay.now();
    List<int> days = reminder?.days ?? [1, 2, 3, 4, 5, 6, 7];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(isEdit ? "تعديل تنبيه" : "إضافة تنبيه جديد"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(labelText: "عنوان التنبيه", prefixIcon: Icon(Icons.title)),
                    controller: TextEditingController(text: title),
                    onChanged: (v) => title = v,
                  ),
                  TextField(
                    decoration: const InputDecoration(labelText: "نص التنبيه", prefixIcon: Icon(Icons.short_text)),
                    onChanged: (v) => body = v,
                    controller: TextEditingController(text: body),
                  ),
                  const SizedBox(height: 20),
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: time);
                      if (picked != null) setDialogState(() => time = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(children: [Icon(Icons.access_time, size: 20), SizedBox(width: 8), Text("الوقت")]),
                          Text(time.format(context), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Align(alignment: Alignment.centerRight, child: Text("أيام التكرار:", style: TextStyle(fontWeight: FontWeight.bold))),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(7, (index) {
                      final day = index + 1;
                      final dayNames = ["ن", "ث", "ر", "خ", "ج", "س", "ح"];
                      final isSelected = days.contains(day);
                      return FilterChip(
                        label: Text(dayNames[index]),
                        selected: isSelected,
                        onSelected: (val) {
                          setDialogState(() {
                            if (val) days.add(day);
                            else if (days.length > 1) days.remove(day);
                          });
                        },
                      );
                    }),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
              ElevatedButton(
                onPressed: () {
                  if (title.isEmpty) return;
                  final newReminder = Reminder(
                    id: isEdit ? reminder.id : DateTime.now().millisecondsSinceEpoch.toString(),
                    title: title,
                    body: body,
                    time: time,
                    days: days,
                    isEnabled: reminder?.isEnabled ?? true,
                  );
                  setState(() {
                    if (isEdit) {
                      int idx = _reminders.indexWhere((element) => element.id == reminder.id);
                      if (idx != -1) _reminders[idx] = newReminder;
                    } else {
                      _reminders.add(newReminder);
                    }
                  });
                  _saveReminders();
                  Navigator.pop(context);
                },
                child: const Text("حفظ"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // فحص صلاحية القراءة
    if (!widget.currentUser.canRead('reminders')) {
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'reminders',
        child: const Scaffold(
          body: Center(
            child: Text("عذراً، لا تملك صلاحية لعرض صفحة التنبيهات", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'reminders',
      floatingActionButton: widget.currentUser.canCreate('reminders') ? FloatingActionButton.extended(
        onPressed: () => _addOrEditReminder(),
        icon: const Icon(Icons.add_alarm),
        label: const Text("تنبيه جديد"),
      ) : null,
      child: Column(
        children: [
          // شريط تحذير إذا كانت صلاحية المنبه الدقيق معطلة
          if (!_hasExactAlarmPermission)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red),
                      SizedBox(width: 10),
                      Expanded(child: Text("صلاحية 'المنبه الدقيق' معطلة. هذا سيمنع التنبيه من العمل في وقته المحدد تماماً.", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    onPressed: () async {
                      await ReminderService.requestExactAlarmPermission();
                      // بعد العودة من الإعدادات، نفحص مرة أخرى
                      _checkPermissions();
                    },
                    child: const Text("تفعيل من إعدادات الهاتف"),
                  )
                ],
              ),
            ),

          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 10),
                const Expanded(child: Text("اضغط 'تجربة' للتأكد من وصول الإشعارات فوراً.")),
                TextButton.icon(
                  onPressed: () => ReminderService.showTestNow(),
                  icon: const Icon(Icons.bolt),
                  label: const Text("تجربة"),
                )
              ],
            ),
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _reminders.length,
                  itemBuilder: (context, index) {
                    final r = _reminders[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Icon(Icons.alarm, color: r.isEnabled ? Colors.blue : Colors.grey),
                        title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${r.time.format(context)} • ${r.days.length == 7 ? "يومياً" : "أيام محددة"}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: r.isEnabled,
                              onChanged: widget.currentUser.canUpdate('reminders') ? (val) {
                                setState(() {
                                  _reminders[index] = Reminder(id: r.id, title: r.title, body: r.body, time: r.time, days: r.days, isEnabled: val);
                                });
                                _saveReminders();
                              } : null,
                            ),
                            if (widget.currentUser.canCreate('reminders'))
                              IconButton(
                                icon: const Icon(Icons.copy, size: 20),
                                onPressed: () => _duplicateReminder(r),
                              ),
                            if (widget.currentUser.canDelete('reminders'))
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                onPressed: () {
                                  setState(() => _reminders.removeAt(index));
                                  _saveReminders();
                                },
                              ),
                          ],
                        ),
                        onTap: widget.currentUser.canUpdate('reminders') ? () => _addOrEditReminder(r) : null,
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
