import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/receivable.dart';

class FinancialRepository {
  FinancialRepository(this._client);

  final SupabaseClient? _client;
  static const _pageSize = 30;

  SupabaseClient get _db {
    final client = _client;
    if (client == null) {
      throw StateError('SupabaseClient nao configurado.');
    }
    return client;
  }

  Future<({List<Receivable> items, int totalCount})> listReceivables({
    int page = 0,
  }) async {
    try {
      final from = page * _pageSize;
      final to = from + _pageSize - 1;
      final rows = await _db
          .from('receivables')
          .select(
            '*, customers(name), work_orders(number), receipts(*, payment_records(method, reference))',
          )
          .order('due_date')
          .range(from, to);
      final items = (rows as List<dynamic>)
          .map((row) => receivableFromRow(row as Map<String, dynamic>))
          .toList();
      final isLastPage = items.length < _pageSize;
      final totalCount =
          isLastPage ? page * _pageSize + items.length : (page + 2) * _pageSize;
      return (items: items, totalCount: totalCount);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        'Erro ao carregar financeiro.',
        e.toString(),
      );
    }
  }

  Future<void> registerManualPayment({
    required String receivableId,
    required String method,
    required int amountCents,
    String? reference,
    String? notes,
  }) async {
    try {
      await _db.rpc(
        'register_manual_payment',
        params: {
          'p_receivable_id': receivableId,
          'p_method': method,
          'p_amount_cents': amountCents,
          'p_reference': reference,
          'p_notes': notes,
        },
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        'Erro ao registrar pagamento.',
        e.toString(),
      );
    }
  }

  AppError _mapError(PostgrestException e) {
    if (e.code == '42501' || e.code == 'insufficient_privilege') {
      return const PermissionError(
        'Voce nao tem permissao para acessar o financeiro.',
      );
    }
    if (e.code == '23514' || e.code == 'P0001') {
      return const BusinessRuleError('Revise os dados do pagamento.');
    }
    return UnexpectedError(
      'Operacao financeira falhou. Tente novamente.',
      e.message,
    );
  }
}
