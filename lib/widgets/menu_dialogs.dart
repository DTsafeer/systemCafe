import 'package:flutter/material.dart';
import 'app_components.dart';

class MenuDialogs {
  static void showBarcodeLabel({
    required BuildContext context,
    required Map<String, dynamic> product,
    required VoidCallback onPrint,
  }) {
    AppComponents.showAppDialog(
      context: context,
      title: "ملصق الباركود",
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(product['name'] ?? "", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white, 
              border: Border.all(color: Colors.black, width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                const Icon(Icons.view_column_rounded, size: 80, color: Colors.black),
                Text(
                  product['barcode'] ?? "SC-${product['id']?.substring(0, 5) ?? '0000'}", 
                  style: const TextStyle(letterSpacing: 4, fontWeight: FontWeight.bold, color: Colors.black)
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Text("${product['price']} ₪", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.green)),
        ],
      ),
      actions: [
        ElevatedButton.icon(
          onPressed: onPrint,
          icon: const Icon(Icons.print, color: Colors.white),
          label: const Text("طباعة الملصق", style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800]),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("إغلاق")),
      ],
    );
  }
}
