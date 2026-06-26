import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';

class CategoryManagementPage extends StatefulWidget {
  final User currentUser;
  const CategoryManagementPage({super.key, required this.currentUser});

  @override
  State<CategoryManagementPage> createState() => _CategoryManagementPageState();
}

class _CategoryManagementPageState extends State<CategoryManagementPage> {
  @override
  Widget build(BuildContext context) {
    final String managerId = widget.currentUser.parentId ?? widget.currentUser.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text("إدارة التصنيفات"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('categories')
            .where('cafeId', isEqualTo: widget.currentUser.cafeId)
            .where('parentId', isEqualTo: managerId) // تصفية حسب المدير
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("لا توجد تصنيفات مضافة"));

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final String name = doc['name'];
              
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _editCategory(doc.id, name),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteCategory(doc.id, name),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _editCategory(String docId, String oldName) {
    final controller = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("تعديل اسم التصنيف"),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () async {
              String newName = controller.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                await _updateCategoryInProducts(oldName, newName);
                await FirebaseFirestore.instance.collection('categories').doc(docId).update({'name': newName});
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text("حفظ التغيير"),
          )
        ],
      ),
    );
  }

  Future<void> _updateCategoryInProducts(String oldName, String newName) async {
    final String managerId = widget.currentUser.parentId ?? widget.currentUser.id;
    final products = await FirebaseFirestore.instance
        .collection('products')
        .where('cafeId', isEqualTo: widget.currentUser.cafeId)
        .where('parentId', isEqualTo: managerId) // تصفية حسب المدير
        .where('category', isEqualTo: oldName)
        .get();

    WriteBatch batch = FirebaseFirestore.instance.batch();
    for (var doc in products.docs) {
      batch.update(doc.reference, {'category': newName});
    }
    await batch.commit();
  }

  void _deleteCategory(String docId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("حذف التصنيف"),
        content: Text("هل أنت متأكد من حذف '$name'؟ سيتم تحويل منتجاته إلى 'عام'."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _updateCategoryInProducts(name, "عام");
              await FirebaseFirestore.instance.collection('categories').doc(docId).delete();
              if (mounted) Navigator.pop(context);
            },
            child: const Text("حذف", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }
}
