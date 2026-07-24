import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/receipt.dart';

class ReceiptPdfResult {
  const ReceiptPdfResult({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}

class ReceiptPdfGenerator {
  ReceiptPdfGenerator._();

  static Future<ReceiptPdfResult> generate(Receipt receipt) async {
    final regularFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );
    final document = pw.Document(
      title: 'Recibo ${receipt.displayNumber}',
      author: 'ServiceFlow',
      creator: 'ServiceFlow',
    );
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final date = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
    final accent = PdfColor.fromHex('#6C63FF');
    final ink = PdfColor.fromHex('#2F3A46');
    final muted = PdfColor.fromHex('#6B7280');
    final panel = PdfColor.fromHex('#EEF3F8');

    document.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(
            base: regularFont,
            bold: boldFont,
          ),
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(22),
              decoration: pw.BoxDecoration(
                color: panel,
                borderRadius: pw.BorderRadius.circular(18),
                border: pw.Border.all(color: PdfColors.white, width: 1.4),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 44,
                    height: 44,
                    decoration: pw.BoxDecoration(
                      color: accent,
                      borderRadius: pw.BorderRadius.circular(12),
                    ),
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      'SF',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 14),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'ServiceFlow',
                          style: pw.TextStyle(
                            color: ink,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Recibo ${receipt.displayNumber}',
                          style: pw.TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: pw.BoxDecoration(
                      color: accent,
                      borderRadius: pw.BorderRadius.circular(12),
                    ),
                    child: pw.Text(
                      'PAGO',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 22),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(16),
                border: pw.Border.all(color: PdfColor.fromHex('#D7DFEA')),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Valor recebido',
                    style: pw.TextStyle(color: muted, fontSize: 10),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    currency.format(receipt.amountCents / 100),
                    style: pw.TextStyle(
                      color: ink,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 30,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _InfoBlock(
                    title: 'Cliente',
                    value: receipt.customerName ?? 'Cliente',
                    subtitle: receipt.receivableDescription,
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(
                  child: _InfoBlock(
                    title: 'Pagamento',
                    value: _paymentMethodLabel(receipt.paymentMethod),
                    subtitle: receipt.paymentReference == null
                        ? date.format(receipt.issuedAt)
                        : '${receipt.paymentReference} · ${date.format(receipt.issuedAt)}',
                  ),
                ),
              ],
            ),
            pw.Spacer(),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F7FAFD'),
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Text(
                'Documento gerado automaticamente pelo ServiceFlow para confirmação de recebimento manual.',
                style: pw.TextStyle(color: muted, fontSize: 9),
              ),
            ),
          ],
        ),
      ),
    );

    final bytes = await document.save();
    final number = receipt.number.toString().padLeft(5, '0');
    return ReceiptPdfResult(
      bytes: bytes,
      fileName: 'recibo-$number.pdf',
    );
  }

  static String _paymentMethodLabel(String? method) {
    return switch (method) {
      'cash' => 'Dinheiro',
      'pix_manual' => 'Pix manual',
      'transfer' => 'Transferência',
      'card_machine' => 'Máquina de cartão',
      'other' => 'Outro',
      _ => 'Pagamento manual',
    };
  }
}

class _InfoBlock extends pw.StatelessWidget {
  _InfoBlock({
    required this.title,
    required this.value,
    this.subtitle,
  });

  final String title;
  final String value;
  final String? subtitle;

  @override
  pw.Widget build(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F7FAFD'),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              color: PdfColor.fromHex('#6B7280'),
              fontSize: 9,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            value,
            style: pw.TextStyle(
              color: PdfColor.fromHex('#2F3A46'),
              fontWeight: pw.FontWeight.bold,
              fontSize: 12,
            ),
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              subtitle!,
              style: pw.TextStyle(
                color: PdfColor.fromHex('#6B7280'),
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
