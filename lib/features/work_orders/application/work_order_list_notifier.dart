import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/files/stored_attachment.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../data/work_order_repository.dart';
import '../domain/work_order.dart';
import '../domain/work_order_event.dart';
import '../domain/work_order_satisfaction.dart';

class WorkOrderListState {
  const WorkOrderListState({
    this.items = const [],
    this.filter = const WorkOrderFilter(),
    this.page = 0,
    this.totalCount = 0,
    this.isLoading = false,
    this.error,
  });

  final List<WorkOrder> items;
  final WorkOrderFilter filter;
  final int page;
  final int totalCount;
  final bool isLoading;
  final AppError? error;

  bool get isEmpty => !isLoading && items.isEmpty && error == null;

  WorkOrderListState copyWith({
    List<WorkOrder>? items,
    WorkOrderFilter? filter,
    int? page,
    int? totalCount,
    bool? isLoading,
    AppError? error,
    bool clearError = false,
  }) =>
      WorkOrderListState(
        items: items ?? this.items,
        filter: filter ?? this.filter,
        page: page ?? this.page,
        totalCount: totalCount ?? this.totalCount,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
      );
}

class WorkOrderListNotifier extends Notifier<WorkOrderListState> {
  @override
  WorkOrderListState build() => const WorkOrderListState();

  WorkOrderRepository get _repo => ref.read(workOrderRepositoryProvider);

  Future<void> load({WorkOrderFilter? filter}) async {
    final selectedFilter = filter ?? state.filter;
    state = state.copyWith(
      isLoading: true,
      filter: selectedFilter,
      page: 0,
      items: [],
      clearError: true,
    );
    try {
      final result = await _repo.listPaged(filter: selectedFilter);
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
        error: UnexpectedError(
            'Erro ao carregar ordens de servico.', e.toString()),
      );
    }
  }

  Future<void> refresh() => load(filter: state.filter);

  Future<void> applyFilter(WorkOrderFilter filter) => load(filter: filter);
}

final workOrderRepositoryProvider = Provider<WorkOrderRepository>(
  (ref) => WorkOrderRepository(ref.read(supabaseClientProvider)),
);

final workOrderListProvider =
    NotifierProvider<WorkOrderListNotifier, WorkOrderListState>(
  WorkOrderListNotifier.new,
);

final workOrderDetailProvider =
    FutureProvider.autoDispose.family<WorkOrder, String>((ref, id) async {
  return ref.read(workOrderRepositoryProvider).get(id);
});

final workOrderSatisfactionProvider = FutureProvider.autoDispose
    .family<WorkOrderSatisfaction?, String>((ref, workOrderId) async {
  return ref.read(workOrderRepositoryProvider).getSatisfaction(workOrderId);
});

final workOrderEvidenceProvider = FutureProvider.autoDispose
    .family<List<StoredAttachment>, String>((ref, workOrderId) async {
  return ref.read(workOrderRepositoryProvider).listEvidence(workOrderId);
});

final workOrderItemsProvider = FutureProvider.autoDispose
    .family<List<WorkOrderItem>, String>((ref, workOrderId) async {
  return ref.read(workOrderRepositoryProvider).listItems(workOrderId);
});

final workOrderEventsProvider = FutureProvider.autoDispose
    .family<List<WorkOrderEvent>, String>((ref, workOrderId) async {
  return ref.read(workOrderRepositoryProvider).listEvents(workOrderId);
});
