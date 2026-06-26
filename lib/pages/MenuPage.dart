import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';
import 'MainLayout.dart';
import 'addproduct.dart';
import '../widgets/app_components.dart';
import '../widgets/menu_dialogs.dart';
import 'activity_logger.dart';

class MenuPage extends StatefulWidget {
  final User currentUser;
  const MenuPage({super.key, required this.currentUser});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  String _searchQuery = "";
  StreamSubscription? _productsSub;
  List<Map<String, dynamic>> _allProducts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _listenToProducts();
  }

  void _listenToProducts() {
    final String managerId = widget.currentUser.parentId ?? widget.currentUser.id;
    _productsSub = FirebaseFirestore.instance
        .collection('products')
        .where('cafeId', isEqualTo: widget.currentUser.cafeId)
        .where('parentId', isEqualTo: managerId)
        .snapshots()
        .listen((snap) {
      final products = snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      if (mounted) {
        setState(() {
          _allProducts = products;
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _productsSub?.cancel();
    super.dispose();
  }

  void _toggleProductAvailability(String id, String name, bool currentStatus) async {
    if (!widget.currentUser.canUpdate('menu')) return;
    
    await FirebaseFirestore.instance.collection('products').doc(id).update({'isAvailable': !currentStatus});
    
    await ActivityLogger.log(
      cafeId: widget.currentUser.cafeId,
      parentId: widget.currentUser.parentId ?? widget.currentUser.id,
      userId: widget.currentUser.id,
      userName: widget.currentUser.name,
      action: "منيو - تعديل حالة",
      details: "تعديل حالة المنتج ($name) من ${currentStatus ? 'متاح' : 'غير متاح'} إلى ${!currentStatus ? 'متاح' : 'غير متاح'}",
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    // فحص صلاحية القراءة
    if (!widget.currentUser.canRead('menu')) {
      return MainLayout(
        currentUser: widget.currentUser,
        currentPage: 'menu',
        child: const Scaffold(
          body: Center(
            child: Text("عذراً، لا تملك صلاحية لعرض قائمة المنيو", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }

    final filteredProducts = _allProducts.where((p) {
      final name = p['name'].toString().toLowerCase();
      final barcode = (p['barcode'] ?? "").toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || barcode.contains(query);
    }).toList();

    return MainLayout(
      currentUser: widget.currentUser,
      currentPage: 'menu',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _buildHeader(primaryColor),
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator()) 
                : _buildProductList(filteredProducts, primaryColor),
            ),
          ],
        ),
        floatingActionButton: widget.currentUser.canCreate('menu') ? FloatingActionButton.extended(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddProduct(currentUser: widget.currentUser, ))),
          label: const Text("إضافة صنف جديد", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          icon: const Icon(Icons.add, color: Colors.white),
          backgroundColor: primaryColor,
        ) : null,
      ),
    );
  }

  Widget _buildHeader(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      decoration: BoxDecoration(
        color: primaryColor, 
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30))
      ),
      child: Column(
        children: [
          const Text("إدارة قائمة الأصناف والباركود", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: AppComponents.fieldInput("بحث عن صنف بالاسم أو الباركود...", Icons.qr_code_scanner, iconColor: Colors.white70).copyWith(
              filled: true, fillColor: Colors.white.withOpacity(0.2),
              hintStyle: const TextStyle(color: Colors.white70),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList(List<Map<String, dynamic>> products, Color primaryColor) {
    if (products.isEmpty) {
      return const Center(child: Text("لا توجد أصناف مطابقة للبحث", style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        final bool isAvailable = product['isAvailable'] ?? true;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ListTile(
            onTap: widget.currentUser.canUpdate('menu') ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddProduct(currentUser: widget.currentUser, productToEdit: product))) : null,
            leading: CircleAvatar(
              backgroundColor: Colors.grey[100],
              backgroundImage: (product['imagePath'] != null && product['imagePath'].isNotEmpty) ? NetworkImage(product['imagePath']) : null,
              child: (product['imagePath'] == null || product['imagePath'].isEmpty) ? const Icon(Icons.fastfood, color: Colors.grey) : null,
            ),
            title: Text(product['name'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${product['price']} ₪ | ${product['category'] ?? 'عام'}"),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.qr_code_2_rounded, color: Colors.blue), 
                  onPressed: () => MenuDialogs.showBarcodeLabel(
                    context: context, 
                    product: product,
                    onPrint: () { /* منطق الطباعة */ }
                  )
                ),
                Switch(
                  value: isAvailable,
                  onChanged: widget.currentUser.canUpdate('menu') ? (v) => _toggleProductAvailability(product['id'], product['name'], isAvailable) : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
