import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/features/quotations/application/quotation_list_notifier.dart';
import 'package:serviceflow/features/quotations/domain/quotation.dart';
import 'package:serviceflow/features/quotations/presentation/quotation_detail_screen.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
  });

  testWidgets('QuotationDetailScreen mostra acao para copiar link publico',
      (tester) async {
    final quote = Quotation(
      id: 'quote-1',
      tenantId: 'tenant-1',
      number: 7,
      customerId: 'customer-1',
      status: QuotationStatus.draft,
      subtotalCents: 100000,
      discountCents: 0,
      taxCents: 0,
      totalCents: 100000,
      createdAt: DateTime(2026, 7, 21),
      updatedAt: DateTime(2026, 7, 21),
      customerName: 'Cliente Teste',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quotationDetailProvider('quote-1').overrideWith((ref) async => quote),
          quotationAttachmentsProvider('quote-1')
              .overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const QuotationDetailScreen(quotationId: 'quote-1'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Copiar link público'), findsOneWidget);
    expect(find.text('Revogar link público'), findsOneWidget);
    expect(find.text('Gerar PDF'), findsOneWidget);
    expect(find.text('Arquivos do orçamento'), findsOneWidget);
  });

  testWidgets('QuotationDetailScreen mostra acao para gerar OS quando aprovado',
      (tester) async {
    final quote = Quotation(
      id: 'quote-1',
      tenantId: 'tenant-1',
      number: 7,
      customerId: 'customer-1',
      status: QuotationStatus.approved,
      subtotalCents: 100000,
      discountCents: 0,
      taxCents: 0,
      totalCents: 100000,
      createdAt: DateTime(2026, 7, 21),
      updatedAt: DateTime(2026, 7, 21),
      customerName: 'Cliente Teste',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quotationDetailProvider('quote-1').overrideWith((ref) async => quote),
          quotationAttachmentsProvider('quote-1')
              .overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const QuotationDetailScreen(quotationId: 'quote-1'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Gerar OS'), findsOneWidget);
  });
}
