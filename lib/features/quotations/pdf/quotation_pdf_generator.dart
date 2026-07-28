import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/quotation.dart';

class QuotationPdfResult {
  const QuotationPdfResult({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}

class QuotationPdfGenerator {
  QuotationPdfGenerator._();

  /// [items] vem separado porque `Quotation` não carrega as linhas — sem
  /// passá-las, o PDF saía só com os totais.
  static Future<QuotationPdfResult> generate(
    Quotation quote, {
    List<QuotationItem> items = const [],
  }) async {
    final regularFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );
    final document = pw.Document(
      title: 'Orçamento ${quote.displayNumber}',
      author: 'ServiceFlow',
      creator: 'ServiceFlow',
    );
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final date = DateFormat('dd/MM/yyyy', 'pt_BR');
    final accent = PdfColor.fromHex('#6C63FF');
    final ink = PdfColor.fromHex('#2F3A46');
    final muted = PdfColor.fromHex('#6B7280');
    final panel = PdfColor.fromHex('#EEF3F8');

    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(
            base: regularFont,
            bold: boldFont,
          ),
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'ServiceFlow',
              style: pw.TextStyle(color: muted, fontSize: 9),
            ),
            pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: pw.TextStyle(color: muted, fontSize: 9),
            ),
          ],
        ),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(22),
            decoration: pw.BoxDecoration(
              color: panel,
              borderRadius: pw.BorderRadius.circular(18),
              border: pw.Border.all(color: PdfColors.white, width: 1.4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
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
                            'Orçamento ${quote.displayNumber}',
                            style: pw.TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    _StatusPill(label: quote.status.label, color: accent),
                  ],
                ),
                pw.SizedBox(height: 24),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: _InfoBlock(
                        title: 'Cliente',
                        value: quote.customerName ?? 'Cliente',
                        subtitle: quote.requestTitle,
                      ),
                    ),
                    pw.SizedBox(width: 14),
                    pw.Expanded(
                      child: _InfoBlock(
                        title: 'Emissão',
                        value: date.format(quote.createdAt),
                        subtitle: quote.validUntil == null
                            ? null
                            : 'Validade: ${date.format(quote.validUntil!)}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 22),
          pw.Text(
            'Itens do orçamento',
            style: pw.TextStyle(
              color: ink,
              fontWeight: pw.FontWeight.bold,
              fontSize: 16,
            ),
          ),
          pw.SizedBox(height: 10),
          if (items.isEmpty)
            pw.Text(
              'Nenhum item detalhado neste orçamento.',
              style: pw.TextStyle(color: muted, fontSize: 11),
            )
          else
            ..._itemGroups(items, currency, ink, muted, accent),
          pw.SizedBox(height: 22),
          pw.Text(
            'Resumo financeiro',
            style: pw.TextStyle(
              color: ink,
              fontWeight: pw.FontWeight.bold,
              fontSize: 16,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColor.fromHex('#D7DFEA')),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(1),
            },
            children: [
              _MoneyRow('Subtotal', currency.format(quote.subtotalCents / 100)),
              _MoneyRow('Impostos', currency.format(quote.taxCents / 100)),
              _MoneyRow(
                'Descontos',
                currency.format(quote.discountCents / 100),
              ),
              _MoneyRow(
                'Total',
                currency.format(quote.totalCents / 100),
                highlight: true,
              ),
            ],
          ),
          if ((quote.notes ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(height: 22),
            pw.Text(
              'Observações',
              style: pw.TextStyle(
                color: ink,
                fontWeight: pw.FontWeight.bold,
                fontSize: 16,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F7FAFD'),
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: PdfColor.fromHex('#D7DFEA')),
              ),
              child: pw.Text(
                quote.notes!.trim(),
                style: pw.TextStyle(color: ink, fontSize: 11, lineSpacing: 3),
              ),
            ),
          ],
          pw.SizedBox(height: 28),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F7FAFD'),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Text(
              'Documento gerado automaticamente pelo ServiceFlow. Valores em reais e sujeitos às condições informadas no orçamento.',
              style: pw.TextStyle(color: muted, fontSize: 9),
            ),
          ),
        ],
      ),
    );

    final bytes = await document.save();
    final number = quote.number.toString().padLeft(5, '0');
    return QuotationPdfResult(
      bytes: bytes,
      fileName: 'orcamento-$number.pdf',
    );
  }
}

