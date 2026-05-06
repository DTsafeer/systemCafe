import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'user_model.dart';

class OrderPage extends StatefulWidget {
  final String tableName;
  final User currentUser;

  const OrderPage({super.key, required this.tableName, required this.currentUser});

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> with TickerProviderStateMixin {
  final CollectionReference productsRef = FirebaseFirestore.instance.collection('products');
  final Map<String, Map<String, dynamic>> selectedProducts = {};
  TabController? _tabController;
  List<String> _currentCategories = [];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  bool _isSearching = false;

  final String cloudName = "dbjnnbhaw";
  final String uploadPreset = "floracafe";

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // دالة تسجيل النشاط (Tracking)
  Future<void> _logAction(String action, String details) async {
    try {
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'cafeId': widget.currentUser.cafeId,
        'userName': widget.currentUser.name,
        'action': action,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("خطأ في تسجيل النشاط: $e");
    }
  }

  void _updateTabController(List<String> newCategories) {
    List<String> finalCategories = ["الكل", ...newCategories];
    if (_currentCategories.join(',') != finalCategories.join(',')) {
      _currentCategories = finalCategories;
      _tabController?.dispose();
      _tabController = TabController(length: finalCategories.length, vsync: this);
      Future.delayed(Duration.zero, () { if (mounted) setState(() {}); });
    }
  }

  void updateQuantity(String productId, Map<String, dynamic> productData, double newQuantity) {
    setState(() {
      if (newQuantity <= 0) {
        selectedProducts.remove(productId);
      } else {
        selectedProducts[productId] = {
          ...productData,
          'quantity': newQuantity,
        };
      }
    });
  }

  // --- نافذة تعديل المنتج مع التتبع ---
  void _showEditProductDialog(String productId, Map<String, dynamic> data) {
    if (widget.currentUser.permissions['canEditMenu'] != true) return;
    final nameController = TextEditingController(text: data['name']);
    final priceController = TextEditingController(text: data['price'].toString());
    String? newImageUrl = data['image'] ?? data['image_url'];
    bool isUploading = false;
    final theme = Theme.of(context);

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
      return AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("تعديل المنتج"),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: () async {
                final picker = ImagePicker();
                final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
                if (image == null) return;
                setDialogState(() => isUploading = true);
                try {
                  final url = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
                  var request = http.MultipartRequest('POST', url)
                    ..fields['upload_preset'] = uploadPreset
                    ..files.add(await http.MultipartFile.fromPath('file', image.path));
                  var response = await http.Response.fromStream(await request.send());
                  var responseData = jsonDecode(response.body);
                  if (response.statusCode == 200) {
                    setDialogState(() => newImageUrl = responseData['secure_url']);
                  }
                } catch (e) {
                  debugPrint("خطأ في الرفع: $e");
                } finally {
                  setDialogState(() => isUploading = false);
                }
              },
              child: Container(
                width: 120, height: 120, clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
                child: isUploading
                    ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                    : (newImageUrl != null && newImageUrl!.isNotEmpty ? Image.network(newImageUrl!, fit: BoxFit.cover) : Icon(Icons.add_a_photo, color: theme.colorScheme.primary)),
              ),
            ),
            const SizedBox(height: 15),
            TextField(controller: nameController, decoration: const InputDecoration(labelText: "اسم المنتج")),
            const SizedBox(height: 10),
            TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "السعر")),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () async {
              String oldName = data['name'];
              String newName = nameController.text.trim();
              double newPrice = double.tryParse(priceController.text) ?? 0.0;

              await productsRef.doc(productId).update({
                'name': newName,
                'price': newPrice,
                'image': newImageUrl,
              });

              // ✅ تتبع التعديل
              await _logAction("تعديل منتج", "تم تعديل '$oldName' إلى '$newName' بسعر $newPrice");

              Navigator.pop(ctx);
            },
            child: const Text("حفظ"),
          ),
        ],
      );
    }));
  }

  // --- نافذة تأكيد الحذف مع التتبع ---
  void _confirmDelete(String productId, String productName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("تأكيد الحذف"),
        content: Text("هل أنت متأكد من حذف المنتج '$productName' نهائياً من المنيو والمخزن؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await productsRef.doc(productId).delete();
              // ✅ تتبع الحذف
              await _logAction("حذف منتج", "قام بحذف المنتج '$productName' من المنيو");

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم حذف $productName")));
              }
            },
            child: const Text("حذف", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // --- إرسال الطلب مع التتبع الكامل ---
  // --- إرسال الطلب مع دعم كامل لوضع الأوفلاين ---
  Future<void> submitOrder() async {
    if (selectedProducts.isEmpty) return;
    List<Map<String, dynamic>> itemsList = selectedProducts.values.toList();

    // تجهيز تفاصيل التتبع
    String orderDetails = itemsList.map((e) => "${e['name']} (${e['quantity']})").join(", ");

    // 1️⃣ التعديل الأول: تصفير السلة وإغلاق الصفحة فوراً (قبل الـ commit)
    // هذا يضمن أن النادل يمكنه العودة للرئيسية والعمل على طاولة أخرى دون انتظار الإنترنت
    setState(() => selectedProducts.clear());
    Navigator.pop(context);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final newOrderRef = FirebaseFirestore.instance.collection('orders').doc();

      batch.set(newOrderRef, {
        'items': itemsList,
        'cafeId': widget.currentUser.cafeId,
        'table': widget.tableName,
        'ordered_at': FieldValue.serverTimestamp(), // فايبربيز سيعالج التوقيت محلياً ثم يصححه عند المزامنة
        'paid': false,
        'kitchen_status': 'pending',
        'waiter_name': widget.currentUser.name,
      });

      DocumentReference notificationRef = FirebaseFirestore.instance.collection('notifications').doc();
      batch.set(notificationRef, {
        'cafeId': widget.currentUser.cafeId,
        'title': '🔔 طلب جديد: طاولة ${widget.tableName}',
        'body': 'وصلت طلبات جديدة بانتظار التحضير 👨‍🍳',
        'targetRole': 'kitchen',
        'isRead': false,
        'senderName': widget.currentUser.name,
        'timestamp': FieldValue.serverTimestamp(),
      });

      for (var item in itemsList) {
        DocumentReference inventoryDoc = FirebaseFirestore.instance.collection('inventory').doc(item['id']);
        batch.set(inventoryDoc, {
          'quantity': FieldValue.increment(-(item['quantity'] as double)),
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      DocumentReference logRef = FirebaseFirestore.instance.collection('activity_logs').doc();
      batch.set(logRef, {
        'cafeId': widget.currentUser.cafeId,
        'userName': widget.currentUser.name,
        'action': "طلب جديد",
        'details': "طاولة ${widget.tableName}: $orderDetails",
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 2️⃣ التعديل الثاني (الأهم): إزالة الـ await من الـ commit
      // فايبربيز سيقوم بحفظ الـ batch في الذاكرة المحلية (Persistence) فوراً
      // وسيرسلها للسيرفر تلقائياً في الخلفية عند توفر الإنترنت.
      batch.commit().catchError((e) {
        debugPrint("🔴 فشل المزامنة التلقائية: $e");
      });

      // 3️⃣ التعديل الثالث: إظهار رسالة طمأنة للمستخدم
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم تسجيل الطلب (سيتم الرفع عند توفر الإنترنت) 📶"),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("🔴 خطأ برمي في إعداد الطلب: $e");
    }
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('cafes').doc(widget.currentUser.cafeId).snapshots(),
      builder: (context, cafeSnap) {
        String currencySymbol = "₪";
        if (cafeSnap.hasData && cafeSnap.data!.exists) {
          currencySymbol = (cafeSnap.data!.data() as Map<String, dynamic>)['currency_symbol'] ?? "₪";
        }

        return StreamBuilder<QuerySnapshot>(
          stream: productsRef.where('cafeId', isEqualTo: widget.currentUser.cafeId).snapshots(),
          builder: (context, prodSnapshot) {
            if (!prodSnapshot.hasData) return Scaffold(body: Center(child: CircularProgressIndicator(color: primaryColor)));

            final productsDocs = prodSnapshot.data!.docs;
            if (productsDocs.isEmpty) {
              return Scaffold(
                appBar: AppBar(backgroundColor: primaryColor, title: Text('طاولة: ${widget.tableName}')),
                body: const Center(child: Text("لا توجد منتجات مضافة")),
              );
            }

            final categories = productsDocs.map((doc) => (doc.data() as Map<String, dynamic>)['category']?.toString() ?? 'عام').toSet().toList()..sort();
            _updateTabController(categories);

            if (_tabController == null) return Scaffold(body: Center(child: CircularProgressIndicator(color: primaryColor)));

            return Scaffold(
              backgroundColor: theme.scaffoldBackgroundColor,
              appBar: AppBar(
                backgroundColor: primaryColor,
                foregroundColor: theme.colorScheme.onPrimary,
                title: _isSearching
                    ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "بحث عن صنف...",
                    hintStyle: const TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _isSearching = false;
                          _searchController.clear();
                          _searchQuery = "";
                        });
                      },
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                )
                    : Text('طاولة: ${widget.tableName}'),
                actions: [
                  if (!_isSearching)
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => setState(() => _isSearching = true),
                    ),
                ],
                bottom: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorColor: theme.colorScheme.onPrimary,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  tabs: _currentCategories.map((cat) => Tab(text: cat)).toList(),
                ),
              ),
              floatingActionButton: selectedProducts.isNotEmpty
                  ? FloatingActionButton.extended(
                onPressed: submitOrder,
                backgroundColor: primaryColor,
                label: Text('تأكيد (${selectedProducts.length})'),
                icon: const Icon(Icons.send),
              )
                  : null,
              body: TabBarView(
                controller: _tabController,
                children: _currentCategories.map((cat) {
                  final filteredProducts = productsDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = (data['name'] ?? "").toString().toLowerCase();
                    final pCategory = data['category'] ?? 'عام';
                    bool matchesSearch = name.contains(_searchQuery);
                    bool matchesCategory = (cat == "الكل") || (pCategory == cat);
                    return matchesSearch && matchesCategory;
                  }).toList();

                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, childAspectRatio: 0.7, crossAxisSpacing: 10, mainAxisSpacing: 10),
                    itemCount: filteredProducts.length,
                    itemBuilder: (context, index) {
                      final pDoc = filteredProducts[index];
                      final pData = pDoc.data() as Map<String, dynamic>;
                      pData['id'] = pDoc.id;

                      return ModernProductCard(
                        productData: pData,
                        theme: theme,
                        currencySymbol: currencySymbol,
                        currentUser: widget.currentUser,
                        onValueChanged: updateQuantity,
                        onEdit: () => _showEditProductDialog(pDoc.id, pData),
                        onDelete: () => _confirmDelete(pDoc.id, pData['name']),
                      );
                    },
                  );
                }).toList(),
              ),
            );
          },
        );
      },
    );
  }
}

