import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:serviceflow/features/quotations/domain/quotation.dart';
import 'package:serviceflow/features/quotations/pdf/quotation_pdf_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
  });

  test('QuotationPdfGenerator gera bytes PDF e nome de arquivo', () async {
    final quote = Quotation(
      id: 'quote-1',
      tenantId: 'tenant-1',
      number: 42,
      customerId: 'customer-1',
      status: QuotationStatus.sent,
      subtotalCents: 150000,
      discountCents: 10000,
      taxCents: 0,
      totalCents: 140000,
      createdAt: DateTime(2026, 7, 21),
      updatedAt: DateTime(2026, 7, 21),
      validUntil: DateTime(2026, 8, 5),
      notes: 'Instalação com garantia técnica.',
      customerName: 'Cliente Teste',
      requestTitle: 'Instalação elétrica',
    );

    final result = await QuotationPdfGenerator.generate(quote);
    final header = ascii.decode(result.bytes.take(4).toList());

    expect(header, '%PDF');
    expect(result.bytes.length, greaterThan(1000));
    expect(result.fileName, 'orcamento-00042.pdf');
  });
}
