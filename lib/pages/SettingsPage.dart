import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ ضروري لتحديث الجلسة
import '../main.dart';
import 'CafeActivityLogPage.dart';
import 'user_model.dart';

class SettingsPage extends StatefulWidget {
  final User user;
  const SettingsPage({super.key, required this.user});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final List<Map<String, String>> allCurrencies = [
    {'name': 'شيكل إسرائيلي', 'symbol': '₪'},
    {'name': 'دولار أمريكي', 'symbol': r'$'},
    {'name': 'دينار أردني', 'symbol': 'JOD'},
    {'name': 'جنيه مصري', 'symbol': 'EGP'},
    {'name': 'ريال سعودي', 'symbol': 'SAR'},
    {'name': 'درهم إماراتي', 'symbol': 'AED'},
    {'name': 'يورو', 'symbol': '€'},
    {'name': 'ليرة تركية', 'symbol': '₺'},
  ];

  // دالة تحديث إعدادات المنشأة (مظهر، اسم، عملة)
  // دالة تحديث إعدادات المنشأة وتحديث الجلسة المحلية فوراً
  Future<void> _updateSetting(String key, dynamic value) async {
    // 1. تحديث قاعدة البيانات (Firestore)
    await FirebaseFirestore.instance
        .collection('cafes')
        .doc(widget.user.cafeId)
        .set({key: value}, SetOptions(merge: true));

    // 2. تحديث الذاكرة المحلية (SharedPreferences) ليراها ملف main.dart فوراً
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    }

