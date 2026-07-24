import 'package:file_picker/file_picker.dart';

import 'attachment_picker_io.dart'
    if (dart.library.js_interop) 'attachment_picker_web.dart' as impl;

Future<List<PlatformFile>?> pickAttachments({
  required bool allowDocuments,
  bool allowMultiple = true,
}) {
  return impl.pickAttachments(
    allowDocuments: allowDocuments,
    allowMultiple: allowMultiple,
  );
}
