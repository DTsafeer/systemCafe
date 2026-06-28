import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:ai_barcode_scanner/ai_barcode_scanner.dart';
import '../widgets/app_components.dart';
import '../widgets/product_search_sheet.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import 'CategoryManagementPage.dart';
import 'activity_logger.dart';

class AddProduct extends StatefulWidget {
  final User currentUser;
  final Map<String, dynamic>? productToEdit;
  final String? initialBarcode; // إضافة باركود ابتدائي عند الفتح من صفحة البيع

  const AddProduct({super.key, required this.currentUser, this.productToEdit, this.initialBarcode});

  @override
  State<AddProduct> createState() => _AddProductState();
}

class _AddProductState extends State<AddProduct> {
  final nameController = TextEditingController();
  final priceController = TextEditingController(); 
  final costPriceController = TextEditingController(); 
  final barcodeController = TextEditingController();
  
  final taxController = TextEditingController();
  final extraCostsController = TextEditingController();
  final extraDetailsController = TextEditingController();

  bool isManualPrice = false;
  bool isUploading = false;
  bool _isSaving = false;
  String? imageUrl;
  List<String> categories = ["عام"];
  String? selectedCategory;

  List<Map<String, dynamic>> selectedIngredients = [];
  bool _isEditMode = false;
  String? _linkedInventoryId; 

  final String cloudName = "dbjnnbhaw";
  final String uploadPreset = "floracafe";

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.productToEdit != null;
    
