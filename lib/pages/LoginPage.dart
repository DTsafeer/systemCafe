import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'SuperAdminPage.dart';
import 'homepage.dart';
import 'user_model.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // تعريف وحدات التحكم للنصوص
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('isLoggedIn') == true) {
      _navigateToTarget();
    }
  }

  // الدالة الأساسية لتسجيل الدخول التقليدي
  Future<void> _handleLogin() async {
    final String username = _userController.text.trim().toLowerCase();
    final String password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showError("يرجى إدخال اسم المستخدم وكلمة المرور");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // البحث في Firestore عن مستخدم يطابق الاسم وكلمة المرور
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: username)
          .where('password', isEqualTo: password)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        throw 'اسم المستخدم أو كلمة المرور غير صحيحة';
      }

      final userDoc = userQuery.docs.first;
      final userData = userDoc.data();

      if (userData['isActive'] == false) throw 'عذراً، هذا الحساب معطل حالياً.';

      bool isSuper = (userData['isOwner'] == true || userData['role'] == 'super_admin');

      if (isSuper) {
        setState(() => _isLoading = false);
        _showMasterKeyDialog(username, userData, userDoc.id);
      } else {
        await _proceedWithLogin(username, userData, userDoc.id);
      }

    } catch (e) {
      _showError(e.toString());
      setState(() => _isLoading = false);
    }
  }

  // نفس منطق الـ Master Key الخاص بك
  void _showMasterKeyDialog(String username, Map<String, dynamic> userData, String docId) {
    final TextEditingController _keyController = TextEditingController();
    const String secretMasterKey = "salah120212581@admin.flora";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("تأكيد هوية المدير"),
        content: TextField(
          controller: _keyController,
          obscureText: true,
          decoration: const InputDecoration(labelText: "Security Key"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () async {
              if (_keyController.text == secretMasterKey) {
                Navigator.pop(context);
                await _proceedWithLogin(username, userData, docId);
              } else {
                _showError("كود الأمان خاطئ");
              }
            },
            child: const Text("تأكيد"),
          )
        ],
      ),
    );
  }

  Future<void> _proceedWithLogin(String username, Map<String, dynamic> userData, String docId) async {
    final prefs = await SharedPreferences.getInstance();
    String newSessionToken = DateTime.now().millisecondsSinceEpoch.toString();

    await FirebaseFirestore.instance.collection('users').doc(docId).update({
      'currentSessionToken': newSessionToken,
      'isOnline': true,
      'lastLogin': FieldValue.serverTimestamp(),
    });

    await prefs.setString('session_email', username);
    await prefs.setString('session_token', newSessionToken); // حفظ التوكن للتحقق من الجلسة
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('cafe_id', userData['cafeId'] ?? "");
    _navigateToTarget();
  }

  void _navigateToTarget() async {
    if (!mounted) return;
    
    final prefs = await SharedPreferences.getInstance();
    final String username = prefs.getString('session_email') ?? "";
    
    if (username.isEmpty) return;

    final userQuery = await FirebaseFirestore.instance.collection('users').where('username', isEqualTo: username).limit(1).get();

    if (userQuery.docs.isNotEmpty && mounted) {
      final userData = userQuery.docs.first.data();
      final User currentUser = User.fromMap(userData, userQuery.docs.first.id);

      if (userData['role'] == 'super_admin' || userData['isOwner'] == true) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SuperAdminPage()));
      } else {
        MyApp.updateTheme(context);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => Homepage(currentUser: currentUser)));
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.brown[50],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            children: [
              const Icon(Icons.local_cafe, size: 80, color: Colors.brown),
              const SizedBox(height: 20),
              const Text("Flora Cafe Login", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.brown)),
              const SizedBox(height: 40),
              TextField(
                controller: _userController,
                decoration: InputDecoration(
                  labelText: "اسم المستخدم",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  prefixIcon: const Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: "كلمة المرور",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                onPressed: _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.brown,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text("تسجيل الدخول", style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
