import 'dart:async';
import 'dart:js_interop';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart';

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
  final completer = Completer<List<PlatformFile>?>();
  final input = HTMLInputElement()
    ..type = 'file'
    ..multiple = allowMultiple
    ..style.display = 'none'
    ..accept = allowDocuments
        ? [..._photoExtensions, ..._documentExtensions]
            .map((ext) => '.$ext')
            .join(',')
        : 'image/*';

  bool completed = false;

  Future<void> finish(List<PlatformFile>? files) async {
    if (completed) return;
    completed = true;
    input.remove();
    completer.complete(files);
  }

  input.onChange.listen((_) async {
    final files = input.files;
    if (files == null || files.length == 0) {
      await finish(null);
      return;
    }

    final picked = <PlatformFile>[];
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null) continue;
      final reader = FileReader();
      final fileCompleter = Completer<void>();
      reader.onLoadEnd.listen((_) {
        final buffer = (reader.result as JSArrayBuffer?)?.toDart;
        picked.add(
          PlatformFile(
            name: file.name,
            size: file.size,
            bytes: buffer?.asUint8List(),
          ),
        );
        fileCompleter.complete();
      });
      reader.readAsArrayBuffer(file);
      await fileCompleter.future;
    }

    await finish(picked.isEmpty ? null : picked);
  });

  window.addEventListener(
    'focus',
    ((Event _) {
      Future<void>.delayed(const Duration(milliseconds: 500)).then((_) {
        if (!completed) {
          finish(null);
        }
      });
    }).toJS,
    AddEventListenerOptions()..once = true,
  );

  document.body?.append(input);
  input.click();

  return completer.future;
}
