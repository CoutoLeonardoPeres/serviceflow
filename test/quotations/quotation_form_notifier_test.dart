import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/error/app_error.dart';
import 'package:serviceflow/features/quotations/application/quotation_form_notifier.dart';
import 'package:serviceflow/features/quotations/application/quotation_list_notifier.dart';
import 'package:serviceflow/features/quotations/data/quotation_repository.dart';
import 'package:serviceflow/features/quotations/domain/quotation.dart';

void main() {
  test('QuotationFormNotifier comeca em idle', () {
    final container = ProviderContainer(overrides: [
      quotationRepositoryProvider.overrideWithValue(_FakeQuotationRepository()),
    ]);
    addTearDown(container.dispose);

    expect(container.read(quotationFormProvider), isA<QuotationFormIdle>());
  });

  test('cria orcamento com itens e estado de sucesso', () async {
    final repo = _FakeQuotationRepository();
    final container = ProviderContainer(overrides: [
      quotationRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    await container.read(quotationFormProvider.notifier).createQuotation(
      customerId: 'customer-1',
      requestId: 'request-1',
      validUntil: DateTime(2026, 8, 20),
      notes: 'Termos',
      items: const [
        QuotationDraftItem(
          kind: QuotationItemKind.service,
          description: 'Instalacao',
          quantity: 1,
          unitPriceCents: 20000,
          unitCostCents: 12000,
        ),
      ],
    );

    final state = container.read(quotationFormProvider);
    expect(state, isA<QuotationFormSuccess>());
    expect((state as QuotationFormSuccess).quotation.totalCents, 20000);
    expect(repo.createdItems.single.description, 'Instalacao');
  });

  test('erro de regra vira estado de erro', () async {
    final repo = _FakeQuotationRepository(
      error: const BusinessRuleError('Inclua ao menos um item.'),
    );
    final container = ProviderContainer(overrides: [
      quotationRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    await container.read(quotationFormProvider.notifier).createQuotation(
      customerId: 'customer-1',
      validUntil: DateTime(2026, 8, 20),
      items: const [],
    );

    expect(container.read(quotationFormProvider), isA<QuotationFormError>());
  });
}

class _FakeQuotationRepository extends QuotationRepository {
  _FakeQuotationRepository({this.error}) : super(null);

  final AppError? error;
  List<QuotationDraftItem> createdItems = const [];

  @override
  Future<Quotation> create({
    required Quotation quotation,
    required List<QuotationDraftItem> items,
  }) async {
    final error = this.error;
    if (error != null) throw error;
    createdItems = items;
    return quotation.copyWith(
      id: 'quote-1',
      number: 1,
      totalCents: items.fold<int>(0, (sum, item) => sum + item.totalCents),
    );
  }
}
