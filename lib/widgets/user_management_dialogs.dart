import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import '../pages/user_model.dart';
import '../pages/activity_logger.dart';

class UserManagementDialogs {
  static void showEditWorkHours({
    required BuildContext context,
    required String id,
    required String name,
    required Map<String, dynamic> data,
    required User currentUser,
    required Function(String, Map<String, dynamic>) onUpdated,
  }) async {
    String currentStart = data['workStartTime'] ?? "08:00";
    String currentEnd = data['workEndTime'] ?? "16:00";
    final managerId = currentUser.parentId ?? currentUser.id;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text("تعديل ساعات الدوام"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text("بداية الدوام"),
                subtitle: Text(currentStart),
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: int.parse(currentStart.split(":")[0]),
                      minute: int.parse(currentStart.split(":")[1]),
                    ),
                  );
                  if (t != null) {
                    final newTime = t.format(context);
                    await FirebaseFirestore.instance.collection('users').doc(id).update({'workStartTime': newTime});
                    
                    await ActivityLogger.log(
                      cafeId: currentUser.cafeId,
                      parentId: managerId,
                      userId: currentUser.id,
                      userName: currentUser.name,
                      action: "موظفين - دوام",
                      details: "تعديل وقت بداية دوام $name إلى $newTime",
                    );

                    if (ctx.mounted) Navigator.pop(ctx);
                    onUpdated(id, {...data, 'workStartTime': newTime});
                  }
                },
              ),
              ListTile(
                title: const Text("نهاية الدوام"),
                subtitle: Text(currentEnd),
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: int.parse(currentEnd.split(":")[0]),
                      minute: int.parse(currentEnd.split(":")[1]),
                    ),
                  );
                  if (t != null) {
                    final newTime = t.format(context);
                    await FirebaseFirestore.instance.collection('users').doc(id).update({'workEndTime': newTime});
                    
                    await ActivityLogger.log(
                      cafeId: currentUser.cafeId,
                      parentId: managerId,
                      userId: currentUser.id,
                      userName: currentUser.name,
                      action: "موظفين - دوام",
                      details: "تعديل وقت نهاية دوام $name إلى $newTime",
                    );

                    if (ctx.mounted) Navigator.pop(ctx);
                    onUpdated(id, {...data, 'workEndTime': newTime});
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إغلاق")),
          ],
        ),
      ),
    );
  }

  static void showConfirmDelete({
    required BuildContext context,
    required String id,
    required String name,
    required User currentUser,
    required VoidCallback onDeleted,
  }) {
    final managerId = currentUser.parentId ?? currentUser.id;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text("حذف الحساب"),
          content: Text("هل أنت متأكد من حذف $name؟"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                await FirebaseFirestore.instance.collection('users').doc(id).delete();

                await ActivityLogger.log(
                  cafeId: currentUser.cafeId,
                  parentId: managerId,
                  userId: currentUser.id,
                  userName: currentUser.name,
                  action: "موظفين - حذف",
                  details: "حذف حساب الموظف: $name نهائياً",
                );

                if (ctx.mounted) Navigator.pop(ctx);
                onDeleted();
              },
              child: const Text("حذف", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> manualAttendance({
    required BuildContext context,
    required String userId,
    required String userName,
    required String cafeId,
    required String managerId,
    required bool isCheckIn,
  }) async {
    final now = DateTime.now();
    final dateStr = intl.DateFormat('yyyy-MM-dd').format(now);
    final docId = "${userId}_$dateStr";

    try {
      if (isCheckIn) {
        await FirebaseFirestore.instance.collection('attendance').doc(docId).set({
          'userId': userId,
          'userName': userName,
          'cafeId': cafeId,
          'parentId': managerId,
          'date': DateTime(now.year, now.month, now.day),
          'checkIn': now,
          'checkOut': null,
          'isLate': false,
          'delayMinutes': 0,
        }, SetOptions(merge: true));

        await ActivityLogger.log(
          cafeId: cafeId,
          parentId: managerId,
          userId: userId, // Assuming current session might be different, but here it's manual
          userName: "النظام (يدوي)", 
          action: "دوام - دخول",
          details: "تسجيل دخول يدوي للموظف: $userName",
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم تسجيل دخول $userName")));
        }
      } else {
        await FirebaseFirestore.instance.collection('attendance').doc(docId).update({
          'checkOut': now,
        });

        await ActivityLogger.log(
          cafeId: cafeId,
          parentId: managerId,
          userId: userId,
          userName: "النظام (يدوي)",
          action: "دوام - خروج",
          details: "تسجيل خروج يدوي للموظف: $userName",
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم تسجيل خروج $userName")));
        }
      }
    } catch (e) {
      debugPrint("Error attendance: $e");
    }
  }
}
