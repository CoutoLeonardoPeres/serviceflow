import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/photo_attachment_picker.dart';
import '../../customers/application/customer_list_notifier.dart';
import '../../customers/data/customer_repository.dart';
import '../../customers/domain/customer.dart';
import '../../customers/presentation/customer_form_screen.dart';
import '../../settings/presentation/settings_screen.dart' show companySettingsProvider;
import '../application/service_request_form_notifier.dart';
import '../application/service_request_list_notifier.dart';
import '../domain/service_request.dart';
import 'widgets/weekly_availability_picker.dart';

final _activeCustomersForRequestProvider =
    FutureProvider.autoDispose<List<Customer>>((ref) async {
  final repo = ref.read(customerRepositoryProvider);
  final customers = <Customer>[];
  for (var page = 0; page < 5; page++) {
    final result = await repo.listPaged(
      filter: const CustomerFilter(isActive: true),
      page: page,
    );
    customers.addAll(result.items);
    if (result.items.length < 20) break;
  }
  return customers;
});

class ServiceRequestFormScreen extends ConsumerStatefulWidget {
  const ServiceRequestFormScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<ServiceRequestFormScreen> createState() =>
      _ServiceRequestFormScreenState();
}

class _ServiceRequestFormScreenState
    extends ConsumerState<ServiceRequestFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  Map<String, Set<String>> _availabilitySelection = {};

  String? _customerId;
  String? _categoryId;
  String? _priorityId;
  ServiceRequestChannel _channel = ServiceRequestChannel.whatsapp;
  Customer? _justCreatedCustomer;
  List<SelectedPhotoAttachment> _photos = const [];
  bool _isUploadingPhotos = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um cliente.')),
      );
      return;
    }

    await ref.read(serviceRequestFormProvider.notifier).createRequest(
          customerId: _customerId!,
          title: _titleController.text,
          description: _descriptionController.text,
          channel: _channel,
          categoryId: _categoryId,
          priorityId: _priorityId,
          availabilityNotes: buildAvailabilitySummary(_availabilitySelection),
        );

    final state = ref.read(serviceRequestFormProvider);
    if (!mounted) return;
    if (state is ServiceRequestFormSuccess) {
      if (_photos.isNotEmpty) {
        setState(() => _isUploadingPhotos = true);
        try {
          await _uploadPhotos(state.request);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
          return;
        } finally {
          if (mounted) setState(() => _isUploadingPhotos = false);
        }
      }
      if (!mounted) return;
      if (widget.embedded) {
        Navigator.of(context).pop(true);
      } else {
        context.go(AppRoutes.serviceRequestDetail(state.request.id));
      }
    }
  }

  Future<void> _openCreateCustomerDialog() async {
    final created = await showAppFormDialog<Object?>(
      context: context,
      title: 'Novo cliente',
      child: const CustomerFormScreen(
        embedded: true,
        returnCreatedCustomerOnCreate: true,
      ),
    );
    if (!mounted || created is! Customer) return;

    ref.invalidate(_activeCustomersForRequestProvider);
    setState(() {
      _justCreatedCustomer = created;
      _customerId = created.id;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cliente criado e selecionado para o chamado.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(_activeCustomersForRequestProvider);
    final categories = ref.watch(serviceRequestCategoriesProvider);
    final priorities = ref.watch(serviceRequestPrioritiesProvider);
    final formState = ref.watch(serviceRequestFormProvider);
    final isLoading =
        formState is ServiceRequestFormLoading || _isUploadingPhotos;

    final form = Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (formState is ServiceRequestFormError)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ErrorView(message: formState.error.userMessage),
            ),
          AppFormSection(
            title: 'Dados do atendimento',
            icon: Icons.support_agent_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppFormGrid(
                  children: [
                    AppFormFieldSpan(
                      widthFactor: 2.2,
                      child: customers.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (_, __) =>
                            const Text('Clientes indisponiveis.'),
                        data: (items) => _CustomerAutocompleteField(
                          customers: [
                            if (_justCreatedCustomer != null)
                              _justCreatedCustomer!,
                            ...items.where(
                              (customer) =>
                                  customer.id != _justCreatedCustomer?.id,
                            ),
                          ],
                          selectedCustomerId: _customerId,
                          enabled: !isLoading,
                          onChanged: (value) =>
                              setState(() => _customerId = value),
                          onCreateCustomer: _openCreateCustomerDialog,
                          trailing: priorities.when(
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                            data: (items) => DropdownButtonFormField<String>(
                              initialValue: _priorityId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Prioridade',
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('Sem prioridade'),
                                ),
                                ...items.map(
                                  (priority) => DropdownMenuItem(
                                    value: priority.id,
                                    child: Text(priority.name),
                                  ),
                                ),
                              ],
                              onChanged: isLoading
                                  ? null
                                  : (value) =>
                                      setState(() => _priorityId = value),
                            ),
                          ),
                        ),
                      ),
                    ),
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Título',
                        hintText: 'Ex.: Ar-condicionado sem refrigerar',
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.length < 3) return 'Informe um título.';
                        return null;
                      },
                    ),
                    DropdownButtonFormField<ServiceRequestChannel>(
                      initialValue: _channel,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Canal'),
                      items: ServiceRequestChannel.values
                          .map(
                            (channel) => DropdownMenuItem(
                              value: channel,
                              child: Text(channel.label),
                            ),
                          )
                          .toList(),
                      onChanged: isLoading
                          ? null
                          : (value) => setState(
                                () => _channel =
                                    value ?? ServiceRequestChannel.whatsapp,
                              ),
                    ),
                    categories.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (items) => DropdownButtonFormField<String>(
                        initialValue: _categoryId,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Categoria'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Sem categoria'),
                          ),
                          ...items.map(
                            (category) => DropdownMenuItem(
                              value: category.id,
                              child: Text(category.name),
                            ),
                          ),
                        ],
                        onChanged: isLoading
                            ? null
                            : (value) => setState(() => _categoryId = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descrição do problema',
                  ),
                  minLines: 4,
                  maxLines: 6,
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.length < 10) return 'Descreva o problema.';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Text(
                  'Disponibilidade do cliente',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Consumer(
                  builder: (context, ref, _) {
                    final companySettings = ref.watch(companySettingsProvider);
                    return companySettings.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const Text(
                        'Não foi possível carregar o horário de funcionamento.',
                      ),
                      data: (settings) => WeeklyAvailabilityPicker(
                        businessHours: settings.weeklySchedule,
                        selected: _availabilitySelection,
                        onChanged: (value) =>
                            setState(() => _availabilitySelection = value),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                PhotoAttachmentPicker(
                  photos: _photos,
                  enabled: !isLoading,
                  onChanged: (value) => setState(() => _photos = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: isLoading ? null : _submit,
            icon: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(
              _isUploadingPhotos ? 'Enviando fotos...' : 'Salvar chamado',
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) return form;

    return Scaffold(
      appBar: AppBar(title: const Text('Novo chamado')),
      body: form,
    );
  }

  Future<void> _uploadPhotos(ServiceRequest request) async {
    final repo = ref.read(serviceRequestRepositoryProvider);
    for (final photo in _photos) {
      final bytes = photo.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      await repo.uploadPhotoAttachment(
        tenantId: request.tenantId,
        requestId: request.id,
        fileName: photo.name,
        bytes: bytes,
        mimeType: photo.mimeType,
      );
    }
  }
}

class _CustomerAutocompleteField extends StatelessWidget {
  const _CustomerAutocompleteField({
    required this.customers,
    required this.selectedCustomerId,
    required this.enabled,
    required this.onChanged,
    required this.onCreateCustomer,
    this.trailing,
  });

  final List<Customer> customers;
  final String? selectedCustomerId;
  final bool enabled;
  final ValueChanged<String?> onChanged;
  final Future<void> Function() onCreateCustomer;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final selectedCustomer = customers
        .where((customer) => customer.id == selectedCustomerId)
        .cast<Customer?>()
        .firstOrNull;

    return FormField<String>(
      initialValue: selectedCustomerId,
      validator: (value) => value == null ? 'Selecione um cliente.' : null,
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Autocomplete<Customer>(
              displayStringForOption: (customer) => customer.name,
              initialValue: TextEditingValue(
                text: selectedCustomer?.name ?? '',
              ),
              optionsBuilder: (textEditingValue) {
                final query = _normalizeSearch(textEditingValue.text);
                final digits = _digitsOnly(textEditingValue.text);
                if (query.isEmpty && digits.isEmpty) {
                  return customers.take(12);
                }
                return customers.where(
                  (customer) {
                    final haystack = _normalizeSearch(
                      [
                        customer.name,
                        customer.tradeName,
                        customer.email,
                      ].whereType<String>().join(' '),
                    );
                    final numericHaystack = _digitsOnly(
                      [
                        customer.document,
                        customer.phone,
                      ].whereType<String>().join(' '),
                    );
                    return haystack.contains(query) ||
                        (digits.isNotEmpty && numericHaystack.contains(digits));
                  },
                ).take(12);
              },
              onSelected: enabled
                  ? (customer) {
                      field.didChange(customer.id);
                      onChanged(customer.id);
                    }
                  : null,
              fieldViewBuilder: (
                context,
                textController,
                focusNode,
                onFieldSubmitted,
              ) {
                return TextField(
                  controller: textController,
                  focusNode: focusNode,
                  enabled: enabled,
                  decoration: InputDecoration(
                    labelText: 'Cliente',
                    hintText: 'Buscar por nome, CPF/CNPJ ou telefone',
                    errorText: field.errorText,
                    suffixIcon: const Icon(Icons.search_outlined),
                  ),
                  onChanged: (_) {
                    if (field.value != null) {
                      field.didChange(null);
                      onChanged(null);
                    }
                  },
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                final theme = Theme.of(context);
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 12,
                    borderRadius: BorderRadius.circular(20),
                    color: theme.colorScheme.surface,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 320,
                        maxWidth: 420,
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shrinkWrap: true,
                        itemCount: options.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final customer = options.elementAt(index);
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              child: Text(customer.name[0].toUpperCase()),
                            ),
                            title: Text(
                              customer.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _customerSearchSubtitle(customer),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => onSelected(customer),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: enabled ? onCreateCustomer : null,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Cliente não cadastrado? Novo cliente'),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  Expanded(child: trailing!),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

String _customerSearchSubtitle(Customer customer) {
  final parts = [
    if (customer.document != null)
      customer.type.usesCpf
          ? _formatCpf(customer.document!)
          : _formatCnpj(customer.document!),
    if (customer.phone != null) _formatPhone(customer.phone!),
  ];
  return parts.isEmpty ? customer.type.label : parts.join(' | ');
}

String _normalizeSearch(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[áàâãä]'), 'a')
    .replaceAll(RegExp(r'[éèêë]'), 'e')
    .replaceAll(RegExp(r'[íìîï]'), 'i')
    .replaceAll(RegExp(r'[óòôõö]'), 'o')
    .replaceAll(RegExp(r'[úùûü]'), 'u')
    .replaceAll('ç', 'c')
    .trim();

String _digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

String _formatCpf(String value) {
  final digits = _digitsOnly(value);
  if (digits.length != 11) return value;
  return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9)}';
}

String _formatCnpj(String value) {
  final digits = _digitsOnly(value);
  if (digits.length != 14) return value;
  return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5, 8)}/${digits.substring(8, 12)}-${digits.substring(12)}';
}

String _formatPhone(String value) {
  final digits = _digitsOnly(value);
  if (digits.length == 10) {
    return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
  }
  if (digits.length == 11) {
    return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7)}';
  }
  return value;
}
