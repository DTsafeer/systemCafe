import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/database_helper.dart';

class ActivityLogger {
  static Future<void> log({
    required String cafeId,
    required String parentId,
    required String userId,
    required String userName,
    required String action,
    required String details,
  }) async {
    // نستخدم الـ DatabaseHelper الموجود مسبقاً لأنه مهيأ للتعامل مع السحابي والمحلي معاً
    await DatabaseHelper().logActivity(
      cafeId: cafeId,
      parentId: parentId,
      userId: userId,
      userName: userName,
      action: action,
      details: details,
    );
  }
}
