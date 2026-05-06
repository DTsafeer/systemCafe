import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'user_model.dart';

class AddProduct extends StatefulWidget {
  final User currentUser;
  const AddProduct({super.key, required this.currentUser});

  @override
  State<AddProduct> createState() => _AddProductState();
}

class _AddProductState extends State<AddProduct> {
  // Controllers and State
  final nameController = TextEditingController();
  final priceController = TextEditingController();
  bool isUploading = false;
  String? imageUrl;
  List<String> categories = [];
  String? selectedCategory;
  bool _toKitchen = true;

  // Cloudinary Settings
  final String cloudName = "dbjnnbhaw";
  final String uploadPreset = "floracafe";

  @override
  void initState() {
    super.initState();
    fetchCategories(); // جلب التصنيفات فور بدء الصفحة
    nameController.addListener(() => setState(() {}));
    priceController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    nameController.dispose();
    priceController.dispose();
    super.dispose();
  }

  // ---  ✅ تم التعديل هنا ✅ ---
  /// جلب التصنيفات الخاصة بهذا الكافيه فقط بالاعتماد على المستخدم الحالي
  Future<void> fetchCategories() async {
    // استخدام cafeId مباشرة من المستخدم الحالي لضمان الدقة
    final String cafeId = widget.currentUser.cafeId;

    if (cafeId.isNotEmpty) {
      final snapshot = await FirebaseFirestore.instance
          .collection('categories')
          .where('cafeId', isEqualTo: cafeId) // فلترة حسب الكافيه
          .get();

      if (mounted) {
        setState(() {
          // فرز التصنيفات أبجدياً لسهولة الوصول
          categories = snapshot.docs.map((doc) => doc['name'] as String).toList()..sort();
        });
      }
    } else {
      _showSnackBar("خطأ: لم يتم تحديد المنشأة للمستخدم", Colors.red);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image == null) return;

    _showSnackBar("جاري رفع الصورة...", Colors.blue, isLoading: true);
    setState(() => isUploading = true);

    try {
      final url = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
      var request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', image.path));

      var response = await http.Response.fromStream(await request.send());

      if (response.statusCode == 200) {
        var responseData = jsonDecode(response.body);
        setState(() => imageUrl = responseData['secure_url']);
        _showSnackBar("تم رفع الصورة بنجاح ✅", Colors.green);
      } else {
        throw "فشل رفع الصورة (خطأ ${response.statusCode})";
      }
    } catch (e) {
      _showSnackBar("خطأ في رفع الصورة: $e ❌", Colors.redAccent);
    } finally {
      if(mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        setState(() => isUploading = false);
      }
    }
  }

  // --- ✅ تم التعديل هنا ✅ ---
  /// حفظ المنتج مع ربطه بالـ cafeId الخاص بالمستخدم الحالي
  Future<void> _saveProduct() async {
    if (nameController.text.isEmpty || priceController.text.isEmpty || selectedCategory == null) {
      _showSnackBar("يرجى إكمال البيانات (الاسم، السعر، التصنيف) ⚠️", Colors.orange);
      return;
    }

    final String cafeId = widget.currentUser.cafeId;
    if (cafeId.isEmpty) {
      _showSnackBar("خطأ: لم يتم التعرف على المنشأة للمستخدم الحالي ❌", Colors.red);
      return;
    }

    setState(() => isUploading = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      DocumentReference productRef = FirebaseFirestore.instance.collection('products').doc();
      String productId = productRef.id;

      DocumentReference inventoryRef = FirebaseFirestore.instance.collection('inventory').doc(productId);

      String productName = nameController.text.trim();

      // 1. حفظ المنتج في قائمة المنيو (مربوط بالـ cafeId)
      batch.set(productRef, {
        'id': productId,
        'cafeId': cafeId, // الربط لضمان عدم تداخل البيانات
        'name': productName,
        'price': double.tryParse(priceController.text.trim()) ?? 0.0,
        'category': selectedCategory,
        'image': imageUrl ?? "",
        'toKitchen': _toKitchen,
        'created_at': FieldValue.serverTimestamp(),
      });

      // 2. حفظ المنتج في المخزن (مربوط بالـ cafeId)
      batch.set(inventoryRef, {
        'id': productId,
        'cafeId': cafeId, // الربط في المخزن أيضاً
        'name': productName,
        'image': imageUrl ?? "",
        'quantity': 0, // الكمية الأولية في المخزن تكون صفر
        'category': selectedCategory,
        'last_updated': FieldValue.serverTimestamp(),
      });
      DocumentReference logRef = FirebaseFirestore.instance.collection('activity_logs').doc();
      batch.set(logRef, {
        'cafeId': widget.currentUser.cafeId,
        'userName': widget.currentUser.name, // اسم الشخص الذي أضاف المنتج
        'action': "إضافة منتج جديد",
        'details': "قام بإضافة المنتج '$productName' بسعر ${priceController.text} ₪ إلى تصنيف $selectedCategory",
        'timestamp': FieldValue.serverTimestamp(),
      });
      await batch.commit();

      _showSnackBar("تم إضافة المنتج للمنيو والمخزن بنجاح ✅", Colors.green);

      // إعادة تعيين الحقول بعد الحفظ
      nameController.clear();
      priceController.clear();
      setState(() {
        imageUrl = null;
        selectedCategory = null;
        _toKitchen = true;
      });

    } catch (e) {
      _showSnackBar("حدث خطأ أثناء الحفظ: $e ❌", Colors.red);
    } finally {
      if (mounted) setState(() => isUploading = false);
    }
  }

