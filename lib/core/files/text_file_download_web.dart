// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

/// Baixa um arquivo de texto gerado pelo app.
///
/// CSV sai com BOM UTF-8 (EF BB BF). Sem ele, o Excel abre o arquivo na
/// codificação local do sistema e "Material elétrico" vira "Material
/// el√©trico" — foi o que corrompeu o modelo de preços. O BOM é a única
/// forma de o Excel reconhecer UTF-8 num CSV; LibreOffice, Google Sheets e
/// Numbers também o respeitam.
Future<void> downloadTextFile({
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  final isCsv = mimeType.contains('csv') || fileName.endsWith('.csv');
  final payload = isCsv ? '﻿$content' : content;

  final href = Uri.dataFromString(
    payload,
    mimeType: mimeType,
    encoding: utf8,
  ).toString();

  html.AnchorElement(href: href)
    ..setAttribute('download', fileName)
    ..click();
}
