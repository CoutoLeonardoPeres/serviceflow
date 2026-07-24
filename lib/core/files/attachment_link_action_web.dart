import 'package:web/web.dart';

Future<void> openAttachmentLink(String url) async {
  window.open(url, '_blank');
}

Future<void> downloadAttachmentLink(String url, String fileName) async {
  final anchor = document.createElement('a') as HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
