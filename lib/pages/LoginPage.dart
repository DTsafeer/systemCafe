import 'package:flutter/material.dart';
import '../widgets/app_components.dart';
import 'AuthService.dart';
import 'SuperAdminPage.dart';
import 'homepage.dart';
import 'user_model.dart';
import 'ActivationPage.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
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
    setState(() => _isLoading = true);
    final user = await AuthService.checkAutoLogin();
    if (user != null && mounted) {
      _navigateToTarget(user);
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogin() async {
    final String username = _userController.text.trim().toLowerCase();
    final String password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final user = await AuthService.login(username, password);
      await AuthService.saveSession(user);
      if (mounted) _navigateToTarget(user);
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString();
        if (errorMsg == 'DEVICE_MISMATCH') {
          errorMsg = "❌ هذا الحساب مرتبط بجهاز آخر بالفعل. يرجى مراجعة مدير النظام لفك الارتباط.";
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.redAccent,
        ));
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToTarget(User user) {
    if (user.role == UserRole.super_admin) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SuperAdminPage()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomePage(currentUser: user)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          width: double.infinity, height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [theme.colorScheme.primary, theme.colorScheme.primary.withOpacity(0.7)], 
              begin: Alignment.topCenter, end: Alignment.bottomCenter
            )
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: _LoginCard(
                userController: _userController,
                passwordController: _passwordController,
                isLoading: _isLoading,
                obscurePassword: _obscurePassword,
                onObscurePressed: () => setState(() => _obscurePassword = !_obscurePassword),
                onLoginPressed: _handleLogin,
                onActivationPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivationPage())),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  final TextEditingController userController;
  final TextEditingController passwordController;
  final bool isLoading;
  final bool obscurePassword;
  final VoidCallback onObscurePressed;
  final VoidCallback onLoginPressed;
  final VoidCallback onActivationPressed;

  const _LoginCard({
    required this.userController,
    required this.passwordController,
    required this.isLoading,
    required this.obscurePassword,
    required this.onObscurePressed,
    required this.onLoginPressed,
    required this.onActivationPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 450),
      child: Container(
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(30), 
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 25, offset: Offset(0, 10))]
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.coffee_rounded, size: 60, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 15),
            const Text("FLORA CAFE POS", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const Text("نظام إدارة المقاهي والمطاعم", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 35),
            TextField(controller: userController, decoration: AppComponents.fieldInput("اسم المستخدم", Icons.person_outline)),
            const SizedBox(height: 20),
            TextField(
              controller: passwordController, 
              obscureText: obscurePassword, 
              decoration: AppComponents.fieldInput("كلمة المرور", Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility), 
                  onPressed: onObscurePressed
                )
              )
            ),
            const SizedBox(height: 40),
            isLoading 
              ? const CircularProgressIndicator() 
              : SizedBox(
                  width: double.infinity, height: 55, 
                  child: ElevatedButton(
                    onPressed: onLoginPressed, 
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 5
                    ), 
                    child: const Text("دخول للنظام", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
                  )
                ),
            const SizedBox(height: 25),
            TextButton(
              onPressed: onActivationPressed,
              child: Text("تفعيل النظام / إدخال رمز الترخيص", style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
