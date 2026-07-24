import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../domain/service_request.dart';
import 'service_request_list_notifier.dart';

sealed class ServiceRequestFormState {
  const ServiceRequestFormState();
}

final class ServiceRequestFormIdle extends ServiceRequestFormState {
  const ServiceRequestFormIdle();
}

final class ServiceRequestFormLoading extends ServiceRequestFormState {
  const ServiceRequestFormLoading();
}

final class ServiceRequestFormSuccess extends ServiceRequestFormState {
  const ServiceRequestFormSuccess({
    required this.request,
    required this.isCreate,
  });

  final ServiceRequest request;
  final bool isCreate;
}

final class ServiceRequestFormError extends ServiceRequestFormState {
  const ServiceRequestFormError({required this.error});

  final AppError error;
}

class ServiceRequestFormNotifier extends Notifier<ServiceRequestFormState> {
  @override
  ServiceRequestFormState build() => const ServiceRequestFormIdle();

  Future<void> createRequest({
    required String customerId,
    required String title,
    required String description,
    required ServiceRequestChannel channel,
    String? requesterContactId,
    String? addressId,
    String? categoryId,
    String? priorityId,
    String? availabilityNotes,
    String? assignedTo,
  }) async {
    state = const ServiceRequestFormLoading();

    final request = ServiceRequest(
      id: '',
      tenantId: '',
      number: 0,
      customerId: customerId,
      requesterContactId: _emptyToNull(requesterContactId),
      addressId: _emptyToNull(addressId),
      categoryId: _emptyToNull(categoryId),
      priorityId: _emptyToNull(priorityId),
      title: title.trim(),
      description: description.trim(),
      availabilityNotes: _emptyToNull(availabilityNotes?.trim()),
      channel: channel,
      status: ServiceRequestStatus.opened,
      assignedTo: _emptyToNull(assignedTo),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      final created =
          await ref.read(serviceRequestRepositoryProvider).create(request);
      ref.read(serviceRequestListProvider.notifier).addOrReplace(created);
      state = ServiceRequestFormSuccess(request: created, isCreate: true);
    } on AppError catch (e) {
      state = ServiceRequestFormError(error: e);
    } catch (e) {
      state = ServiceRequestFormError(
        error: UnexpectedError('Erro ao criar chamado.', e.toString()),
      );
    }
  }

  Future<void> updateRequest({
    required ServiceRequest original,
    required String customerId,
    required String title,
    required String description,
    required ServiceRequestChannel channel,
    String? requesterContactId,
    String? addressId,
    String? categoryId,
    String? priorityId,
    String? availabilityNotes,
    String? assignedTo,
  }) async {
    state = const ServiceRequestFormLoading();

    final updated = original.copyWith(
      customerId: customerId,
      requesterContactId: _emptyToNull(requesterContactId),
      addressId: _emptyToNull(addressId),
      categoryId: _emptyToNull(categoryId),
      priorityId: _emptyToNull(priorityId),
      title: title.trim(),
      description: description.trim(),
      availabilityNotes: _emptyToNull(availabilityNotes?.trim()),
      channel: channel,
      assignedTo: _emptyToNull(assignedTo),
    );

    try {
      final saved = await ref
          .read(serviceRequestRepositoryProvider)
          .update(original.id, updated);
      ref.read(serviceRequestListProvider.notifier).addOrReplace(saved);
      state = ServiceRequestFormSuccess(request: saved, isCreate: false);
    } on AppError catch (e) {
      state = ServiceRequestFormError(error: e);
    } catch (e) {
      state = ServiceRequestFormError(
        error: UnexpectedError('Erro ao atualizar chamado.', e.toString()),
      );
    }
  }

  void reset() => state = const ServiceRequestFormIdle();
}

String? _emptyToNull(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return value.trim();
}

final serviceRequestFormProvider =
    NotifierProvider<ServiceRequestFormNotifier, ServiceRequestFormState>(
  ServiceRequestFormNotifier.new,
);
