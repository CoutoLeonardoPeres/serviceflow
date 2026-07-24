import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/financial_list_notifier.dart';
import '../domain/receivable.dart';

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(financialListProvider.notifier).load();
    });
  }

  Future<void> _openPaymentDialog(Receivable receivable) async {
    final saved = await showAppFormDialog<bool>(
      context: context,
      title: 'Registrar pagamento',
      maxWidth: 620,
      child: _PaymentsForm(receivable: receivable),
    );
    if (saved == true && mounted) {
      await ref.read(financialListProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pagamento registrado.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financialListProvider);
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final pendingItems = state.items.where((item) => item.balanceCents > 0);
    final overdueItems = pendingItems.where((item) => item.isOverdue);
    final paidItems = state.items.where((item) => item.balanceCents <= 0);
    final receivedCents = state.items.fold<int>(
      0,
      (total, item) => total + (item.amountCents - item.balanceCents),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagamentos'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(financialListProvider.notifier).refresh(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(financialListProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            NeomorphicPanel(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Operação de pagamentos',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Centralize a baixa operacional das cobranças, acompanhe o que está vencido e identifique rapidamente o que já foi liquidado.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 16),
                  const Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      NeomorphicBadge(
                        icon: Icons.pix_outlined,
                        label: 'Pix manual',
                      ),
                      NeomorphicBadge(
                        icon: Icons.credit_card_outlined,
                        label: 'Cartão e maquininha',
                      ),
                      NeomorphicBadge(
                        icon: Icons.link_outlined,
                        label: 'Link de cobrança',
                      ),
                      NeomorphicBadge(
                        icon: Icons.account_balance_outlined,
                        label: 'Transferência',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            NeomorphicPanel(
              borderRadius: 24,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _SummaryTile(
                    icon: Icons.pending_actions_outlined,
                    label: 'Pendentes',
                    value: pendingItems.length.toString(),
                  ),
                  _SummaryTile(
                    icon: Icons.warning_amber_outlined,
                    label: 'Vencidos',
                    value: overdueItems.length.toString(),
                  ),
                  _SummaryTile(
                    icon: Icons.check_circle_outline,
                    label: 'Liquidados',
                    value: paidItems.length.toString(),
                  ),
                  _SummaryTile(
                    icon: Icons.payments_outlined,
                    label: 'Recebido',
                    value: currency.format(receivedCents / 100),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (state.isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 96),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.error != null)
              ErrorView(
                message:
                    state.error?.userMessage ?? 'Erro ao carregar pagamentos.',
                onRetry: () =>
                    ref.read(financialListProvider.notifier).refresh(),
              )
            else if (state.isEmpty)
              const EmptyView(
                message:
                    'Nenhuma cobrança disponível ainda. Os próximos recebíveis e pagamentos vão aparecer aqui.',
              )
            else ...[
              Text(
                'Cobranças que pedem ação',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 12),
              ...pendingItems.map(
                (receivable) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PaymentActionCard(
                    receivable: receivable,
                    onRegisterPayment: () => _openPaymentDialog(receivable),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: NeomorphicInset(
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentActionCard extends StatelessWidget {
  const _PaymentActionCard({
    required this.receivable,
    required this.onRegisterPayment,
  });

  final Receivable receivable;
  final VoidCallback onRegisterPayment;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final date = DateFormat('dd/MM/yyyy');

    return NeomorphicPanel(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  receivable.customerName ?? 'Cliente',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              _StatusBadge(status: receivable.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            receivable.description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.3,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              NeomorphicBadge(
                icon: Icons.payments_outlined,
                label:
                    'Saldo ${currency.format(receivable.balanceCents / 100)}',
              ),
              NeomorphicBadge(
                icon: Icons.event_outlined,
                label: 'Vence ${date.format(receivable.dueDate)}',
              ),
              if (receivable.workOrderNumber != null)
                NeomorphicBadge(
                  icon: Icons.engineering_outlined,
                  label:
                      'OS #${receivable.workOrderNumber!.toString().padLeft(5, '0')}',
                ),
              if (receivable.isOverdue)
                const NeomorphicBadge(
                  icon: Icons.priority_high_outlined,
                  label: 'Cobrança vencida',
                ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onRegisterPayment,
              icon: const Icon(Icons.price_check_outlined),
              label: const Text('Registrar pagamento'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ReceivableStatus status;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        status == ReceivableStatus.paid
            ? Icons.check_circle_outline
            : Icons.pending_actions_outlined,
        size: 18,
      ),
      label: Text(status.label),
    );
  }
}

class _PaymentsForm extends ConsumerStatefulWidget {
  const _PaymentsForm({required this.receivable});

  final Receivable receivable;

  @override
  ConsumerState<_PaymentsForm> createState() => _PaymentsFormState();
}

class _PaymentsFormState extends ConsumerState<_PaymentsForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  String _method = 'pix_manual';
  bool _isSaving = false;

  static const _methods = [
    ('pix_manual', 'Pix manual'),
    ('cash', 'Dinheiro'),
    ('transfer', 'Transferência'),
    ('card_machine', 'Máquina de cartão'),
    ('other', 'Outro'),
  ];

  @override
  void initState() {
    super.initState();
    _amountController.text =
        (widget.receivable.balanceCents / 100).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int _moneyToCents(String value) {
    final parsed = double.tryParse(value.replaceAll(',', '.')) ?? 0;
    return (parsed * 100).round();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(financialRepositoryProvider).registerManualPayment(
            receivableId: widget.receivable.id,
            method: _method,
            amountCents: _moneyToCents(_amountController.text),
            reference: _referenceController.text.trim().isEmpty
                ? null
                : _referenceController.text.trim(),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title: 'Baixa do recebível',
              icon: Icons.price_check_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppFormGrid(
                    children: [
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _method,
                        decoration: const InputDecoration(
                          labelText: 'Forma de pagamento',
                          prefixIcon:
                              Icon(Icons.account_balance_wallet_outlined),
                        ),
                        items: _methods
                            .map(
                              (method) => DropdownMenuItem(
                                value: method.$1,
                                child: Text(
                                  method.$2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _isSaving
                            ? null
                            : (value) =>
                                setState(() => _method = value ?? _method),
                      ),
                      TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Valor recebido',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        validator: (value) {
                          final cents = _moneyToCents(value ?? '');
                          if (cents <= 0) return 'Informe um valor válido.';
                          if (cents > widget.receivable.balanceCents) {
                            return 'Valor maior que o saldo em aberto.';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: _referenceController,
                        decoration: const InputDecoration(
                          labelText: 'Referência',
                          prefixIcon: Icon(Icons.tag_outlined),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Observações',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.price_check_outlined),
              label: const Text('Salvar pagamento'),
            ),
          ],
        ),
      ),
    );
  }
}