  void _showSnackBar(String msg, Color color, {bool isLoading = false}) {
    if(!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (isLoading) const Padding(padding: EdgeInsets.only(right: 12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
            Expanded(child: Text(msg, textAlign: TextAlign.center)),
          ],
        ),
        backgroundColor: color,
        duration: Duration(seconds: isLoading ? 60 : 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteCategory(String categoryName) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("حذف التصنيف؟"),
        content: Text("هل أنت متأكد من حذف '$categoryName'؟ سيؤثر هذا على المنتجات المرتبطة به."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("حذف", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final snap = await FirebaseFirestore.instance
          .collection('categories')
          .where('cafeId', isEqualTo: widget.currentUser.cafeId) // فلترة إضافية للأمان
          .where('name', isEqualTo: categoryName)
          .get();

      for (var doc in snap.docs) {
        await doc.reference.delete();
      }
      // إعادة تعيين القائمة المنسدلة إذا كان التصنيف المحذوف هو المختار
      if (selectedCategory == categoryName) setState(() => selectedCategory = null);
      fetchCategories(); // تحديث القائمة
    }
  }

  // --- ✅ تم التعديل هنا ✅ ---
  /// إضافة تصنيف جديد مع ربطه بالـ cafeId الخاص بالمستخدم الحالي
  Future<void> _addCategoryDialog(ThemeData theme) async {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("إضافة تصنيف جديد"),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: "مثلاً: مشروبات باردة")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () async {
              final String categoryName = c.text.trim();
              if (categoryName.isNotEmpty) {
                // استخدام cafeId مباشرة من المستخدم الحالي
                final String cafeId = widget.currentUser.cafeId;

                await FirebaseFirestore.instance.collection('categories').add({
                  'name': categoryName,
                  'cafeId': cafeId, // ربط التصنيف الجديد بالكافيه الحالي
                });

                // تحديث القائمة واختيار التصنيف الجديد تلقائياً
                await fetchCategories();
                setState(() {
                  selectedCategory = categoryName;
                });

                if(ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text("إضافة"),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final canSave = widget.currentUser.permissions['canEditMenu'] == true;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('إدارة الأصناف', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: primaryColor,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: AbsorbPointer(
        absorbing: isUploading,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: canSave ? _pickImage : null,
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: primaryColor.withOpacity(0.2)),
                    image: imageUrl != null ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover) : null,
                  ),
                  child: isUploading
                      ? Center(child: CircularProgressIndicator(color: primaryColor))
                      : imageUrl == null
                      ? Icon(Icons.add_a_photo_outlined, size: 50, color: primaryColor.withOpacity(0.4))
                      : null,
                ),
              ),
              const SizedBox(height: 20),

              _buildField(theme, nameController, "اسم المنتج", Icons.fastfood_outlined, readOnly: !canSave),
              const SizedBox(height: 15),

              _buildField(theme, priceController, "السعر", Icons.payments_outlined, isNum: true, suffixText: "₪", readOnly: !canSave),
              const SizedBox(height: 15),

              Container(
                decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(15)
                ),
                child: SwitchListTile(
                  title: const Text("إرسال للمطبخ؟", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text("للأصناف التي تحتاج تحضير", style: TextStyle(fontSize: 12)),
                  value: _toKitchen,
                  activeColor: primaryColor,
                  onChanged: canSave ? (val) => setState(() => _toKitchen = val) : null,
                  secondary: Icon(Icons.soup_kitchen_rounded, color: _toKitchen ? primaryColor : Colors.grey),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedCategory,
                          hint: const Text("اختر التصنيف"),
                          isExpanded: true,
                          dropdownColor: theme.cardColor,
                          onChanged: canSave ? (v) => setState(() => selectedCategory = v) : null,
                          items: categories.map((String category) {
                            return DropdownMenuItem<String>(
                              value: category,
                              child: Row(
                                children: [
                                  Expanded(child: Text(category, overflow: TextOverflow.ellipsis)),
                                  if (canSave)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                                      onPressed: () => _deleteCategory(category),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                  if (canSave) ...[
                    const SizedBox(width: 10),
                    _smallBtn(primaryColor, Icons.add, () => _addCategoryDialog(theme)),
                  ]
                ],
              ),
              const SizedBox(height: 30),

              if (canSave)
                SizedBox(
                  height: 55,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isUploading ? Colors.grey : primaryColor,
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 3,
                    ),
                    onPressed: _saveProduct,
                    icon: isUploading ? const SizedBox.shrink() : const Icon(Icons.save_alt_rounded),
                    label: isUploading
                        ? CircularProgressIndicator(color: theme.colorScheme.onPrimary)
                        : const Text("حفظ المنتج", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(ThemeData theme, TextEditingController ctrl, String hint, IconData icon, {bool isNum = false, String? suffixText, bool readOnly = false}) {
    return TextField(
      controller: ctrl,
      readOnly: readOnly,
      keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: TextStyle(color: theme.hintColor),
        prefixIcon: Icon(icon, color: theme.colorScheme.primary),
        suffixText: suffixText,
        suffixStyle: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16),
        filled: true,
        fillColor: theme.cardColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
      ),
    );
  }

  Widget _smallBtn(Color color, IconData icon, VoidCallback onTap) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
