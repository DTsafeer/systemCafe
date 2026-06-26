import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../main.dart';

class SettingsService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> updateSetting({
    required String cafeId,
    required String key,
    required dynamic value,
    required BuildContext context,
  }) async {
    try {
      await _db.collection('cafes').doc(cafeId).set({key: value}, SetOptions(merge: true));
      final prefs = await SharedPreferences.getInstance();
      if (value is bool) await prefs.setBool(key, value);
      else if (value is int) await prefs.setInt(key, value);
      else if (value is String) await prefs.setString(key, value);
      else if (value is double) await prefs.setDouble(key, value);

      if (key == 'isDarkMode' || key == 'primaryColor') {
        if (context.mounted) MyApp.updateTheme(context);
      }
    } catch (e) {
      debugPrint("Update Setting Error: $e");
      rethrow;
    }
  }

  static Future<void> performClearData({
    required String cafeId,
    required String managerId,
    required Map<String, bool> selection,
  }) async {
    // زيادة الأمان: التحقق من وجود معرفات صحيحة وغير فارغة
    if (cafeId.isEmpty || managerId.isEmpty) {
      throw Exception("Invalid Cafe ID or Manager ID. Operation aborted.");
    }

    for (var entry in selection.entries) {
      if (entry.value) {
        // فلترة مزدوجة: الكافيه + المالك لضمان عدم مسح بيانات حسابات أخرى
        final snapshots = await _db.collection(entry.key)
            .where('cafeId', isEqualTo: cafeId)
            .where('parentId', isEqualTo: managerId)
            .get();

        if (snapshots.docs.isNotEmpty) {
          // الحذف على دفعات (Batch) لتجنب أخطاء Firestore (حد 500 عملية)
          final List<DocumentSnapshot> docs = snapshots.docs;
          for (var i = 0; i < docs.length; i += 500) {
            final batch = _db.batch();
            final end = (i + 500 < docs.length) ? i + 500 : docs.length;
            for (var j = i; j < end; j++) {
              batch.delete(docs[j].reference);
            }
            await batch.commit();
          }
        }
      }
    }
  }
}