    // 3. أمر التطبيق بإعادة بناء الثيم وحجم الخط فوراً
    if (mounted) {
      MyApp.updateTheme(context);
    }
  }
  // 🔥 دالة احترافية لتحديث كلمة المرور وسد ثغرة الجلسة


  void _showEditNameDialog(String currentName) {
    final controller = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder( // استخدام StatefulBuilder لتحديث أيقونة المسح أثناء الكتابة
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text('تغيير اسم المنشأة'),
          content: TextField(
            controller: controller,
            autofocus: true,
            onChanged: (value) => setState(() {}), // لتحديث ظهور/اختفاء زر المسح
            decoration: InputDecoration(
              labelText: 'الاسم الجديد',
              // ✅ إضافة زر كنسل (مسح النص) في نهاية الحقل
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.cancel, color: Colors.grey),
                onPressed: () {
                  controller.clear();
                  setState(() {}); // إعادة بناء الواجهة ليختفي الزر بعد المسح
                },
              )
                  : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  _updateSetting('cafe_name', controller.text.trim());
                  Navigator.pop(context);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cafes')
          .doc(widget.user.cafeId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

        bool isDarkMode = data['isDarkMode'] ?? false;
        int primaryColorValue = data['primaryColor'] ?? Colors.brown.value;
        Color primaryColor = Color(primaryColorValue);

        String cafeName = data['cafe_name'] ?? "اسم المنشأة";
        String currency = data['currency_symbol'] ?? "₪";
        String currentFontSize = data['global_font_size'] ?? "medium";
        double hourlyRate = (data['hourly_rate'] ?? 1.0).toDouble();

        return Scaffold(
          appBar: AppBar(


            title: const Text('الإعدادات'),
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            actions: [

              IconButton(onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CafeActivityLogPage(currentUser: widget.user),
                  ),
                );
              }, icon: Icon(Icons.view_list_sharp))


            ],

          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionTitle('الملف الشخصي', primaryColor),
              _buildCard([
                _buildListTile(Icons.person, 'الاسم', widget.user.name, primaryColor),
                _buildListTile(Icons.badge, 'الدور', widget.user.role.name, primaryColor),
                // ✅ إضافة خيار تغيير كلمة المرور هنا

              ]),

              _buildSectionTitle('مظهر التطبيق', primaryColor),
              _buildCard([
                SwitchListTile(
                  secondary: Icon(isDarkMode ? Icons.dark_mode : Icons.light_mode, color: primaryColor),
                  title: const Text('الوضع الداكن'),
                  value: isDarkMode,
                  onChanged: (val) => _updateSetting('isDarkMode', val),
                ),
                _buildListTile(Icons.palette, 'لون الهوية', '', primaryColor,
                    trailing: CircleAvatar(backgroundColor: primaryColor, radius: 12),
                    onTap: () => _showColorPicker(primaryColorValue)),
              ]),

              if (widget.user.canManageUsers) ...[
                _buildSectionTitle('إدارة المنشأة', primaryColor),
                _buildCard([
                  _buildListTile(Icons.store, 'اسم الكافيه', cafeName, primaryColor,
                      onTap: () => _showEditNameDialog(cafeName)),
                  SwitchListTile(
                    secondary: Icon(Icons.timer, color: primaryColor),
                    title: const Text('تفعيل عداد الوقت المفتوح'),
                    subtitle: const Text('إظهار الوقت المنقضي وتكلفة الساعة'),
                    value: data['show_time_counter'] ?? true, // القيمة الافتراضية true
                    onChanged: (val) => _updateSetting('show_time_counter', val),
                  ),

                  const Divider(height: 1, indent: 50),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.format_size, color: primaryColor, size: 22),
                            const SizedBox(width: 12),
                            const Text("حجم خط النظام", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _fontSizeChip("صغير", "small", currentFontSize, primaryColor),
                            _fontSizeChip("متوسط", "medium", currentFontSize, primaryColor),
                            _fontSizeChip("كبير", "large", currentFontSize, primaryColor),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, indent: 50),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: DropdownButtonFormField<String>(
                      value: currency,
                      decoration: InputDecoration(
                        labelText: 'عملة النظام',
                        prefixIcon: Icon(Icons.monetization_on, color: primaryColor),
                        border: InputBorder.none,
                      ),
                      items: allCurrencies.map((c) => DropdownMenuItem(
                        value: c['symbol'],
                        child: Text("${c['name']} (${c['symbol']})"),
                      )).toList(),
                      onChanged: (val) => _updateSetting('currency_symbol', val),
                    ),
                  ),
                ]),

                const SizedBox(height: 10),

                Container(
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: Icon(Icons.history_toggle_off_rounded, color: primaryColor),
                    title: const Text('تعرفة ساعة الشحن', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('السعر لكل ساعة طاولة مفتوحة', style: TextStyle(fontSize: 11)),
                    trailing: Text(
                      "${hourlyRate.toStringAsFixed(1)} $currency",
                      style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
                    ),
                    onTap: () => _showEditHourlyRateDialog(hourlyRate.toString()),
                  ),
                ),
              ],
              const SizedBox(height: 50), // يمكنك زيادة أو تقليل الارتفاع حسب الحاجة
            ],
          ),
        );
      },
    );
  }

  Widget _fontSizeChip(String label, String value, String currentValue, Color color) {
    bool isSelected = value == currentValue;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black)),
      selected: isSelected,
      selectedColor: color,
      onSelected: (selected) {
        if (selected) _updateSetting('global_font_size', value);
      },
    );
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
      child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(children: children),
    );
  }

  Widget _buildListTile(IconData icon, String title, String subtitle, Color color, {Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
      trailing: trailing ?? (onTap != null ? const Icon(Icons.arrow_forward_ios, size: 14) : null),
      onTap: onTap,
    );
  }

  void _showColorPicker(int currentColor) {
    List<Color> colors = [Colors.brown, Colors.blue, Colors.green, Colors.red, Colors.orange, Colors.teal, Colors.deepPurple];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختر لون الهوية'),
        content: Wrap(
          spacing: 10,
          children: colors.map((color) => GestureDetector(
            onTap: () {
              _updateSetting('primaryColor', color.value);
              Navigator.pop(context);
            },
            child: CircleAvatar(
              backgroundColor: color,
              child: currentColor == color.value ? const Icon(Icons.check, color: Colors.white) : null,
            ),
          )).toList(),
        ),
      ),
    );
  }

  void _showEditHourlyRateDialog(String currentRate) {
    final controller = TextEditingController(text: currentRate);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text('تعديل سعر الساعة'),
            content: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              onChanged: (value) {
                // تحديث حالة الدايالوج لإظهار أو إخفاء زر المسح
                setDialogState(() {});
              },
              decoration: InputDecoration(
                labelText: 'السعر لكل ساعة',
                // ✅ إضافة زر كنسل (مسح) للنص
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.grey),
                  onPressed: () {
                    controller.clear();
                    setDialogState(() {}); // لتحديث الواجهة بعد المسح
                  },
                )
                    : null,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () {
                  double? newRate = double.tryParse(controller.text.trim());
                  if (newRate != null) {
                    _updateSetting('hourly_rate', newRate);
                    Navigator.pop(context);
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );
  }
}