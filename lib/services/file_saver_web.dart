import 'dart:convert';
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';

Future<void> saveOrShareBytesImpl(Uint8List bytes, String fileName) async {
  final b64 = base64Encode(bytes);
  final uri = Uri.parse('data:application/octet-stream;base64,$b64');
  await launchUrl(uri, mode: LaunchMode.platformDefault);
}

