import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/quotations/domain/quotation.dart';

void main() {
  test('QuotationStatus fromValue e value sao simetricos', () {
    for (final status in QuotationStatus.values) {
      expect(QuotationStatus.fromValue(status.value), status);
    }
  });

  test('QuotationItem calcula total em centavos', () {
    final item = QuotationItem(
      id: '',
      quotationId: '',
      versionId: '',
      kind: QuotationItemKind.service,
      description: 'Instalacao',
      quantity: 2,
      unitPriceCents: 12500,
      unitCostCents: 8000,
      createdAt: DateTime(2026),
    );

    expect(item.totalCents, 25000);
    expect(item.marginCents, 9000);
  });

  test('Quotation toCreatePayload omite tenant_id e totais server-side', () {
    final quotation = Quotation(
      id: '',
      tenantId: '',
      number: 0,
      customerId: 'customer-1',
      requestId: 'request-1',
      status: QuotationStatus.draft,
      subtotalCents: 0,
      discountCents: 0,
      taxCents: 0,
      totalCents: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      validUntil: DateTime(2026, 8, 20),
      notes: 'Validar acesso',
    );

    final payload = quotation.toCreatePayload();

    expect(payload['customer_id'], 'customer-1');
    expect(payload['request_id'], 'request-1');
    expect(payload['tenant_id'], isNull);
    expect(payload['total_cents'], isNull);
  });

  test('QuotationPublicDecision fromValue e value sao simetricos', () {
    for (final decision in QuotationPublicDecision.values) {
      expect(QuotationPublicDecision.fromValue(decision.value), decision);
    }
  });
}
