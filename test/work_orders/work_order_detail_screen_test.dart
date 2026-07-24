import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/features/work_orders/application/work_order_list_notifier.dart';
import 'package:serviceflow/features/work_orders/domain/work_order.dart';
import 'package:serviceflow/features/work_orders/presentation/work_order_detail_screen.dart';

void main() {
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
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const WorkOrderDetailScreen(workOrderId: 'wo-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Registrar horas'), findsOneWidget);
    expect(find.text('Adicionar material'), findsOneWidget);
    expect(find.text('Registrar despesa'), findsOneWidget);
    expect(find.text('Anexar foto/evidência'), findsOneWidget);
    expect(find.text('Registrar aceite'), findsOneWidget);
    expect(find.text('Gerar cobrança'), findsOneWidget);
    expect(find.text('Registrar satisfação'), findsOneWidget);
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
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const WorkOrderDetailScreen(workOrderId: 'wo-1'),
        ),
      ),
    );
    await tester.pump();

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
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const WorkOrderDetailScreen(workOrderId: 'wo-1'),
        ),
      ),
    );
    await tester.pump();

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
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const WorkOrderDetailScreen(workOrderId: 'wo-1'),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Registrar satisfação'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Satisfação do cliente'), findsWidgets);
    expect(find.text('Salvar satisfação'), findsOneWidget);
  });
}
