import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  String _selectedPackage = "الأساسية";
  bool _isLoading = false;

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('subscription_requests').add({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'cafeName': _cafeNameController.text.trim(),
        'requestedPackage': _selectedPackage,
        'status': 'pending', // حالة الطلب قيد الانتظار
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("تم إرسال طلبك بنجاح ✅"),
            content: const Text("سيتواصل معك فريق الإدارة قريباً لتزويدك بكود التفعيل وتنشيط حسابك."),
            actions: [
              TextButton(onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              }, child: const Text("حسناً"))
            ],
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("حدث خطأ: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("طلب اشتراك جديد")),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const Icon(Icons.assignment_ind_outlined, size: 80, color: Colors.brown),
                  const SizedBox(height: 20),
                  const Text("سجل بياناتك وسنتواصل معك", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 30),
                  _buildField(_nameController, "اسمك الشخصي", Icons.person),
                  const SizedBox(height: 15),
                  _buildField(_phoneController, "رقم الهاتف / واتساب", Icons.phone, isPhone: true),
                  const SizedBox(height: 15),
                  _buildField(_cafeNameController, "اسم الكافيه المقترح", Icons.store),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    value: _selectedPackage,
                    decoration: InputDecoration(labelText: "الحزمة المطلوبة", border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))),
                    items: ["الأساسية", "الاحترافية", "VIP"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() => _selectedPackage = v!),
                  ),
                  const SizedBox(height: 40),
                  _isLoading 
                    ? const CircularProgressIndicator()
                    : SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: _submitRequest,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.brown,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                          ),
                          child: const Text("إرسال الطلب الآن", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon, {bool isPhone = false}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))),
      validator: (v) => v!.isEmpty ? "هذا الحقل مطلوب" : null,
    );
  }
}
