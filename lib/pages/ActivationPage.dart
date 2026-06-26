import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/activation_service.dart';
import '../utils/device_info.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'SetupPage.dart';
import 'SubscriptionRequestPage.dart';
import 'LoginPage.dart';

class ActivationPage extends StatefulWidget {
  const ActivationPage({super.key});

  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String _deviceId = "";

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
    _checkIfDeviceAlreadyLinked(); // فحص تلقائي عند الدخول
  }

  Future<void> _loadDeviceInfo() async {
    String id = await DeviceUtils.getDeviceId();
    if (mounted) setState(() => _deviceId = id);
  }

  // ميزة فريدة: فحص إذا كان الأدمن قد ربط الجهاز يدوياً بالفعل
  Future<void> _checkIfDeviceAlreadyLinked() async {
    setState(() => _isLoading = true);
    try {
      String deviceId = await DeviceUtils.getDeviceId();
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('deviceId', isEqualTo: deviceId)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        // الجهاز مرتبط بموظف بالفعل، نفعله تلقائياً
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_activated', true);
        await prefs.setBool('isSetupComplete', true);
        
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginPage()),
          );
        }
      }
    } catch (e) {
      debugPrint("Auto-check error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _activateApp() async {
    final String code = _codeController.text.trim().toUpperCase();

    if (code.isEmpty) {
      _showSnackBar("يرجى إدخال كود التفعيل أولاً");
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ActivationService.activate(code);

      if (mounted) {
        _showSnackBar("تم تفعيل المنشأة بنجاح!", isSuccess: true);
        Future.delayed(const Duration(seconds: 1), () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const SetupPage()),
          );
        });
      }
    } catch (e) {
      _showSnackBar("خطأ: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Colors.brown[900]!, Colors.brown[600]!, Colors.black],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  // شعار أو أيقونة علوية
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_fix_high_rounded, size: 70, color: Colors.orangeAccent),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "نظام فـلورا كـافيه",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const Text(
                    "تفعيل المنشأة الجديدة",
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  const SizedBox(height: 40),
                  
                  Card(
                    elevation: 20,
                    shadowColor: Colors.black54,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    child: Padding(
                      padding: const EdgeInsets.all(30.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "أدخل كود التفعيل",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _codeController,
                            textAlign: TextAlign.center,
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 20),
                            decoration: InputDecoration(
                              hintText: "FLORA-XXXX",
                              hintStyle: TextStyle(color: Colors.grey[400], letterSpacing: 0, fontSize: 16),
                              prefixIcon: const Icon(Icons.vpn_key_outlined),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.content_paste_rounded, color: Colors.brown),
                                tooltip: "لصق الكود",
                                onPressed: () async {
                                  ClipboardData? data = await Clipboard.getData('text/plain');
                                  if (data != null) {
                                    _codeController.text = data.text ?? "";
                                  }
                                },
                              ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                          ),
                          const SizedBox(height: 30),
                          _isLoading
                              ? const CircularProgressIndicator()
                              : SizedBox(
                                  width: double.infinity,
                                  height: 55,
                                  child: ElevatedButton(
                                    onPressed: _activateApp,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.brown[800],
                                      foregroundColor: Colors.white,
                                      elevation: 5,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                    ),
                                    child: const Text("تـفـعـيل الآن", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // روابط إضافية
                  TextButton(
                    onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage())),
                    child: const Text("لديك حساب مفعل؟ تسجيل الدخول", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // قسم معلومات الجهاز (مهم لميزة إلغاء الارتباط)
                  if (_deviceId.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          const Text("معرف الجهاز الحالي", style: TextStyle(color: Colors.white54, fontSize: 10)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_deviceId, style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace')),
                              const SizedBox(width: 3),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: _deviceId));
                                  _showSnackBar("تم نسخ معرف الجهاز", isSuccess: true);
                                },
                                child: const Icon(Icons.copy, size: 14, color: Colors.orangeAccent),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionRequestPage())),
                    child: const Text("طلب نظام جديد / تواصل مع الدعم", style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
