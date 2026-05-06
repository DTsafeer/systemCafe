import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'LoginPage.dart';
import 'package:shared_preferences/shared_preferences.dart';
class RegisterCafePage extends StatefulWidget {
  final String cafeId;
  const RegisterCafePage({super.key, required this.cafeId});

  @override
  State<RegisterCafePage> createState() => _RegisterCafePageState();
}

class _RegisterCafePageState extends State<RegisterCafePage> {
  final _formKey = GlobalKey<FormState>();

  final nameCont = TextEditingController();
  final cafeNameCont = TextEditingController();
  final emailCont = TextEditingController();
  final passCont = TextEditingController();
  final locationCont = TextEditingController();

  bool _isLoading = false;
  bool _isFetchingLocation = false; // متغير خاص لجلب الموقع

  Future<void> _getCurrentLocation() async {
    setState(() => _isFetchingLocation = true);

    try {
      // 1. التحقق من أن خدمة الموقع مفعلة
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'يرجى تفعيل خدمة الموقع (GPS) في الجوال.';
      }

      // 2. طلب إذن الوصول للموقع
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'تم رفض إذن الوصول للموقع. لا يمكن جلب الإحداثيات.';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw 'تم رفض إذن الوصول للموقع بشكل دائم. يرجى تعديله من إعدادات التطبيق.';
      }

      // 3. جلب الموقع
      // استخدام دقة عالية للحصول على أفضل النتائج
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        locationCont.text = "${position.latitude}, ${position.longitude}";
      });
      _showSuccess("تم تحديد الموقع بنجاح!");

    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }

  // دالة حفظ بيانات المدير
  // دالة حفظ بيانات المدير (النسخة المصححة)
  // دالة حفظ بيانات المدير والمنشأة بشكل كامل وتلقائي
  Future<void> _saveAdminData() async {
    // 1. التحقق من صحة المدخلات في النموذج (Form)
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final String userEmail = emailCont.text.trim().toLowerCase();
      final String cafeId = widget.cafeId;

      // 2. 🔥 التحقق من فرادة البريد الإلكتروني قبل أي إجراء آخر
      // نقوم بفحص مستند المستخدم بناءً على الايميل (Document ID)
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(userEmail);
      final userSnapshot = await userDocRef.get();

      if (userSnapshot.exists) {
        // إذا وجدنا المستند، فهذا يعني أن الايميل مستخدم مسبقاً
        throw 'هذا البريد الإلكتروني (اسم المستخدم) مسجل مسبقاً في النظام. يرجى استخدام بريد آخر.';
      }

      // 3. تحديث بيانات المنشأة في مجموعة 'cafes'
      await FirebaseFirestore.instance.collection('cafes').doc(cafeId).set({
        'cafeName': cafeNameCont.text.trim(),
        'adminName': nameCont.text.trim(),
        'location_gps': locationCont.text.trim(),
        'setupCompleted': true,
        'isActive': true,
        'isUsed': true,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 4. إنشاء حساب المستخدم (المدير) في مجموعة 'users'
      // نستخدم الـ userDocRef الذي عرفناه في الأعلى
      await userDocRef.set({
        'username': userEmail,
        'email': userEmail,
        'password': passCont.text.trim(),
        'name': nameCont.text.trim(),
        'role': 'admin',
        'cafeId': cafeId,
        'isActive': true,
        'isOnline': false,
        'permissions': {
          'canManageUsers': true,
          'canViewReports': true,
          'canViewInventory': true,
          'canViewDashboard': true,
          'canEditMenu': true,
          'canManageTables': true,
          'canEditTable': true,
          'canDeleteTable': true,
          'canMakeOrders': true,
          'canPayOrders': true,
          'canDeleteOrders': true,
          'canViewActiveOrders': true,
          'canViewKitchen': true,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 5. حفظ كود المنشأة في ذاكرة الهاتف (لضمان بقاء الألوان والهوية صحيحة)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cafe_id', cafeId);

      // 6. عرض رسالة نجاح والتوجه لصفحة تسجيل الدخول
      if (mounted) {
        _showSuccess("تم إعداد النظام بنجاح! يمكنك الآن تسجيل الدخول.");

        // إفراغ المسار والانتقال لصفحة اللوجن
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
        );
      }
    } catch (e) {
      // إظهار الخطأ سواء كان من Firestore أو خطأ البريد المكرر
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("إكمال إعداد المنشأة")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ... الحقول الأخرى ...
              TextFormField(controller: nameCont, validator: (v) => v!.isEmpty ? 'الحقل مطلوب' : null, decoration: const InputDecoration(labelText: "اسم مدير المنشأة", prefixIcon: Icon(Icons.person))),
              const SizedBox(height: 15),
              TextFormField(controller: cafeNameCont, validator: (v) => v!.isEmpty ? 'الحقل مطلوب' : null, decoration: const InputDecoration(labelText: "اسم الكافي الرسمي", prefixIcon: Icon(Icons.coffee))),
              const SizedBox(height: 15),
              TextFormField(
                controller: emailCont,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: "البريد الإلكتروني (اسم المستخدم)",
                  prefixIcon: Icon(Icons.email),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'الحقل مطلوب';
                  // تعبير نمطي للتحقق من البريد الإلكتروني
                  final bool emailValid = RegExp(
                      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+")
                      .hasMatch(v);
                  if (!emailValid) {
                    return 'يرجى إدخال بريد إلكتروني صحيح (مثال: name@mail.com)';
                  }
                  return null;
                },
              ),              const SizedBox(height: 15),
              TextFormField(
                controller: passCont,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "كلمة المرور",
                  prefixIcon: Icon(Icons.lock),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'الحقل مطلوب';
                  if (v.length < 8) return 'يجب أن تكون كلمة المرور 8 خانات على الأقل';

                  // شروط إضافية لقوة كلمة المرور (اختياري يمكنك تفعيلها)
                  if (!v.contains(RegExp(r'[A-Z]'))) return 'يجب أن تحتوي على حرف كبير واحد على الأقل';
                  if (!v.contains(RegExp(r'[a-z]'))) return 'يجب أن تحتوي على حرف صغير واحد على الأقل';
                  if (!v.contains(RegExp(r'[0-9]'))) return 'يجب أن تحتوي على رقم واحد على الأقل';

                  return null;
                },
              ),              const SizedBox(height: 15),

              // --- حقل الموقع الجغرافي مع زر خاص به ---
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: locationCont,
                      readOnly: true, // جعله للقراءة فقط لتجنب التعديل اليدوي
                      decoration: const InputDecoration(
                        labelText: "الموقع الجغرافي (GPS)",
                        prefixIcon: Icon(Icons.map),
                      ),
                    ),
                  ),
                  // زر جلب الموقع مع مؤشر تحميل خاص به
                  _isFetchingLocation
                      ? const Padding(padding: EdgeInsets.all(8.0), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator()))
                      : IconButton(
                    icon: const Icon(Icons.my_location, color: Colors.blue, size: 30),
                    onPressed: _getCurrentLocation,
                  ),
                ],
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saveAdminData,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.brown),
                  child: const Text("حفظ وإنشاء الحساب", style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
