import 'package:url_launcher/url_launcher.dart';

Future<void> openAttachmentLink(String url) async {
  await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
}

Future<void> downloadAttachmentLink(String url, String fileName) async {
  await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
}
