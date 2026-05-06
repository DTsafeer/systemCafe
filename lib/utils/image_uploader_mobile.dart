import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'image_uploader.dart';

ImageUploader getImageUploader() => _MobileUploader();

class _MobileUploader implements ImageUploader {
  @override
  Future<String> uploadImage(
      dynamic image, String cloudName, String uploadPreset) async {
    final file = image as File;

    final uri =
    Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();
    if (response.statusCode == 200) {
      final data = json.decode(await response.stream.bytesToString());
      return data['secure_url'];
    } else {
      throw Exception('Upload failed');
    }
  }
}
