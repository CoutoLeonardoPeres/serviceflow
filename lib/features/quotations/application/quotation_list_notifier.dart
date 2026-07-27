import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/files/stored_attachment.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../data/quotation_repository.dart';
import '../domain/quotation.dart';
import '../domain/quotation_version.dart';

class QuotationListState {
  const QuotationListState({
    this.items = const [],
    this.filter = const QuotationFilter(),
    this.page = 0,
    this.totalCount = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<Quotation> items;
  final QuotationFilter filter;
  final int page;
  final int totalCount;
  final bool isLoading;
  final bool isLoadingMore;
  final AppError? error;

  bool get hasMore => items.length < totalCount;
  bool get isEmpty => !isLoading && items.isEmpty && error == null;

  QuotationListState copyWith({
    List<Quotation>? items,
    QuotationFilter? filter,
    int? page,
    int? totalCount,
    bool? isLoading,
    bool? isLoadingMore,
    AppError? error,
    bool clearError = false,
  }) =>
      QuotationListState(
        items: items ?? this.items,
        filter: filter ?? this.filter,
        page: page ?? this.page,
        totalCount: totalCount ?? this.totalCount,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        error: clearError ? null : error ?? this.error,
      );
}

class QuotationListNotifier extends Notifier<QuotationListState> {
  @override
  QuotationListState build() => const QuotationListState();

  QuotationRepository get _repo => ref.read(quotationRepositoryProvider);

  Future<void> load({QuotationFilter? filter}) async {
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
        error: UnexpectedError('Erro ao carregar orcamentos.', e.toString()),
      );
    }
  }

  Future<void> refresh() => load(filter: state.filter);

  void addOrReplace(Quotation quotation) {
    final exists = state.items.any((item) => item.id == quotation.id);
    state = state.copyWith(
      items: exists
          ? state.items
              .map((item) => item.id == quotation.id ? quotation : item)
              .toList()
          : [quotation, ...state.items],
      totalCount: exists ? state.totalCount : state.totalCount + 1,
    );
  }
}

final quotationRepositoryProvider = Provider<QuotationRepository>(
  (ref) => QuotationRepository(ref.read(supabaseClientProvider)),
);

final quotationListProvider =
    NotifierProvider<QuotationListNotifier, QuotationListState>(
  QuotationListNotifier.new,
);

final quotationDetailProvider =
    FutureProvider.autoDispose.family<Quotation, String>((ref, id) async {
  return ref.read(quotationRepositoryProvider).get(id);
});

final quotationAttachmentsProvider = FutureProvider.autoDispose
    .family<List<StoredAttachment>, String>((ref, quotationId) async {
  return ref.read(quotationRepositoryProvider).listAttachments(quotationId);
});

final quotationItemsProvider = FutureProvider.autoDispose
    .family<List<QuotationItem>, ({String quotationId, String? versionId})>(
        (ref, args) async {
  return ref
      .read(quotationRepositoryProvider)
      .listItems(args.quotationId, versionId: args.versionId);
});

final quotationVersionsProvider = FutureProvider.autoDispose
    .family<List<QuotationVersion>, String>((ref, quotationId) async {
  return ref.read(quotationRepositoryProvider).listVersions(quotationId);
});

final quotationStatusHistoryProvider = FutureProvider.autoDispose
    .family<List<QuotationStatusEvent>, String>((ref, quotationId) async {
  return ref.read(quotationRepositoryProvider).listStatusHistory(quotationId);
});
