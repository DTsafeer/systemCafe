import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// استيراد المساعد الذي أنشأناه للويب
import 'web_request_helper_stub.dart'
    if (dart.library.html) 'web_request_helper_web.dart';

class GoogleSheetsService {
  static Future<bool> sendOrderToSheet(Map<String, dynamic> orderData, {String? customUrl}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String url = customUrl ?? prefs.getString('googleSheetUrl') ?? "";

      if (url.isEmpty) return false;

      final Map<String, dynamic> payload = {
        'timestamp': DateTime.now().toIso8601String(),
        'cafeName': prefs.getString('cafeName') ?? 'System Cafe',
        ...orderData,
      };

      final String body = jsonEncode(payload);

      if (kIsWeb) {
        final String encodedPayload = Uri.encodeComponent(body);
        final String finalUrl = url.contains('?') 
            ? "$url&payload=$encodedPayload" 
            : "$url?payload=$encodedPayload";
            
        // استدعاء دالة الويب بشكل آمن
        await sendFireAndForgetImageRequest(finalUrl);
        return true; 
      } else {
        final response = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: body,
        );
        return response.statusCode == 200 || response.statusCode == 302;
      }
    } catch (e) {
      print("❌ خطأ Google Sheets: $e");
      return false;
    }
  }
}
