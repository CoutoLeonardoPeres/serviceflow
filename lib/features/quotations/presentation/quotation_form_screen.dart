import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/photo_attachment_picker.dart';
import '../../customers/application/customer_list_notifier.dart';
import '../../customers/data/customer_repository.dart';
import '../../customers/domain/customer.dart';
import '../../service_requests/application/service_request_list_notifier.dart';
import '../../service_requests/data/service_request_repository.dart';
import '../../service_requests/domain/service_request.dart';
import '../application/quotation_form_notifier.dart';
import '../application/quotation_list_notifier.dart';
import '../domain/quotation.dart';

final _quoteCustomersProvider =
    FutureProvider.autoDispose<List<Customer>>((ref) async {
  final result = await ref.read(customerRepositoryProvider).listPaged(
        filter: const CustomerFilter(isActive: true),
      );
  return result.items.take(30).toList();
});

final _quoteRequestsProvider =
    FutureProvider.autoDispose<List<ServiceRequest>>((ref) async {
  final result = await ref.read(serviceRequestRepositoryProvider).listPaged(
        filter: const ServiceRequestFilter(),
      );
  return result.items.where((request) => !request.status.isTerminal).toList();
});

class QuotationFormScreen extends ConsumerStatefulWidget {
  const QuotationFormScreen({
    super.key,
    this.embedded = false,
    this.initialRequestId,
  });

  final bool embedded;

  /// Chamado de origem, quando o orçamento nasce de uma visita técnica na
  /// agenda. Pré-seleciona o chamado e o cliente dele.
  final String? initialRequestId;

  @override
  ConsumerState<QuotationFormScreen> createState() =>
      _QuotationFormScreenState();
}

