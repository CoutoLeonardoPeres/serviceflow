import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:serviceflow/features/financials/domain/receipt.dart';
import 'package:serviceflow/features/financials/pdf/receipt_pdf_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
  });

  test('ReceiptPdfGenerator gera bytes PDF e nome de arquivo', () async {
    final receipt = Receipt(
      id: 'receipt-1',
      tenantId: 'tenant-1',
      number: 23,
      receivableId: 'rec-1',
      paymentId: 'pay-1',
      customerId: 'customer-1',
      amountCents: 150000,
      issuedAt: DateTime(2026, 7, 22, 14, 30),
      customerName: 'Cliente Teste',
      receivableDescription: 'OS #00012 - Troca de compressor',
      paymentMethod: 'pix_manual',
      paymentReference: 'PIX-123',
    );

    final result = await ReceiptPdfGenerator.generate(receipt);
    final header = ascii.decode(result.bytes.take(4).toList());

    expect(header, '%PDF');
    expect(result.bytes.length, greaterThan(1000));
    expect(result.fileName, 'recibo-00023.pdf');
  });
}