    if (_isEditMode) {
      nameController.text = widget.productToEdit!['name'] ?? "";
      priceController.text = (widget.productToEdit!['price'] ?? 0.0).toString();
      costPriceController.text = (widget.productToEdit!['costPrice'] ?? 0.0).toString();
      barcodeController.text = widget.productToEdit!['barcode'] ?? "";
      imageUrl = widget.productToEdit!['imagePath'];
      selectedCategory = widget.productToEdit!['category']?.toString().trim();
      isManualPrice = widget.productToEdit!['isManualPrice'] ?? (widget.productToEdit!['price'] == 0);
      
      _linkedInventoryId = widget.productToEdit!['id'];
      
      taxController.text = (widget.productToEdit!['tax'] ?? "").toString();
      extraCostsController.text = (widget.productToEdit!['extraCosts'] ?? "").toString();
      extraDetailsController.text = widget.productToEdit!['extraDetails'] ?? "";

      if (selectedCategory != null && !categories.contains(selectedCategory)) {
        categories.add(selectedCategory!);
      }
      selectedIngredients = List<Map<String, dynamic>>.from(widget.productToEdit!['ingredients'] ?? []);
    } else if (widget.initialBarcode != null) {
      // إذا تم تمرير باركود من صفحة البيع، نضعه في الخانة تلقائياً
      barcodeController.text = widget.initialBarcode!;
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final String managerId = widget.currentUser.parentId ?? widget.currentUser.id;
      final snapshot = await FirebaseFirestore.instance
          .collection('categories')
          .where('cafeId', isEqualTo: widget.currentUser.cafeId)
          .where('parentId', isEqualTo: managerId)
          .get();

      if (mounted) {
        setState(() {
          final fetched = snapshot.docs.map((doc) => doc['name'].toString().trim()).toList();
          Set<String> allCats = {"عام", ...fetched};
          if (selectedCategory != null) allCats.add(selectedCategory!);
          categories = allCats.toList();
          selectedCategory ??= "عام";
        });
      }
    } catch (e) { debugPrint("Error: $e"); }
  }

  void _linkExistingInventory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) => ProductSearchSheet(
        activeCafeId: widget.currentUser.cafeId,
        managerId: widget.currentUser.parentId ?? widget.currentUser.id,
        onItemSelected: (id, name, qty, unit) {
          setState(() {
            _linkedInventoryId = id;
            nameController.text = name;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم ربط المنتج بصنف من المخزن")));
        },
      ),
    );
  }

  Future<void> _scanBarcode() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AiBarcodeScanner(
          onDispose: () => Navigator.of(context).pop(),
          onDetect: (BarcodeCapture capture) {
            final String? value = capture.barcodes.first.rawValue;
            if (value != null) {
              setState(() {
                barcodeController.text = value;
              });
              Navigator.of(context).pop();
            }
          },
        ),
      ),
    );
  }

  void _saveProduct() async {
    if (nameController.text.isEmpty || (priceController.text.isEmpty && !isManualPrice)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إكمال البيانات الأساسية")));
      return;
    }
    
    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);
    
    final String productId = _linkedInventoryId ?? (_isEditMode ? widget.productToEdit!['id'] : FirebaseFirestore.instance.collection('products').doc().id);
    
    final sellingPrice = isManualPrice ? 0.0 : (double.tryParse(priceController.text.trim()) ?? 0.0);
    final rawCostPrice = double.tryParse(costPriceController.text.trim()) ?? 0.0;
    final taxPercent = double.tryParse(taxController.text) ?? 0.0;
    final extraCosts = double.tryParse(extraCostsController.text) ?? 0.0;

    final double finalCostPrice = (rawCostPrice + extraCosts) * (1 + (taxPercent / 100));

    final productData = {
      'name': nameController.text.trim(),
      'price': sellingPrice,
      'costPrice': rawCostPrice, 
      'finalCostPrice': finalCostPrice, 
      'barcode': barcodeController.text.trim(),
      'category': selectedCategory,
      'imagePath': imageUrl ?? "",
      'ingredients': List.from(selectedIngredients),
      'isManualPrice': isManualPrice,
      'trackInventory': true, 
      'cafeId': widget.currentUser.cafeId,
      'parentId': widget.currentUser.parentId ?? widget.currentUser.id,
      'isAvailable': true,
      'tax': taxPercent,
      'extraCosts': extraCosts,
      'extraDetails': extraDetailsController.text.trim(),
      'created_at': _isEditMode ? widget.productToEdit!['created_at'] : FieldValue.serverTimestamp(),
      'last_update': FieldValue.serverTimestamp(),
    };

    try {
      final batch = FirebaseFirestore.instance.batch();
      
      final productRef = FirebaseFirestore.instance.collection('products').doc(productId);
      batch.set(productRef, productData, SetOptions(merge: true));

      final inventoryRef = FirebaseFirestore.instance.collection('inventory').doc(productId);
      batch.set(inventoryRef, {
        'sellingPrice': sellingPrice,
        'costPrice': finalCostPrice, 
        'lastCostPrice': finalCostPrice,
        'barcode': productData['barcode'], 
        'name': productData['name'],
      }, SetOptions(merge: true));

      await batch.commit();

      await ActivityLogger.log(
        cafeId: widget.currentUser.cafeId,
        parentId: widget.currentUser.parentId ?? widget.currentUser.id,
        userId: widget.currentUser.id,
        userName: widget.currentUser.name,
        action: _isEditMode ? "منيو - تعديل" : "منيو - إضافة",
        details: "تحديث ${productData['name']}: باركود (${productData['barcode']})",
      );

      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ أثناء الحفظ: $e")));
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    priceController.dispose();
    costPriceController.dispose();
    barcodeController.dispose();
    taxController.dispose();
    extraCostsController.dispose();
    extraDetailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLinked = _linkedInventoryId != null;

    return MainLayout(
      currentUser: widget.currentUser, currentPage: 'menu',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_isEditMode ? "تعديل منتج" : "إضافة منتج مبيعات", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), 
          backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0.5,
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildImagePicker(theme.primaryColor),
                  const SizedBox(height: 25),
                  Row(
                    children: [
                      Expanded(child: TextField(
                        controller: nameController, 
                        readOnly: isLinked,
                        decoration: AppComponents.fieldInput("اسم المنتج", isLinked ? Icons.lock_outline : Icons.fastfood_outlined)
                      )),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(onPressed: _isEditMode ? null : _linkExistingInventory, icon: const Icon(Icons.link), tooltip: "ربط مع صنف من المخزن"),
                    ],
                  ),
                  if (isLinked)
                    const Padding(
                      padding: EdgeInsets.only(top: 8, right: 12),
                      child: Text("هذا المنتج مرتبط بالمخزن، يتم تحديث البيانات تلقائياً.", style: TextStyle(color: Colors.blueGrey, fontSize: 10, fontStyle: FontStyle.italic)),
                    ),
                  const SizedBox(height: 15),
                  
                  TextField(
                    controller: barcodeController, 
                    decoration: InputDecoration(
                      labelText: "الباركود (رقم علبة الكولا مثلاً)",
                      prefixIcon: const Icon(Icons.qr_code_scanner),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.camera_alt_rounded, color: Colors.blue),
                        onPressed: _scanBarcode,
                        tooltip: "مسح بالكاميرا",
                      ),
                      filled: true, fillColor: Colors.grey[50],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      helperText: "يمكنك كتابة الرقم يدوياً أو استخدام القارئ",
                    )
                  ),
                  
                  const SizedBox(height: 25),
                  const Text("بيانات التسعير والربح", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("سعر متغير (ميزان / وزن)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    value: isManualPrice, activeColor: theme.primaryColor,
                    onChanged: (v) => setState(() => isManualPrice = v),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: costPriceController, 
                            readOnly: isLinked,
                            keyboardType: TextInputType.number, 
                            decoration: AppComponents.fieldInput("سعر التكلفة", isLinked ? Icons.lock_clock_outlined : Icons.shopping_bag_outlined)
                          ),
                          if (isLinked)
                            const Padding(
                              padding: EdgeInsets.only(top: 4, right: 8),
                              child: Text("التكلفة ممررة من المخزن (WAC)", style: TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      )),
                      const SizedBox(width: 10),
                      if (!isManualPrice)
                        Expanded(child: TextField(controller: priceController, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("سعر البيع", Icons.sell_outlined))),
                    ],
                  ),
                  const SizedBox(height: 25),
                  const Text("الضرائب والتكاليف الإضافية", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: taxController, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("الضريبة (%)", Icons.percent))),
                      const SizedBox(width: 10),
                      Expanded(child: TextField(controller: extraCostsController, keyboardType: TextInputType.number, decoration: AppComponents.fieldInput("تكاليف إضافية", Icons.add_card_outlined))),
                    ],
                  ),
                  const SizedBox(height: 15),
                  TextField(controller: extraDetailsController, decoration: AppComponents.fieldInput("تفصيل التكاليف الإضافية", Icons.description_outlined)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: _buildCategoryDropdown()),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryManagementPage(currentUser: widget.currentUser))).then((_) => _loadCategories()), icon: const Icon(Icons.add)),
                    ],
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed: (_isSaving || isUploading) ? null : _saveProduct,
                    style: ElevatedButton.styleFrom(backgroundColor: theme.primaryColor, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                    child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : Text(_isEditMode ? "تحديث البيانات" : "حفظ المنتج في المنيو", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            if (isUploading || _isSaving)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePicker(Color primary) => GestureDetector(
    onTap: isUploading ? null : _pickImage,
    child: Container(
      height: 150, width: double.infinity,
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.grey[200]!, width: 2)),
      child: isUploading ? const Center(child: CircularProgressIndicator()) : (imageUrl == null ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo_outlined, size: 40, color: primary.withOpacity(0.5)), const Text("إضافة صورة", style: TextStyle(color: Colors.grey, fontSize: 12))]) : ClipRRect(borderRadius: BorderRadius.circular(23), child: Image.network(imageUrl!, fit: BoxFit.cover))),
    ),
  );

  Widget _buildCategoryDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15)),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        value: categories.contains(selectedCategory) ? selectedCategory : (categories.isNotEmpty ? categories.first : null), 
        isExpanded: true, 
        items: categories.toSet().map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
        onChanged: (v) => setState(() => selectedCategory = v),
      )),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image == null) return;
    setState(() => isUploading = true);
    try {
      final url = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
      final bytes = await image.readAsBytes();
      var request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: image.name));
      var response = await http.Response.fromStream(await request.send());
      if (response.statusCode == 200) {
        var responseData = jsonDecode(response.body);
        setState(() { imageUrl = responseData['secure_url']; isUploading = false; });
      }
    } catch (e) { 
      setState(() => isUploading = false); 
    }
  }
}
