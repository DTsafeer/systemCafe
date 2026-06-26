import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';
import 'homepage.dart';
import '../services/setup_service.dart';
import '../widgets/setup_widgets.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _cafeNameController = TextEditingController();
  final TextEditingController _promoCodeController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();
  final TextEditingController _ownerEmailController = TextEditingController();
  final TextEditingController _ownerPasswordController = TextEditingController();

  String _selectedPackage = ""; 
  String _selectedCurrency = "₪";
  bool _isLoading = false;
  bool _isFetching = true;
  List<Map<String, dynamic>> _dynamicPackages = [];

  final Map<String, String> _permLabels = {
    'canViewReports': 'تقارير مالية',
    'canEditMenu': 'إدارة المنيو',
    'canManageTables': 'الطاولات',
    'canViewInventory': 'المخازن',
    'canViewKitchen': 'المطبخ',
    'canViewDashboard': 'الإحصائيات',
  };

  final Map<String, IconData> _permIcons = {
    'canViewReports': Icons.analytics_outlined,
    'canEditMenu': Icons.restaurant_menu_rounded,
    'canManageTables': Icons.table_bar_rounded,
    'canViewInventory': Icons.inventory_2_outlined,
    'canViewKitchen': Icons.soup_kitchen_rounded,
    'canViewDashboard': Icons.dashboard_outlined,
  };

  @override
  void initState() {
    super.initState();
    _fetchPackages();
  }

  Future<void> _fetchPackages() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('subscription_packages').get();
      final pkgs = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();

      if (mounted) {
        setState(() {
          _dynamicPackages = pkgs;
          if (_dynamicPackages.isNotEmpty) {
            int index = _dynamicPackages.indexWhere((p) => p['name'].toString().contains("احترافية"));
            _selectedPackage = index != -1 ? _dynamicPackages[index]['name'] : _dynamicPackages[0]['name'];
          }
          _isFetching = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching packages: $e");
      if (mounted) setState(() => _isFetching = false);
    }
  }

  Future<void> _completeSetup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPackage.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى اختيار حزمة أولاً")));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final selectedPkg = _dynamicPackages.firstWhere((p) => p['name'] == _selectedPackage);
      final Map<String, dynamic> packagePerms = Map<String, dynamic>.from(selectedPkg['permissions'] ?? {});
      final int maxEmployees = selectedPkg['maxEmployees'] ?? -1;

      final String email = _ownerEmailController.text.trim().toLowerCase();
      final String name = _ownerNameController.text.trim();
      final String password = _ownerPasswordController.text.trim();
      final String cafeName = _cafeNameController.text.trim();

      await SetupService.completeSetup(
        cafeName: cafeName,
        selectedPackage: _selectedPackage,
        maxEmployees: maxEmployees,
        currencySymbol: _selectedCurrency,
        promoCode: _promoCodeController.text.trim(),
        email: email,
        name: name,
        password: password,
        packagePerms: packagePerms,
      );

      if (mounted) {
        final userPermissions = { ...packagePerms, 'canManageUsers': true };
        final currentUser = User(
          id: email,
          name: name,
          email: email,
          password: password,
          role: UserRole.admin,
          cafeId: "get_from_prefs", // SetupService sets it
          permissions: userPermissions,
          isOnline: true,
          isActive: true,
        );

        final prefs = await SharedPreferences.getInstance();
        final actualCafeId = prefs.getString('cafe_id') ?? "";

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomePage(currentUser: currentUser.copyWith(cafeId: actualCafeId)))
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل في حفظ البيانات: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("إكمال إعداد المنشأة"), 
        centerTitle: true, elevation: 0,
      ),
      body: _isFetching 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Container(
                width: double.infinity,
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          const Text("اختر خطة النجاح المناسبة لك", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.brown)),
                          const Text("انضم إلى مئات الكافيهات التي تستخدم نظامنا الذكي", style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 40),
                          
                          LayoutBuilder(builder: (context, constraints) {
                            if (_dynamicPackages.isEmpty) return const Text("لا توجد حزم متاحة حالياً");
                            return Wrap(
                              spacing: 25, runSpacing: 25,
                              alignment: WrapAlignment.center,
                              children: _dynamicPackages.map((pkg) => PackageCard(
                                pkg: pkg, 
                                isWide: constraints.maxWidth > 900, 
                                isSelected: _selectedPackage == pkg['name'], 
                                currency: _selectedCurrency, 
                                onTap: () => setState(() => _selectedPackage = pkg['name']), 
                                permLabels: _permLabels, 
                                permIcons: _permIcons,
                              )).toList(),
                            );
                          }),

                          const SizedBox(height: 50),
                          _sectionTitle("🏷️ هل تملك كود خصم؟"),
                          _buildTextField(_promoCodeController, "أدخل رمز الكوبون", Icons.local_offer, color: Colors.green),

                          const SizedBox(height: 40),
                          _sectionTitle("🏢 بيانات المنشأة"),
                          _buildFormSection([
                            _buildTextField(_cafeNameController, "اسم الكافيه / المطعم", Icons.store_mall_directory_rounded),
                            const SizedBox(height: 15),
                            _buildDropdown("العملة", ["₪", "\$", "JOD", "EGP"], _selectedCurrency, (v) => setState(() => _selectedCurrency = v!)),
                          ]),

                          const SizedBox(height: 40),
                          _sectionTitle("👤 بيانات المدير"),
                          _buildFormSection([
                            _buildTextField(_ownerNameController, "الاسم الكامل", Icons.person_pin_rounded),
                            const SizedBox(height: 15),
                            _buildTextField(_ownerEmailController, "البريد الإلكتروني", Icons.alternate_email_rounded),
                            const SizedBox(height: 15),
                            _buildTextField(_ownerPasswordController, "كلمة المرور", Icons.lock_person_rounded, isPass: true),
                          ]),

                          const SizedBox(height: 60),
                          _isLoading 
                            ? const CircularProgressIndicator()
                            : SizedBox(
                                width: double.infinity, height: 65,
                                child: ElevatedButton(
                                  onPressed: _completeSetup,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.colorScheme.primary, 
                                    foregroundColor: Colors.white, 
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    elevation: 8,
                                  ),
                                  child: const Text("تأكيد الاشتراك وبدء العمل 🚀", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                                ),
                              ),
                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildFormSection(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20)]),
      child: Column(children: children),
    );
  }

  Widget _sectionTitle(String title) => Padding(padding: const EdgeInsets.only(bottom: 15, top: 10), child: Align(alignment: Alignment.centerRight, child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.brown))));

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon, {bool isPass = false, Color? color}) {
    return TextFormField(
      controller: ctrl, obscureText: isPass,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: color), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none), filled: true, fillColor: const Color(0xFFF1F3F5)),
      validator: (v) => v!.isEmpty ? "هذا الحقل مطلوب" : null,
    );
  }

  Widget _buildDropdown(String label, List<String> items, String current, Function(String?) onChange) {
    return DropdownButtonFormField<String>(
      value: current,
      decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none), filled: true, fillColor: const Color(0xFFF1F3F5)),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChange,
    );
  }
}
