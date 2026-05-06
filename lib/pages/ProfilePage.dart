import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfilePage extends StatefulWidget {
  final User user;
  const ProfilePage({super.key, required this.user});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isLoading = false;
  String? _currentImageUrl;
  late String _currentName;

  final String cloudName = "dbjnnbhaw";
  final String uploadPreset = "floracafe";

  @override
  void initState() {
    super.initState();
    _currentImageUrl = widget.user.profileImageUrl;
    _currentName = widget.user.name;
  }

  // --- دالة تحديث اسم المستخدم ---
  void _showEditNameDialog() {
    final theme = Theme.of(context);
    final nameController = TextEditingController(text: _currentName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Row(
          children: [
            Icon(Icons.edit, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            const Text("تغيير الاسم", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: "الاسم الجديد",
            filled: true,
            fillColor: theme.scaffoldBackgroundColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("إلغاء", style: TextStyle(color: theme.disabledColor))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              String newName = nameController.text.trim();
              if (newName.isEmpty) return;

              try {
                // التأكد من استخدام doc id الصحيح
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.user.id)
                    .update({'name': newName});

                setState(() => _currentName = newName);
                if (mounted) Navigator.pop(context);
                _showSnackBar("تم تحديث الاسم بنجاح ✅", Colors.green);
              } catch (e) {
                debugPrint("Update Name Error: $e");
                _showSnackBar("حدث خطأ في تحديث الاسم", Colors.red);
              }
            },
            child: const Text("حفظ", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // --- دالة رفع الصورة إلى Cloudinary ---
  Future<void> _uploadImageToCloudinary() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image == null) return;

    setState(() => _isLoading = true);
    try {
      final url = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
      var request = http.MultipartRequest('POST', url);
      request.fields['upload_preset'] = uploadPreset;
      final bytes = await image.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: image.name));

      var response = await http.Response.fromStream(await request.send());
      var responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        String newUrl = responseData['secure_url'];
        await FirebaseFirestore.instance.collection('users').doc(widget.user.id).update({'profileImageUrl': newUrl});
        setState(() => _currentImageUrl = newUrl);
        _showSnackBar("تم تحديث الصورة بنجاح ✅", Colors.green);
      } else {
        _showSnackBar("فشل رفع الصورة على الخادم", Colors.red);
      }
    } catch (e) {
      debugPrint("Upload Image Error: $e");
      _showSnackBar("خطأ في الاتصال بالإنترنت", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- دالة تحديث كلمة المرور ---
  void _showChangePasswordDialog() {
    final theme = Theme.of(context);
    final oldPassController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();
    bool isObscure = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: theme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          title: Row(
            children: [
              Icon(Icons.lock_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              const Text("تحديث كلمة المرور", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogField(theme, oldPassController, "كلمة المرور الحالية", Icons.key, isObscure),
                const SizedBox(height: 12),
                _buildDialogField(theme, newPassController, "كلمة المرور الجديدة", Icons.lock_reset, isObscure),
                const SizedBox(height: 12),
                _buildDialogField(theme, confirmPassController, "تأكيد الكلمة الجديدة", Icons.check_circle_outline, isObscure),
                TextButton(
                  onPressed: () => setDialogState(() => isObscure = !isObscure),
                  child: Text(isObscure ? "إظهار الكلمات" : "إخفاء الكلمات", style: const TextStyle(fontSize: 12)),
                )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text("إلغاء", style: TextStyle(color: theme.disabledColor))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                // التحقق من صحة الكلمة القديمة
                if (oldPassController.text.trim() != widget.user.password) {
                  _showSnackBar("كلمة المرور الحالية غير صحيحة ❌", Colors.red);
                  return;
                }

                // التحقق من تطابق الجديدتين
                if (newPassController.text.isEmpty || newPassController.text != confirmPassController.text) {
                  _showSnackBar("كلمة المرور الجديدة غير متطابقة ❌", Colors.orange);
                  return;
                }

                // التحقق من الطول
                if (newPassController.text.length < 4) {
                  _showSnackBar("كلمة المرور قصيرة جداً ⚠️", Colors.orange);
                  return;
                }

                try {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(widget.user.id)
                      .update({'password': newPassController.text.trim()});

                  // ✅ التعديل هنا: تحديث الذاكرة المحلية للجلسة لضمان الدخول التلقائي
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('session_password', newPassController.text.trim());

                  if (mounted) Navigator.pop(context);
                  _showSnackBar("تم تغيير كلمة المرور بنجاح ✅", Colors.green);
                } catch (e) {
                  debugPrint("Change Password Error: $e");
                  _showSnackBar("حدث خطأ في قاعدة البيانات", Colors.red);
                }
              },
              child: const Text("تحديث الآن", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogField(ThemeData theme, TextEditingController controller, String label, IconData icon, bool obscure) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: theme.colorScheme.primary),
        filled: true,
        fillColor: theme.scaffoldBackgroundColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(theme, primaryColor),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  _buildProfileDetails(theme, primaryColor),
                  const SizedBox(height: 20),
                  _buildAccountActions(theme, primaryColor),
                  const SizedBox(height: 40),
                  Text(
                    "يتم استضافة الصور خارجياً لضمان أفضل أداء",
                    style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(ThemeData theme, Color primaryColor) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      elevation: 0,
      backgroundColor: primaryColor,
      foregroundColor: theme.colorScheme.onPrimary,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryColor, primaryColor.withOpacity(0.8)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 50),
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.colorScheme.onPrimary, width: 4),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15)],
                    ),
                    child: CircleAvatar(
                      radius: 65,
                      backgroundColor: theme.disabledColor.withOpacity(0.1),
                      backgroundImage: _currentImageUrl != null && _currentImageUrl!.isNotEmpty
                          ? NetworkImage(_currentImageUrl!)
                          : null,
                      child: (_currentImageUrl == null || _currentImageUrl!.isEmpty)
                          ? Icon(Icons.person, size: 70, color: theme.colorScheme.onPrimary)
                          : null,
                    ),
                  ),
                  GestureDetector(
                    onTap: _isLoading ? null : _uploadImageToCloudinary,
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      child: _isLoading
                          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor))
                          : Icon(Icons.camera_alt, color: primaryColor, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 30),
                  Text(
                    _currentName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, color: theme.colorScheme.onPrimary.withOpacity(0.7), size: 18),
                    onPressed: _showEditNameDialog,
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(top: 5),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onPrimary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.user.role.name.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileDetails(ThemeData theme, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
        border: Border.all(color: theme.dividerColor.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          _infoRow(theme, Icons.email_outlined, "البريد الإلكتروني", widget.user.email, primaryColor),
          Divider(height: 40, color: theme.dividerColor.withOpacity(0.1)),
          _infoRow(theme, Icons.badge_outlined, "معرف الحساب", widget.user.id, primaryColor),
        ],
      ),
    );
  }

  Widget _infoRow(ThemeData theme, IconData icon, String label, String value, Color primaryColor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: primaryColor, size: 22),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor)),
              Text(value, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountActions(ThemeData theme, Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          leading: Icon(Icons.lock_reset, color: theme.colorScheme.secondary),
          title: Text("تحديث كلمة المرور", style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
          trailing: Icon(Icons.arrow_forward_ios, size: 16, color: theme.disabledColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          onTap: _showChangePasswordDialog,
        ),
      ),
    );
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        margin: const EdgeInsets.all(20),
      ),
    );
  }
}