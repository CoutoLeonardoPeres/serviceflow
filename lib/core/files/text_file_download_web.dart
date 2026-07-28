// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

Future<void> downloadTextFile({
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  final href = Uri.dataFromString(
    content,
    mimeType: mimeType,
    encoding: utf8,
  ).toString();

  html.AnchorElement(href: href)
    ..setAttribute('download', fileName)
    ..click();
}
