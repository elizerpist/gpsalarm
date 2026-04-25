import 'dart:html' as html;

Future<bool> copyToClipboard(String text) async {
  final ta = html.TextAreaElement()
    ..value = text
    ..style.position = 'fixed'
    ..style.left = '-9999px'
    ..style.opacity = '0';
  html.document.body!.append(ta);
  ta.select();
  final ok = html.document.execCommand('copy');
  ta.remove();
  return ok;
}
