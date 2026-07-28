import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/features/customers/application/customer_list_notifier.dart';
import 'package:serviceflow/features/customers/domain/customer.dart';
import 'package:serviceflow/features/quotations/application/quotation_list_notifier.dart';
import 'package:serviceflow/features/quotations/domain/quotation.dart';
import 'package:serviceflow/features/quotations/domain/quotation_version.dart';
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
          quotationVersionsProvider('quote-1')
              .overrideWith((ref) async => const []),
          quotationStatusHistoryProvider('quote-1')
              .overrideWith((ref) async => const []),
          customerDetailProvider('customer-1').overrideWith((ref) async =>
              Customer(
                id: 'customer-1',
                tenantId: 'tenant-1',
                type: CustomerType.company,
                name: 'Cliente Teste',
                isActive: true,
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
              )),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const QuotationDetailScreen(quotationId: 'quote-1'),
        ),
      ),
    );
    await tester.pump();

    // Uma ação primária conforme o status; link e revogação foram para o
    // menu. Antes eram três FilledButton competindo entre si na mesma barra.
    expect(find.text('Gerar PDF'), findsWidgets);
    expect(find.text('Arquivos do orçamento'), findsOneWidget);
    expect(find.text('Mais ações'), findsOneWidget);

    await tester.tap(find.text('Mais ações'));
    await tester.pumpAndSettle();
    expect(find.text('Copiar link público'), findsOneWidget);
    expect(find.text('Revogar link público'), findsOneWidget);
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
          quotationVersionsProvider('quote-1')
              .overrideWith((ref) async => const []),
          quotationStatusHistoryProvider('quote-1')
              .overrideWith((ref) async => const []),
          customerDetailProvider('customer-1').overrideWith((ref) async =>
              Customer(
                id: 'customer-1',
                tenantId: 'tenant-1',
                type: CustomerType.company,
                name: 'Cliente Teste',
                isActive: true,
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
              )),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const QuotationDetailScreen(quotationId: 'quote-1'),
        ),
      ),
    );
    await tester.pump();

    // A OS já nasce com a aprovação (trigger da 0056); a ação aqui é abrir a
    // que existe, não criar uma segunda.
    expect(find.text('Abrir OS'), findsOneWidget);
  });

  // ── F2-P1: novos comportamentos ──────────────────────────────────────────

  Customer makeCustomer() => Customer(
        id: 'customer-1',
        tenantId: 'tenant-1',
        type: CustomerType.company,
        name: 'Cliente Teste',
        isActive: true,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

  List<Override> baseOverrides(Quotation q) => [
        quotationDetailProvider(q.id).overrideWith((ref) async => q),
        quotationAttachmentsProvider(q.id)
            .overrideWith((ref) async => const []),
        quotationVersionsProvider(q.id).overrideWith((ref) async => const []),
        quotationStatusHistoryProvider(q.id)
            .overrideWith((ref) async => const []),
        customerDetailProvider('customer-1')
            .overrideWith((ref) async => makeCustomer()),
      ];

  testWidgets(
      'QuotationDetailScreen mostra botão Cancelar orçamento para status rascunho',
      (tester) async {
    final q = Quotation(
      id: 'q-draft',
      tenantId: 'tenant-1',
      number: 10,
      customerId: 'customer-1',
      status: QuotationStatus.draft,
      subtotalCents: 50000,
      discountCents: 0,
      taxCents: 0,
      totalCents: 50000,
      createdAt: DateTime(2026, 7, 25),
      updatedAt: DateTime(2026, 7, 25),
      customerName: 'Cliente Teste',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: baseOverrides(q),
      child: MaterialApp(
          theme: AppTheme.light,
          home: QuotationDetailScreen(quotationId: q.id)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mais ações'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelar orçamento'), findsOneWidget);
  });

  testWidgets(
      'QuotationDetailScreen não mostra botão Cancelar para orçamento aprovado',
      (tester) async {
    final q = Quotation(
      id: 'q-approved',
      tenantId: 'tenant-1',
      number: 11,
      customerId: 'customer-1',
      status: QuotationStatus.approved,
      subtotalCents: 80000,
      discountCents: 0,
      taxCents: 0,
      totalCents: 80000,
      createdAt: DateTime(2026, 7, 25),
      updatedAt: DateTime(2026, 7, 25),
      customerName: 'Cliente Teste',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: baseOverrides(q),
      child: MaterialApp(
          theme: AppTheme.light,
          home: QuotationDetailScreen(quotationId: q.id)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mais ações'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelar orçamento'), findsNothing);
  });

  testWidgets(
      'QuotationDetailScreen não mostra botão Cancelar para orçamento cancelado',
      (tester) async {
    final q = Quotation(
      id: 'q-cancelled',
      tenantId: 'tenant-1',
      number: 12,
      customerId: 'customer-1',
      status: QuotationStatus.cancelled,
      subtotalCents: 30000,
      discountCents: 0,
      taxCents: 0,
      totalCents: 30000,
      createdAt: DateTime(2026, 7, 25),
      updatedAt: DateTime(2026, 7, 25),
      customerName: 'Cliente Teste',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: baseOverrides(q),
      child: MaterialApp(
          theme: AppTheme.light,
          home: QuotationDetailScreen(quotationId: q.id)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mais ações'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelar orçamento'), findsNothing);
  });

  testWidgets('QuotationDetailScreen exibe painel de versões com dados',
      (tester) async {
    final q = Quotation(
      id: 'q-versions',
      tenantId: 'tenant-1',
      number: 13,
      customerId: 'customer-1',
      status: QuotationStatus.sent,
      subtotalCents: 120000,
      discountCents: 0,
      taxCents: 0,
      totalCents: 120000,
      createdAt: DateTime(2026, 7, 25),
      updatedAt: DateTime(2026, 7, 25),
      customerName: 'Cliente Teste',
    );

    final versions = [
      QuotationVersion(
        id: 'v1',
        versionNumber: 1,
        totalCents: 100000,
        subtotalCents: 100000,
        discountCents: 0,
        taxCents: 0,
        isCurrent: false,
        createdAt: DateTime(2026, 7, 24),
      ),
      QuotationVersion(
        id: 'v2',
        versionNumber: 2,
        totalCents: 120000,
        subtotalCents: 120000,
        discountCents: 0,
        taxCents: 0,
        isCurrent: true,
        createdAt: DateTime(2026, 7, 25),
      ),
    ];

    final overrides = [
      quotationDetailProvider(q.id).overrideWith((ref) async => q),
      quotationAttachmentsProvider(q.id)
          .overrideWith((ref) async => const []),
      quotationVersionsProvider(q.id).overrideWith((ref) async => versions),
      quotationStatusHistoryProvider(q.id)
          .overrideWith((ref) async => const []),
      customerDetailProvider('customer-1')
          .overrideWith((ref) async => makeCustomer()),
    ];

    // Viewport alto: o painel de versões fica abaixo da dobra em um ListView lazy.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp(
          theme: AppTheme.light,
          home: QuotationDetailScreen(quotationId: q.id)),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Versões do orçamento'),
      300,
    );
    await tester.pumpAndSettle();

    expect(find.text('Versões do orçamento'), findsOneWidget);
    expect(find.text('Versão 1'), findsOneWidget);
    expect(find.text('Versão 2 (atual)'), findsOneWidget);
  });
}
