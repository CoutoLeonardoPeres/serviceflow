import 'package:file_picker/file_picker.dart';

const _photoExtensions = ['jpg', 'jpeg', 'png', 'webp'];
const _documentExtensions = [
  'mp4',
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'csv',
  'txt',
];

Future<List<PlatformFile>?> pickAttachments({
  required bool allowDocuments,
  bool allowMultiple = true,
}) async {
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: allowMultiple,
    withData: true,
    type: allowDocuments ? FileType.custom : FileType.image,
    allowedExtensions:
        allowDocuments ? [..._photoExtensions, ..._documentExtensions] : null,
  );
  if (result == null || result.files.isEmpty) return null;
  return result.files;
}
