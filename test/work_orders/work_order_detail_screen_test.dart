import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/features/customers/application/customer_list_notifier.dart';
import 'package:serviceflow/features/customers/domain/customer.dart';
import 'package:serviceflow/features/work_orders/application/work_order_list_notifier.dart';
import 'package:serviceflow/features/work_orders/domain/work_order.dart';
import 'package:serviceflow/features/work_orders/domain/work_order_event.dart';
import 'package:serviceflow/features/work_orders/presentation/work_order_detail_screen.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
  });

  testWidgets('WorkOrderDetailScreen mostra acoes de horas e materiais',
      (tester) async {
    final workOrder = WorkOrder(
      id: 'wo-1',
      tenantId: 'tenant-1',
      number: 12,
      customerId: 'customer-1',
      status: WorkOrderStatus.inProgress,
      title: 'Troca de compressor',
      description: 'Executar substituicao do compressor.',
      totalCents: 250000,
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 22),
      customerName: 'Cliente Teste',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workOrderDetailProvider('wo-1')
              .overrideWith((ref) async => workOrder),
          workOrderEvidenceProvider('wo-1')
              .overrideWith((ref) async => const []),
          workOrderItemsProvider('wo-1').overrideWith((ref) async => const []),
          workOrderSatisfactionProvider('wo-1')
              .overrideWith((ref) async => null),
          workOrderEventsProvider('wo-1')
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
          home: const WorkOrderDetailScreen(workOrderId: 'wo-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A barra deriva do status (0057). Em execução: uma ação primária
    // (Concluir OS) e as ações de campo ao lado.
    expect(find.text('Concluir OS'), findsOneWidget);
    expect(find.text('Registrar horas'), findsOneWidget);
    expect(find.text('Adicionar material'), findsOneWidget);
    expect(find.text('Anexar foto/evidência'), findsOneWidget);
    expect(find.text('Mais ações'), findsOneWidget);

    // Cobrança e satisfação pertencem à OS concluída — não aparecem aqui nem
    // desabilitadas. Era o defeito P0: "Gerar cobrança" sólido numa OS que
    // ainda não terminou.
    expect(find.text('Gerar cobrança'), findsNothing);
    expect(find.text('Registrar satisfação'), findsNothing);

    // Despesa e aceite existem, mas no menu.
    await tester.tap(find.text('Mais ações'));
    await tester.pumpAndSettle();
    expect(find.text('Registrar despesa'), findsOneWidget);
    expect(find.text('Registrar aceite'), findsOneWidget);
    expect(find.text('Cancelar OS'), findsOneWidget);
  });

  testWidgets('WorkOrderDetailScreen abre popup de horas', (tester) async {
    final workOrder = WorkOrder(
      id: 'wo-1',
      tenantId: 'tenant-1',
      number: 12,
      customerId: 'customer-1',
      status: WorkOrderStatus.inProgress,
      title: 'Troca de compressor',
      description: 'Executar substituicao do compressor.',
      totalCents: 250000,
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 22),
      customerName: 'Cliente Teste',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workOrderDetailProvider('wo-1')
              .overrideWith((ref) async => workOrder),
          workOrderEvidenceProvider('wo-1')
              .overrideWith((ref) async => const []),
          workOrderItemsProvider('wo-1').overrideWith((ref) async => const []),
          workOrderSatisfactionProvider('wo-1')
              .overrideWith((ref) async => null),
          workOrderEventsProvider('wo-1')
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
          home: const WorkOrderDetailScreen(workOrderId: 'wo-1'),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Registrar horas'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Horas trabalhadas'), findsWidgets);
  });

  testWidgets('WorkOrderDetailScreen abre popup de aceite', (tester) async {
    final workOrder = WorkOrder(
      id: 'wo-1',
      tenantId: 'tenant-1',
      number: 12,
      customerId: 'customer-1',
      status: WorkOrderStatus.done,
      title: 'Troca de compressor',
      description: 'Executar substituicao do compressor.',
      totalCents: 250000,
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 22),
      customerName: 'Cliente Teste',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workOrderDetailProvider('wo-1')
              .overrideWith((ref) async => workOrder),
          workOrderEvidenceProvider('wo-1')
              .overrideWith((ref) async => const []),
          workOrderItemsProvider('wo-1').overrideWith((ref) async => const []),
          workOrderSatisfactionProvider('wo-1')
              .overrideWith((ref) async => null),
          workOrderEventsProvider('wo-1')
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
          home: const WorkOrderDetailScreen(workOrderId: 'wo-1'),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Mais ações'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar aceite'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Aceite do cliente'), findsWidgets);
    expect(find.text('Nome do responsável *'), findsOneWidget);
    expect(find.text('Assinatura do cliente'), findsOneWidget);
    expect(find.text('Limpar assinatura'), findsOneWidget);
  });

  testWidgets('WorkOrderDetailScreen abre popup de evidencia', (tester) async {
    final workOrder = WorkOrder(
      id: 'wo-1',
      tenantId: 'tenant-1',
      number: 12,
      customerId: 'customer-1',
      status: WorkOrderStatus.inProgress,
      title: 'Troca de compressor',
      description: 'Executar substituicao do compressor.',
      totalCents: 250000,
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 22),
      customerName: 'Cliente Teste',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workOrderDetailProvider('wo-1')
              .overrideWith((ref) async => workOrder),
          workOrderEvidenceProvider('wo-1')
              .overrideWith((ref) async => const []),
          workOrderItemsProvider('wo-1').overrideWith((ref) async => const []),
          workOrderSatisfactionProvider('wo-1')
              .overrideWith((ref) async => null),
          workOrderEventsProvider('wo-1')
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
          home: const WorkOrderDetailScreen(workOrderId: 'wo-1'),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Anexar foto/evidência'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Evidência da OS'), findsWidgets);
    expect(find.text('Selecionar foto ou arquivo'), findsOneWidget);
  });

  testWidgets('WorkOrderDetailScreen abre popup de despesa', (tester) async {
    final workOrder = WorkOrder(
      id: 'wo-1',
      tenantId: 'tenant-1',
      number: 12,
      customerId: 'customer-1',
      status: WorkOrderStatus.inProgress,
      title: 'Troca de compressor',
      description: 'Executar substituicao do compressor.',
      totalCents: 250000,
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 22),
      customerName: 'Cliente Teste',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workOrderDetailProvider('wo-1')
              .overrideWith((ref) async => workOrder),
          workOrderEvidenceProvider('wo-1')
              .overrideWith((ref) async => const []),
          workOrderItemsProvider('wo-1').overrideWith((ref) async => const []),
          workOrderSatisfactionProvider('wo-1')
              .overrideWith((ref) async => null),
          workOrderEventsProvider('wo-1')
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
          home: const WorkOrderDetailScreen(workOrderId: 'wo-1'),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Mais ações'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar despesa'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Despesa da OS'), findsWidgets);
    expect(find.text('Tipo de despesa'), findsOneWidget);
  });

  testWidgets('WorkOrderDetailScreen abre popup de satisfacao', (tester) async {
    final workOrder = WorkOrder(
      id: 'wo-1',
      tenantId: 'tenant-1',
      number: 12,
      customerId: 'customer-1',
      status: WorkOrderStatus.done,
      title: 'Troca de compressor',
      description: 'Executar substituicao do compressor.',
      totalCents: 250000,
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 22),
      customerName: 'Cliente Teste',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workOrderDetailProvider('wo-1')
              .overrideWith((ref) async => workOrder),
          workOrderEvidenceProvider('wo-1')
              .overrideWith((ref) async => const []),
          workOrderItemsProvider('wo-1').overrideWith((ref) async => const []),
          workOrderSatisfactionProvider('wo-1')
              .overrideWith((ref) async => null),
          workOrderEventsProvider('wo-1')
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
          home: const WorkOrderDetailScreen(workOrderId: 'wo-1'),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Mais ações'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar satisfação'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Satisfação do cliente'), findsWidgets);
    expect(find.text('Salvar satisfação'), findsOneWidget);
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

  List<Override> baseOverrides(WorkOrder wo) => [
        workOrderDetailProvider(wo.id).overrideWith((ref) async => wo),
        workOrderEvidenceProvider(wo.id).overrideWith((ref) async => const []),
        workOrderItemsProvider(wo.id).overrideWith((ref) async => const []),
        workOrderSatisfactionProvider(wo.id)
            .overrideWith((ref) async => null),
        workOrderEventsProvider(wo.id).overrideWith((ref) async => const []),
        customerDetailProvider('customer-1')
            .overrideWith((ref) async => makeCustomer()),
      ];

  testWidgets(
      'WorkOrderDetailScreen mostra botão Criar retorno para OS concluída',
      (tester) async {
    final wo = WorkOrder(
      id: 'wo-done',
      tenantId: 'tenant-1',
      number: 5,
      customerId: 'customer-1',
      status: WorkOrderStatus.done,
      title: 'Revisão completa',
      description: 'Concluída.',
      totalCents: 100000,
      createdAt: DateTime(2026, 7, 25),
      updatedAt: DateTime(2026, 7, 25),
      customerName: 'Cliente Teste',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: baseOverrides(wo),
      child: MaterialApp(
          theme: AppTheme.light,
          home: WorkOrderDetailScreen(workOrderId: wo.id)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mais ações'));
    await tester.pumpAndSettle();
    expect(find.text('Criar retorno'), findsOneWidget);
  });

  testWidgets('WorkOrderDetailScreen mostra painel de cancelamento para OS cancelada',
      (tester) async {
    final wo = WorkOrder(
      id: 'wo-cancelled',
      tenantId: 'tenant-1',
      number: 6,
      customerId: 'customer-1',
      status: WorkOrderStatus.cancelled,
      title: 'OS cancelada',
      description: 'Desc.',
      totalCents: 0,
      cancellationReason: 'Cliente desistiu.',
      createdAt: DateTime(2026, 7, 25),
      updatedAt: DateTime(2026, 7, 25),
      customerName: 'Cliente Teste',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: baseOverrides(wo),
      child: MaterialApp(
          theme: AppTheme.light,
          home: WorkOrderDetailScreen(workOrderId: wo.id)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Cliente desistiu.'), findsWidgets);
    expect(find.text('Criar retorno'), findsNothing);
  });

  testWidgets(
      'WorkOrderDetailScreen mostra chip Retorno para OS com parentWorkOrderId',
      (tester) async {
    final wo = WorkOrder(
      id: 'wo-return',
      tenantId: 'tenant-1',
      number: 7,
      customerId: 'customer-1',
      status: WorkOrderStatus.opened,
      title: 'Retorno de ajuste',
      description: 'Retorno.',
      totalCents: 0,
      parentWorkOrderId: 'wo-parent',
      createdAt: DateTime(2026, 7, 25),
      updatedAt: DateTime(2026, 7, 25),
      customerName: 'Cliente Teste',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: baseOverrides(wo),
      child: MaterialApp(
          theme: AppTheme.light,
          home: WorkOrderDetailScreen(workOrderId: wo.id)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Retorno'), findsOneWidget);
  });

  testWidgets('WorkOrderDetailScreen exibe eventos no painel de histórico',
      (tester) async {
    final wo = WorkOrder(
      id: 'wo-events',
      tenantId: 'tenant-1',
      number: 8,
      customerId: 'customer-1',
      status: WorkOrderStatus.inProgress,
      title: 'Com eventos',
      description: 'Desc.',
      totalCents: 0,
      createdAt: DateTime(2026, 7, 25),
      updatedAt: DateTime(2026, 7, 25),
      customerName: 'Cliente Teste',
    );

    final events = [
      WorkOrderEvent(
        id: 'evt-1',
        eventType: 'created',
        createdAt: DateTime(2026, 7, 25, 8),
      ),
      WorkOrderEvent(
        id: 'evt-2',
        eventType: 'started',
        notes: 'Técnico chegou.',
        createdAt: DateTime(2026, 7, 25, 9),
      ),
    ];

    final overrides = [
      workOrderDetailProvider(wo.id).overrideWith((ref) async => wo),
      workOrderEvidenceProvider(wo.id).overrideWith((ref) async => const []),
      workOrderItemsProvider(wo.id).overrideWith((ref) async => const []),
      workOrderSatisfactionProvider(wo.id).overrideWith((ref) async => null),
      workOrderEventsProvider(wo.id).overrideWith((ref) async => events),
      customerDetailProvider('customer-1')
          .overrideWith((ref) async => makeCustomer()),
    ];

    // Viewport alto: o painel de histórico fica abaixo da dobra em um ListView lazy.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp(
          theme: AppTheme.light,
          home: WorkOrderDetailScreen(workOrderId: wo.id)),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Criada'), 300);
    await tester.pumpAndSettle();

    expect(find.text('Criada'), findsOneWidget);
    expect(find.text('Execução iniciada'), findsOneWidget);
    expect(find.text('Técnico chegou.'), findsOneWidget);
  });
}
