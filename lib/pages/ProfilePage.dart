import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import '../services/profile_service.dart';

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

  @override
  void initState() {
    super.initState();
    _currentImageUrl = widget.user.profileImageUrl;
    _currentName = widget.user.name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return MainLayout(
      currentUser: widget.user,
      currentPage: 'profile',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                children: [
                  _buildHeaderCard(theme, primaryColor),
                  const SizedBox(height: 20),
                  _buildInfoSection(theme, primaryColor),
                  const SizedBox(height: 20),
                  _buildActionsSection(theme, primaryColor),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme, Color primary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: primary.withOpacity(0.3), blurRadius: 15)],
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: Colors.white,
                backgroundImage: _currentImageUrl != null && _currentImageUrl!.isNotEmpty ? NetworkImage(_currentImageUrl!) : null,
                child: (_currentImageUrl == null || _currentImageUrl!.isEmpty) ? Icon(Icons.person, size: 60, color: primary) : null,
              ),
              GestureDetector(
                onTap: _isLoading ? null : _uploadImage,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white,
                  child: _isLoading ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.camera_alt, size: 18, color: primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_currentName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(onPressed: _showEditNameDialog, icon: const Icon(Icons.edit, color: Colors.white70, size: 18)),
            ],
          ),
          Text(widget.user.role.name.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildInfoSection(ThemeData theme, Color primary) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        children: [
          _infoTile(Icons.email_outlined, "البريد الإلكتروني", widget.user.email, primary),
          const Divider(),
          _infoTile(Icons.badge_outlined, "معرف المستخدم", widget.user.id, primary),
        ],
      ),
    );
  }

  Widget _buildActionsSection(ThemeData theme, Color primary) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _showChangePasswordDialog,
        icon: const Icon(Icons.lock_reset),
        label: const Text("تغيير كلمة المرور"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white, foregroundColor: primary,
          side: BorderSide(color: primary),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String val, Color primary) {
    return ListTile(
      leading: Icon(icon, color: primary),
      title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      subtitle: Text(val, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  void _showEditNameDialog() {
    final ctrl = TextEditingController(text: _currentName);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("تغيير الاسم"),
      content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: "الاسم الجديد")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
        ElevatedButton(onPressed: () async {
          if (ctrl.text.isNotEmpty) {
            await ProfileService.updateProfileField(widget.user.id, 'name', ctrl.text.trim());
            setState(() => _currentName = ctrl.text.trim());
            if (mounted) Navigator.pop(ctx);
          }
        }, child: const Text("حفظ")),
      ],
    ));
  }

  Future<void> _uploadImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image == null) return;
    
    setState(() => _isLoading = true);
    final String? newUrl = await ProfileService.uploadImage(image);
    
    if (newUrl != null) {
      await ProfileService.updateProfileField(widget.user.id, 'profileImageUrl', newUrl);
      if (mounted) setState(() => _currentImageUrl = newUrl);
    }
    
    if (mounted) setState(() => _isLoading = false);
  }

  void _showChangePasswordDialog() {
    final newPassCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("تغيير كلمة المرور"),
      content: TextField(controller: newPassCtrl, decoration: const InputDecoration(hintText: "كلمة المرور الجديدة"), obscureText: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
        ElevatedButton(onPressed: () async {
          if (newPassCtrl.text.length >= 4) {
            await ProfileService.updateProfileField(widget.user.id, 'password', newPassCtrl.text.trim());
            if (mounted) {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تحديث كلمة المرور بنجاح ✅")));
            }
          }
        }, child: const Text("تحديث")),
      ],
    ));
  }
}
