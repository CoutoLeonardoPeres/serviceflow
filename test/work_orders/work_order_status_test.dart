import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/work_orders/domain/work_order.dart';

/// Guarda a máquina de estados da OS. Existe porque, até a migration 0057, o
/// banco aceitava qualquer status → qualquer status e a tela oferecia
/// "Concluir OS" numa OS recém-aberta, sem uma hora lançada.
///
/// Se algum destes testes falhar, `_sf_work_order_can_transition` (0057) e
/// `WorkOrderStatus.allowedNext` divergiram — arrume os dois, não só um.
void main() {
  group('WorkOrderStatus.allowedNext', () {
    test('não existe atalho de aberta para concluída', () {
      expect(WorkOrderStatus.opened.canGoTo(WorkOrderStatus.done), isFalse);
      expect(WorkOrderStatus.scheduled.canGoTo(WorkOrderStatus.done), isFalse);
      expect(WorkOrderStatus.draft.canGoTo(WorkOrderStatus.done), isFalse);
    });

    test('concluir exige ter passado pela execução', () {
      expect(WorkOrderStatus.inProgress.canGoTo(WorkOrderStatus.done), isTrue);
      expect(
        WorkOrderStatus.awaitingCustomer.canGoTo(WorkOrderStatus.done),
        isTrue,
      );
    });

    test('status terminal não vai para lugar nenhum', () {
      expect(WorkOrderStatus.done.isTerminal, isTrue);
      expect(WorkOrderStatus.cancelled.isTerminal, isTrue);
      expect(WorkOrderStatus.done.allowedNext, isEmpty);
      expect(WorkOrderStatus.cancelled.allowedNext, isEmpty);
    });

    test('cancelar é possível de qualquer status não terminal', () {
      for (final status in WorkOrderStatus.values) {
        if (status.isTerminal) continue;
        expect(
          status.canGoTo(WorkOrderStatus.cancelled),
          isTrue,
          reason: '$status deveria poder ser cancelada',
        );
      }
    });

    test('nenhum status pode ir para si mesmo pela máquina de estados', () {
      // Repetir o status é tratado como no-op pelo banco (0057), não como
      // transição válida — o app não deve oferecer o botão.
      for (final status in WorkOrderStatus.values) {
        expect(
          status.canGoTo(status),
          isFalse,
          reason: '$status não deveria listar a si mesma',
        );
      }
    });

    test('pausada volta para execução, nunca direto para concluída', () {
      expect(WorkOrderStatus.paused.canGoTo(WorkOrderStatus.inProgress), isTrue);
      expect(WorkOrderStatus.paused.canGoTo(WorkOrderStatus.done), isFalse);
    });

    test('OS terminal não aceita mais apontamento de execução', () {
      expect(WorkOrderStatus.done.acceptsExecutionInput, isFalse);
      expect(WorkOrderStatus.cancelled.acceptsExecutionInput, isFalse);
      expect(WorkOrderStatus.inProgress.acceptsExecutionInput, isTrue);
    });
  });
}
