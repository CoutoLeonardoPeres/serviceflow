import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/work_orders/domain/satisfaction_public_context.dart';

void main() {
  group('satisfactionPublicContextFromRow', () {
    test('desserializa row completo', () {
      final row = {
        'work_order_number': 42,
        'service_title': 'Troca de compressor',
        'company_name': 'Eletroceu',
        'completed_at': '2026-07-25T14:00:00Z',
        'already_answered': true,
        'current_rating': 4,
      };

      final ctx = satisfactionPublicContextFromRow(row);
      expect(ctx.workOrderNumber, 42);
      expect(ctx.serviceTitle, 'Troca de compressor');
      expect(ctx.companyName, 'Eletroceu');
      expect(ctx.completedAt, DateTime.utc(2026, 7, 25, 14));
      expect(ctx.alreadyAnswered, isTrue);
      expect(ctx.currentRating, 4);
    });

    test('desserializa row de pesquisa ainda não respondida', () {
      final row = {
        'work_order_number': 7,
        'service_title': 'Manutenção preventiva',
        'company_name': 'Eletroceu',
        'completed_at': '2026-07-25T09:00:00Z',
        'already_answered': false,
        'current_rating': null,
      };

      final ctx = satisfactionPublicContextFromRow(row);
      expect(ctx.alreadyAnswered, isFalse);
      expect(ctx.currentRating, isNull);
    });

    test('usa defaults seguros quando campos vêm nulos', () {
      final row = <String, dynamic>{
        'work_order_number': null,
        'service_title': null,
        'company_name': null,
        'completed_at': null,
        'already_answered': null,
        'current_rating': null,
      };

      final ctx = satisfactionPublicContextFromRow(row);
      expect(ctx.workOrderNumber, 0);
      expect(ctx.serviceTitle, '');
      expect(ctx.companyName, '');
      expect(ctx.completedAt, isNull);
      expect(ctx.alreadyAnswered, isFalse);
    });

    test('não expõe campos sensíveis mesmo se vierem no row', () {
      // Garante que o modelo ignora qualquer dado além do contrato mínimo:
      // o RPC não deve mandar isso, e o cliente não deve depender disso.
      final row = {
        'work_order_number': 1,
        'service_title': 'S',
        'company_name': 'C',
        'already_answered': false,
        'customer_phone': '11999999999',
        'total_cents': 250000,
        'address': 'Rua X, 123',
      };

      final ctx = satisfactionPublicContextFromRow(row);
      expect(ctx.workOrderNumber, 1);
      // O tipo não possui esses campos — a checagem é estrutural, por
      // construção. Este teste documenta a intenção do contrato.
      expect(ctx.serviceTitle, 'S');
      expect(ctx.companyName, 'C');
    });
  });

  group('satisfactionRatingLabel', () {
    test('mapeia todas as notas válidas', () {
      expect(satisfactionRatingLabel(1), 'Muito insatisfeito');
      expect(satisfactionRatingLabel(2), 'Insatisfeito');
      expect(satisfactionRatingLabel(3), 'Neutro');
      expect(satisfactionRatingLabel(4), 'Satisfeito');
      expect(satisfactionRatingLabel(5), 'Muito satisfeito');
    });

    test('retorna rótulo neutro para nota fora da faixa', () {
      expect(satisfactionRatingLabel(0), 'Sem nota');
      expect(satisfactionRatingLabel(6), 'Sem nota');
      expect(satisfactionRatingLabel(-1), 'Sem nota');
    });
  });
}
