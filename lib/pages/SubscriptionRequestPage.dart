import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionRequestPage extends StatefulWidget {
  const SubscriptionRequestPage({super.key});

  @override
  State<SubscriptionRequestPage> createState() => _SubscriptionRequestPageState();
}

class _SubscriptionRequestPageState extends State<SubscriptionRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cafeNameController = TextEditingController();

  // دالة إرسال الطلب لواتساب وللقاعدة
  void _submitRequest() async {
    if (_formKey.currentState!.validate()) {
      String name = _nameController.text.trim();
      String cafe = _cafeNameController.text.trim();
      String phone = _phoneController.text.trim();

      String message = "طلب اشتراك جديد في Flora Cafe:\n"
          "صاحب الكافيه: $name\n"
          "اسم الكافيه: $cafe\n"
          "رقم الجوال: $phone";

      // اكتب رقمك هنا بالصيغة الدولية بدون (+) أو أصفار في البداية
      String _whatsappNumber = "972592623701"; // الرقم الافتراضي
      // 1. رابط لفتح التطبيق مباشرة (Deep Link)
      final Uri whatsappAppUrl = Uri.parse("whatsapp://send?phone=$_whatsappNumber&text=${Uri.encodeComponent(message)}");

      // 2. رابط لفتح المتصفح (Web Link) كخطة بديلة
      final Uri whatsappWebUrl = Uri.parse("https://wa.me/$_whatsappNumber?text=${Uri.encodeComponent(message)}");

      try {
        // المحاولة الأولى: محاولة فتح التطبيق
        bool launched = await launchUrl(whatsappAppUrl);

        if (!launched) {
          // المحاولة الثانية: إذا لم يفتح التطبيق (لأنه غير مثبت مثلاً)، نفتح المتصفح
          await launchUrl(whatsappWebUrl, mode: LaunchMode.externalApplication);
        }
      } catch (e) {
        // المحاولة الأخيرة: فتح الرابط في المتصفح الافتراضي إذا فشل كل ما سبق
        try {
          await launchUrl(whatsappWebUrl, mode: LaunchMode.platformDefault);
        } catch (finalError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("عذراً، لا يمكن فتح الرابط، يرجى التأكد من وجود متصفح إنترنت")),
            );
          }
        }
      }
    }
  }  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("طلب نظام جديد"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const Icon(Icons.storefront, size: 80, color: Colors.brown),
              const SizedBox(height: 20),
              const Text(
                "ابدأ بإدارة كافيهك باحترافية الآن",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text("املأ البيانات وسنقوم بتجهيز النظام لك خلال دقائق"),
              const SizedBox(height: 30),
              _buildTextField(_cafeNameController, "اسم الكافيه", Icons.restaurant),
              const SizedBox(height: 15),
              _buildTextField(_nameController, "اسم صاحب الكافيه", Icons.person),
              const SizedBox(height: 15),
              _buildTextField(_phoneController, "رقم الجوال", Icons.phone, isPhone: true),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: _submitRequest,
                icon: const Icon(Icons.contact_mail_outlined),
                label: const Text("إرسال الطلب عبر واتساب", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isPhone = false}) {
    return TextFormField(
      controller: controller,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
      ),
      validator: (v) => v!.isEmpty ? "هذا الحقل مطلوب" : null,
    );
  }
}