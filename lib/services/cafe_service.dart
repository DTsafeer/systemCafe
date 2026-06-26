import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CafeSettings {
  final String name;
  final String currencySymbol;
  final bool isKitchenEnabled;
  final bool isInventoryTrackingEnabled;
  final bool showTimeCounter;
  final double hourlyRate;
  final List<String> paymentMethods;
  final String businessType; // 'cafe' or 'supermarket'

  CafeSettings({
    required this.name,
    required this.currencySymbol,
    required this.isKitchenEnabled,
    this.isInventoryTrackingEnabled = true,
    required this.showTimeCounter,
    required this.hourlyRate,
    required this.paymentMethods,
    this.businessType = 'cafe',
  });

  factory CafeSettings.fromMap(Map<String, dynamic> map) {
    return CafeSettings(
      name: map['cafe_name'] ?? map['name'] ?? "Flora Cafe",
      currencySymbol: map['currency_symbol'] ?? "₪",
      isKitchenEnabled: map['isKitchenEnabled'] ?? true,
      isInventoryTrackingEnabled: map['isInventoryTrackingEnabled'] ?? true,
      showTimeCounter: map['show_time_counter'] ?? map['isTimerEnabled'] ?? true,
      hourlyRate: (map['hourly_rate'] ?? map['hour_price'] ?? 0.0).toDouble(),
      paymentMethods: List<String>.from(map['payment_methods'] ?? ["كاش", "شبكة", "دين"]),
      businessType: map['businessType'] ?? 'cafe',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'cafe_name': name,
      'currency_symbol': currencySymbol,
      'isKitchenEnabled': isKitchenEnabled,
      'isInventoryTrackingEnabled': isInventoryTrackingEnabled,
      'show_time_counter': showTimeCounter,
      'hourly_rate': hourlyRate,
      'payment_methods': paymentMethods,
      'businessType': businessType,
    };
  }
}

class CafeService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // مراقبة الإعدادات بشكل مباشر (Stream)
  static Stream<CafeSettings> streamCafeSettings(String cafeId) {
    if (cafeId.isEmpty) return Stream.value(_defaultSettings());
    return _db.collection('cafes').doc(cafeId).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return CafeSettings.fromMap(doc.data()!);
      }
      return _defaultSettings();
    });
  }

  // جلب الإعدادات مرة واحدة (Future)
  static Future<CafeSettings> getCafeSettings(String cafeId) async {
    if (cafeId.isEmpty) return _defaultSettings();
    final doc = await _db.collection('cafes').doc(cafeId).get();
    if (doc.exists && doc.data() != null) {
      return CafeSettings.fromMap(doc.data()!);
    }
    return _defaultSettings();
  }

  // تحديث الإعدادات في Firebase
  static Future<void> updateCafeSettings(String cafeId, CafeSettings settings) async {
    await _db.collection('cafes').doc(cafeId).set(
      settings.toMap(),
      SetOptions(merge: true),
    );
  }

  // إعدادات افتراضية في حال عدم وجود بيانات
  static CafeSettings _defaultSettings() {
    return CafeSettings(
      name: "Flora Cafe",
      currencySymbol: "₪",
      isKitchenEnabled: true,
      isInventoryTrackingEnabled: true,
      showTimeCounter: true,
      hourlyRate: 0.0,
      paymentMethods: ["كاش", "شبكة", "دين"],
      businessType: 'cafe',
    );
  }

  // الحصول على معرف الكافيه النشط من التخزين المحلي
  static Future<String> getActiveCafeId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('cafe_id') ?? "";
  }
  
  // حفظ معرف الكافيه النشط محلياً
  static Future<void> setActiveCafeId(String cafeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cafe_id', cafeId);
  }
}
