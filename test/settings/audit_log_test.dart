import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/settings/domain/audit_log_event.dart';

void main() {
  group('AuditLogEvent', () {
    AuditLogEvent make(String action, String entity) => AuditLogEvent(
          id: 'id-1',
          action: action,
          entity: entity,
          createdAt: DateTime(2026, 7, 25),
        );

    group('actionLabel', () {
      test('mapeia ações de orçamento', () {
        expect(make('quotation.created', 'quotations').actionLabel,
            'Orçamento criado');
        expect(make('quotation.cancelled', 'quotations').actionLabel,
            'Orçamento cancelado');
        expect(make('quotation.new_version_created', 'quotations').actionLabel,
            'Nova versão de orçamento');
        expect(make('quotation.public_link_created', 'quotations').actionLabel,
            'Link público gerado');
      });

      test('mapeia ações de OS', () {
        expect(make('work_order.created', 'work_orders').actionLabel,
            'OS criada');
        expect(make('work_order.cancelled', 'work_orders').actionLabel,
            'OS cancelada');
        expect(make('work_order.return_created', 'work_orders').actionLabel,
            'Retorno de OS criado');
        expect(make('work_order.status_changed', 'work_orders').actionLabel,
            'Status de OS alterado');
      });

      test('mapeia ações de cliente e financeiro', () {
        expect(
            make('customer.created', 'customers').actionLabel, 'Cliente criado');
        expect(make('receivable.created', 'receivables').actionLabel,
            'Cobrança gerada');
        expect(make('payment.registered', 'receivables').actionLabel,
            'Pagamento registrado');
      });

      test('retorna a própria ação para desconhecidas', () {
        const unknown = 'modulo.acao_desconhecida';
        expect(make(unknown, 'unknown').actionLabel, unknown);
      });
    });

    group('entityLabel', () {
      test('mapeia entidades conhecidas', () {
        expect(make('x', 'quotations').entityLabel, 'Orçamento');
        expect(make('x', 'work_orders').entityLabel, 'OS');
        expect(make('x', 'customers').entityLabel, 'Cliente');
        expect(make('x', 'service_requests').entityLabel, 'Chamado');
        expect(make('x', 'appointments').entityLabel, 'Agendamento');
        expect(make('x', 'receivables').entityLabel, 'Financeiro');
        expect(make('x', 'tenant_memberships').entityLabel, 'Membros');
        expect(make('x', 'tenants').entityLabel, 'Empresa');
      });

      test('retorna o próprio nome para entidades desconhecidas', () {
        expect(make('x', 'unknown_table').entityLabel, 'unknown_table');
      });
    });
  });

  group('auditLogEventFromRow', () {
    test('desserializa row completo', () {
      final row = {
        'id': 'evt-1',
        'action': 'work_order.cancelled',
        'entity': 'work_orders',
        'entity_id': 'wo-123',
        'actor_id': 'user-abc',
        'after_data': {'status': 'cancelled'},
        'metadata': <String, dynamic>{},
        'created_at': '2026-07-25T14:30:00Z',
      };

      final event = auditLogEventFromRow(row);
      expect(event.id, 'evt-1');
      expect(event.action, 'work_order.cancelled');
      expect(event.entity, 'work_orders');
      expect(event.entityId, 'wo-123');
      expect(event.actorId, 'user-abc');
      expect(event.afterData, {'status': 'cancelled'});
      expect(event.createdAt, DateTime.utc(2026, 7, 25, 14, 30));
    });

    test('desserializa row sem campos opcionais', () {
      final row = {
        'id': 'evt-2',
        'action': 'customer.created',
        'entity': 'customers',
        'entity_id': null,
        'actor_id': null,
        'after_data': null,
        'metadata': null,
        'created_at': '2026-07-25T00:00:00Z',
      };

      final event = auditLogEventFromRow(row);
      expect(event.entityId, isNull);
      expect(event.actorId, isNull);
      expect(event.afterData, isNull);
    });
  });
}
