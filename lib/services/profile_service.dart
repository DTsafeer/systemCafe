import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class ProfileService {
  static const String _cloudName = "dbjnnbhaw";
  static const String _uploadPreset = "floracafe";

  static Future<String?> uploadImage(XFile image) async {
    try {
      final url = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
      var request = http.MultipartRequest('POST', url)..fields['upload_preset'] = _uploadPreset;
      final bytes = await image.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: image.name));
      
      var response = await http.Response.fromStream(await request.send());
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['secure_url'];
      }
    } catch (e) {
      print("Upload Error: $e");
    }
    return null;
  }

  static Future<void> updateProfileField(String userId, String field, dynamic value) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).update({field: value});
  }
}
