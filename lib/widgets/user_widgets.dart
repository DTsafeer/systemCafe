import 'package:flutter/material.dart';
import '../pages/user_model.dart';

class UserStatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const UserStatItem({super.key, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class UserPermissionChip extends StatelessWidget {
  final String label;
  final bool enabled;
  final Color primary;
  final VoidCallback onTap;

  const UserPermissionChip({
    super.key,
    required this.label,
    required this.enabled,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: enabled ? primary.withOpacity(0.1) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: enabled ? primary.withOpacity(0.2) : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(enabled ? Icons.check_circle : Icons.circle_outlined, size: 14, color: enabled ? primary : Colors.grey),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(
              fontSize: 11, 
              color: enabled ? primary : Colors.grey[700], 
              fontWeight: enabled ? FontWeight.bold : FontWeight.normal
            )),
          ],
        ),
      ),
    );
  }
}
