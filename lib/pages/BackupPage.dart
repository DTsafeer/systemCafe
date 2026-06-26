import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'user_model.dart';
import 'MainLayout.dart';

class BackupPage extends StatefulWidget {
  final User currentUser;
  const BackupPage({super.key, required this.currentUser});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _isExporting = false;

  Future<void> _runFullBackup() async {
    setState(() => _isExporting = true);
    final String cafeId = widget.currentUser.cafeId;
    final Map<String, dynamic> backupData = {
      'exportDate': DateTime.now().toIso8601String(),
      'cafeId': cafeId,
      'data': {}
    };

    try {
      // 1. جلب كافة المجموعات الهامة
      List<String> collections = ['debts', 'payments', 'expenses', 'suppliers', 'products', 'inventory'];
      
      for (String collection in collections) {
        final snap = await FirebaseFirestore.instance.collection(collection)
            .where('cafeId', isEqualTo: cafeId).get();
        
        backupData['data'][collection] = snap.docs.map((doc) => doc.data()).toList();
      }

      // 2. تحويل البيانات إلى نص JSON
      String jsonString = jsonEncode(backupData);

      // 3. حفظ في ملف مؤقت
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/FloraCafe_Backup_${DateFormat('yyyyMMdd').format(DateTime.now())}.json');
      await file.writeAsString(jsonString);

      // 4. مشاركة الملف (إرسال للإيميل أو واتساب أو درايف)
      await Share.shareXFiles([XFile(file.path)], text: 'نسخة احتياطية كاملة لبيانات النظام - ${widget.currentUser.name}');

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تجهيز النسخة الاحتياطية بنجاح ✅")));
    } catch (e) {
      debugPrint("Backup Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("فشل في إنشاء النسخة الاحتياطية ❌"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'backup',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("تأمين البيانات والنسخ الاحتياطي"),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_done_outlined, size: 100, color: primaryColor),
                const SizedBox(height: 30),
                const Text(
                  "تأمين معلوماتك بشكل يومي",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                const Text(
                  "يقوم النظام بحفظ بياناتك تلقائياً على السحابة، ولكن يمكنك تحميل نسخة شاملة لإرسالها لإيميلك الشخصي لزيادة الأمان.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 50),
                _isExporting 
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor, foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 65),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: _runFullBackup,
                      icon: const Icon(Icons.security_update_good_rounded),
                      label: const Text("إنشاء نسخة احتياطية وإرسالها للإيميل", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                const SizedBox(height: 20),
                const Text("سيتم تصدير ملف بصيغة JSON يحتوي على كافة الحركات المالية والديون.", style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
