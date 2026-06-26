import 'package:flutter/material.dart';

class ReportInfoCard extends StatelessWidget {
  final String title;
  final double value;
  final Color color;
  final IconData icon;
  final String currencySymbol;
  final bool isBold;

  const ReportInfoCard({
    super.key,
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    required this.currencySymbol,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [BoxShadow(color: color.withOpacity(0.12), blurRadius: 25, offset: const Offset(0, 12))]
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 25),
            Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text("${value.toStringAsFixed(1)} $currencySymbol",
              style: TextStyle(color: color, fontSize: 24, fontWeight: isBold ? FontWeight.w900 : FontWeight.w800))
          ]
      ),
    );
  }
}

class AttendanceStatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const AttendanceStatItem({super.key, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.1))
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 5),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ),
    );
  }
}

class LuxuryTableContainer extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final Widget child;
  final VoidCallback? onExport;

  const LuxuryTableContainer({
    super.key,
    required this.title,
    required this.color,
    required this.icon,
    required this.child,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 480),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(35),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.12), blurRadius: 30, offset: const Offset(0, 15)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 25),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, color.withOpacity(0.8)], begin: Alignment.topRight, end: Alignment.bottomLeft),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 26),
                const SizedBox(width: 15),
                Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5))),
                if (onExport != null)
                  IconButton(onPressed: onExport, icon: const Icon(Icons.download, color: Colors.white)),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class TransactionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final double amount;
  final String currency;

  const TransactionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.receipt_long_rounded, color: Colors.blue),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              ],
            ),
          ),
          Text(
            "${amount.toStringAsFixed(1)} $currency",
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.green),
          ),
        ],
      ),
    );
  }
}
