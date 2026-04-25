import 'package:flutter/services.dart';

Future<bool> copyToClipboard(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  return true;
}
