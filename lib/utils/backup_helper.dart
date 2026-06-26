import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class BackupResult {
  final bool success;
  final List<XFile> files;
  final String? error;
  BackupResult({required this.success, this.files = const [], this.error});
}

class BackupHelper {
  static const List<String> collectionsToBackup = [
    'products', 'debts', 'payments', 'expenses', 'inventory', 'cafes', 'tables', 'categories'
  ];

  static Future<String> _getTempPath() async {
    if (kIsWeb) return "";
    try {
      final directory = await getTemporaryDirectory();
      return directory.path;
    } catch (e) {
      return Directory.systemTemp.path;
    }
  }

  static dynamic _sanitizeData(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is GeoPoint) return {'lat': value.latitude, 'lng': value.longitude};
    if (value is DocumentReference) return value.path;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _sanitizeData(v)));
    }
    if (value is List) {
      return value.map((e) => _sanitizeData(e)).toList();
    }
    if (value is num || value is String || value is bool) return value;
    return value.toString(); 
  }

  static Future<Map<String, dynamic>> _fetchAllData(String cafeId) async {
    Map<String, dynamic> backupData = {
      'backup_date': DateTime.now().toIso8601String(),
      'cafeId': cafeId,
      'data': {}
    };

    for (String coll in collectionsToBackup) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection(coll)
            .where('cafeId', isEqualTo: cafeId)
            .get()
            .timeout(const Duration(seconds: 15));
        
        backupData['data'][coll] = snap.docs.map((doc) {
          final data = doc.data();
          return {'id': doc.id, ..._sanitizeData(data)};
        }).toList();
      } catch (e) {
        debugPrint("Error in $coll: $e");
        backupData['data'][coll] = []; 
      }
    }
    return backupData;
  }

  static Future<BackupResult> prepareFullBackupFiles(String cafeId) async {
    List<XFile> files = [];
    try {
      final dateStr = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      final tempPath = await _getTempPath();

      final firestoreData = await _fetchAllData(cafeId);
      final jsonFile = File('$tempPath/Cloud_Backup_$dateStr.json');
      await jsonFile.writeAsString(jsonEncode(firestoreData));
      files.add(XFile(jsonFile.path));

      if (!kIsWeb) {
        final dbPath = join(await getDatabasesPath(), 'cafe_system.db');
        final dbFile = File(dbPath);
        if (await dbFile.exists()) {
          final backupDbFile = File('$tempPath/Local_DB_$dateStr.db');
          await dbFile.copy(backupDbFile.path);
          files.add(XFile(backupDbFile.path));
        }
      }
      return BackupResult(success: true, files: files);
    } catch (e) {
      return BackupResult(success: false, error: e.toString());
    }
  }

  static Future<void> createManualBackup(String cafeId) async {
    try {
      final data = await _fetchAllData(cafeId);
      final jsonString = jsonEncode(data);
      final dateStr = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      if (kIsWeb) {
        final blob = "data:application/json;charset=utf-8,${Uri.encodeComponent(jsonString)}";
        await launchUrl(Uri.parse(blob));
      } else {
        final tempPath = await _getTempPath();
        final file = File('$tempPath/Backup_$dateStr.json');
        await file.writeAsString(jsonString);
        await Share.shareXFiles([XFile(file.path)], text: 'نسخة احتياطية Firestore');
      }
    } catch (e) {
      debugPrint("Backup Error: $e");
    }
  }

  static Future<String> sendBackupToCloud(String cafeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cloudUrl = prefs.getString('backupCloudUrl');
      if (cloudUrl == null || cloudUrl.isEmpty) return "no_url";
      
      final data = await _fetchAllData(cafeId);
      final response = await http.post(
        Uri.parse(cloudUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'backup', 'content': data}),
      ).timeout(const Duration(seconds: 60));
      
      return response.statusCode < 400 ? "success" : "error";
    } catch (e) {
      return "error: $e";
    }
  }

  static Future<void> checkAndPerformAutoBackup(String cafeId) async {
    final prefs = await SharedPreferences.getInstance();
    
    // هل النسخ التلقائي مفعل؟
    bool isEnabled = prefs.getBool('isAutoBackupEnabled') ?? true;
    if (!isEnabled) return;

    // الفترة الزمنية (افتراضياً كل 3 أيام)
    int daysInterval = prefs.getInt('autoBackupInterval') ?? 3;
    final lastBackup = prefs.getString('last_auto_backup');
    
    if (lastBackup != null) {
      final lastDate = DateTime.parse(lastBackup);
      if (DateTime.now().difference(lastDate).inDays < daysInterval) return;
    }

    try {
      // إرسال النسخة للسحابة تلقائياً
      String res = await sendBackupToCloud(cafeId);
      if (res == "success") {
        await prefs.setString('last_auto_backup', DateTime.now().toIso8601String());
        debugPrint("✅ تم النسخ الاحتياطي التلقائي بنجاح");
      }
    } catch (e) {
      debugPrint("❌ فشل النسخ الاحتياطي التلقائي: $e");
    }
  }
}
