import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/photo_attachment_picker.dart';
import '../application/work_order_list_notifier.dart';
import '../domain/work_order.dart';

class WorkOrderFormScreen extends ConsumerStatefulWidget {
  const WorkOrderFormScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<WorkOrderFormScreen> createState() =>
      _WorkOrderFormScreenState();
}

class _WorkOrderFormScreenState extends ConsumerState<WorkOrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _professionalController = TextEditingController();
  final _customerIdController = TextEditingController();
  final _quotationIdController = TextEditingController();
  final _requestIdController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _itemDescriptionController = TextEditingController();
  final _itemQuantityController = TextEditingController(text: '1');
  final _itemUnitPriceController = TextEditingController(text: '0');
  final _totalController = TextEditingController(text: '0');
  WorkOrderItemKind _itemKind = WorkOrderItemKind.service;
  final List<WorkOrderDraftItem> _items = [];
  List<SelectedPhotoAttachment> _attachments = const [];
  bool _isSaving = false;

  @override
  void dispose() {
    _professionalController.dispose();
    _customerIdController.dispose();
    _quotationIdController.dispose();
    _requestIdController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _itemDescriptionController.dispose();
    _itemQuantityController.dispose();
    _itemUnitPriceController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final total = _items.isEmpty
          ? (double.tryParse(_totalController.text.replaceAll(',', '.')) ?? 0)
          : _items.fold<int>(0, (sum, item) => sum + item.totalCents) / 100;
      final created = await ref.read(workOrderRepositoryProvider).create(
            WorkOrder(
              id: '',
              tenantId: '',
              number: 0,
              customerId: _customerIdController.text.trim(),
              requestId: _emptyToNull(_requestIdController.text),
              quotationId: _emptyToNull(_quotationIdController.text),
              status: WorkOrderStatus.opened,
              title: _titleController.text.trim(),
              description: _descriptionController.text.trim(),
              totalCents: (total * 100).round(),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            items: _items,
          );
      await _uploadAttachments(created);
      if (!mounted) return;
      if (widget.embedded) {
        Navigator.of(context).pop(true);
      } else {
        context.go(AppRoutes.workOrderDetail(created.id));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addItem() {
    final description = _itemDescriptionController.text.trim();
    final professional = _professionalController.text.trim();
    final quantity =
        num.tryParse(_itemQuantityController.text.replaceAll(',', '.'));
    final unitPrice = _moneyToCents(_itemUnitPriceController.text);
    if (description.length < 3 ||
        quantity == null ||
        quantity <= 0 ||
        unitPrice < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Preencha a linha com descrição e quantidade válidas.')),
      );
      return;
    }
    final fullDescription =
        professional.isEmpty ? description : '$professional - $description';
    setState(() {
      _items.add(
        WorkOrderDraftItem(
          kind: _itemKind,
          description: fullDescription,
          quantity: quantity,
          unitPriceCents: unitPrice,
        ),
      );
      _professionalController.clear();
      _itemDescriptionController.clear();
      _itemQuantityController.text = '1';
      _itemUnitPriceController.text = '0';
      _itemKind = WorkOrderItemKind.service;
      _totalController.text =
          (_items.fold<int>(0, (sum, item) => sum + item.totalCents) / 100)
              .toStringAsFixed(2)
              .replaceAll('.', ',');
    });
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title: 'Dados da OS',
              icon: Icons.engineering_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppFormGrid(
                    children: [
                      TextFormField(
                        controller: _customerIdController,
                        decoration: const InputDecoration(
                          labelText: 'Cliente *',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Informe o cliente.'
                                : null,
                      ),
                      TextFormField(
                        controller: _quotationIdController,
                        decoration: const InputDecoration(
                          labelText: 'Orçamento aprovado',
                          prefixIcon: Icon(Icons.request_quote_outlined),
                        ),
                      ),
                      TextFormField(
                        controller: _requestIdController,
                        decoration: const InputDecoration(
                          labelText: 'Chamado vinculado',
                          prefixIcon: Icon(Icons.support_agent_outlined),
                        ),
                      ),
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Título *',
                          prefixIcon: Icon(Icons.build_circle_outlined),
                        ),
                        validator: (value) =>
                            value == null || value.trim().length < 3
                                ? 'Informe um título.'
                                : null,
                      ),
                      TextFormField(
                        controller: _totalController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Valor previsto',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descrição *',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    minLines: 3,
                    maxLines: 5,
                    validator: (value) =>
                        value == null || value.trim().length < 3
                            ? 'Descreva a execução.'
                            : null,
                  ),
                  const SizedBox(height: 18),
                  AppFormSection(
                    title: 'Linhas de execução',
                    icon: Icons.view_list_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppFormGrid(
                          children: [
                            DropdownButtonFormField<WorkOrderItemKind>(
                              initialValue: _itemKind,
                              isExpanded: true,
                              decoration:
                                  const InputDecoration(labelText: 'Tipo'),
                              items: WorkOrderItemKind.values
                                  .map(
                                    (kind) => DropdownMenuItem(
                                      value: kind,
                                      child: Text(kind.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _isSaving
                                  ? null
                                  : (value) => setState(
                                        () => _itemKind =
                                            value ?? WorkOrderItemKind.service,
                                      ),
                            ),
                            TextFormField(
                              controller: _professionalController,
                              decoration: const InputDecoration(
                                labelText: 'Profissional / especialidade',
                              ),
                            ),
                            TextFormField(
                              controller: _itemDescriptionController,
                              decoration: const InputDecoration(
                                labelText: 'Descrição da linha',
                              ),
                            ),
                            TextFormField(
                              controller: _itemQuantityController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'HH / quantidade'),
                            ),
                            TextFormField(
                              controller: _itemUnitPriceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Valor unitário',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _isSaving ? null : _addItem,
                            icon: const Icon(Icons.add),
                            label: const Text('Adicionar linha'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_items.isEmpty)
                          const Text('Nenhuma linha adicionada.')
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
                                        '${entry.value.kind.label} · Qtd ${entry.value.quantity} · Total ${_formatMoney(entry.value.totalCents)}',
                                      ),
                                      trailing: IconButton(
                                        tooltip: 'Remover linha',
                                        onPressed: _isSaving
                                            ? null
                                            : () => setState(() {
                                                  _items.removeAt(entry.key);
                                                  _totalController
                                                      .text = (_items.fold<int>(
                                                              0,
                                                              (sum, item) =>
                                                                  sum +
                                                                  item.totalCents) /
                                                          100)
                                                      .toStringAsFixed(2)
                                                      .replaceAll('.', ',');
                                                }),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  PhotoAttachmentPicker(
                    photos: _attachments,
                    enabled: !_isSaving,
                    title: 'Arquivos da OS',
                    helper:
                        'Anexe fotos e documentos iniciais da execução, equipamento, cliente ou local.',
                    allowDocuments: true,
                    onChanged: (value) => setState(() => _attachments = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_isSaving ? 'Salvando anexos...' : 'Criar OS'),
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(title: const Text('Nova OS')),
      body: content,
    );
  }

  Future<void> _uploadAttachments(WorkOrder workOrder) async {
    final repo = ref.read(workOrderRepositoryProvider);
    for (final attachment in _attachments) {
      final bytes = attachment.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      await repo.uploadEvidence(
        tenantId: workOrder.tenantId,
        workOrderId: workOrder.id,
        kind: attachment.isImage ? 'photo' : 'document',
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
