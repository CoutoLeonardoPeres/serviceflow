import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../data/reports_repository.dart';
import '../domain/reports_snapshot.dart';

class ReportsState {
  const ReportsState({
    this.snapshot,
    this.period = ReportsPeriod.last30Days,
    this.isLoading = false,
    this.error,
  });

  final ReportsSnapshot? snapshot;
  final ReportsPeriod period;
  final bool isLoading;
  final AppError? error;

  ReportsState copyWith({
    ReportsSnapshot? snapshot,
    ReportsPeriod? period,
    bool? isLoading,
    AppError? error,
    bool clearError = false,
  }) =>
      ReportsState(
        snapshot: snapshot ?? this.snapshot,
        period: period ?? this.period,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
      );
}

class ReportsNotifier extends Notifier<ReportsState> {
  @override
  ReportsState build() => const ReportsState();

  ReportsRepository get _repo => ref.read(reportsRepositoryProvider);

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final snapshot = await _repo.loadSnapshot(period: state.period);
      state = state.copyWith(snapshot: snapshot, isLoading: false);
    } on AppError catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: UnexpectedError('Erro ao carregar relatorios.', e.toString()),
      );
    }
  }

  Future<void> refresh() => load();

  Future<void> changePeriod(ReportsPeriod period) async {
    state = state.copyWith(period: period);
    await load();
  }
}

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(ref.read(supabaseClientProvider)),
);

final reportsProvider = NotifierProvider<ReportsNotifier, ReportsState>(
  ReportsNotifier.new,
);
