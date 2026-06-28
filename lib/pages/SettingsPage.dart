import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/report_helper.dart';
import '../widgets/settings_dialogs.dart';
import '../services/settings_service.dart';
import '../services/account_service.dart';
import '../services/cafe_service.dart';
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
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadLocalTheme();
  }

  Future<void> _loadLocalTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _localDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _toggleLocalTheme(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
    setState(() => _localDarkMode = value);
    if (mounted) MyApp.updateTheme(context);
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
    final String cafeId = widget.user.cafeId;

    return MainLayout(
      currentUser: widget.user, currentPage: 'settings',
      child: StreamBuilder<DocumentSnapshot>(
        stream: cafeId.isEmpty ? null : FirebaseFirestore.instance.collection('cafes').doc(cafeId).snapshots(),
        builder: (context, snapshot) {
          if (cafeId.isEmpty) return const Center(child: Text("معرف الكافيه غير موجود"));

          var data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          String cafeName = data['cafe_name'] ?? "اسم المنشأة";
          String currencySymbol = data['currency_symbol'] ?? "₪";
          bool isKitchenEnabled = data['isKitchenEnabled'] ?? true;
          bool isInventoryTrackingEnabled = data['isInventoryTrackingEnabled'] ?? true;
          List<String> paymentMethods = List<String>.from(data['payment_methods'] ?? ["كاش", "شبكة", "دين"]);

          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800), child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text("الإعدادات", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),

                // قسم إدارة الخزينة (الأرصدة)
                if (canManage) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionTitle('أرصدة الخزينة والحسابات (الصافي)', Colors.green[700]!),
                      TextButton.icon(
                        onPressed: _isSyncing ? null : () async {
                          setState(() => _isSyncing = true);
                          try {
                            await AccountService.syncAllAccountBalances(cafeId, managerId);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم تحديث الأرصدة بنجاح (الحد الأدنى 0)"), backgroundColor: Colors.green));
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ خطأ: $e")));
                          }
                          setState(() => _isSyncing = false);
                        },
                        icon: _isSyncing ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync, size: 18),
                        label: const Text("مزامنة وتحديث"),
                      )
                    ],
                  ),
                  _buildTreasuryManagement(cafeId, primaryColor),
                  const SizedBox(height: 20),
                ],

                _buildSectionTitle('إعدادات جهازي', primaryColor),
                _buildCard([
                  SwitchListTile(
                    secondary: const Icon(Icons.dark_mode), 
                    title: const Text('الوضع الداكن'), 
                    value: _localDarkMode, 
                    onChanged: (v) => _toggleLocalTheme(v)
                  ),
                ]),

                if (canManage) ...[
                  _buildSectionTitle('تخصيص النظام', primaryColor),
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
                    SwitchListTile(secondary: const Icon(Icons.inventory), title: const Text('تتبع المخزون'), value: isInventoryTrackingEnabled, onChanged: (v) => _updateSetting('isInventoryTrackingEnabled', v)),
                  ]),
                ],

                if (canViewReports) ...[
                  _buildSectionTitle('التقارير المحاسبية', Colors.orange),
                  _buildCard([
                    ListTile(
                      leading: const Icon(Icons.summarize, color: Colors.orange),
                      title: const Text('تقرير محاسبي شامل'),
                      onTap: () => ReportHelper.exportCombinedComprehensiveReport(cafeId, managerId),
                    ),
                    ListTile(
                      leading: const Icon(Icons.account_balance_wallet_outlined, color: Colors.orange),
                      title: const Text('تصدير ملف الحوالات'),
                      onTap: () => ReportHelper.exportTransfersToExcel(cafeId, managerId),
                    ),
                  ]),
                ],

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

  Widget _buildTreasuryManagement(String cafeId, Color primary) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('cafes').doc(cafeId).collection('accounts').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.green.withOpacity(0.2))),
          child: Column(
            children: [
              if (docs.isEmpty) 
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text("لا توجد مبالغ مسجلة. اضغط على 'مزامنة' للتنشيط.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              ...docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                double bal = (d['balance'] ?? 0.0).toDouble();
                String name = d['methodName'] ?? doc.id;
                return ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.green[50], child: const Icon(Icons.account_balance_wallet, color: Colors.green, size: 20)),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("${bal.toStringAsFixed(1)} ₪", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: bal > 0 ? Colors.green[800] : Colors.black)),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.edit_note, color: Colors.blue),
                        onPressed: () => _showAdjustBalanceDialog(cafeId, name, bal),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showAdjustBalanceDialog(String cafeId, String methodName, double currentBal) {
    final ctrl = TextEditingController(text: currentBal.toString());
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text("تعديل رصيد ($methodName)"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("ضبط الرصيد الفعلي لهذه المحفظة (الحد الأدنى 0).", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 15),
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: "القيمة الجديدة", border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
            ElevatedButton(
              onPressed: () async {
                double? newVal = double.tryParse(ctrl.text);
                if (newVal != null) {
                  if (newVal < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ الرصيد لا يمكن أن يكون أقل من صفر")));
                    return;
                  }
                  final batch = FirebaseFirestore.instance.batch();
                  await AccountService.updateBalance(cafeId: cafeId, method: methodName, amount: newVal - currentBal, batch: batch);
                  await batch.commit();
                  if (mounted) Navigator.pop(ctx);
                }
              }, 
              child: const Text("تأكيد")
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String t, Color c) => Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5), child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold)));
  Widget _buildCard(List<Widget> c) => Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey[200]!)), child: Column(children: c));
}
