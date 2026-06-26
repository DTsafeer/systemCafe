import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart'; // هذا السطر سيصبح سليماً بعد pub get
import 'package:flutter/foundation.dart';

class DeviceUtils {
  static Future<String> getDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    // .
    try {
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        // تعريف فريد للمتصفح
        return '${webInfo.vendor}${webInfo.userAgent}${webInfo.hardwareConcurrency}';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id; 
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'unknown_ios';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        return windowsInfo.deviceId;
      } else if (Platform.isMacOS) {
        final macOsInfo = await deviceInfo.macOsInfo;
        return macOsInfo.systemGUID ?? 'unknown_mac';
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        return linuxInfo.machineId ?? 'unknown_linux';
      }
    } catch (e) {
      debugPrint("Error getting device ID: $e");
    }
    
    return 'unknown_device';
  }
}
