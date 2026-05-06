import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart'; // ✅ استيراد المكتبة الأساسية
import 'firebase_options.dart'; // ✅ تأكد من وجود هذا الملف في مجلد lib

// استيراد الصفحات الخاصة بك
import 'pages/ActivationPage.dart';
import 'pages/LoginPage.dart';

Future<void> main() async {
  // ✅ 1. التأكد من تهيئة روابط فلاتر
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 2. تهيئة Firebase بشكل آمن وقاطع
  try {
    // نتحقق أولاً إذا كان هناك تطبيق مهيأ مسبقاً لتجنب خطأ التكرار
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint("✅ Firebase Initialized Successfully");
    }
  } catch (e) {
    debugPrint('❌ Firebase Initialization Error: $e');
  }

  // ✅ 3. تهيئة الإعدادات الأخرى
  final prefs = await SharedPreferences.getInstance();
  await initializeDateFormatting('ar', null);

  bool isActivated = prefs.getString('cafe_id') != null;
  bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

  runApp(MyApp(
    isActivated: isActivated,
    isLoggedIn: isLoggedIn,
  ));
}


class MyApp extends StatefulWidget {
  final bool isActivated;
  final bool isLoggedIn;

  const MyApp({super.key, required this.isActivated, required this.isLoggedIn});

  static void updateTheme(BuildContext context) {
    _MyAppState? state = context.findAncestorStateOfType<_MyAppState>();
    if (state != null) {
      state.loadSettings();
    }
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Color primaryColor = Colors.brown;
  bool isDarkMode = false;
  double fontScale = 1.0;
  bool isActivatedUI = false;

  @override
  void initState() {
    super.initState();
    isActivatedUI = widget.isActivated;
    loadSettings();
  }

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (mounted) {
        setState(() {
          isActivatedUI = prefs.getString('cafe_id') != null;
          int colorValue = prefs.getInt('primaryColor') ?? Colors.brown.value;
          primaryColor = Color(colorValue);
          isDarkMode = prefs.getBool('isDarkMode') ?? false;

          String fontSizeKey = prefs.getString('global_font_size') ?? "medium";
          switch (fontSizeKey) {
            case 'small':
              fontScale = 0.85;
              break;
            case 'large':
              fontScale = 1.25;
              break;
            default:
              fontScale = 1.0;
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Flora Cafe',
        themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: primaryColor,
            primary: primaryColor,
            brightness: Brightness.light,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: primaryColor,
            primary: primaryColor,
            brightness: Brightness.dark,
          ),
        ),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              // ignore: deprecated_member_use
              textScaleFactor: fontScale,
            ),
            child: child!,
          );
        },
        home: const LoginPage()
    );
  }
}