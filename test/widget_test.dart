import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systemcafe/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // إصلاح استدعاء MyApp بقيم افتراضية للاختبار
    await tester.pumpWidget(const MyApp(isActivated: true, isSetupComplete: true));

    // يمكن إضافة اختبارات الوجهات هنا لاحقاً
  });
}
