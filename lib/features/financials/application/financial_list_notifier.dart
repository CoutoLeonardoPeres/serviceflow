import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../data/financial_repository.dart';
import '../domain/receivable.dart';

class FinancialListState {
  const FinancialListState({
    this.items = const [],
    this.page = 0,
    this.totalCount = 0,
    this.isLoading = false,
    this.error,
  });

  final List<Receivable> items;
  final int page;
  final int totalCount;
  final bool isLoading;
  final AppError? error;

  bool get isEmpty => !isLoading && items.isEmpty && error == null;

  int get openBalanceCents =>
      items.fold(0, (total, item) => total + item.balanceCents);

  int get overdueBalanceCents => items
      .where((item) => item.isOverdue)
      .fold(0, (total, item) => total + item.balanceCents);

  FinancialListState copyWith({
    List<Receivable>? items,
    int? page,
    int? totalCount,
    bool? isLoading,
    AppError? error,
    bool clearError = false,
  }) =>
      FinancialListState(
        items: items ?? this.items,
        page: page ?? this.page,
        totalCount: totalCount ?? this.totalCount,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
      );
}

class FinancialListNotifier extends Notifier<FinancialListState> {
  @override
  FinancialListState build() => const FinancialListState();

  FinancialRepository get _repo => ref.read(financialRepositoryProvider);

  Future<void> load() async {
    state = state.copyWith(isLoading: true, items: [], clearError: true);
    try {
      final result = await _repo.listReceivables();
      state = state.copyWith(
        items: result.items,
        totalCount: result.totalCount,
        isLoading: false,
      );
    } on AppError catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: UnexpectedError('Erro ao carregar financeiro.', e.toString()),
      );
    }
  }

  Future<void> refresh() => load();
}

final financialRepositoryProvider = Provider<FinancialRepository>(
  (ref) => FinancialRepository(ref.read(supabaseClientProvider)),
);

final financialListProvider =
    NotifierProvider<FinancialListNotifier, FinancialListState>(
  FinancialListNotifier.new,
);
