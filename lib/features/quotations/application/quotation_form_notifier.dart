import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../domain/quotation.dart';
import 'quotation_list_notifier.dart';

sealed class QuotationFormState {
  const QuotationFormState();
}

final class QuotationFormIdle extends QuotationFormState {
  const QuotationFormIdle();
}

final class QuotationFormLoading extends QuotationFormState {
  const QuotationFormLoading();
}

final class QuotationFormSuccess extends QuotationFormState {
  const QuotationFormSuccess(this.quotation);
  final Quotation quotation;
}

final class QuotationFormError extends QuotationFormState {
  const QuotationFormError(this.error);
  final AppError error;
}

class QuotationFormNotifier extends Notifier<QuotationFormState> {
  @override
  QuotationFormState build() => const QuotationFormIdle();

  Future<void> createQuotation({
    required String customerId,
    String? requestId,
    DateTime? validUntil,
    String? notes,
    String? terms,
    required List<QuotationDraftItem> items,
  }) async {
    state = const QuotationFormLoading();
    if (items.isEmpty) {
      state = const QuotationFormError(
        BusinessRuleError('Inclua ao menos um item.'),
      );
      return;
    }

    final quotation = Quotation(
      id: '',
      tenantId: '',
      number: 0,
      customerId: customerId,
      requestId: _emptyToNull(requestId),
      status: QuotationStatus.draft,
      validUntil: validUntil,
      subtotalCents: 0,
      discountCents: 0,
      taxCents: 0,
      totalCents: 0,
      notes: _emptyToNull(notes?.trim()),
      terms: _emptyToNull(terms?.trim()),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      final created = await ref.read(quotationRepositoryProvider).create(
            quotation: quotation,
            items: items,
          );
      ref.read(quotationListProvider.notifier).addOrReplace(created);
      state = QuotationFormSuccess(created);
    } on AppError catch (e) {
      state = QuotationFormError(e);
    } catch (e) {
      state = QuotationFormError(
        UnexpectedError('Erro ao criar orcamento.', e.toString()),
      );
    }
  }

  void reset() => state = const QuotationFormIdle();
}

String? _emptyToNull(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return value.trim();
}

final quotationFormProvider =
    NotifierProvider<QuotationFormNotifier, QuotationFormState>(
  QuotationFormNotifier.new,
);
