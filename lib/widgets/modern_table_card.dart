import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/user_model.dart';
import '../services/table_service.dart';

class ModernTableCard extends StatefulWidget {
  final Map<String, dynamic> tableData;
  final User currentUser;
  final bool isKitchenEnabled;
  final bool showTimeCounter;
  final double hourlyRate;
  final String currencySymbol;
  final VoidCallback onTap;
  final VoidCallback? onPayTap; // جعلها اختيارية
  final VoidCallback? onDelete; // جعلها اختيارية
  final Function(bool) onClose;

  const ModernTableCard({
    super.key,
    required this.tableData,
    required this.currentUser,
    required this.isKitchenEnabled,
    required this.showTimeCounter,
    required this.hourlyRate,
    required this.currencySymbol,
    required this.onTap,
    this.onPayTap,
    this.onDelete,
    required this.onClose,
  });

  @override
  State<ModernTableCard> createState() => _ModernTableCardState();
}

class _ModernTableCardState extends State<ModernTableCard> {
  final ValueNotifier<double> _priceNotifier = ValueNotifier(0.0);
  int _currentSeconds = 0;

  @override
  void dispose() {
    _priceNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isOpen = widget.tableData['is_open'] == true;
    final String managerId = widget.currentUser.parentId ?? widget.currentUser.id;
    final String cafeId = widget.currentUser.cafeId;
    final String tableName = widget.tableData['name'] ?? "";
    final String tableId = widget.tableData['id'];
    final Timestamp? startTime = widget.tableData['start_time'];
    final bool isTimerRunning = startTime != null;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('cafeId', isEqualTo: cafeId)
          .where('parentId', isEqualTo: managerId)
          .where('table', isEqualTo: tableName)
          .where('paid', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        double ordersTotal = 0.0;
        bool hasUnpaid = snapshot.hasData && snapshot.data!.docs.isNotEmpty;

        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            ordersTotal += (double.tryParse(data['total']?.toString() ?? "0") ?? 0.0);
          }
        }

        Color primaryColor = isOpen ? (isTimerRunning ? Colors.orange[700]! : Colors.blue[700]!) : Colors.green[600]!;
        if (hasUnpaid && isOpen) primaryColor = Colors.red[600]!;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
            border: Border.all(color: primaryColor.withOpacity(0.2)),
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(19), topRight: Radius.circular(19)),
                  ),
                  child: Center(child: Text(tableName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                ),
                
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ValueListenableBuilder<double>(
                          valueListenable: _priceNotifier,
                          builder: (context, dynamicPrice, _) {
                            double finalSum = ordersTotal + dynamicPrice;
                            return FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                "${finalSum.ceil()} ${widget.currencySymbol}",
                                style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            );
                          },
                        ),
                        if (widget.showTimeCounter && (isOpen || (widget.tableData['accumulated_seconds'] ?? 0) > 0))
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: ModernTimerWidget(
                              startTime: startTime,
                              accumulatedSeconds: widget.tableData['accumulated_seconds'] ?? 0,
                              hourlyRate: widget.hourlyRate,
                              onPriceChanged: (p) => _priceNotifier.value = p,
                              onTick: (secs) => _currentSeconds = secs,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(color: Colors.grey[50], borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20))),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      if (isOpen || hasUnpaid) ...[
                        if (widget.onPayTap != null) _smallActionBtn(Icons.payments, Colors.green, widget.onPayTap!),
                        if (isOpen) ...[
                          _smallActionBtn(
                            isTimerRunning ? Icons.pause_circle_filled : Icons.play_circle_filled,
                            isTimerRunning ? Colors.orange : Colors.blue,
                            () {
                              if (isTimerRunning) TableService.pauseTimer(tableId, _currentSeconds);
                              else TableService.resumeTimer(tableId);
                            },
                          ),
                          _smallActionBtn(Icons.refresh, Colors.purple, () async {
                             final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text("تصفير الوقت"),
                                  content: const Text("إعادة العداد للصفر؟"),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
                                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("تصفير")),
                                  ],
                                ),
                              );
                              if (confirm == true) TableService.resetTimer(tableId, isTimerRunning);
                          }),
                        ],
                        _smallActionBtn(Icons.power_settings_new, Colors.red, () => widget.onClose(hasUnpaid)),
                      ] else ...[
                        _smallActionBtn(Icons.play_arrow_rounded, Colors.green, () {
                          TableService.updateTableStatus(tableId, true, startTime: null);
                        }),
                        if (widget.onDelete != null) _smallActionBtn(Icons.delete_outline, Colors.grey, widget.onDelete!),
                      ],
                    ],
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _smallActionBtn(IconData icon, Color color, VoidCallback onTap) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(),
      icon: Icon(icon, color: color, size: 24),
      onPressed: onTap,
    );
  }
}

class ModernTimerWidget extends StatefulWidget {
  final Timestamp? startTime;
  final int accumulatedSeconds;
  final double hourlyRate;
  final Function(double) onPriceChanged;
  final Function(int)? onTick;

  const ModernTimerWidget({
    super.key, 
    required this.startTime, 
    required this.accumulatedSeconds, 
    required this.hourlyRate, 
    required this.onPriceChanged,
    this.onTick,
  });

  @override
  State<ModernTimerWidget> createState() => _ModernTimerWidgetState();
}

class _ModernTimerWidgetState extends State<ModernTimerWidget> {
  Timer? _timer;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _calculate();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _calculate());
  }

  void _calculate() {
    if (!mounted) return;
    setState(() {
      if (widget.startTime == null) {
        _duration = Duration(seconds: widget.accumulatedSeconds);
      } else {
        _duration = DateTime.now().difference(widget.startTime!.toDate()) + Duration(seconds: widget.accumulatedSeconds);
      }
    });
    double price = (_duration.inSeconds / 3600) * widget.hourlyRate;
    widget.onPriceChanged(price);
    if (widget.onTick != null) widget.onTick!(_duration.inSeconds);
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Text(
      "${_duration.inHours}:${(_duration.inMinutes % 60).toString().padLeft(2, '0')}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}",
      style: TextStyle(
        fontSize: 12, 
        fontWeight: FontWeight.bold, 
        color: widget.startTime != null ? Colors.blue[800] : Colors.orange[900],
      ),
    );
  }
}