// الكلاس الفرعي (ModernProductCard) يبقى كما هو تقريباً مع التأكد من تمرير onDelete بشكل صحيح
class ModernProductCard extends StatefulWidget {
  final Map<String, dynamic> productData;
  final String currencySymbol;
  final User currentUser;
  final ThemeData theme;
  final Function(String, Map<String, dynamic>, double) onValueChanged;
  final VoidCallback onEdit, onDelete;

  const ModernProductCard({
    super.key, required this.productData,
    required this.theme, required this.onValueChanged,
    required this.onEdit, required this.onDelete, required this.currentUser,
    required this.currencySymbol
  });

  @override
  State<ModernProductCard> createState() => _ModernProductCardState();
}

class _ModernProductCardState extends State<ModernProductCard> {
  int quantity = 0;

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.theme.colorScheme.primary;
    bool canModify = widget.currentUser.permissions['canEditMenu'] == true;
    final String imageUrl = widget.productData['image'] ?? '';
    final String name = widget.productData['name'] ?? 'N/A';
    final double price = (widget.productData['price'] ?? 0.0).toDouble();
    final String productId = widget.productData['id'];

    return Container(
      decoration: BoxDecoration(
          color: widget.theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
      ),
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: (imageUrl.isEmpty)
                      ? Container(color: Colors.grey[200], child: const Center(child: Text("لا توجد صورة", style: TextStyle(fontSize: 10))))
                      : Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.red.withOpacity(0.1),
                      child: const Center(child: Icon(Icons.broken_image, color: Colors.red)),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${widget.currencySymbol}${price.toStringAsFixed(2)}', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _btn(Icons.remove, () {
                          if (quantity > 0) {
                            setState(() => quantity--);
                            widget.onValueChanged(productId, widget.productData, quantity.toDouble());
                          }
                        }),
                        Text('$quantity', style: const TextStyle(fontWeight: FontWeight.bold)),
                        _btn(Icons.add, () {
                          setState(() => quantity++);
                          widget.onValueChanged(productId, widget.productData, quantity.toDouble());
                        }),
                      ],
                    )
                  ],
                ),
              ),
            ],
          ),
          if (canModify) Positioned(top: 5, right: 5, child: Row(children: [
            _adminBtn(Icons.edit, Colors.blue, widget.onEdit),
            const SizedBox(width: 4),
            _adminBtn(Icons.delete, Colors.red, widget.onDelete),
          ])),
        ],
      ),
    );
  }

  Widget _adminBtn(IconData icon, Color color, VoidCallback onTap) => InkWell(
      onTap: onTap,
      child: CircleAvatar(radius: 14, backgroundColor: Colors.white.withOpacity(0.9), child: Icon(icon, size: 14, color: color))
  );

  Widget _btn(IconData icon, VoidCallback onTap) => InkWell(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: widget.theme.colorScheme.primary, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 18, color: Colors.white)
      )
  );
}