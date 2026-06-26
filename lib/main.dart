import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'firebase_options.dart';
import 'pages/LoginPage.dart';
import 'pages/SetupPage.dart';
import 'pages/ActivationPage.dart';
import 'utils/device_info.dart';
import 'services/reminder_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  bool isActivated = false;
  bool isSetupComplete = false;
  
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }

    // إعدادات Firestore
    if (kIsWeb) {
      // على الويب، نستخدم الإعدادات الافتراضية لضمان التوافق مع Hot Restart
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false, // الويب يتعامل مع التخزين بشكل مختلف
      );
    } else {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }

    // تهيئة نظام التنبيهات
    await ReminderService.init();

    final prefs = await SharedPreferences.getInstance();
    isActivated = prefs.getBool('is_activated') ?? false;
    isSetupComplete = prefs.getBool('isSetupComplete') ?? false;

    // إنشاء حساب المسؤول بشكل آمن
    _ensureAdminAccount();

    if (!isActivated) {
      String deviceId = await DeviceUtils.getDeviceId();
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('deviceId', isEqualTo: deviceId)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        isActivated = true;
        isSetupComplete = true;
        await prefs.setBool('is_activated', true);
        await prefs.setBool('isSetupComplete', true);
      }
    }
  } catch (e) {
    debugPrint('⚠️ Firebase Init Notice: $e');
  }

  await initializeDateFormatting('ar', null);

  runApp(MyApp(isActivated: isActivated, isSetupComplete: isSetupComplete));
}

// دالة لإنشاء حساب المسؤول بشكل آمن دون التسبب في تضارب أثناء التشغيل
void _ensureAdminAccount() {
  Timer(const Duration(seconds: 2), () async {
    try {
      await FirebaseFirestore.instance.collection('users').doc('admin').set({
        'username': 'admin',
        'password': '123',
        'role': 'super_admin',
        'isActive': true,
        'name': 'المدير العام',
        'cafeId': 'system',
        'isOnline': false,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Admin Init: $e");
    }
  });
}

class MyApp extends StatefulWidget {
  final bool isActivated;
  final bool isSetupComplete;
  const MyApp({super.key, required this.isActivated, required this.isSetupComplete});

  static void updateTheme(BuildContext context) {
    _MyAppState? state = context.findAncestorStateOfType<_MyAppState>();
    state?.loadSettings();
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Color primaryColor = const Color(0xFF6F4E37); 
  bool isDarkMode = false;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        int colorValue = prefs.getInt('primaryColor') ?? const Color(0xFF6F4E37).value;
        primaryColor = Color(colorValue);
        isDarkMode = prefs.getBool('isDarkMode') ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget initialHome = widget.isActivated ? const LoginPage() : const ActivationPage();

    return MaterialApp(
      navigatorKey: navigatorKey, 
      debugShowCheckedModeBanner: false,
      title: 'Flora Cafe POS',
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', 'AE'), Locale('en', 'US')],
      locale: const Locale('ar', 'AE'),
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Cairo', 
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          primary: primaryColor,
          surface: Colors.white,
        ),
      ),
      routes: {
        '/login': (context) => const LoginPage(),
        '/setup': (context) => const SetupPage(),
        '/activation': (context) => const ActivationPage(),
      },
      home: initialHome,
    );
  }
}
