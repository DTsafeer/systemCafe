import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/report_helper.dart';
import '../widgets/settings_dialogs.dart';
import '../services/settings_service.dart';
import '../main.dart';
import 'CafeActivityLogPage.dart';
import 'user_model.dart';
import 'MainLayout.dart';

class SettingsPage extends StatefulWidget {
  final User user;
  const SettingsPage({super.key, required this.user});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _localDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadLocalTheme();
  }

  // تحميل الثيم من إعدادات الجهاز المحلية
  Future<void> _loadLocalTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _localDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  // حفظ الثيم للجهاز الحالي فقط وتحديث التطبيق فوراً
  Future<void> _toggleLocalTheme(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
    setState(() {
      _localDarkMode = value;
    });
    if (mounted) {
      MyApp.updateTheme(context);
    }
  }

  bool _checkPermission() {
    if (!widget.user.canManageSettings) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ لا تملك صلاحية لتعديل هذا الإعداد."), backgroundColor: Colors.orange));
      return false;
    }
    return true;
  }

  void _updateSetting(String key, dynamic value) async {
    if (!_checkPermission()) return;
    await SettingsService.updateSetting(cafeId: widget.user.cafeId, key: key, value: value, context: context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final bool canManage = widget.user.canManageSettings;
    final bool canViewReports = widget.user.canViewReports;
    final String managerId = widget.user.parentId ?? widget.user.id;

    return MainLayout(
      currentUser: widget.user, currentPage: 'settings',
      child: StreamBuilder<DocumentSnapshot>(
        stream: widget.user.cafeId.isEmpty ? null : FirebaseFirestore.instance.collection('cafes').doc(widget.user.cafeId).snapshots(),
        builder: (context, snapshot) {
          if (widget.user.cafeId.isEmpty) return const Center(child: Text("معرف الكافيه غير موجود"));

          var data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          String cafeName = data['cafe_name'] ?? "اسم المنشأة";
          String currencySymbol = data['currency_symbol'] ?? "₪";
          bool isKitchenEnabled = data['isKitchenEnabled'] ?? true;
          bool isInventoryTrackingEnabled = data['isInventoryTrackingEnabled'] ?? true;
          bool showTimeCounter = data['show_time_counter'] ?? true;
          double hourlyRate = (data['hourly_rate'] ?? 0.0).toDouble();
          List<String> paymentMethods = List<String>.from(data['payment_methods'] ?? ["كاش", "شبكة", "دين"]);

          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800), child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text("الإعدادات", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),

                // قسم عام للجميع (إعدادات محلية للجهاز)
                _buildSectionTitle('إعدادات جهازي', primaryColor),
                _buildCard([
                  SwitchListTile(
                    secondary: const Icon(Icons.dark_mode), 
                    title: const Text('الوضع الداكن'), 
                    subtitle: const Text('تغيير مظهر التطبيق على هذا الجهاز فقط'),
                    value: _localDarkMode, 
                    onChanged: (v) => _toggleLocalTheme(v)
                  ),
                ]),

                // إعدادات النظام المحمية (تؤثر على الجميع في السحابة)
                if (canManage) ...[
                  _buildSectionTitle('تخصيص النظام (للكافيه بالكامل)', primaryColor),
                  _buildCard([
                    ListTile(
                      leading: const Icon(Icons.currency_exchange), 
                      title: const Text('رمز العملة'), 
                      subtitle: Text(currencySymbol),
                      onTap: () => SettingsDialogs.showEditSettingDialog(context: context, title: 'رمز العملة', initialValue: currencySymbol, hint: 'الرمز الجديد', icon: Icons.currency_exchange, onSave: (v) => _updateSetting('currency_symbol', v))
                    ),
                    ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: const Text('طرق الدفع'),
                      subtitle: Text(paymentMethods.join("، ")),
                      onTap: () => SettingsDialogs.showPaymentMethodsDialog(
                          context: context,
                          currentMethods: paymentMethods,
                          onSave: (methods) => _updateSetting('payment_methods', methods)
                      ),
                    ),
                  ]),

                  _buildSectionTitle('إدارة الميزات', primaryColor),
                  _buildCard([
                    SwitchListTile(secondary: const Icon(Icons.soup_kitchen), title: const Text('نظام المطبخ'), value: isKitchenEnabled, onChanged: (v) => _updateSetting('isKitchenEnabled', v)),
                    SwitchListTile(secondary: const Icon(Icons.inventory), title: const Text('تتبع المخزون'), subtitle: const Text('عند الإيقاف، سيتم السماح بالطلب حتى لو نفذت الكمية'), value: isInventoryTrackingEnabled, onChanged: (v) => _updateSetting('isInventoryTrackingEnabled', v)),
                    if (showTimeCounter) 
                      ListTile(leading: const Icon(Icons.monetization_on), title: const Text('سعر الساعة'), subtitle: Text("$hourlyRate $currencySymbol"),
                      onTap: () => SettingsDialogs.showEditSettingDialog(context: context, title: 'سعر الساعة', initialValue: hourlyRate.toString(), hint: 'السعر الجديد', icon: Icons.timer, isNumeric: true, onSave: (v) => _updateSetting('hourly_rate', double.tryParse(v) ?? 0))),
                  ]),
                ],

                // التقارير المحاسبية
                if (canViewReports) ...[
                  _buildSectionTitle('التقارير المحاسبية (تحميل مباشر)', Colors.orange),
                  _buildCard([
                    ListTile(
                      leading: const Icon(Icons.summarize, color: Colors.orange),
                      title: const Text('تصدير تقرير محاسبي شامل (الكل)', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('ملف واحد يحتوي على: الديون، الحوالات، المبيعات والمصاريف'),
                      onTap: () async {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⏳ جاري تجهيز التقرير الشامل...")));
                        await ReportHelper.exportCombinedComprehensiveReport(widget.user.cafeId, managerId);
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.description_outlined, color: Colors.orange),
                      title: const Text('تصدير كشف الديون الحالي'),
                      subtitle: const Text('ملف Excel بجميع المبالغ المستحقة على الزبائن'),
                      onTap: () async {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⏳ جاري تجهيز كشف الديون...")));
                        await ReportHelper.exportDebtsToExcel(widget.user.cafeId, managerId);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.account_balance_wallet_outlined, color: Colors.orange),
                      title: const Text('تصدير ملف الحوالات'),
                      subtitle: const Text('سجل كامل بجميع عمليات الاستلام والسداد'),
                      onTap: () async {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⏳ جاري تجهيز ملف الحوالات...")));
                        await ReportHelper.exportTransfersToExcel(widget.user.cafeId, managerId);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.analytics_outlined, color: Colors.orange),
                      title: const Text('تصدير تقرير المبيعات والمصاريف'),
                      subtitle: const Text('ملف شامل للمبيعات والمصاريف خلال الشهر الحالي'),
                      onTap: () async {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⏳ جاري تجهيز التقرير المالي...")));
                        await ReportHelper.exportFullFinancialReport(widget.user.cafeId, managerId);
                      },
                    ),
                  ]),
                ],

                // بيانات الكافيه
                if (canManage) ...[
                  _buildSectionTitle('بيانات المنشأة', primaryColor),
                  _buildCard([
                    ListTile(leading: const Icon(Icons.store), title: const Text('اسم الكافيه'), subtitle: Text(cafeName),
                        onTap: () => SettingsDialogs.showEditSettingDialog(context: context, title: 'اسم الكافيه', initialValue: cafeName, hint: 'الاسم الجديد', icon: Icons.edit, onSave: (v) => _updateSetting('cafe_name', v))),
                    ListTile(leading: const Icon(Icons.history), title: const Text('سجل نشاط الكافيه'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CafeActivityLogPage(currentUser: widget.user)))),
                  ]),
                ],

                const SizedBox(height: 40),
              ],
            ))),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String t, Color c) => Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5), child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold)));
  Widget _buildCard(List<Widget> c) => Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey[200]!)), child: Column(children: c));
}