class _StatusPill extends pw.StatelessWidget {
  _StatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final PdfColor color;

  @override
  pw.Widget build(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 9,
        ),
      ),
    );
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
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
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
          if (subtitle != null) ...[
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

/// Agrupa as linhas pela natureza do custo — mesma divisão dos cards do
/// formulário: serviços, materiais, despesas e impostos.
const _pdfGroups = <(String, List<QuotationItemKind>)>[
  (
    'Serviços e horas técnicas',
    [QuotationItemKind.service, QuotationItemKind.laborHour],
  ),
  (
    'Materiais e equipamentos',
    [QuotationItemKind.material, QuotationItemKind.equipment],
  ),
  ('Despesas', [QuotationItemKind.travel, QuotationItemKind.other]),
  ('Impostos', [QuotationItemKind.tax]),
  ('Descontos', [QuotationItemKind.discount]),
];

List<pw.Widget> _itemGroups(
  List<QuotationItem> items,
  NumberFormat currency,
  PdfColor ink,
  PdfColor muted,
  PdfColor accent,
) {
  final widgets = <pw.Widget>[];

  for (final (title, kinds) in _pdfGroups) {
    final group = items.where((item) => kinds.contains(item.kind)).toList();
    if (group.isEmpty) continue;

    final subtotal =
        group.fold<int>(0, (sum, item) => sum + item.totalCents);

    widgets.addAll([
      pw.SizedBox(height: 10),
      pw.Text(
        title,
        style: pw.TextStyle(
          color: accent,
          fontWeight: pw.FontWeight.bold,
          fontSize: 12,
        ),
      ),
      pw.SizedBox(height: 6),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColor.fromHex('#D7DFEA')),
        columnWidths: const {
          0: pw.FlexColumnWidth(5),
          1: pw.FlexColumnWidth(1),
          2: pw.FlexColumnWidth(1.6),
          3: pw.FlexColumnWidth(1.8),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColor.fromHex('#EEF3F8')),
            children: [
              _cell('Descrição', ink, bold: true),
              _cell('Qtd', ink, bold: true, align: pw.TextAlign.right),
              _cell('Unitário', ink, bold: true, align: pw.TextAlign.right),
              _cell('Total', ink, bold: true, align: pw.TextAlign.right),
            ],
          ),
          ...group.map(
            (item) => pw.TableRow(
              children: [
                _cell(item.description, ink),
                _cell(
                  _formatQuantity(item.quantity),
                  ink,
                  align: pw.TextAlign.right,
                ),
                _cell(
                  currency.format(item.unitPriceCents / 100),
                  ink,
                  align: pw.TextAlign.right,
                ),
                _cell(
                  currency.format(item.totalCents / 100),
                  ink,
                  align: pw.TextAlign.right,
                ),
              ],
            ),
          ),
          pw.TableRow(
            children: [
              _cell('Subtotal', muted, align: pw.TextAlign.right),
              _cell('', muted),
              _cell('', muted),
              _cell(
                currency.format(subtotal / 100),
                ink,
                bold: true,
                align: pw.TextAlign.right,
              ),
            ],
          ),
        ],
      ),
    ]);
  }

  return widgets;
}

pw.Widget _cell(
  String text,
  PdfColor color, {
  bool bold = false,
  pw.TextAlign align = pw.TextAlign.left,
}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );

/// 2 vira "2"; 2.5 vira "2,5" — quantidade fracionada existe em hora técnica.
String _formatQuantity(num quantity) {
  if (quantity == quantity.roundToDouble()) return quantity.round().toString();
  return quantity.toString().replaceAll('.', ',');
}

class _MoneyRow extends pw.TableRow {
  _MoneyRow(String label, String value, {bool highlight = false})
      : super(
          decoration: pw.BoxDecoration(
            color: highlight ? PdfColor.fromHex('#EEF3F8') : PdfColors.white,
          ),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(10),
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  color: PdfColor.fromHex('#2F3A46'),
                  fontWeight:
                      highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(10),
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  value,
                  style: pw.TextStyle(
                    color: PdfColor.fromHex('#2F3A46'),
                    fontWeight:
                        highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        );
}
