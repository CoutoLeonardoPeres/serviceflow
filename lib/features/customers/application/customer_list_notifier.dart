import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../data/customer_repository.dart';
import '../domain/customer.dart';
import '../domain/customer_address.dart';
import '../domain/customer_asset.dart';
import '../domain/customer_contact.dart';

// ── Estado ────────────────────────────────────────────────────────────────────

class CustomerListState {
  const CustomerListState({
    this.items = const [],
    this.filter = const CustomerFilter(),
    this.page = 0,
    this.totalCount = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<Customer> items;
  final CustomerFilter filter;
  final int page;
  final int totalCount;
  final bool isLoading;
  final bool isLoadingMore;
  final AppError? error;

  bool get hasMore => items.length < totalCount;
  bool get isEmpty => !isLoading && items.isEmpty && error == null;

  CustomerListState copyWith({
    List<Customer>? items,
    CustomerFilter? filter,
    int? page,
    int? totalCount,
    bool? isLoading,
    bool? isLoadingMore,
    AppError? error,
    bool clearError = false,
  }) =>
      CustomerListState(
        items: items ?? this.items,
        filter: filter ?? this.filter,
        page: page ?? this.page,
        totalCount: totalCount ?? this.totalCount,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        error: clearError ? null : error ?? this.error,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class CustomerListNotifier extends Notifier<CustomerListState> {
  @override
  CustomerListState build() => const CustomerListState();

  CustomerRepository get _repo => ref.read(customerRepositoryProvider);

  /// Carrega a primeira página com os filtros dados.
  Future<void> load({CustomerFilter? filter}) async {
    final f = filter ?? state.filter;
    state = state.copyWith(
      isLoading: true,
      filter: f,
      page: 0,
      items: [],
      clearError: true,
    );

    try {
      final result = await _repo.listPaged(filter: f, page: 0);
      state = state.copyWith(
        items: result.items,
        totalCount: result.totalCount,
        page: 0,
        isLoading: false,
      );
    } on AppError catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: UnexpectedError(
            'Erro inesperado ao carregar clientes.', e.toString()),
      );
    }
  }

  /// Carrega a próxima página (infinite scroll).
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;

    final nextPage = state.page + 1;
    state = state.copyWith(isLoadingMore: true);

    try {
      final result =
          await _repo.listPaged(filter: state.filter, page: nextPage);
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
        error: UnexpectedError('Erro ao carregar mais clientes.', e.toString()),
      );
    }
  }

  /// Atualiza o filtro e recarrega.
  Future<void> applyFilter(CustomerFilter filter) => load(filter: filter);

  /// Recarrega com o filtro atual.
  Future<void> refresh() => load(filter: state.filter);

  /// Remove um cliente da lista local (após desativar).
  void removeFromList(String customerId) {
    state = state.copyWith(
      items: state.items.where((c) => c.id != customerId).toList(),
      totalCount: state.totalCount > 0 ? state.totalCount - 1 : 0,
    );
  }

  /// Substitui um cliente na lista local (após editar).
  void updateInList(Customer updated) {
    state = state.copyWith(
      items: state.items.map((c) => c.id == updated.id ? updated : c).toList(),
    );
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final customerListProvider =
    NotifierProvider<CustomerListNotifier, CustomerListState>(
  CustomerListNotifier.new,
);

/// Provider de um cliente individual (para tela de detalhe).
final customerDetailProvider =
    FutureProvider.autoDispose.family<Customer, String>((ref, id) async {
  final repo = CustomerRepository(ref.read(supabaseClientProvider));
  return repo.get(id);
});

/// Provider de contatos de um cliente.
final customerContactsProvider = FutureProvider.autoDispose
    .family<List<CustomerContact>, String>((ref, customerId) async {
  final repo = CustomerRepository(ref.read(supabaseClientProvider));
  return repo.getContacts(customerId);
});

/// Provider de endereços de um cliente.
final customerAddressesProvider = FutureProvider.autoDispose
    .family<List<CustomerAddress>, String>((ref, customerId) async {
  final repo = CustomerRepository(ref.read(supabaseClientProvider));
  return repo.getAddresses(customerId);
});

/// Provider de ativos de um cliente.
final customerAssetsProvider = FutureProvider.autoDispose
    .family<List<CustomerAsset>, String>((ref, customerId) async {
  final repo = CustomerRepository(ref.read(supabaseClientProvider));
  return repo.getAssets(customerId);
});

/// Provider do repositório (para uso nos form notifiers).
final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(ref.read(supabaseClientProvider)),
);
