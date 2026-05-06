// واجهة مشتركة
abstract class ImageUploader {
  Future<String> uploadImage(
      dynamic image,
      String cloudName,
      String uploadPreset,
      );
}
