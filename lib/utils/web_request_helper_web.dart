import 'dart:html' as html;

Future<void> sendFireAndForgetImageRequest(String url) async {
  final img = html.ImageElement();
  img.src = url;
}
