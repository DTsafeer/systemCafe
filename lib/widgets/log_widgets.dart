import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ActivityLogCard extends StatelessWidget {
  final String user;
  final String action;
  final String details;
  final DateTime timestamp;
  final Color? color;
  final IconData? icon;

  const ActivityLogCard({
    super.key,
    required this.user,
    required this.action,
    required this.details,
    required this.timestamp,
    this.color,
    this.icon,
  });

  IconData _getIconForAction(String action) {
    final act = action.toLowerCase();
    if (act.contains("بيع") || act.contains("طلب")) return Icons.receipt_long_rounded;
    if (act.contains("حذف") || act.contains("إلغاء")) return Icons.delete_sweep_rounded;
    if (act.contains("تعديل") || act.contains("تحديث")) return Icons.edit_note_rounded;
    if (act.contains("مخزن") || act.contains("بضاعة") || act.contains("كمية")) return Icons.inventory_2_outlined;
    if (act.contains("دين") || act.contains("دفع")) return Icons.payments_outlined;
    if (act.contains("دخول") || act.contains("خروج")) return Icons.admin_panel_settings_outlined;
    if (act.contains("طاولة")) return Icons.table_restaurant_rounded;
    return Icons.history_rounded;
  }

  Color _getStatusColor(String action, Color themeColor) {
    if (action.contains("حذف") || action.contains("إلغاء") || action.contains("خصم")) return Colors.redAccent;
    if (action.contains("إضافة") || action.contains("جديد")) return Colors.green;
    if (action.contains("تعديل") || action.contains("تغيير")) return Colors.orange[800]!;
    return themeColor;
  }

  // دالة لتنسيق النص وإبراز "من" و "إلى"
  Widget _buildFormattedDetails(String text) {
    if (text.contains("من") && text.contains("إلى")) {
      List<String> parts = text.split(RegExp(r'(من|إلى)'));
      // هذا مجرد تبسيط، التنسيق المتقدم يستخدم RichText
      return RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.4, fontFamily: 'Tajawal'),
          children: _parseDetails(text),
        ),
      );
    }
    return Text(
      text,
      style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  List<TextSpan> _parseDetails(String text) {
    List<TextSpan> spans = [];
    final words = text.split(" ");
    
    for (var word in words) {
      if (word == "من") {
        spans.add(const TextSpan(text: "من ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)));
      } else if (word == "إلى") {
        spans.add(const TextSpan(text: " إلى ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)));
      } else {
        // إذا كان الرقم يأتي بعد "إلى" نلونه بالأخضر أو البرتقالي
        spans.add(TextSpan(text: "$word "));
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = color ?? Colors.blueGrey;
    final statusColor = _getStatusColor(action, themeColor);
    final displayIcon = icon ?? _getIconForAction(action);
    final isEdit = action.contains("تعديل");

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isEdit ? Colors.orange.withOpacity(0.02) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: isEdit ? Colors.orange.withOpacity(0.1) : Colors.grey.withOpacity(0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: statusColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(displayIcon, color: statusColor, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  user,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    action,
                                    style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            _buildFormattedDetails(details),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            DateFormat('HH:mm').format(timestamp),
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey[800]),
                          ),
                          Text(
                            DateFormat('dd/MM').format(timestamp),
                            style: TextStyle(color: Colors.grey[400], fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
