import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../data/service_request_repository.dart';
import '../domain/service_category.dart';
import '../domain/service_priority.dart';
import '../domain/service_request.dart';

class ServiceRequestListState {
  const ServiceRequestListState({
    this.items = const [],
    this.filter = const ServiceRequestFilter(),
    this.page = 0,
    this.totalCount = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<ServiceRequest> items;
  final ServiceRequestFilter filter;
  final int page;
  final int totalCount;
  final bool isLoading;
  final bool isLoadingMore;
  final AppError? error;

  bool get hasMore => items.length < totalCount;
  bool get isEmpty => !isLoading && items.isEmpty && error == null;

  ServiceRequestListState copyWith({
    List<ServiceRequest>? items,
    ServiceRequestFilter? filter,
    int? page,
    int? totalCount,
    bool? isLoading,
    bool? isLoadingMore,
    AppError? error,
    bool clearError = false,
  }) =>
      ServiceRequestListState(
        items: items ?? this.items,
        filter: filter ?? this.filter,
        page: page ?? this.page,
        totalCount: totalCount ?? this.totalCount,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        error: clearError ? null : error ?? this.error,
      );
}

class ServiceRequestListNotifier extends Notifier<ServiceRequestListState> {
  @override
  ServiceRequestListState build() => const ServiceRequestListState();

  ServiceRequestRepository get _repo =>
      ref.read(serviceRequestRepositoryProvider);

  Future<void> load({ServiceRequestFilter? filter}) async {
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
            'Erro inesperado ao carregar chamados.', e.toString()),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;

    final nextPage = state.page + 1;
    state = state.copyWith(isLoadingMore: true);

    try {
      final result = await _repo.listPaged(
        filter: state.filter,
        page: nextPage,
      );
      state = state.copyWith(
        items: [...state.items, ...result.items],
        totalCount: result.totalCount,
        page: nextPage,
        isLoadingMore: false,
      );
    } on AppError catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e);
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        error: UnexpectedError('Erro ao carregar mais chamados.', e.toString()),
      );
    }
  }

  Future<void> applyFilter(ServiceRequestFilter filter) => load(filter: filter);

  Future<void> refresh() => load(filter: state.filter);

  void addOrReplace(ServiceRequest request) {
    final exists = state.items.any((item) => item.id == request.id);
    state = state.copyWith(
      items: exists
          ? state.items
              .map((item) => item.id == request.id ? request : item)
              .toList()
          : [request, ...state.items],
      totalCount: exists ? state.totalCount : state.totalCount + 1,
    );
  }
}

final serviceRequestRepositoryProvider = Provider<ServiceRequestRepository>(
  (ref) => ServiceRequestRepository(ref.read(supabaseClientProvider)),
);

final serviceRequestListProvider =
    NotifierProvider<ServiceRequestListNotifier, ServiceRequestListState>(
  ServiceRequestListNotifier.new,
);

final serviceRequestDetailProvider =
    FutureProvider.autoDispose.family<ServiceRequest, String>((ref, id) async {
  return ref.read(serviceRequestRepositoryProvider).get(id);
});

final serviceRequestCategoriesProvider =
    FutureProvider.autoDispose<List<ServiceCategory>>((ref) async {
  return ref.read(serviceRequestRepositoryProvider).listCategories();
});

final serviceRequestPrioritiesProvider =
    FutureProvider.autoDispose<List<ServicePriority>>((ref) async {
  return ref.read(serviceRequestRepositoryProvider).listPriorities();
});

final serviceRequestStatusHistoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, requestId) async {
  return ref.read(serviceRequestRepositoryProvider).getStatusHistory(requestId);
});
