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
import '../../customers/domain/customer_search.dart';
import '../../customers/presentation/widgets/customer_search_field.dart';
import '../../professionals/application/service_professional_list_notifier.dart';
import '../../professionals/domain/service_professional.dart';
import '../../scheduling/application/appointment_list_notifier.dart';
import '../../scheduling/data/appointment_repository.dart';
import '../../scheduling/domain/appointment.dart';
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

/// Profissionais ativos, para a coluna "Profissional" das linhas.
final _quoteProfessionalsProvider =
    FutureProvider.autoDispose<List<ServiceProfessional>>((ref) async {
  final result = await ref.read(serviceProfessionalRepositoryProvider).list();
  return result.where((professional) => professional.isActive).toList();
});

/// Id do profissional que atendeu o chamado — vira o valor inicial da coluna
/// profissional, e continua trocável linha a linha.
final _requestTechnicianProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, requestId) async {
  final appointments = await ref.read(appointmentRepositoryProvider).list(
        filter: AppointmentFilter(serviceRequestId: requestId),
      );
  for (final appointment in appointments) {
    if (appointment.status == AppointmentStatus.cancelled) continue;
    if (appointment.technicians.isNotEmpty) {
      return appointment.technicians.first.professionalId;
    }
  }
  return null;
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
  final _notesCtrl = TextEditingController();
  final _taxRateCtrl = TextEditingController(text: '0');

  // Três planilhas separadas, cada uma com os tipos que fazem sentido nela.
  final List<_QuoteLine> _serviceLines = [_QuoteLine(QuotationItemKind.service)];
  final List<_QuoteLine> _materialLines = [
    _QuoteLine(QuotationItemKind.material),
  ];
  final List<_QuoteLine> _expenseLines = [_QuoteLine(QuotationItemKind.travel)];

  List<_QuoteLine> get _allLines =>
      [..._serviceLines, ..._materialLines, ..._expenseLines];
  Customer? _customer;
  ServiceRequest? _request;
  bool _initialRequestApplied = false;

  /// Cliente para o qual o chamado já foi escolhido sozinho — evita repetir a
  /// seleção depois que o usuário limpar o campo de propósito.
  String? _autoPickedRequestFor;

  /// Profissionais cujas despesas já foram lançadas — evita duplicar a cada
  /// nova linha de serviço com a mesma pessoa.
  final Set<String> _expenseAppliedFor = {};

  /// Escolher o cliente já traz o chamado dele quando só existe um em aberto.
  /// Sem isso o campo continuava vazio: o Autocomplete não abre a lista com o
  /// texto em branco, então filtrar por cliente não bastava para "puxar".
  void _autoPickSingleRequest(List<ServiceRequest> visible) {
    final customer = _customer;
    if (customer == null ||
        _request != null ||
        _autoPickedRequestFor == customer.id ||
        visible.length != 1) {
      return;
    }
    _autoPickedRequestFor = customer.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _request = visible.first);
    });
  }

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
  DateTime _validUntil = DateTime.now().add(const Duration(days: 15));
  List<SelectedPhotoAttachment> _attachments = const [];
  bool _isUploadingAttachments = false;

  @override
  void dispose() {
    for (final line in _allLines) {
      line.dispose();
    }
    _notesCtrl.dispose();
    _taxRateCtrl.dispose();
    super.dispose();
  }

  /// Linhas preenchidas viram itens. Linha em branco é ignorada: cada grade
  /// começa com uma vazia e sempre sobra a última em edição.
  List<QuotationDraftItem> _itemsOf(List<_QuoteLine> lines) =>
      lines.where((line) => line.isFilled).map((line) => line.toItem()).toList();

  int _subtotalOf(List<_QuoteLine> lines) => _itemsOf(lines)
      .fold<int>(0, (sum, item) => sum + item.totalCents);

  /// Base de cálculo do imposto: tudo que foi cotado, antes do próprio imposto.
  int get _subtotalCents => _subtotalOf(_allLines);

  double get _taxRate {
    final parsed =
        double.tryParse(_taxRateCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    return parsed.clamp(0, 100).toDouble();
  }

  int get _taxCents => (_subtotalCents * _taxRate / 100).round();

  int get _draftTotalCents => _subtotalCents + _taxCents;

  /// Itens enviados ao banco: os três grupos mais a linha de imposto, que é
  /// calculada e não digitada.
  List<QuotationDraftItem> get _draftItems => [
        ..._itemsOf(_serviceLines),
        ..._itemsOf(_materialLines),
        ..._itemsOf(_expenseLines),
        if (_taxCents > 0)
          QuotationDraftItem(
            kind: QuotationItemKind.tax,
            description:
                'Impostos (${_taxRate.toStringAsFixed(2).replaceAll('.', ',')}%)',
            quantity: 1,
            unitPriceCents: _taxCents,
            unitCostCents: 0,
          ),
      ];

  void _addLine(List<_QuoteLine> lines, QuotationItemKind kind) =>
      setState(() => lines.add(_QuoteLine(kind)));

  void _removeLine(List<_QuoteLine> lines, int index, QuotationItemKind kind) {
    setState(() {
      lines.removeAt(index).dispose();
      if (lines.isEmpty) lines.add(_QuoteLine(kind));
    });
  }

  /// Escolher o profissional traz o valor da hora dele para a linha e, na
  /// primeira vez, lança as despesas cadastradas (transporte, refeição,
  /// deslocamento, hospedagem, outros). Tudo continua editável.
  void _pickProfessional(
    _QuoteLine line,
    String? professionalId,
    List<ServiceProfessional> people,
  ) {
    final professional = professionalId == null
        ? null
        : people.cast<ServiceProfessional?>().firstWhere(
              (item) => item?.id == professionalId,
              orElse: () => null,
            );

    setState(() {
      line.professionalId = professional?.id;
      line.professionalName = professional?.name;
      if (professional == null) return;

      // Não sobrescreve valor já digitado — só preenche o que está em branco.
      if (professional.hourlyRateCents > 0) {
        if (line.priceCtrl.text.trim().isEmpty) {
          line.priceCtrl.text = _centsToInput(professional.hourlyRateCents);
        }
        if (line.costCtrl.text.trim().isEmpty) {
          line.costCtrl.text = _centsToInput(professional.hourlyRateCents);
        }
      }
      if (line.descriptionCtrl.text.trim().isEmpty &&
          line.kind == QuotationItemKind.laborHour) {
        line.descriptionCtrl.text = 'Hora técnica — ${professional.name}';
      }
      _applyProfessionalExpenses(professional);
    });
  }

  /// Lança as despesas do profissional no card de despesas extras, uma vez por
  /// profissional. Só ocupa linhas em branco; não mexe no que já foi digitado.
  void _applyProfessionalExpenses(ServiceProfessional professional) {
    if (!_expenseAppliedFor.add(professional.id)) return;

    final expenses = <(String, int, QuotationItemKind)>[
      ('Transporte', professional.transportCostCents, QuotationItemKind.travel),
      ('Refeição', professional.mealCostCents, QuotationItemKind.other),
      (
        'Deslocamento',
        professional.travelCostCents,
        QuotationItemKind.travel,
      ),
      ('Hospedagem', professional.lodgingCostCents, QuotationItemKind.other),
      ('Outros custos', professional.otherCostCents, QuotationItemKind.other),
    ].where((expense) => expense.$2 > 0);

    for (final (label, cents, kind) in expenses) {
      final line = _expenseLines.firstWhere(
        (candidate) => !candidate.isFilled && candidate.isBlank,
        orElse: () {
          final created = _QuoteLine(kind);
          _expenseLines.add(created);
          return created;
        },
      );
      line.kind = kind;
      line.professionalId = professional.id;
      line.professionalName = professional.name;
      line.descriptionCtrl.text = '$label — ${professional.name}';
      line.quantityCtrl.text = '1';
      line.priceCtrl.text = _centsToInput(cents);
      line.costCtrl.text = _centsToInput(cents);
    }
  }

  /// Preenche o profissional das linhas de serviço ainda em branco com quem
  /// atendeu o chamado. Não sobrescreve o que o usuário já escolheu.
  void _applyRequestTechnician(
    String? professionalId,
    List<ServiceProfessional> people,
  ) {
    if (professionalId == null || professionalId.isEmpty) return;
    if (_serviceLines.every((line) => line.professionalId != null)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final line in _serviceLines) {
        if (line.professionalId == null) {
          _pickProfessional(line, professionalId, people);
        }
      }
    });
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
    if (_draftItems.isEmpty) {
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
          items: _draftItems,
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

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(_quoteCustomersProvider);
    final requests = ref.watch(_quoteRequestsProvider);
    final professionals = ref.watch(_quoteProfessionalsProvider);
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
                AppFormFieldSpan(
                  widthFactor: 2,
                  child: customers.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const Text('Clientes indisponíveis.'),
                    data: (items) => CustomerSearchField(
                      // O Autocomplete só lê o texto inicial na primeira
                      // construção: sem trocar a key, escolher um chamado
                      // mudaria o cliente no estado e deixaria o campo vazio
                      // na tela.
                      key: ValueKey('customer-${_customer?.id ?? ''}'),
                      customers: items,
                      selected: _customer,
                      enabled: !isLoading,
                      onChanged: (value) => setState(() {
                        _customer = value;
                        // Escolher outro cliente invalida o chamado que estava
                        // selecionado — ele é de outra pessoa.
                        if (value != null && _request?.customerId != value.id) {
                          _request = null;
                        }
                      }),
                      validator: (value) =>
                          value == null ? 'Selecione um cliente.' : null,
                    ),
                  ),
                ),
                AppFormFieldSpan(
                  widthFactor: 2,
                  child: requests.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (items) {
                      _applyInitialRequest(items);
                      // Com cliente escolhido, o campo de chamado já abre só
                      // com os chamados dele.
                      final customer = _customer;
                      final visible = customer == null
                          ? items
                          : items
                              .where((r) => r.customerId == customer.id)
                              .toList();
                      _autoPickSingleRequest(visible);
                      return _RequestSearchField(
                        // Mesma razão da key do cliente: trocar o cliente
                        // limpa o chamado, e o campo precisa refletir isso.
                        key: ValueKey(
                          'request-${_request?.id ?? ''}-${customer?.id ?? ''}',
                        ),
                        requests: visible,
                        selected: _request,
                        enabled: !isLoading,
                        helper: customer == null
                            ? null
                            : visible.isEmpty
                                ? 'Nenhum chamado aberto para ${customer.name}.'
                                : visible.length == 1
                                    ? null
                                    : '${visible.length} chamados abertos '
                                        'deste cliente — toque para escolher.',
                        onChanged: (value) => setState(() {
                          _request = value;
                          // Trocar o chamado troca o cliente junto: orçamento
                          // de um chamado é sempre do cliente dele.
                          if (value != null) {
                            _customer = customers.maybeWhen(
                                  data: (list) => list
                                      .cast<Customer?>()
                                      .firstWhere(
                                        (item) => item?.id == value.customerId,
                                        orElse: () => null,
                                      ),
                                  orElse: () => null,
                                ) ??
                                _customer;
                          }
                        }),
                      );
                    },
                  ),
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
          // Quem atendeu o chamado vira o valor inicial da coluna
          // profissional das linhas de serviço.
          Builder(
            builder: (_) {
              final request = _request;
              if (request != null) {
                final people = ref.watch(_quoteProfessionalsProvider).value;
                if (people != null) {
                  ref
                      .watch(_requestTechnicianProvider(request.id))
                      .whenData((id) => _applyRequestTechnician(id, people));
                }
              }
              return const SizedBox.shrink();
            },
          ),
          professionals.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text('Profissionais indisponíveis.'),
            data: (people) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LinesCard(
                  title: 'Serviços e horas técnicas',
                  icon: Icons.handyman_outlined,
                  lines: _serviceLines,
                  kinds: const [
                    QuotationItemKind.service,
                    QuotationItemKind.laborHour,
                  ],
                  professionals: people,
                  showProfessional: true,
                  enabled: !isLoading,
                  subtotalCents: _subtotalOf(_serviceLines),
                  onChanged: () => setState(() {}),
                  onPickProfessional: (line, id) =>
                      _pickProfessional(line, id, people),
                  onAdd: () =>
                      _addLine(_serviceLines, QuotationItemKind.service),
                  onRemove: (index) => _removeLine(
                    _serviceLines,
                    index,
                    QuotationItemKind.service,
                  ),
                ),
                const SizedBox(height: 16),
                _LinesCard(
                  title: 'Materiais e equipamentos',
                  icon: Icons.inventory_2_outlined,
                  lines: _materialLines,
                  kinds: const [
                    QuotationItemKind.material,
                    QuotationItemKind.equipment,
                  ],
                  professionals: people,
                  showProfessional: false,
                  enabled: !isLoading,
                  subtotalCents: _subtotalOf(_materialLines),
                  onChanged: () => setState(() {}),
                  onPickProfessional: (line, id) =>
                      _pickProfessional(line, id, people),
                  onAdd: () =>
                      _addLine(_materialLines, QuotationItemKind.material),
                  onRemove: (index) => _removeLine(
                    _materialLines,
                    index,
                    QuotationItemKind.material,
                  ),
                ),
                const SizedBox(height: 16),
                _LinesCard(
                  title: 'Despesas extras',
                  icon: Icons.local_shipping_outlined,
                  helper: 'Deslocamento, refeição, estacionamento, pedágio.',
                  lines: _expenseLines,
                  kinds: const [
                    QuotationItemKind.travel,
                    QuotationItemKind.other,
                  ],
                  professionals: people,
                  showProfessional: false,
                  enabled: !isLoading,
                  subtotalCents: _subtotalOf(_expenseLines),
                  onChanged: () => setState(() {}),
                  onPickProfessional: (line, id) =>
                      _pickProfessional(line, id, people),
                  onAdd: () =>
                      _addLine(_expenseLines, QuotationItemKind.travel),
                  onRemove: (index) => _removeLine(
                    _expenseLines,
                    index,
                    QuotationItemKind.travel,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppFormSection(
            title: 'Fechamento',
            icon: Icons.calculate_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TotalRow(label: 'Subtotal', cents: _subtotalCents),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: TextFormField(
                        controller: _taxRateCtrl,
                        enabled: !isLoading,
                        decoration: const InputDecoration(
                          labelText: 'Alíquota %',
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                        ],
                        // O imposto é calculado sobre o subtotal, não digitado
                        // linha a linha.
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _TotalRow(label: 'Impostos', cents: _taxCents),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _TotalRow(
                  label: 'Total do orçamento',
                  cents: _draftTotalCents,
                  emphasis: true,
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

/// Uma linha da planilha. Guarda os próprios controllers para permitir edição
/// in-place — antes as linhas eram somente-leitura depois de adicionadas.
class _QuoteLine {
  _QuoteLine(this.kind);

  final descriptionCtrl = TextEditingController();
  final quantityCtrl = TextEditingController(text: '1');
  final priceCtrl = TextEditingController();
  final costCtrl = TextEditingController();
  QuotationItemKind kind;

  /// Guarda o id (e não só o nome) para conseguir puxar hora e despesas do
  /// cadastro do profissional.
  String? professionalId;
  String? professionalName;

  /// Linha ainda intocada: serve para reaproveitar antes de criar outra.
  bool get isBlank =>
      descriptionCtrl.text.trim().isEmpty &&
      priceCtrl.text.trim().isEmpty &&
      costCtrl.text.trim().isEmpty;

  bool get isFilled =>
      descriptionCtrl.text.trim().length >= 3 &&
      (num.tryParse(quantityCtrl.text.replaceAll(',', '.')) ?? 0) > 0 &&
      _moneyToCents(priceCtrl.text) > 0;

  num get quantity => num.tryParse(quantityCtrl.text.replaceAll(',', '.')) ?? 0;
  int get unitPriceCents => _moneyToCents(priceCtrl.text);
  int get unitCostCents => _moneyToCents(costCtrl.text);
  int get totalCents => (unitPriceCents * quantity).round();

  QuotationDraftItem toItem() {
    final description = descriptionCtrl.text.trim();
    final who = professionalName?.trim() ?? '';
    return QuotationDraftItem(
      kind: kind,
      // O profissional vira prefixo da descrição: o item de orçamento não tem
      // coluna própria para ele no banco.
      description: who.isEmpty ? description : '$who - $description',
      quantity: quantity,
      unitPriceCents: unitPriceCents,
      unitCostCents: unitCostCents,
    );
  }

  void dispose() {
    descriptionCtrl.dispose();
    quantityCtrl.dispose();
    priceCtrl.dispose();
    costCtrl.dispose();
  }
}

/// Um card com título, planilha e subtotal. Separa serviços, materiais e
/// despesas — cada bloco tem tipos e colunas próprios.
class _LinesCard extends StatelessWidget {
  const _LinesCard({
    required this.title,
    required this.icon,
    required this.lines,
    required this.kinds,
    required this.professionals,
    required this.showProfessional,
    required this.enabled,
    required this.subtotalCents,
    required this.onChanged,
    required this.onAdd,
    required this.onRemove,
    required this.onPickProfessional,
    this.helper,
  });

  final String title;
  final IconData icon;
  final String? helper;
  final List<_QuoteLine> lines;
  final List<QuotationItemKind> kinds;
  final List<ServiceProfessional> professionals;
  final bool showProfessional;
  final bool enabled;
  final int subtotalCents;
  final VoidCallback onChanged;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final void Function(_QuoteLine line, String? professionalId)
      onPickProfessional;

  @override
  Widget build(BuildContext context) {
    return AppFormSection(
      title: title,
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (helper != null) ...[
            Text(helper!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
          ],
          _LinesSpreadsheet(
            lines: lines,
            kinds: kinds,
            professionals: professionals,
            showProfessional: showProfessional,
            enabled: enabled,
            onChanged: onChanged,
            onRemove: onRemove,
            onPickProfessional: onPickProfessional,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: enabled ? onAdd : null,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar linha'),
              ),
              const Spacer(),
              Text(
                'Subtotal: ${_formatMoney(subtotalCents)}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.cents,
    this.emphasis = false,
  });

  final String label;
  final int cents;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasis
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)
        : theme.textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(_formatMoney(cents), style: style),
      ],
    );
  }
}

/// Grade editável no estilo planilha: cabeçalho fixo, uma linha por item,
/// rolagem horizontal quando a tela é estreita.
class _LinesSpreadsheet extends StatelessWidget {
  const _LinesSpreadsheet({
    required this.lines,
    required this.kinds,
    required this.professionals,
    required this.showProfessional,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
    required this.onPickProfessional,
  });

  final List<_QuoteLine> lines;

  /// Escolher o profissional puxa hora e despesas do cadastro dele.
  final void Function(_QuoteLine line, String? professionalId)
      onPickProfessional;

  /// Tipos oferecidos nesta grade. Material não aparece no card de serviço.
  final List<QuotationItemKind> kinds;
  final List<ServiceProfessional> professionals;

  /// Só o card de serviço tem coluna de profissional.
  final bool showProfessional;
  final bool enabled;
  final VoidCallback onChanged;
  final ValueChanged<int> onRemove;

  static const _wKind = 130.0;
  static const _wProfessional = 190.0;
  static const _wDescription = 280.0;
  static const _wQuantity = 90.0;
  static const _wMoney = 120.0;
  static const _wTotal = 130.0;
  static const _wAction = 48.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: _wKind +
              (showProfessional ? _wProfessional : 0) +
              _wDescription +
              _wQuantity +
              _wMoney * 2 +
              _wTotal +
              _wAction,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  SizedBox(width: _wKind, child: Text('Tipo', style: headerStyle)),
                  if (showProfessional)
                    SizedBox(
                      width: _wProfessional,
                      child: Text('Profissional', style: headerStyle),
                    ),
                  SizedBox(
                    width: _wDescription,
                    child: Text('Descrição', style: headerStyle),
                  ),
                  SizedBox(
                    width: _wQuantity,
                    child: Text('Qtd', style: headerStyle),
                  ),
                  SizedBox(
                    width: _wMoney,
                    child: Text('Preço R\$', style: headerStyle),
                  ),
                  SizedBox(
                    width: _wMoney,
                    child: Text('Custo R\$', style: headerStyle),
                  ),
                  SizedBox(
                    width: _wTotal,
                    child: Text('Total', style: headerStyle),
                  ),
                  const SizedBox(width: _wAction),
                ],
              ),
            ),
            const SizedBox(height: 4),
            ...lines.asMap().entries.map((entry) {
              final index = entry.key;
              final line = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: _wKind,
                      child: DropdownButtonFormField<QuotationItemKind>(
                        initialValue: line.kind,
                        isExpanded: true,
                        isDense: true,
                        decoration: _cellDecoration,
                        items: kinds
                            .map(
                              (kind) => DropdownMenuItem(
                                value: kind,
                                child: Text(
                                  kind.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: enabled
                            ? (value) {
                                line.kind = value ?? kinds.first;
                                onChanged();
                              }
                            : null,
                      ),
                    ),
                    if (showProfessional)
                      SizedBox(
                        width: _wProfessional,
                        child: DropdownButtonFormField<String>(
                          initialValue: _professionalValue(line),
                          isExpanded: true,
                          isDense: true,
                          decoration: _cellDecoration,
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('—'),
                            ),
                            ...professionals.map(
                              (professional) => DropdownMenuItem(
                                value: professional.id,
                                child: Text(
                                  professional.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: enabled
                              ? (value) => onPickProfessional(line, value)
                              : null,
                        ),
                      ),
                    SizedBox(
                      width: _wDescription,
                      child: TextField(
                        controller: line.descriptionCtrl,
                        enabled: enabled,
                        decoration: _cellDecoration,
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                    SizedBox(
                      width: _wQuantity,
                      child: TextField(
                        controller: line.quantityCtrl,
                        enabled: enabled,
                        textAlign: TextAlign.right,
                        decoration: _cellDecoration,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                        ],
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                    SizedBox(
                      width: _wMoney,
                      child: TextField(
                        controller: line.priceCtrl,
                        enabled: enabled,
                        textAlign: TextAlign.right,
                        decoration: _cellDecoration,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                    SizedBox(
                      width: _wMoney,
                      child: TextField(
                        controller: line.costCtrl,
                        enabled: enabled,
                        textAlign: TextAlign.right,
                        decoration: _cellDecoration,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                    SizedBox(
                      width: _wTotal,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          _formatMoney(line.totalCents),
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: _wAction,
                      child: IconButton(
                        tooltip: 'Remover linha',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: enabled ? () => onRemove(index) : null,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Um profissional inativado depois de escolhido sai da lista; sem isso o
  /// dropdown estoura por valor fora das opções.
  String? _professionalValue(_QuoteLine line) {
    final current = line.professionalId;
    if (current == null) return null;
    return professionals.any((p) => p.id == current) ? current : null;
  }

  static const _cellDecoration = InputDecoration(
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    border: OutlineInputBorder(),
  );
}

/// Busca de chamado por número, título ou cliente. Lista os não encerrados.
class _RequestSearchField extends StatelessWidget {
  const _RequestSearchField({
    super.key,
    required this.requests,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.helper,
  });

  final List<ServiceRequest> requests;
  final ServiceRequest? selected;
  final ValueChanged<ServiceRequest?> onChanged;
  final bool enabled;

  /// Texto de apoio: quantos chamados o cliente tem, ou que não tem nenhum.
  /// Sem ele o campo parece quebrado ao não sugerir nada com o texto vazio.
  final String? helper;

  String _label(ServiceRequest request) =>
      '${request.displayNumber} · ${request.title}';

  @override
  Widget build(BuildContext context) {
    return Autocomplete<ServiceRequest>(
      displayStringForOption: _label,
      initialValue: TextEditingValue(
        text: selected == null ? '' : _label(selected!),
      ),
      optionsBuilder: (value) {
        final query = normalizeSearchText(value.text);
        if (query.isEmpty) return requests.take(12);
        return requests.where((request) {
          final haystack = normalizeSearchText(
            '${request.displayNumber} ${request.title} '
            '${request.customerName ?? ''}',
          );
          return haystack.contains(query);
        }).take(12);
      },
      onSelected: enabled ? onChanged : null,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          decoration: InputDecoration(
            labelText: 'Chamado (opcional)',
            hintText: 'Buscar por número, título ou cliente',
            helperText: helper,
            suffixIcon: controller.text.isEmpty
                ? const Icon(Icons.search_outlined)
                : IconButton(
                    tooltip: 'Limpar',
                    icon: const Icon(Icons.close),
                    onPressed: enabled
                        ? () {
                            controller.clear();
                            onChanged(null);
                          }
                        : null,
                  ),
          ),
          onChanged: (_) {
            if (selected != null) onChanged(null);
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
              constraints: const BoxConstraints(maxHeight: 320, maxWidth: 460),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final request = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.support_agent_outlined),
                    title: Text(
                      _label(request),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${request.customerName ?? 'Cliente não informado'}'
                      ' · ${request.status.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onSelected(request),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Centavos para o formato que `_moneyToCents` lê de volta (1234 -> "12,34").
String _centsToInput(int cents) =>
    (cents / 100).toStringAsFixed(2).replaceAll('.', ',');

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
