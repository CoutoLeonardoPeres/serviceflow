import 'attachment_link_action_io.dart'
    if (dart.library.js_interop) 'attachment_link_action_web.dart' as impl;

Future<void> openAttachmentLink(String url) => impl.openAttachmentLink(url);

Future<void> downloadAttachmentLink(String url, String fileName) =>
    impl.downloadAttachmentLink(url, fileName);