class _QuotationFormScreenState extends ConsumerState<QuotationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _professionalCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  Customer? _customer;
  ServiceRequest? _request;
  bool _initialRequestApplied = false;

  /// Pré-seleciona o chamado (e o cliente dele) quando o orçamento nasce de
  /// uma visita na agenda. Roda uma vez, assim que a lista de chamados chega —
  /// o `initialRequestId` sozinho não basta porque o dropdown compara objetos.
  void _applyInitialRequest(List<ServiceRequest> requests) {
    final wanted = widget.initialRequestId;
    if (wanted == null || _initialRequestApplied) return;

    final match = requests
        .cast<ServiceRequest?>()
        .firstWhere((request) => request?.id == wanted, orElse: () => null);
    if (match == null) return;

    _initialRequestApplied = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final customer = ref.read(_quoteCustomersProvider).maybeWhen(
            data: (items) => items
                .cast<Customer?>()
                .firstWhere(
                  (item) => item?.id == match.customerId,
                  orElse: () => null,
                ),
            orElse: () => null,
          );
      setState(() {
        _request = match;
        _customer ??= customer;
      });
    });
  }
  QuotationItemKind _kind = QuotationItemKind.service;
  DateTime _validUntil = DateTime.now().add(const Duration(days: 15));
  final List<QuotationDraftItem> _items = [];
  List<SelectedPhotoAttachment> _attachments = const [];
  bool _isUploadingAttachments = false;

  @override
  void dispose() {
    _professionalCtrl.dispose();
    _descriptionCtrl.dispose();
    _quantityCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickValidUntil() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _validUntil,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (date == null) return;
    setState(() => _validUntil = date);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final customer = _customer;
    if (customer == null) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Adicione ao menos uma linha no orçamento.')),
      );
      return;
    }

    await ref.read(quotationFormProvider.notifier).createQuotation(
          customerId: customer.id,
          requestId: _request?.id,
          validUntil: _validUntil,
          notes: _notesCtrl.text,
          items: _items,
        );

    final state = ref.read(quotationFormProvider);
    if (!mounted) return;
    if (state is QuotationFormSuccess) {
      if (_attachments.isNotEmpty) {
        setState(() => _isUploadingAttachments = true);
        try {
          await _uploadAttachments(state.quotation);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
          return;
        } finally {
          if (mounted) setState(() => _isUploadingAttachments = false);
        }
      }
      if (!mounted) return;
      if (widget.embedded) {
        Navigator.of(context).pop(true);
      } else {
        context.go(AppRoutes.quotationDetail(state.quotation.id));
      }
    }
  }

  void _addDraftItem() {
    final description = _descriptionCtrl.text.trim();
    final professional = _professionalCtrl.text.trim();
    final quantity = num.tryParse(_quantityCtrl.text.replaceAll(',', '.'));
    final price = _moneyToCents(_priceCtrl.text);
    final cost = _moneyToCents(_costCtrl.text);

    if (description.length < 3 ||
        quantity == null ||
        quantity <= 0 ||
        price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Preencha a linha com descrição, quantidade e valor válidos.')),
      );
      return;
    }

    final fullDescription =
        professional.isEmpty ? description : '$professional - $description';

    setState(() {
      _items.add(
        QuotationDraftItem(
          kind: _kind,
          description: fullDescription,
          quantity: quantity,
          unitPriceCents: price,
          unitCostCents: cost,
        ),
      );
      _professionalCtrl.clear();
      _descriptionCtrl.clear();
      _quantityCtrl.text = '1';
      _priceCtrl.clear();
      _costCtrl.clear();
      _kind = QuotationItemKind.service;
    });
  }

  int get _draftTotalCents =>
      _items.fold<int>(0, (sum, item) => sum + item.totalCents);

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(_quoteCustomersProvider);
    final requests = ref.watch(_quoteRequestsProvider);
    final formState = ref.watch(quotationFormProvider);
    final isLoading =
        formState is QuotationFormLoading || _isUploadingAttachments;
    final dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');

    final form = Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (formState is QuotationFormError)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ErrorView(message: formState.error.userMessage),
            ),
          AppFormSection(
            title: 'Dados da proposta',
            icon: Icons.request_quote_outlined,
            child: AppFormGrid(
              children: [
                customers.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Clientes indisponíveis.'),
                  data: (items) => DropdownButtonFormField<Customer>(
                    initialValue: _customer,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Cliente'),
                    items: items
                        .map(
                          (customer) => DropdownMenuItem(
                            value: customer,
                            child: Text(customer.name),
                          ),
                        )
                        .toList(),
                    onChanged: isLoading
                        ? null
                        : (value) => setState(() => _customer = value),
                    validator: (value) =>
                        value == null ? 'Selecione um cliente.' : null,
                  ),
                ),
                requests.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (items) {
                    _applyInitialRequest(items);
                    return DropdownButtonFormField<ServiceRequest>(
                      initialValue: _request,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Chamado opcional'),
                      items: items
                          .map(
                            (request) => DropdownMenuItem(
                              value: request,
                              child: Text(
                                '${request.displayNumber} · ${request.title}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: isLoading
                          ? null
                          : (value) => setState(() => _request = value),
                    );
                  },
                ),
                OutlinedButton.icon(
                  onPressed: isLoading ? null : _pickValidUntil,
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Validade: ${dateFormat.format(_validUntil)}'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppFormSection(
            title: 'Linhas do orçamento',
            icon: Icons.inventory_2_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppFormGrid(
                  children: [
                    DropdownButtonFormField<QuotationItemKind>(
                      initialValue: _kind,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Tipo'),
                      items: QuotationItemKind.values
                          .map(
                            (kind) => DropdownMenuItem(
                              value: kind,
                              child: Text(kind.label),
                            ),
                          )
                          .toList(),
                      onChanged: isLoading
                          ? null
                          : (value) => setState(
                                () =>
                                    _kind = value ?? QuotationItemKind.service,
                              ),
                    ),
                    TextFormField(
                      controller: _professionalCtrl,
                      enabled: !isLoading,
                      decoration: const InputDecoration(
                        labelText: 'Profissional / especialidade',
                      ),
                    ),
                    TextFormField(
                      controller: _descriptionCtrl,
                      enabled: !isLoading,
                      decoration: const InputDecoration(
                          labelText: 'Descrição da linha'),
                    ),
                    TextFormField(
                      controller: _quantityCtrl,
                      enabled: !isLoading,
                      decoration:
                          const InputDecoration(labelText: 'Quantidade'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                      ],
                    ),
                    TextFormField(
                      controller: _priceCtrl,
                      enabled: !isLoading,
                      decoration: const InputDecoration(labelText: 'Preço R\$'),
                      keyboardType: TextInputType.number,
                    ),
                    TextFormField(
                      controller: _costCtrl,
                      enabled: !isLoading,
                      decoration: const InputDecoration(labelText: 'Custo R\$'),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: isLoading ? null : _addDraftItem,
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar linha'),
                  ),
                ),
                const SizedBox(height: 14),
                if (_items.isEmpty)
                  const Text('Nenhuma linha adicionada ainda.')
                else
                  Column(
                    children: _items
                        .asMap()
                        .entries
                        .map(
                          (entry) => Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              title: Text(entry.value.description),
                              subtitle: Text(
                                '${entry.value.kind.label} · Qtd ${entry.value.quantity} · Venda ${_formatMoney(entry.value.unitPriceCents)} · Custo ${_formatMoney(entry.value.unitCostCents)}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Remover linha',
                                onPressed: isLoading
                                    ? null
                                    : () => setState(() {
                                          _items.removeAt(entry.key);
                                        }),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 10),
                Text(
                  'Total previsto do orçamento: ${_formatMoney(_draftTotalCents)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesCtrl,
                  enabled: !isLoading,
                  decoration: const InputDecoration(labelText: 'Observações'),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 14),
                PhotoAttachmentPicker(
                  photos: _attachments,
                  enabled: !isLoading,
                  title: 'Arquivos do orçamento',
                  helper:
                      'Anexe fotos e documentos do equipamento, ambiente, peça ou serviço cotado.',
                  allowDocuments: true,
                  onChanged: (value) => setState(() => _attachments = value),
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
                : const Icon(Icons.save_outlined),
            label: Text(
              _isUploadingAttachments
                  ? 'Enviando anexos...'
                  : 'Salvar orçamento',
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) return form;

    return Scaffold(
      appBar: AppBar(title: const Text('Novo orçamento')),
      body: form,
    );
  }

  Future<void> _uploadAttachments(Quotation quotation) async {
    final repo = ref.read(quotationRepositoryProvider);
    for (final attachment in _attachments) {
      final bytes = attachment.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      await repo.uploadAttachment(
        tenantId: quotation.tenantId,
        quotationId: quotation.id,
        fileName: attachment.name,
        bytes: bytes,
        mimeType: attachment.mimeType,
      );
    }
  }
}

int _moneyToCents(String value) {
  final normalized = value
      .replaceAll(RegExp(r'[^0-9,.-]'), '')
      .replaceAll('.', '')
      .replaceAll(',', '.');
  final parsed = double.tryParse(normalized);
  if (parsed == null) return 0;
  return (parsed * 100).round();
}

String _formatMoney(int cents) {
  final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
  return currency.format(cents / 100);
}
