import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirebaseConfigPage extends StatefulWidget {
  const FirebaseConfigPage({super.key});

  @override
  State<FirebaseConfigPage> createState() => _FirebaseConfigPageState();
}

class _FirebaseConfigPageState extends State<FirebaseConfigPage> {
  final _formKey = GlobalKey<FormState>();

  // تعريف المتحكمات بناءً على المثال الذي زودتني به
  final Map<String, TextEditingController> _controllers = {
    'apiKey': TextEditingController(),
    'authDomain': TextEditingController(),
    'projectId': TextEditingController(),
    'storageBucket': TextEditingController(),
    'messagingSenderId': TextEditingController(),
    'appId': TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  // تحميل البيانات الحالية إذا كانت مخزنة مسبقاً
  Future<void> _loadCurrentConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _controllers['apiKey']!.text = prefs.getString('dyn_api_key') ?? "";
      _controllers['authDomain']!.text = prefs.getString('dyn_auth_domain') ?? "";
      _controllers['projectId']!.text = prefs.getString('dyn_project_id') ?? "";
      _controllers['storageBucket']!.text = prefs.getString('dyn_storage_bucket') ?? "";
      _controllers['messagingSenderId']!.text = prefs.getString('dyn_sender_id') ?? "";
      _controllers['appId']!.text = prefs.getString('dyn_app_id') ?? "";
    });
  }

  // حفظ الإعدادات في SharedPreferences وتطبيقها عند إعادة التشغيل
  Future<void> _saveAndRestart() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();

      // حفظ القيم
      await prefs.setString('dyn_api_key', _controllers['apiKey']!.text.trim());
      await prefs.setString('dyn_auth_domain', _controllers['authDomain']!.text.trim());
      await prefs.setString('dyn_project_id', _controllers['projectId']!.text.trim());
      await prefs.setString('dyn_storage_bucket', _controllers['storageBucket']!.text.trim());
      await prefs.setString('dyn_sender_id', _controllers['messagingSenderId']!.text.trim());
      await prefs.setString('dyn_app_id', _controllers['appId']!.text.trim());

      _showSuccessDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("إعدادات الربط السحابي",style: TextStyle(color: Colors.white),),
        backgroundColor: Colors.blueGrey.shade800,
        elevation: 0,
      ),
      body: Container(
        color: Colors.grey.shade100,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoBanner(),
                const SizedBox(height: 25),
                _buildSectionTitle("بيانات الهوية (Credentials)"),
                _buildField("API Key", 'apiKey', "AIzaSyAF72gqzifQY7LD..."),
                _buildField("App ID", 'appId', "1:355752069358:web:c31542..."),

                const SizedBox(height: 20),
                _buildSectionTitle("بيانات المشروع (Project Details)"),
                _buildField("Project ID", 'projectId', "flora-5bfdb"),
                _buildField("Auth Domain", 'authDomain', "flora-5bfdb.firebaseapp.com"),
                _buildField("Storage Bucket", 'storageBucket', "flora-5bfdb.firebasestorage.app"),
                _buildField("Messaging Sender ID", 'messagingSenderId', "355752069358"),

                const SizedBox(height: 40),
                _buildSaveButton(),
                const SizedBox(height: 20),
                _buildResetButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 5),
      child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
    );
  }

  Widget _buildField(String label, String key, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: _controllers[key],
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        ),
        validator: (v) => (v == null || v.isEmpty) ? "هذا الحقل مطلوب" : null,
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.shade200)),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 15),
          Expanded(child: Text("تغيير هذه البيانات سينقل التطبيق لقاعدة بيانات أخرى تماماً. تأكد من صحة الرموز قبل الحفظ.", style: TextStyle(fontSize: 12, color: Colors.brown))),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade600,
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
      onPressed: _saveAndRestart,
      child: const Text("حفظ وتفعيل الحساب الجديد", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildResetButton() {
    return Center(
      child: TextButton(
        onPressed: _showResetConfirm,
        child: const Text("العودة للحساب الافتراضي (الملف الأصلي)", style: TextStyle(color: Colors.redAccent)),
      ),
    );
  }

  void _showResetConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("إعادة ضبط؟"),
        content: const Text("هل تريد حذف الإعدادات الديناميكية والعودة لاستخدام ملف google-services.json المدمج؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          TextButton(onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.clear();
            exit(0);
          }, child: const Text("تأكيد وحذف", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("تم التحديث بنجاح ✅"),
        content: const Text("تم تغيير وجهة قاعدة البيانات. يجب إغلاق التطبيق وفتحه يدوياً لتطبيق التغييرات الجديدة."),
        actions: [
          ElevatedButton(
              onPressed: () => exit(0),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
              child: const Text("إغلاق التطبيق الآن",style: TextStyle(color: Colors.white),)
          )
        ],
      ),
    );
  }
}