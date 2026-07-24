import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../data/service_professional_repository.dart';
import '../domain/service_professional.dart';

class ServiceProfessionalListState {
  const ServiceProfessionalListState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  final List<ServiceProfessional> items;
  final bool isLoading;
  final AppError? error;

  ServiceProfessionalListState copyWith({
    List<ServiceProfessional>? items,
    bool? isLoading,
    AppError? error,
    bool clearError = false,
  }) {
    return ServiceProfessionalListState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class ServiceProfessionalListNotifier
    extends Notifier<ServiceProfessionalListState> {
  @override
  ServiceProfessionalListState build() => const ServiceProfessionalListState();

  ServiceProfessionalRepository get _repo =>
      ref.read(serviceProfessionalRepositoryProvider);

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _repo.list();
      state = state.copyWith(items: items, isLoading: false);
    } on AppError catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: UnexpectedError(
          'Erro ao carregar profissionais.',
          e.toString(),
        ),
      );
    }
  }
}

final serviceProfessionalRepositoryProvider =
    Provider<ServiceProfessionalRepository>(
  (ref) => ServiceProfessionalRepository(ref.read(supabaseClientProvider)),
);

final serviceProfessionalListProvider = NotifierProvider<
    ServiceProfessionalListNotifier, ServiceProfessionalListState>(
  ServiceProfessionalListNotifier.new,
);

final serviceProfessionalInternalUsersProvider =
    FutureProvider.autoDispose<List<TechnicianUserOption>>((ref) async {
  return ref.read(serviceProfessionalRepositoryProvider).listInternalUsers();
});
