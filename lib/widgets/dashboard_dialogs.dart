import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../pages/user_model.dart';
import '../services/transfer_service.dart';

class DashboardDialogs {
  static void showDebtSelectionDialog({
    required BuildContext context,
    required List<Map<String, String>> customerSuggestions,
    required TextEditingController nameController,
    required TextEditingController phoneController,
    required Function(String?, String?) onSelected,
  }) {
    final TextEditingController searchCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = searchCtrl.text.trim().toLowerCase();
          final filtered = customerSuggestions.where((s) => 
            s['name']!.toLowerCase().contains(query) || (s['no'] ?? "").contains(query)
          ).toList();

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              title: const Row(children: [Icon(Icons.person_search, color: Color(0xFF634231)), SizedBox(width: 10), Text("اختر صاحب الحساب")]),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      onChanged: (v) => setDialogState(() {}),
                      decoration: InputDecoration(
                        hintText: "بحث عن اسم أو رقم الحساب...",
                        prefixIcon: const Icon(Icons.search),
                        filled: true, fillColor: Colors.grey[100],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 15),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final s = filtered[i];
                            return ListTile(
                              title: Text(s['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text("الرصيد الحالي: ${s['debt'] ?? '0.0'} ₪"),
                              trailing: const Icon(Icons.chevron_left),
                              onTap: () {
                                nameController.text = s['name']!;
                                phoneController.text = s['phone']!;
                                onSelected(s['id'], s['debt']);
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء", style: TextStyle(fontSize: 16))),
              ],
            ),
          );
        }
      ),
    );
  }

  // --- 1. نافذة الحوالة اليدوية ---
  static void showManualTransferDialog({
    required BuildContext context,
    required User currentUser,
    required List<String> paymentMethods,
    required List<Map<String, String>> customerSuggestions,
    required String managerId,
    DocumentSnapshot? editDoc,
  }) {
    final Map? d = editDoc?.data() as Map?;
    final nC = TextEditingController(text: d?['customer_name'] ?? "");
    final aC = TextEditingController(text: d?['total_amount']?.toString() ?? "");
    final pC = TextEditingController(text: d?['customer_phone'] ?? "");
    final noteC = TextEditingController(text: d?['note'] ?? "");
    
    List<String> methods = paymentMethods.where((m) => !m.contains("دين")).toList();
    if (methods.isEmpty) methods = ["كاش", "شبكة"];
    
    String method = d?['payment_method'] ?? methods.first;
    DateTime selectedDate = (d?['paid_at'] as Timestamp?)?.toDate() ?? DateTime.now();
    bool isSaving = false;
    String? selectedCustomerId;
    bool isPending = d?['is_pending'] ?? false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFF0D47A1), Color(0xFF1976D2)]),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Row(children: [Icon(Icons.send_to_mobile, color: Colors.white, size: 28), SizedBox(width: 15), Text("تسجيل حوالة يدوية", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx))
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          title: const Text("حوالة معلقة", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                          subtitle: const Text("سيتم وضع الحوالة في قائمة الانتظار"),
                          value: isPending,
                          onChanged: (v) => setState(() => isPending = v),
                        ),
                        const Divider(),
                        const Text("اسم المرسل / الزبون:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
                        const SizedBox(height: 8),
                        Autocomplete<Map<String, String>>(
                          displayStringForOption: (option) => option['name']!,
                          initialValue: TextEditingValue(text: nC.text),
                          optionsBuilder: (textEditingValue) {
                            if (textEditingValue.text.isEmpty) return const Iterable.empty();
                            return customerSuggestions.where((c) =>
                                c['name']!.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                          },
                          onSelected: (selection) {
                            setState(() {
                              nC.text = selection['name']!;
                              pC.text = selection['phone'] ?? "";
                              selectedCustomerId = selection['id'];
                            });
                          },
                          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                            return _popupInput(
                              controller, "ادخل اسم الزبون هنا...", Icons.person_outline,
                              enabled: !isSaving,
                              focusNode: focusNode,
                              onChanged: (val) {
                                nC.text = val;
                                selectedCustomerId = null;
                              },
                              suffix: IconButton(
                                icon: const Icon(Icons.search, size: 20, color: Color(0xFF0D47A1)),
                                onPressed: () => showDebtSelectionDialog(
                                  context: context,
                                  customerSuggestions: customerSuggestions,
                                  nameController: nC,
                                  phoneController: pC,
                                  onSelected: (id, balance) {
                                    setState(() {
                                      selectedCustomerId = id;
                                      controller.text = nC.text;
                                    });
                                  },
                                ),
                              )
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(child: _popupInput(aC, "المبلغ", Icons.monetization_on_outlined, isNum: true, enabled: !isSaving)),
                            const SizedBox(width: 10),
                            Expanded(child: _popupInput(pC, "رقم الهاتف", Icons.phone_android_outlined, isPhone: true, enabled: !isSaving)),
                          ],
                        ),
                        const SizedBox(height: 15),
                        DropdownButtonFormField<String>(
                          value: method,
                          items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                          onChanged: isSaving ? null : (v) => setState(() => method = v!),
                          decoration: InputDecoration(labelText: "طريقة الاستلام", filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
                        ),
                        const SizedBox(height: 15),
                        _popupInput(noteC, "ملاحظات الحوالة (مثال: بيع بن)", Icons.notes, enabled: !isSaving),
                        const SizedBox(height: 15),
                        InkWell(
                          onTap: isSaving ? null : () async {
                            final pickedDate = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                            if (pickedDate != null) {
                              final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(selectedDate));
                              if (pickedTime != null) {
                                setState(() => selectedDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute));
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15)),
                            child: Row(children: [
                              Icon(Icons.calendar_today_outlined, color: Colors.grey[600], size: 18),
                              const SizedBox(width: 10),
                              Text("التاريخ: ${intl.DateFormat('yyyy/MM/dd HH:mm').format(selectedDate)}", style: TextStyle(color: Colors.grey[800])),
                              const Spacer(), const Icon(Icons.edit, size: 16, color: Color(0xFF0D47A1))
                            ]),
                          ),
                        ),
                        const SizedBox(height: 25),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), 
                            onPressed: isSaving ? null : () async {
                              final String customerName = nC.text.trim();
                              final double? amount = double.tryParse(aC.text.trim());
                              if (customerName.isEmpty || amount == null || amount <= 0) return;
                              
                              setState(() => isSaving = true);
                              try {
                                await TransferService.performSave(
                                  context: context, editDoc: editDoc, currentUser: currentUser,
                                  customerName: customerName, payerName: customerName,
                                  phone: pC.text.trim(), amt: amount, method: method,
                                  cafeId: currentUser.cafeId, isDebtPayment: false, 
                                  selectedDebtId: selectedCustomerId, note: noteC.text.trim(),
                                  customDate: selectedDate, table: 'حوالة يدوية', isPending: isPending
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                if (ctx.mounted) setState(() => isSaving = false);
                              }
                            }, 
                            child: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("تأكيد تسجيل الحوالة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), side: const BorderSide(color: Colors.grey)),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text("إلغاء", style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- 2. نافذة تسجيل مبيعات يدوية ---
  static void showManualSaleDialog({
    required BuildContext context,
    required User currentUser,
    required List<String> paymentMethods,
    required List<Map<String, String>> customerSuggestions,
    required String managerId,
    DocumentSnapshot? editDoc,
  }) {
    final Map? d = editDoc?.data() as Map?;
    final nC = TextEditingController(text: d?['customer_name'] ?? "");
    final aC = TextEditingController(text: d?['total_amount']?.toString() ?? "");
    final pC = TextEditingController(text: d?['customer_phone'] ?? "");
    final noteC = TextEditingController(text: d?['note'] ?? "");
    
    List<String> methods = paymentMethods.toList();
    if (currentUser.canManageDebts && !methods.contains("دين")) methods.add("دين");

    String method = d?['payment_method'] ?? methods.first;
    String? selectedCustomerId = d?['selectedDebtId'];
    DateTime selectedDate = (d?['paid_at'] as Timestamp?)?.toDate() ?? DateTime.now();
    bool isSaving = false;
    bool isPending = d?['is_pending'] ?? false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Colors.blue[900]!, Colors.blue[600]!]),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Row(children: [Icon(Icons.add_shopping_cart, color: Colors.white, size: 28), SizedBox(width: 15), Text("تسجيل مبيعات يدوية", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx))
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          title: const Text("حوالة معلقة", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                          subtitle: const Text("سيتم وضع الحوالة في قائمة الانتظار"),
                          value: isPending,
                          onChanged: (v) => setState(() => isPending = v),
                        ),
                        const Divider(),
                        const Text("اسم الزبون / المشتري:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                        const SizedBox(height: 8),
                        Autocomplete<Map<String, String>>(
                          displayStringForOption: (option) => option['name']!,
                          initialValue: TextEditingValue(text: nC.text),
                          optionsBuilder: (textEditingValue) {
                            if (textEditingValue.text.isEmpty) return const Iterable.empty();
                            return customerSuggestions.where((c) =>
                                c['name']!.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                          },
                          onSelected: (selection) {
                            setState(() {
                              nC.text = selection['name']!;
                              pC.text = selection['phone'] ?? "";
                              selectedCustomerId = selection['id'];
                            });
                          },
                          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                            return _popupInput(
                              controller, "ادخل اسم الزبون هنا...", Icons.person_outline,
                              enabled: !isSaving,
                              focusNode: focusNode,
                              onChanged: (val) {
                                nC.text = val;
                                selectedCustomerId = null;
                              },
                              suffix: IconButton(
                                icon: const Icon(Icons.search, color: Colors.blue),
                                onPressed: () => showDebtSelectionDialog(
                                  context: context,
                                  customerSuggestions: customerSuggestions,
                                  nameController: nC,
                                  phoneController: pC,
                                  onSelected: (id, balance) {
                                    setState(() {
                                      selectedCustomerId = id;
                                      controller.text = nC.text;
                                    });
                                  },
                                ),
                              )
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(child: _popupInput(aC, "سعر البيع", Icons.monetization_on, isNum: true, enabled: !isSaving)),
                            const SizedBox(width: 10),
                            Expanded(child: _popupInput(pC, "رقم الهاتف", Icons.phone_android, isPhone: true, enabled: !isSaving)),
                          ],
                        ),
                        const SizedBox(height: 15),
                        DropdownButtonFormField<String>(
                          value: method,
                          items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                          onChanged: isSaving ? null : (v) => setState(() => method = v!),
                          decoration: InputDecoration(labelText: "طريقة الدفع", filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
                        ),
                        const SizedBox(height: 15),
                        _popupInput(noteC, "ملاحظات (مثلاً: بيع بن، خدمة...)", Icons.notes, enabled: !isSaving),
                        const SizedBox(height: 15),
                        InkWell(
                          onTap: isSaving ? null : () async {
                            final pickedDate = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                            if (pickedDate != null) {
                              final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(selectedDate));
                              if (pickedTime != null) {
                                setState(() => selectedDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute));
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15)),
                            child: Row(children: [
                              Icon(Icons.calendar_today_outlined, color: Colors.grey[600], size: 18),
                              const SizedBox(width: 10),
                              Text("التاريخ: ${intl.DateFormat('yyyy/MM/dd HH:mm').format(selectedDate)}", style: TextStyle(color: Colors.grey[800])),
                              const Spacer(), const Icon(Icons.edit, size: 16, color: Colors.blue)
                            ]),
                          ),
                        ),
                        const SizedBox(height: 25),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[900], padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                            onPressed: isSaving ? null : () async {
                              final String customerName = nC.text.trim();
                              final double? amount = double.tryParse(aC.text.trim());
                              if (customerName.isEmpty || amount == null || amount <= 0) return;
                              setState(() => isSaving = true);
                              try {
                                await TransferService.performSave(
                                  context: context, editDoc: editDoc, currentUser: currentUser,
                                  customerName: customerName, payerName: customerName,
                                  phone: pC.text, amt: amount, method: method,
                                  cafeId: currentUser.cafeId, isDebtPayment: false,
                                  selectedDebtId: selectedCustomerId, note: noteC.text,
                                  customDate: selectedDate, table: 'مبيعات يدوية', isPending: isPending
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                if (ctx.mounted) setState(() => isSaving = false);
                              }
                            }, 
                            child: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("تسجيل المبيعات", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), side: const BorderSide(color: Colors.grey)),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text("إلغاء", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- 3. نافذة تسجيل سداد دين ---
  static void showAddTransferDialog({
    required BuildContext context,
    required User currentUser,
    required List<String> paymentMethods,
    required List<Map<String, String>> customerSuggestions,
    required String managerId,
    DocumentSnapshot? editDoc,
    String? initialName,
    String? initialPhone,
    String? initialCustomerId,
  }) {
    final Map? d = editDoc?.data() as Map?;
    final nC = TextEditingController(text: initialName ?? d?['customer_name'] ?? "");
    final payerC = TextEditingController(text: d?['payer_name'] ?? initialName ?? d?['customer_name'] ?? ""); 
    final aC = TextEditingController(text: d?['total_amount']?.toString() ?? "");
    final pC = TextEditingController(text: initialPhone ?? d?['customer_phone'] ?? "");
    final noteC = TextEditingController(text: d?['note'] ?? "");
    
    List<String> filteredMethods = paymentMethods.where((m) => !m.contains("دين") && !m.contains("ديون")).toList();
    if (filteredMethods.isEmpty) filteredMethods = ["كاش", "شبكة"];

    String method = d?['payment_method'] ?? filteredMethods.first;
    String? selectedCustomerId = initialCustomerId;
    DateTime selectedDate = (d?['paid_at'] as Timestamp?)?.toDate() ?? DateTime.now();
    bool isSaving = false;
    double? oldAmount = d?['total_amount']?.toDouble();
    bool isPending = d?['is_pending'] ?? false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFF634231), Color(0xFF8D6E63)]),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Row(children: [Icon(editDoc == null ? Icons.payments_outlined : Icons.edit_note_rounded, color: Colors.white, size: 28), const SizedBox(width: 15), Text(editDoc == null ? "تسجيل دفعة سداد" : "تعديل دفعة", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx))
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          title: const Text("حوالة معلقة", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                          subtitle: const Text("سيتم وضع الحوالة في قائمة الانتظار"),
                          value: isPending,
                          onChanged: (v) => setStateDialog(() => isPending = v),
                        ),
                        const Divider(),
                        const Text("اسم الشخص المحول:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF634231))),
                        const SizedBox(height: 8),
                        _popupInput(payerC, "اكتب اسم من قام بالتحويل", Icons.person, enabled: !isSaving),
                        const SizedBox(height: 20),
                        const Text("يخصم من حساب الزبون (صاحب الدين):", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 8),
                        Autocomplete<Map<String, String>>(
                          displayStringForOption: (option) => option['name']!,
                          initialValue: TextEditingValue(text: nC.text),
                          optionsBuilder: (textEditingValue) {
                            if (textEditingValue.text.isEmpty) return const Iterable.empty();
                            return customerSuggestions.where((c) =>
                                c['name']!.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                          },
                          onSelected: (selection) {
                            setStateDialog(() {
                              nC.text = selection['name']!;
                              pC.text = selection['phone'] ?? "";
                              selectedCustomerId = selection['id'];
                            });
                          },
                          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                            if (controller.text.isEmpty && nC.text.isNotEmpty) controller.text = nC.text;
                            return _popupInput(
                              controller, "ادخل اسم صاحب الحساب هنا...", Icons.account_box_outlined,
                              enabled: !isSaving,
                              focusNode: focusNode,
                              onChanged: (val) {
                                nC.text = val;
                                selectedCustomerId = null;
                              },
                              suffix: IconButton(
                                icon: const Icon(Icons.search, color: Color(0xFF634231)),
                                onPressed: () => showDebtSelectionDialog(
                                  context: context,
                                  customerSuggestions: customerSuggestions,
                                  nameController: nC,
                                  phoneController: pC,
                                  onSelected: (id, balance) {
                                    setStateDialog(() {
                                      selectedCustomerId = id;
                                      controller.text = nC.text;
                                    });
                                  },
                                ),
                              )
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(child: _popupInput(aC, "المبلغ", Icons.monetization_on, isNum: true, enabled: !isSaving)),
                            const SizedBox(width: 10),
                            Expanded(child: _popupInput(pC, "الهاتف", Icons.phone_android, isPhone: true, enabled: !isSaving)),
                          ],
                        ),
                        const SizedBox(height: 15),
                        DropdownButtonFormField<String>(
                          value: filteredMethods.contains(method) ? method : filteredMethods.first,
                          items: filteredMethods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                          onChanged: isSaving ? null : (v) => setStateDialog(() => method = v!),
                          decoration: InputDecoration(labelText: "طريقة الاستلام", filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
                        ),
                        const SizedBox(height: 15),
                        _popupInput(noteC, "ملاحظات", Icons.notes, enabled: !isSaving),
                        const SizedBox(height: 15),
                        InkWell(
                          onTap: isSaving ? null : () async {
                            final DateTime? pickedDate = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (pickedDate != null) {
                              final TimeOfDay? pickedTime = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(selectedDate),
                              );
                              if (pickedTime != null) {
                                setStateDialog(() {
                                  selectedDate = DateTime(
                                    pickedDate.year, pickedDate.month, pickedDate.day,
                                    pickedTime.hour, pickedTime.minute,
                                  );
                                });
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today_outlined, color: Colors.grey[600], size: 18),
                                const SizedBox(width: 10),
                                Text(
                                  "التاريخ: ${intl.DateFormat('yyyy/MM/dd HH:mm').format(selectedDate)}",
                                  style: TextStyle(color: Colors.grey[800]),
                                ),
                                const Spacer(),
                                const Icon(Icons.edit, size: 16, color: Color(0xFF634231)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 25),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF634231), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), 
                            onPressed: isSaving ? null : () async {
                              final double? amount = double.tryParse(aC.text.trim());
                              if (nC.text.isEmpty || amount == null || amount <= 0) return;
                              setStateDialog(() => isSaving = true);
                              try {
                                await TransferService.performSave(
                                  context: context, editDoc: editDoc, currentUser: currentUser,
                                  customerName: nC.text.trim(), payerName: payerC.text.trim(), phone: pC.text.trim(), 
                                  amt: amount, method: method, cafeId: currentUser.cafeId, isDebtPayment: true, 
                                  selectedDebtId: selectedCustomerId, oldAmount: oldAmount, note: noteC.text.trim(), 
                                  customDate: selectedDate, table: 'حوالة سريعة', isPending: isPending
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                if (ctx.mounted) setStateDialog(() => isSaving = false);
                              }
                            }, 
                            child: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("تأكيد وإضافة السداد", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), side: const BorderSide(color: Colors.grey)),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text("إلغاء", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _popupInput(TextEditingController ctrl, String label, IconData icon, {bool isNum = false, bool isPhone = false, bool enabled = true, Widget? suffix, FocusNode? focusNode, Function(String)? onChanged}) {
    return TextField(
      controller: ctrl, enabled: enabled, focusNode: focusNode, onChanged: onChanged,
      keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : (isPhone ? TextInputType.phone : TextInputType.text),
      decoration: InputDecoration(
        hintText: label, prefixIcon: Icon(icon, color: Colors.grey[600], size: 18), suffixIcon: suffix,
        filled: true, fillColor: Colors.grey[100], 
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none), 
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }
}
