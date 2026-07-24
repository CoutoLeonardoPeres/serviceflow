import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../data/appointment_repository.dart';
import '../domain/appointment.dart';
import '../domain/technician.dart';

class AppointmentListState {
  const AppointmentListState({
    this.items = const [],
    this.filter = const AppointmentFilter(),
    this.isLoading = false,
    this.error,
  });

  final List<Appointment> items;
  final AppointmentFilter filter;
  final bool isLoading;
  final AppError? error;

  bool get isEmpty => !isLoading && items.isEmpty && error == null;

  AppointmentListState copyWith({
    List<Appointment>? items,
    AppointmentFilter? filter,
    bool? isLoading,
    AppError? error,
    bool clearError = false,
  }) =>
      AppointmentListState(
        items: items ?? this.items,
        filter: filter ?? this.filter,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
      );
}

class AppointmentListNotifier extends Notifier<AppointmentListState> {
  @override
  AppointmentListState build() => const AppointmentListState();

  AppointmentRepository get _repo => ref.read(appointmentRepositoryProvider);

  Future<void> load({AppointmentFilter? filter}) async {
    final selectedFilter = filter ?? state.filter;
    state = state.copyWith(
      isLoading: true,
      filter: selectedFilter,
      clearError: true,
    );

    try {
      final items = await _repo.list(filter: selectedFilter);
      state = state.copyWith(items: items, isLoading: false);
    } on AppError catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: UnexpectedError(
            'Erro inesperado ao carregar agenda.', e.toString()),
      );
    }
  }

  Future<void> refresh() => load(filter: state.filter);

  void addOrReplace(Appointment appointment) {
    final exists = state.items.any((item) => item.id == appointment.id);
    final items = exists
        ? state.items
            .map((item) => item.id == appointment.id ? appointment : item)
            .toList()
        : [appointment, ...state.items];
    items.sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
    state = state.copyWith(items: items);
  }
}

final appointmentRepositoryProvider = Provider<AppointmentRepository>(
  (ref) => AppointmentRepository(ref.read(supabaseClientProvider)),
);

final appointmentListProvider =
    NotifierProvider<AppointmentListNotifier, AppointmentListState>(
  AppointmentListNotifier.new,
);

final appointmentDetailProvider =
    FutureProvider.autoDispose.family<Appointment, String>((ref, id) async {
  return ref.read(appointmentRepositoryProvider).get(id);
});

final techniciansProvider = FutureProvider.autoDispose<List<Technician>>((ref) {
  return ref.read(appointmentRepositoryProvider).listTechnicians();
});
