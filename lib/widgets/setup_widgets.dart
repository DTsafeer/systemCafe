import 'package:flutter/material.dart';

class PackageCard extends StatelessWidget {
  final Map<String, dynamic> pkg;
  final bool isWide;
  final bool isSelected;
  final String currency;
  final VoidCallback onTap;
  final Map<String, String> permLabels;
  final Map<String, IconData> permIcons;

  const PackageCard({
    super.key,
    required this.pkg,
    required this.isWide,
    required this.isSelected,
    required this.currency,
    required this.onTap,
    required this.permLabels,
    required this.permIcons,
  });

  @override
  Widget build(BuildContext context) {
    Color pkgColor = Color(pkg['colorValue'] ?? Colors.brown.value);
    final Map<String, dynamic> perms = Map<String, dynamic>.from(pkg['permissions'] ?? {});

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: isWide ? 320 : double.infinity,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: isSelected ? pkgColor : Colors.transparent, width: 4),
          boxShadow: [
            BoxShadow(
              color: isSelected ? pkgColor.withOpacity(0.15) : Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Column(
          children: [
            Text(pkg['name'], style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: pkgColor)),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(currency, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: pkgColor)),
                ),
                Text(pkg['price'].toString(), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
                Padding(
                  padding: const EdgeInsets.only(top: 25),
                  child: Text(pkg['billingCycle'] ?? "/شهر", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ),
              ],
            ),
            const Divider(height: 30),
            ... (pkg['features'] as List? ?? []).map<Widget>((feature) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(feature.toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                ],
              ),
            )).toList(),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: pkgColor.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, 
                  childAspectRatio: 3.2, 
                  mainAxisSpacing: 8, 
                  crossAxisSpacing: 8
                ),
                itemCount: perms.entries.where((e) => e.value == true).length,
                itemBuilder: (context, index) {
                  final entry = perms.entries.where((e) => e.value == true).elementAt(index);
                  if (entry.key == 'canUseGoogleSheets') return const SizedBox.shrink();
                  return Row(
                    children: [
                      Icon(permIcons[entry.key] ?? Icons.check_circle_outline, size: 14, color: pkgColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          permLabels[entry.key] ?? entry.key, 
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600), 
                          maxLines: 1, 
                          overflow: TextOverflow.ellipsis
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 25),
            Container(
              width: double.infinity,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: isSelected ? pkgColor : Colors.grey[100], borderRadius: BorderRadius.circular(15)),
              child: Text(
                isSelected ? "الخطة المختارة" : "اختر هذه الخطة", 
                style: TextStyle(color: isSelected ? Colors.white : Colors.black54, fontWeight: FontWeight.bold)
              ),
            ),
          ],
        ),
      ),
    );
  }
}
