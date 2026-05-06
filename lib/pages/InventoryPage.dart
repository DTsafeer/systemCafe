import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';

// ----------------- الصفحة الرئيسية للمخزن -----------------
class InventoryPage extends StatefulWidget {
  final User currentUser;

  const InventoryPage({super.key, required this.currentUser});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool canEditInventory = widget.currentUser.role == UserRole.admin || widget.currentUser.permissions['canEditMenu'] == true;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("إدارة المخزن 📦", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // --- حقل البحث ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'بحث في الأصناف...',
                prefixIcon: Icon(Icons.search, color: theme.colorScheme.primary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = "");
                  },
                )
                    : null,
                filled: true,
                fillColor: theme.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
            ),
          ),

          // --- قائمة المنتجات (تعمل أوفلاين تلقائياً عبر snapshots) ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // فايبربيز سيعيد البيانات من الكاش إذا كان الجهاز أوفلاين
              stream: FirebaseFirestore.instance
                  .collection('inventory')
                  .where('cafeId', isEqualTo: widget.currentUser.cafeId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

// التأكد من وجود بيانات قبل فحص الميتاداتا
                bool isOffline = false;
                if (snapshot.hasData && snapshot.data != null) {
                  isOffline = snapshot.data!.metadata.isFromCache;
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("المخزن فارغ!"));
                }

                final filteredDocs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  return name.contains(_searchQuery);
                }).toList();

                filteredDocs.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    var doc = filteredDocs[index];
                    var data = doc.data() as Map<String, dynamic>;

                    return InventoryCard(
                      docRef: doc.reference,
                      name: data['name'] ?? 'بدون اسم',
                      imageUrl: data['image'] ?? '',
                      quantity: (data['quantity'] ?? 0.0).toDouble(),
                      theme: theme,
                      canEdit: canEditInventory,
                      currentUser: widget.currentUser,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------- بطاقة عرض المنتج -----------------
class InventoryCard extends StatelessWidget {
  final DocumentReference docRef;
  final String name, imageUrl;
  final double quantity;
  final ThemeData theme;
  final bool canEdit;
  final User currentUser;

  const InventoryCard({
    super.key,
    required this.docRef,
    required this.name,
    required this.imageUrl,
    required this.quantity,
    required this.theme,
    required this.canEdit,
    required this.currentUser,
  });

  // --- دالة التتبع (محدثة للأوفلاين بلمس البيانات محلياً أولاً) ---
  void _logActivity(String action, String details) {
    FirebaseFirestore.instance.collection('activity_logs').add({
      'cafeId': currentUser.cafeId,
      'userName': currentUser.name,
      'action': action,
      'details': details,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // --- نافذة تعديل الكمية (محدثة للأوفلاين) ---
  void _showEditQuantityDialog(BuildContext context) {
    final qtyController = TextEditingController(text: quantity.toInt().toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("تعديل كمية ($name)", textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              autofocus: true,
              decoration: const InputDecoration(labelText: "الكمية الجديدة", border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () {
              double newQty = double.tryParse(qtyController.text) ?? 0;

              // ✅ التعديل للأوفلاين: التحديث محلياً فوراً دون انتظار await
              docRef.update({'quantity': newQty});

              _logActivity("تعديل مخزن", "عدّل كمية '$name' إلى (${newQty.toInt()})");

              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("تم تحديث المخزن محلياً وسيتم المزامنة 📶"))
              );
            },
            child: const Text("حفظ"),
          ),
        ],
      ),
    );
  }

  // --- نافذة الحذف (محدثة للأوفلاين) ---
  void _deleteItem(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("تأكيد الحذف 🗑️"),
        content: Text("حذف ($name) من المخزن؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("تراجع")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              // ✅ التعديل للأوفلاين: الحذف محلياً فوراً دون انتظار await
              _logActivity("حذف من المخزن", "قام بحذف الصنف '$name'");
              docRef.delete();

              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("تم حذف الصنف محلياً 📶"))
              );
            },
            child: const Text("نعم، احذف"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isLowStock = quantity > 0 && quantity <= 5;
    final bool isOutOfStock = quantity <= 0;
    Color qtyColor = isOutOfStock ? theme.colorScheme.error : (isLowStock ? Colors.orange.shade700 : Colors.green.shade700);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: Image.network(imageUrl, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: Colors.grey[200], child: const Icon(Icons.image)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1),
                    Text("المتوفر: ${quantity.toInt()}", style: TextStyle(color: qtyColor, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (canEdit)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => _showEditQuantityDialog(context),
                          child: const Text("تعديل"),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (canEdit)
            Positioned(
              top: 8, right: 8,
              child: GestureDetector(
                onTap: () => _deleteItem(context),
                child: CircleAvatar(radius: 15, backgroundColor: Colors.white70, child: Icon(Icons.delete, color: theme.colorScheme.error, size: 18)),
              ),
            ),
        ],
      ),
    );
  }
}