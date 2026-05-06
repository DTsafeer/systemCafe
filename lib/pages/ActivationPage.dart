import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'LoginPage.dart';
import 'RegisterCafePage.dart';
import 'SubscriptionRequestPage.dart'; // تأكد من صحة مسار صفحة تسجيل الدخول لديك

class ActivationPage extends StatefulWidget {
  const ActivationPage({super.key});

  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  // دالة التفعيل الرئيسية
  Future<void> _activateApp() async {
    final String code = _codeController.text.trim().toUpperCase();

    if (code.isEmpty) {
      _showSnackBar("يرجى إدخال كود التفعيل أولاً");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. البحث عن المنشأة في مجموعة 'cafes' باستخدام الكود (Document ID)
      final doc = await FirebaseFirestore.instance.collection('cafes').doc(code).get();

      if (!doc.exists) {
        throw "عذراً، كود التفعيل هذا غير موجود بالنظام";
      }

      final data = doc.data() as Map<String, dynamic>;

      // ➕ فكرة الاستخدام لمرة واحدة: التحقق مما إذا كان الكود قد استُخدم مسبقاً
      bool isUsed = data['isUsed'] ?? false;
      if (isUsed) {
        throw "عذراً، هذا الكود تم استخدامه مسبقاً لتفعيل منشأة أخرى";
      }

      // --- 2. المعالجة الآمنة للبيانات (حل مشكلة الـ Null) ---
      DateTime expiryDate;
      if (data['expiryDate'] != null && data['expiryDate'] is Timestamp) {
        expiryDate = (data['expiryDate'] as Timestamp).toDate();
      } else {
        expiryDate = DateTime.now().add(const Duration(days: 365));
      }

      bool isActive = data['isActive'] ?? false;

      // 3. التحقق من صلاحية الكود
      if (!isActive) {
        throw "هذا الكود معطل حالياً من قبل الإدارة";
      }

      if (expiryDate.isBefore(DateTime.now())) {
        throw "عذراً، انتهت صلاحية هذا الكود. يرجى التجديد";
      }

      // ➕ فكرة الاستخدام لمرة واحدة: تحديث الكود في الفايربيز فوراً ليصبح "مستخدماً"
      await FirebaseFirestore.instance.collection('cafes').doc(code).update({
        'isUsed': true,
        'activatedAt': FieldValue.serverTimestamp(), // اختياري: تسجيل وقت التفعيل
      });

      // 4. حفظ بيانات التفعيل في ذاكرة الهاتف (SharedPreferences)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cafe_id', doc.id);
      await prefs.setString('cafe_name', data['cafeName'] ?? "Flora Cafe");
      await prefs.setBool('is_activated', true);

      // 5. النجاح والانتقال لصفحة تسجيل الدخول
      if (mounted) {
        _showSnackBar("تم تفعيل المنشأة بنجاح!", isSuccess: true);

        Future.delayed(const Duration(seconds: 1), () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => RegisterCafePage(cafeId: doc.id),
            ),
          );
        });
      }

    } catch (e) {
      _showSnackBar("خطأ: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  // دالة مساعدة لإظهار الرسائل
  void _showSnackBar(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(

      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            colors: [Colors.brown[800]!, Colors.brown[400]!],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Card(
              elevation: 10,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(25.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.vpn_key, size: 80, color: Colors.brown),
                    const SizedBox(height: 20),
                    const Text(
                      "تفعيل النظام",
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.brown),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "يرجى إدخال الكود المستلم من قبل الإدارة لتفعيل المنشأة",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 30),
                    TextField(
                      controller: _codeController,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: "مثلاً: FLORA-VIP",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                    ),
                    const SizedBox(height: 25),
                    _isLoading
                        ? const CircularProgressIndicator()
                        : SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _activateApp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.brown[700],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          "تفعيل الآن",
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SubscriptionRequestPage())),
                      child: const Text("لا تملك نظام خاص بك؟ اطلبه الان"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}