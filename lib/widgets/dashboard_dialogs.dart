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
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ],
            ),
          );
        }
      ),
    );
  }

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
    
    // اسم صاحب الدين الأصلي
    final nC = TextEditingController(text: initialName ?? d?['customer_name'] ?? "");
    // اسم الشخص المحول (الذي يظهر في الأعلى)
    final payerC = TextEditingController(text: d?['payer_name'] ?? initialName ?? d?['customer_name'] ?? ""); 
    final aC = TextEditingController(text: d?['total_amount']?.toString() ?? "");
    final pC = TextEditingController(text: initialPhone ?? d?['customer_phone'] ?? "");
    final noteC = TextEditingController(text: d?['note'] ?? "");
    
    List<String> filteredMethods = paymentMethods.where((m) => !m.contains("دين")).toList();
    if (filteredMethods.isEmpty) filteredMethods = ["كاش", "شبكة"];

    String method = d?['payment_method'] ?? (filteredMethods.contains(d?['payment_method']) ? d!['payment_method'] : filteredMethods.first);
    String? selectedCustomerId = initialCustomerId;
    
    String currentBalance = "0.0";
    if (initialCustomerId != null) {
      try {
        currentBalance = customerSuggestions.firstWhere((s) => s['id'] == initialCustomerId)['debt'] ?? "0.0";
      } catch (_) {}
    } else if (editDoc != null) {
       // محاولة إيجاد رصيد الزبون الحالي من القائمة الممررة
       try {
         currentBalance = customerSuggestions.firstWhere((s) => s['name'] == nC.text)['debt'] ?? "0.0";
       } catch (_) {}
    }

    DateTime selectedDate = (d?['paid_at'] as Timestamp?)?.toDate() ?? DateTime.now();
    bool isDebtPayment = initialCustomerId != null || (d?['is_debt_payment'] ?? true);
    bool isSaving = false;
    double? oldAmount = d?['total_amount']?.toDouble();

    String? nameError;
    String? amountError;

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
                        // 1. حقل اسم المحول (الأعلى والأساسي)
                        const Text("اسم الشخص المحول:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF634231))),
                        const SizedBox(height: 8),
                        _popupInput(payerC, "اكتب اسم من قام بالتحويل", Icons.person, enabled: !isSaving),
                        
                        const SizedBox(height: 20),

                        // 2. حقل صاحب الدين (تنويهي/اختياري)
                        const Text("يخصم من حساب الزبون:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: isSaving ? null : () => showDebtSelectionDialog(
                            context: context,
                            customerSuggestions: customerSuggestions,
                            nameController: nC,
                            phoneController: pC,
                            onSelected: (id, balance) => setStateDialog(() {
                              selectedCustomerId = id;
                              currentBalance = balance ?? "0.0";
                              nameError = null;
                              // إذا كان اسم المحول فارغاً، نضع اسم الزبون تلقائياً
                              if (payerC.text.isEmpty) payerC.text = nC.text;
                            }),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[50], 
                              borderRadius: BorderRadius.circular(15), 
                              border: Border.all(color: nameError != null ? Colors.red : Colors.grey[300]!)
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.account_box_outlined, color: nC.text.isEmpty ? Colors.grey : const Color(0xFF634231)),
                                const SizedBox(width: 12),
                                Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(nC.text.isEmpty ? "اضغط لاختيار صاحب الدين" : nC.text, style: TextStyle(color: nC.text.isEmpty ? Colors.grey : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                                    if (nC.text.isNotEmpty)
                                      Text("الرصيد الحالي: $currentBalance ₪", style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                                  ],
                                )),
                                const Icon(Icons.search, size: 20, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                        if (nameError != null)
                          Padding(padding: const EdgeInsets.only(top: 5, right: 10), child: Text(nameError!, style: const TextStyle(color: Colors.red, fontSize: 11))),

                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 10),

                        // باقي الحقول (مبلغ، تاريخ، طريقة دفع)
                        Row(
                          children: [
                            Expanded(child: _popupInput(aC, "المبلغ", Icons.monetization_on, isNum: true, enabled: !isSaving, errorText: amountError)),
                            const SizedBox(width: 10),
                            Expanded(child: _popupInput(pC, "الهاتف", Icons.phone_android, isPhone: true, enabled: !isSaving)),
                          ],
                        ),
                        const SizedBox(height: 15),
                        
                        InkWell(
                          onTap: isSaving ? null : () async {
                            final d = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2022), lastDate: DateTime.now().add(const Duration(days: 365)));
                            if (d != null) {
                              final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(selectedDate));
                              if (t != null) setStateDialog(() => selectedDate = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
                            child: Row(children: [
                              const Icon(Icons.event, color: Colors.grey, size: 18),
                              const SizedBox(width: 10),
                              Text(intl.DateFormat('yyyy/MM/dd HH:mm').format(selectedDate), style: const TextStyle(fontSize: 13)),
                              const Spacer(),
                              const Icon(Icons.edit, size: 14, color: Colors.blue),
                            ]),
                          ),
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
                        
                        const SizedBox(height: 25),
                        
                        // زر التأكيد
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF634231), 
                              padding: const EdgeInsets.symmetric(vertical: 15), 
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              elevation: 5
                            ), 
                            onPressed: isSaving ? null : () async {
                              final String payerName = payerC.text.trim();
                              final String customerName = nC.text.trim();
                              final double? amount = double.tryParse(aC.text.trim());

                              setStateDialog(() {
                                nameError = customerName.isEmpty ? "يجب اختيار صاحب الحساب" : null;
                                amountError = (amount == null || amount <= 0) ? "المبلغ غير صحيح" : null;
                              });

                              if (nameError != null || amountError != null) return;
                              
                              setStateDialog(() => isSaving = true);
                              try {
                                await TransferService.performSave(
                                  context: context,
                                  editDoc: editDoc,
                                  currentUser: currentUser,
                                  customerName: customerName,
                                  payerName: payerName.isEmpty ? customerName : payerName,
                                  phone: pC.text.trim(),
                                  amt: amount!,
                                  method: method,
                                  cafeId: currentUser.cafeId,
                                  isDebtPayment: isDebtPayment,
                                  selectedDebtId: selectedCustomerId,
                                  oldAmount: oldAmount,
                                  note: noteC.text.trim(),
                                  customDate: selectedDate,
                                  table: editDoc == null ? 'حوالة سريعة' : (d?['table'] ?? 'حوالة سريعة')
                                );
                                
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم حفظ العملية بنجاح"), backgroundColor: Colors.green));
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  setStateDialog(() => isSaving = false);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ خطأ: $e"), backgroundColor: Colors.red));
                                }
                              }
                            }, 
                            child: isSaving 
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(editDoc == null ? "تأكيد وإضافة" : "حفظ التعديلات", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء", style: TextStyle(color: Colors.grey)))),
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

  static Widget _popupInput(TextEditingController ctrl, String label, IconData icon, {bool isNum = false, bool isPhone = false, bool enabled = true, String? errorText}) {
    return TextField(
      controller: ctrl,
      enabled: enabled,
      keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : (isPhone ? TextInputType.phone : TextInputType.text),
      decoration: InputDecoration(
        hintText: label, 
        prefixIcon: Icon(icon, color: const Color(0xFF634231), size: 18), 
        filled: true, fillColor: Colors.grey[100], 
        errorText: errorText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none), 
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        errorStyle: const TextStyle(color: Colors.red, fontSize: 10),
      ),
    );
  }
}
