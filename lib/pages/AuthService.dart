import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/device_info.dart';
import 'user_model.dart';
import 'activity_logger.dart';

class AuthService {
  static Future<User?> checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('isLoggedIn') == true) {
      final String? userId = prefs.getString('user_id');
      if (userId != null) {
        final user = await fetchUserById(userId);
        if (user != null) {
          if (user.role != UserRole.super_admin) {
            try {
              await _checkCafeStatus(user.cafeId);
              return user;
            } catch (e) {
              await logout();
              return null;
            }
          }
          return user;
        }
      }
    }
    return null;
  }

  static Future<User?> fetchUserById(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final user = User.fromMap(userDoc.data()!, userDoc.id);
        String currentDeviceId = await DeviceUtils.getDeviceId();
        
        if (user.deviceId != null && user.deviceId != currentDeviceId) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.clear();
          return null; 
        }
        return user.isActive ? user : null;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  static Future<User> login(String username, String password) async {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(username).get();

    if (!userDoc.exists) throw 'اسم المستخدم غير موجود';

    final userData = userDoc.data()!;
    if (userData['password'] != password) throw 'كلمة المرور غير صحيحة';
    
    final user = User.fromMap(userData, userDoc.id);
    if (!user.isActive) throw 'الحساب معطل من قبل الإدارة';

    if (user.role != UserRole.super_admin) {
      await _checkCafeStatus(user.cafeId);
    }

    String currentDeviceId = await DeviceUtils.getDeviceId();
    
    if (user.deviceId != null && user.deviceId != currentDeviceId) {
      throw 'DEVICE_MISMATCH';
    }

    if (user.deviceId == null) {
      await FirebaseFirestore.instance.collection('users').doc(username).update({'deviceId': currentDeviceId});
    }

    // تسجيل نشاط الدخول
    await ActivityLogger.log(
      cafeId: user.cafeId,
      parentId: user.parentId ?? user.id,
      userId: user.id,
      userName: user.name,
      action: "دخول للنظام",
      details: "قام الموظف بتسجيل الدخول بنجاح",
    );
    
    return user;
  }

  static Future<void> _checkCafeStatus(String cafeId) async {
    if (cafeId.isEmpty) return;
    
    final cafeDoc = await FirebaseFirestore.instance.collection('cafes').doc(cafeId).get();
    if (!cafeDoc.exists) throw 'بيانات المنشأة غير موجودة';
    
    final data = cafeDoc.data()!;
    
    if (data['isActive'] == false) {
      throw data['blockReason'] ?? 'تم إيقاف العمل في هذه المنشأة يدوياً';
    }
    
    if (data['expiryDate'] != null) {
      DateTime expiry = (data['expiryDate'] as Timestamp).toDate();
      if (DateTime.now().isAfter(expiry)) {
        throw 'انتهت مدة اشتراك المنشأة، يرجى التواصل مع الإدارة';
      }
    }
    
    if (data['scheduledStopDate'] != null) {
      DateTime stopDate = (data['scheduledStopDate'] as Timestamp).toDate();
      if (DateTime.now().isAfter(stopDate)) {
        await FirebaseFirestore.instance.collection('cafes').doc(cafeId).update({
          'isActive': false,
          'blockReason': 'انتهت فترة العمل المجدولة تلقائياً',
          'scheduledStopDate': null 
        });
        throw 'انتهت فترة العمل المجدولة تلقائياً';
      }
    }
  }

  static Future<void> saveSession(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', user.id);
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('cafe_id', user.cafeId);
  }

  static Future<void> logout({User? currentUser}) async {
    if (currentUser != null) {
      await ActivityLogger.log(
        cafeId: currentUser.cafeId,
        parentId: currentUser.parentId ?? currentUser.id,
        userId: currentUser.id,
        userName: currentUser.name,
        action: "خروج من النظام",
        details: "قام الموظف بتسجيل الخروج يدوياً",
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
